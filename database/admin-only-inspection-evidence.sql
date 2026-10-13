-- Applied incrementally to existing Supabase project. Historical evidence is preserved.
-- Approved PO and delivery readers return restricted snapshots for normal accounts.

create or replace function inspection_internal.public_po_snapshot(value jsonb) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',value->'id','po',value->'po','customer',value->'customer','clientId',value->'clientId','savedAt',value->'savedAt','inspectionVersion',md5(value::text),'rows',coalesce((select jsonb_agg(jsonb_build_object('lineId',r->'lineId','item',r->'item','description',r->'description','category',r->'category','plant',r->'plant') order by n) from jsonb_array_elements(value->'rows') with ordinality x(r,n)),'[]'::jsonb))
$$;
create or replace function inspection_internal.public_delivery(value jsonb) returns jsonb language sql immutable set search_path='' as $$select jsonb_set(value,'{po_snapshot}',inspection_internal.public_po_snapshot(value->'po_snapshot'))$$;
create or replace function inspection_internal.read_approved_pos() returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean; result jsonb;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select exists(select 1 from public.inspection_admins where user_id=auth.uid()) into admin;
 select coalesce(jsonb_agg(case when admin then to_jsonb(p) else jsonb_set(to_jsonb(p),'{snapshot}',inspection_internal.public_po_snapshot(p.snapshot)) end order by approved_at desc),'[]') into result from public.inspection_approved_pos p;
 return result;
end $$;
create or replace function inspection_internal.read_deliveries(approved_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean; result jsonb;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select exists(select 1 from public.inspection_admins where user_id=auth.uid()) into admin;
 select coalesce(jsonb_agg(case when admin then to_jsonb(d) else inspection_internal.public_delivery(to_jsonb(d)) end order by updated_at desc),'[]') into result from public.inspection_deliveries d where approved_po_id=approved_id;
 return result;
end $$;
create or replace function public.inspection_read_approved_pos() returns jsonb language sql security invoker set search_path='' as $$select inspection_internal.read_approved_pos()$$;
create or replace function public.inspection_read_deliveries(approved_id uuid) returns jsonb language sql security invoker set search_path='' as $$select inspection_internal.read_deliveries(approved_id)$$;
revoke all on function inspection_internal.public_po_snapshot(jsonb),inspection_internal.public_delivery(jsonb),inspection_internal.read_approved_pos(),inspection_internal.read_deliveries(uuid),public.inspection_read_approved_pos(),public.inspection_read_deliveries(uuid) from public,anon;
grant execute on function inspection_internal.read_approved_pos(),inspection_internal.read_deliveries(uuid),public.inspection_read_approved_pos(),public.inspection_read_deliveries(uuid) to authenticated;
revoke select on public.inspection_approved_pos,public.inspection_deliveries from public,anon,authenticated;
grant select(id,po_key,approved_by,approved_email,approved_at) on public.inspection_approved_pos to authenticated;
grant select(id,approved_po_id,delivery_number,source_file,rows,updated_by,updated_email,updated_at,customer_number,source_path,weight_unit) on public.inspection_deliveries to authenticated;

CREATE OR REPLACE FUNCTION inspection_internal.save_delivery_v3(operation_id uuid, approved_id uuid, expected_po jsonb, delivery_number text, source_file text, source_rows jsonb, source_path text, expected_delivery jsonb DEFAULT NULL::jsonb, weight_unit text DEFAULT 'lb'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); p public.inspection_approved_pos%rowtype; d public.inspection_deliveries%rowtype; receipt inspection_internal.write_receipts%rowtype; hashed text; result jsonb; line jsonb; chosen jsonb; output_rows jsonb='[]'; number text=btrim(delivery_number); item text; email text; generation text; variants integer; ref_key text; status text;
begin
 if uid is null then raise exception 'Login required' using errcode='42501';end if;
 if operation_id is null or approved_id is null or coalesce(length(number),0) not between 1 and 90 or jsonb_typeof(source_rows) is distinct from 'array' or jsonb_array_length(source_rows) not between 1 and 5000 or octet_length(source_rows::text)>4000000 then raise exception 'Delivery number and valid rows required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 hashed=md5(jsonb_build_array(approved_id,expected_po,number,source_file,source_rows,source_path,expected_delivery,weight_unit)::text);
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=save_delivery_v3.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 select records->'inspection-data-hub-catalog-import-v1'->>'generation' into generation from public.inspection_official_state where id='official';
 if (nullif(current_setting('request.headers',true),'')::jsonb->>'x-inspection-catalog-generation') is distinct from generation then raise exception 'Catalog changed. Refresh first.';end if;
 select * into p from public.inspection_approved_pos where id=approved_id for update;
 if not found then raise exception 'Approved PO not found';end if;
 if p.snapshot is distinct from expected_po and inspection_internal.public_po_snapshot(p.snapshot) is distinct from expected_po then raise exception 'Approved PO changed. Reload and rematch.' using errcode='40001';end if;
 select * into d from public.inspection_deliveries where approved_po_id=approved_id and inspection_deliveries.delivery_number=number for update;
 if found then if expected_delivery is null or (to_jsonb(d) is distinct from expected_delivery and inspection_internal.public_delivery(to_jsonb(d)) is distinct from expected_delivery) then raise exception 'Delivery changed. Reload first.' using errcode='40001';end if;elsif expected_delivery is not null then raise exception 'Delivery removed. Reload first.' using errcode='40001';end if;
 if coalesce(source_path,'')='' or split_part(source_path,'/',2)<>approved_id::text or not exists(select 1 from storage.objects o where o.bucket_id='inspection-delivery-originals' and o.name=source_path and (split_part(source_path,'/',1)=uid::text or exists(select 1 from public.inspection_deliveries x where x.approved_po_id=approved_id and x.source_path=save_delivery_v3.source_path))) then raise exception 'Upload an original file for this approved PO first' using errcode='42501';end if;
 for line in select value from jsonb_array_elements(source_rows) loop
  item=btrim(line->>'item');chosen=null;ref_key=null;
  if coalesce(length(item),0) not between 1 and 90 or jsonb_typeof(line) is distinct from 'object' then raise exception 'Invalid Item';end if;
  if coalesce(line->>'catchWeight','') !~ '^(|[0-9]+([.][0-9]+)?)$' or coalesce(line->>'quantity','') !~ '^(|[0-9]+([.][0-9]+)?)$' then raise exception 'Quantity and weight must be numeric or blank';end if;
  select count(distinct upper(btrim(r->>'plant'))) into variants from jsonb_array_elements(p.snapshot->'rows') r where upper(btrim(r->>'item'))=upper(item) and coalesce(btrim(r->>'plant'),'')<>'';
  if coalesce(line->>'association','')<>'' then
   select value,coalesce(value->>'lineId','legacy:'||(ord-1)::text) into chosen,ref_key from jsonb_array_elements(p.snapshot->'rows') with ordinality r(value,ord) where upper(btrim(value->>'item'))=upper(item) and coalesce(value->>'lineId','legacy:'||(ord-1)::text)=line->>'association';
   if chosen is null then raise exception 'Association does not belong to this approved Item';end if;
  elsif variants=1 then
   select value,coalesce(value->>'lineId','legacy:'||(ord-1)::text) into chosen,ref_key from jsonb_array_elements(p.snapshot->'rows') with ordinality r(value,ord) where upper(btrim(value->>'item'))=upper(item) and coalesce(btrim(value->>'plant'),'')<>'' order by ord limit 1;
  end if;
  status=case when chosen is not null and coalesce(btrim(chosen->>'plant'),'')<>'' then 'matched' when variants>1 then 'ambiguous' else 'unmatched' end;
  output_rows=output_rows||jsonb_build_array(jsonb_build_object('item',item,'description',left(coalesce(line->>'description',''),1000),'catchWeight',coalesce(line->'catchWeight','""'::jsonb),'receivedQuantity',coalesce(line->'quantity','""'::jsonb),'plant',case when status='matched' then chosen->>'plant' else '' end,'matched',status='matched','match_status',status,'association',ref_key,'weightUnit',left(coalesce(line->>'weightUnit',weight_unit,''),20)));
 end loop;
 select coalesce(u.email,'') into email from auth.users u where u.id=uid;
 if exists(select 1 from public.inspection_profiles f where f.user_id=uid and f.display_name='Invitados') then email='Invitados';end if;
 insert into public.inspection_deliveries(approved_po_id,delivery_number,source_file,rows,po_snapshot,updated_by,updated_email,source_path,weight_unit)
 values(approved_id,number,left(coalesce(source_file,''),200),output_rows,p.snapshot,uid,email,source_path,left(coalesce(weight_unit,''),20))
 on conflict on constraint inspection_deliveries_approved_po_id_delivery_number_key do update set source_file=excluded.source_file,rows=excluded.rows,po_snapshot=excluded.po_snapshot,updated_by=excluded.updated_by,updated_email=excluded.updated_email,source_path=excluded.source_path,weight_unit=excluded.weight_unit,updated_at=clock_timestamp()
 returning * into d;
 result=jsonb_build_object('id',d.id,'delivery_number',d.delivery_number);
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);return result;
end $function$


create or replace function inspection_internal.read_official_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean;result jsonb;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select exists(select 1 from public.inspection_admins where user_id=auth.uid()) into admin;
 select jsonb_build_array(jsonb_build_object('id',s.id,'revision',s.revision,'updated_at',s.updated_at,'records',case when admin then s.records else s.records-'inspection-data-hub-observations-v1'-'inspection-data-hub-po-observations-v1'-'inspection-data-hub-po-workspace-v1' end)) into result from public.inspection_official_state s where id='official';
 return coalesce(result,'[]');
end $$;
create or replace function public.inspection_read_official_state() returns jsonb language sql security invoker set search_path='' as $$select inspection_internal.read_official_state()$$;
revoke all on function inspection_internal.read_official_state(),public.inspection_read_official_state() from public,anon;
grant execute on function inspection_internal.read_official_state(),public.inspection_read_official_state() to authenticated;
revoke select on public.inspection_official_state from public,anon,authenticated;
grant select(id,revision,updated_at) on public.inspection_official_state to authenticated;
