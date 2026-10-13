-- Incremental Inspection Data Hub workflow migration.
-- These changes were already applied to project kyhecrvsllableoymqfe.
-- Requires the existing inspection schema and prior migrations. Do not rerun blindly.
-- Preserves catalog, physical observations, approved POs and historical request rows.

create table public.inspection_clients(id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),customer_number text not null default '',updated_by uuid not null default auth.uid(),updated_at timestamptz not null default clock_timestamp());
create unique index inspection_clients_normalized_name on public.inspection_clients(lower(regexp_replace(btrim(name),'[[:space:]]+',' ','g')));
alter table public.inspection_clients enable row level security;
revoke all on public.inspection_clients from anon,authenticated;
grant select on public.inspection_clients to authenticated;
create policy clients_authenticated_read on public.inspection_clients for select to authenticated using((select auth.uid()) is not null);
insert into public.inspection_clients(name,updated_by) select distinct on (lower(btrim(snapshot->>'customer'))) btrim(snapshot->>'customer'),approved_by from public.inspection_approved_pos where coalesce(btrim(snapshot->>'customer'),'')<>'' on conflict do nothing;
alter table public.inspection_deliveries add column if not exists source_path text,add column if not exists weight_unit text not null default 'lb';
insert into storage.buckets(id,name,public,file_size_limit) values('inspection-delivery-originals','inspection-delivery-originals',false,20971520) on conflict(id) do nothing;
create policy delivery_original_upload on storage.objects for insert to authenticated with check(bucket_id='inspection-delivery-originals' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.inspection_approved_pos where id::text=(storage.foldername(name))[2]));
create policy delivery_original_owner_or_linked_read on storage.objects for select to authenticated using(bucket_id='inspection-delivery-originals' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.inspection_deliveries d where d.source_path=name)));
revoke execute on function public.inspection_queued_item_proposal(uuid,jsonb),public.inspection_review_request(uuid,text,bigint,text),public.inspection_queued_review(uuid,uuid,text,bigint) from public,anon,authenticated;
revoke execute on function inspection_internal.queued_item_proposal(uuid,jsonb),inspection_internal.review_request(uuid,text,bigint,text),inspection_internal.queued_review(uuid,uuid,text,bigint) from public,anon,authenticated;


create or replace function inspection_internal.save_client(operation_id uuid,client_id uuid,client_name text,customer_number text,expected_client jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); old public.inspection_clients%rowtype; result jsonb; hashed text=md5(jsonb_build_array(client_id,client_name,customer_number,expected_client)::text); receipt inspection_internal.write_receipts%rowtype;
begin
 if uid is null or not exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Administrator required' using errcode='42501';end if;
 if operation_id is null or coalesce(length(btrim(client_name)),0) not between 1 and 120 then raise exception 'Client name required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=save_client.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 if client_id is null then insert into public.inspection_clients(name,customer_number,updated_by) values(btrim(client_name),coalesce(customer_number,''),uid) returning to_jsonb(inspection_clients.*) into result;
 else select * into old from public.inspection_clients where id=client_id for update;if not found or to_jsonb(old) is distinct from expected_client then raise exception 'Client changed. Refresh first.' using errcode='40001';end if;
 update public.inspection_clients set name=btrim(client_name),customer_number=coalesce(save_client.customer_number,''),updated_by=uid,updated_at=clock_timestamp() where id=client_id returning to_jsonb(inspection_clients.*) into result;end if;
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);return result;
end $$;
revoke all on function inspection_internal.save_client(uuid,uuid,text,text,jsonb) from public,anon;grant execute on function inspection_internal.save_client(uuid,uuid,text,text,jsonb) to authenticated;
create or replace function public.inspection_save_client(operation_id uuid,client_id uuid,client_name text,customer_number text,expected_client jsonb default null) returns jsonb language sql set search_path='' as $$select inspection_internal.save_client(operation_id,client_id,client_name,customer_number,expected_client)$$;
revoke all on function public.inspection_save_client(uuid,uuid,text,text,jsonb) from public,anon;grant execute on function public.inspection_save_client(uuid,uuid,text,text,jsonb) to authenticated;
create or replace function inspection_internal.save_delivery_v3(operation_id uuid,approved_id uuid,expected_po jsonb,delivery_number text,source_file text,source_rows jsonb,source_path text,expected_delivery jsonb default null,weight_unit text default 'lb') returns jsonb language plpgsql security definer set search_path='' as $$
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
 if p.snapshot is distinct from expected_po then raise exception 'Approved PO changed. Reload and rematch.' using errcode='40001';end if;
 select * into d from public.inspection_deliveries where approved_po_id=approved_id and inspection_deliveries.delivery_number=number for update;
 if found then if expected_delivery is null or to_jsonb(d) is distinct from expected_delivery then raise exception 'Delivery changed. Reload first.' using errcode='40001';end if;elsif expected_delivery is not null then raise exception 'Delivery removed. Reload first.' using errcode='40001';end if;
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
end $$;
revoke all on function inspection_internal.save_delivery_v3(uuid,uuid,jsonb,text,text,jsonb,text,jsonb,text) from public,anon;grant execute on function inspection_internal.save_delivery_v3(uuid,uuid,jsonb,text,text,jsonb,text,jsonb,text) to authenticated;
create or replace function public.inspection_save_delivery_v3(operation_id uuid,approved_id uuid,expected_po jsonb,delivery_number text,source_file text,source_rows jsonb,source_path text,expected_delivery jsonb default null,weight_unit text default 'lb') returns jsonb language sql set search_path='' as $$select inspection_internal.save_delivery_v3(operation_id,approved_id,expected_po,delivery_number,source_file,source_rows,source_path,expected_delivery,weight_unit)$$;
revoke all on function public.inspection_save_delivery_v3(uuid,uuid,jsonb,text,text,jsonb,text,jsonb,text) from public,anon;grant execute on function public.inspection_save_delivery_v3(uuid,uuid,jsonb,text,text,jsonb,text,jsonb,text) to authenticated;


CREATE OR REPLACE FUNCTION inspection_internal.manage_approved_po(operation_id uuid, approved_id uuid, expected_snapshot jsonb, replacement jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); a public.inspection_approved_pos%rowtype; receipt inspection_internal.write_receipts%rowtype; hashed text; result jsonb; line jsonb; prior jsonb; rowsout jsonb='[]'; k text; current_generation text;
begin
 if uid is null or not exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Administrator permission required' using errcode='42501';end if;
 if operation_id is null or approved_id is null then raise exception 'Invalid operation';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));hashed=md5(jsonb_build_array(approved_id,expected_snapshot,replacement)::text);
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=manage_approved_po.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 select records->'inspection-data-hub-catalog-import-v1'->>'generation' into current_generation from public.inspection_official_state where id='official' for update;
 if (current_setting('request.headers',true)::jsonb->>'x-inspection-catalog-generation') is distinct from current_generation then raise exception 'Catalog changed. Refresh first.';end if;
 select * into a from public.inspection_approved_pos where id=approved_id for update;
 if not found or a.approved_by<>uid then raise exception 'Your approved PO was not found' using errcode='42501';end if;
 if a.snapshot is distinct from expected_snapshot then raise exception 'PO changed on another device. Refresh first.' using errcode='40001';end if;
 if replacement is null then
  delete from public.inspection_approved_pos where id=approved_id;
  result=jsonb_build_object('id',approved_id,'deleted',true);
 else
  if jsonb_typeof(replacement)<>'object' or coalesce(btrim(replacement->>'po'),'')='' or coalesce(btrim(replacement->>'customer'),'')='' or jsonb_typeof(replacement->'rows') is distinct from 'array' or jsonb_array_length(replacement->'rows')=0 or jsonb_array_length(replacement->'rows')>5000 or octet_length(replacement::text)>8000000 then raise exception 'PO number, customer and Items required';end if;
  k=lower(btrim(replacement->>'po'));
  if exists(select 1 from public.inspection_approved_pos where po_key=k and id<>approved_id) then raise exception 'PO number already approved';end if;

  for line in select value from jsonb_array_elements(replacement->'rows') loop
   if coalesce(btrim(line->>'item'),'')='' or coalesce(btrim(line->>'description'),'')='' or coalesce(btrim(line->>'plant'),'')='' then raise exception 'Item, description and selected EST / Plant required';end if;
   select value into prior from jsonb_array_elements(a.snapshot->'rows') with ordinality r(value,ord) where coalesce(value->>'lineId','legacy:'||(ord-1)::text)=line->>'lineId';
   line=line-array['verifiedAt','verifiedEsts','changeFrom','changeTo'];
   if prior is not null and upper(btrim(prior->>'plant'))=upper(btrim(line->>'plant')) then
    line=line||jsonb_build_object('verifiedAt',coalesce(prior->'verifiedAt','""'),'verifiedEsts',coalesce(prior->'verifiedEsts','[]'),'changeFrom',coalesce(prior->'changeFrom','""'),'changeTo',coalesce(prior->'changeTo','""'));
   else line=line||jsonb_build_object('verifiedAt','','verifiedEsts','[]'::jsonb,'changeFrom','','changeTo','');
   end if;
   rowsout=rowsout||jsonb_build_array(line);
  end loop;
  replacement=jsonb_set(replacement,'{rows}',rowsout);
  update public.inspection_approved_pos set snapshot=replacement,po_key=k,approved_at=clock_timestamp() where id=approved_id;
  update public.inspection_po_workspaces w set workspace=jsonb_set(w.workspace,'{invoices}',coalesce((select jsonb_agg(p) from jsonb_array_elements(w.workspace->'invoices') p where lower(btrim(p->>'po'))<>k),'[]')),updated_at=clock_timestamp() where exists(select 1 from jsonb_array_elements(w.workspace->'invoices') p where lower(btrim(p->>'po'))=k);
  result=jsonb_build_object('id',approved_id,'deleted',false);
 end if;
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);
 return result;
end $function$


create or replace function inspection_internal.set_shared_account(account_email text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if not exists(select 1 from public.inspection_admins where user_id=auth.uid()) then raise exception 'Administrator required' using errcode='42501';end if;
 select id into uid from auth.users where lower(email)=lower(btrim(account_email));
 if uid is null then raise exception 'Create the account in Supabase Authentication first';end if;
 if exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Administrator cannot be shared account';end if;
 update public.inspection_profiles set display_name=email where display_name='Invitados' and user_id<>uid;
 update public.inspection_profiles set display_name='Invitados' where user_id=uid;
end $$;
revoke all on function inspection_internal.set_shared_account(text) from public,anon;grant execute on function inspection_internal.set_shared_account(text) to authenticated;
create or replace function public.inspection_set_shared_account(account_email text) returns void language sql security invoker set search_path='' as $$select inspection_internal.set_shared_account(account_email)$$;
revoke all on function public.inspection_set_shared_account(text) from public,anon;grant execute on function public.inspection_set_shared_account(text) to authenticated;