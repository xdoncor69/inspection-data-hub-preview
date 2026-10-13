-- Applied migration: delivery_first_intake_and_pending_po_review.
-- Reference only; do not rerun against a project where this migration is already applied.
-- Delivery originals stay private. Upload creates an administrator-owned PO In review;
-- approval atomically associates the retained source lines without creating physical observations.
create table public.inspection_delivery_intakes (
 id uuid primary key,
 created_by uuid not null references auth.users(id),
 administrator_id uuid not null references auth.users(id),
 po_number text not null,
 client_id uuid not null references public.inspection_clients(id),
 customer_name text not null,
 delivery_number text not null,
 source_file text not null,
 source_path text not null unique,
 source_rows jsonb not null,
 draft_id text not null unique,
 approved_po_id uuid references public.inspection_approved_pos(id) on delete set null,
 created_at timestamptz not null default now(),
 payload_hash text not null
);
alter table public.inspection_delivery_intakes enable row level security;
create index inspection_delivery_intakes_creator on public.inspection_delivery_intakes(created_by);
create index inspection_delivery_intakes_admin on public.inspection_delivery_intakes(administrator_id);
create index inspection_delivery_intakes_client on public.inspection_delivery_intakes(client_id);
create index inspection_delivery_intakes_approved on public.inspection_delivery_intakes(approved_po_id);
revoke all on public.inspection_delivery_intakes from anon,authenticated;
grant select on public.inspection_delivery_intakes to authenticated;
create policy intake_owner_or_admin_read on public.inspection_delivery_intakes for select to authenticated using(created_by=(select auth.uid()) or exists(select 1 from public.inspection_admins where user_id=(select auth.uid())));
insert into storage.buckets(id,name,public,file_size_limit) values('inspection-delivery-intakes','inspection-delivery-intakes',false,20971520) on conflict(id) do nothing;
create policy intake_original_insert on storage.objects for insert to authenticated with check(bucket_id='inspection-delivery-intakes' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy intake_original_read on storage.objects for select to authenticated using(bucket_id='inspection-delivery-intakes' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.inspection_admins where user_id=(select auth.uid())) or exists(select 1 from public.inspection_delivery_intakes i where i.source_path=name and i.approved_po_id is not null)));
-- The linked-file check uses a narrowly scoped helper: normal accounts cannot enumerate another account's unapproved intakes.
create function inspection_internal.intake_file_published(path text) returns boolean language sql security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.inspection_delivery_intakes where source_path=path and approved_po_id is not null)$$;
revoke all on function inspection_internal.intake_file_published(text) from public,anon;
grant execute on function inspection_internal.intake_file_published(text) to authenticated;
alter policy intake_original_read on storage.objects using(bucket_id='inspection-delivery-intakes' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.inspection_admins where user_id=(select auth.uid())) or inspection_internal.intake_file_published(name)));
alter table public.inspection_deliveries add column source_bucket text not null default 'inspection-delivery-originals';
grant select(source_bucket) on public.inspection_deliveries to authenticated;
create function inspection_internal.submit_delivery_intake(operation_id uuid,po_number text,client_id uuid,delivery_number text,source_file text,source_path text,source_rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); admin_id uuid; catalog jsonb; workdoc jsonb; customer text; number text=btrim(po_number); delivery text=btrim(delivery_number); hash text; old public.inspection_delivery_intakes%rowtype; line jsonb; product jsonb; draft_rows jsonb='[]'; raw_rows jsonb='[]'; line_id text; draft_id text='delivery-intake-'||operation_id::text; item text; description text; draft jsonb; generation text;
begin
 if uid is null then raise exception 'Login required' using errcode='42501';end if;
 if operation_id is null or coalesce(length(delivery),0) not between 1 and 90 or jsonb_typeof(source_rows) is distinct from 'array' or jsonb_array_length(source_rows) not between 1 and 5000 or octet_length(source_rows::text)>4000000 then raise exception 'Delivery number and valid rows are required';end if;
 if number='' or number is null then number='D'||delivery;end if;
 if length(number)>90 then raise exception 'PO number is too long';end if;
 hash=md5(jsonb_build_array(po_number,client_id,delivery,source_file,source_path,source_rows)::text);
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 select * into old from public.inspection_delivery_intakes where id=operation_id;
 if found then if old.created_by<>uid or old.payload_hash<>hash then raise exception 'Operation ID already used' using errcode='40001';end if;return jsonb_build_object('id',old.id,'draft_id',old.draft_id,'po_number',old.po_number);end if;
 select records->'inspection-data-hub-catalog-overrides-v1',records->'inspection-data-hub-catalog-import-v1'->>'generation' into catalog,generation from public.inspection_official_state where id='official' for update;
 if (nullif(current_setting('request.headers',true),'')::jsonb->>'x-inspection-catalog-generation') is distinct from generation then raise exception 'Catalog changed. Refresh first.';end if;
 select a.user_id into admin_id from public.inspection_admins a join auth.users u on u.id=a.user_id where lower(u.email)='david.rodriguez@hapcor.com';
 if admin_id is null then raise exception 'Inspection administrator is not configured';end if;
 select name into customer from public.inspection_clients where id=client_id;
 if customer is null then raise exception 'Choose a saved client';end if;
 if coalesce(source_path,'')='' or split_part(source_path,'/',1)<>uid::text or split_part(source_path,'/',2)<>operation_id::text or not exists(select 1 from storage.objects where bucket_id='inspection-delivery-intakes' and name=source_path) then raise exception 'Upload this delivery original first' using errcode='42501';end if;
 insert into public.inspection_po_workspaces(user_id) values(admin_id) on conflict do nothing;
 select w.workspace into workdoc from public.inspection_po_workspaces w where user_id=admin_id for update;
 if exists(select 1 from public.inspection_approved_pos where po_key=lower(number)) or exists(select 1 from jsonb_array_elements(coalesce(workdoc->'invoices','[]')) p where lower(btrim(p->>'po'))=lower(number)) then raise exception 'That PO number already exists for inspection. Open it or choose another PO number.' using errcode='40001';end if;
 for line in select value from jsonb_array_elements(source_rows) loop
  item=btrim(line->>'item');
  if coalesce(length(item),0) not between 1 and 90 or jsonb_typeof(line)<>'object' then raise exception 'Invalid Item';end if;
  if coalesce(line->>'catchWeight','') !~ '^(|[0-9]+([.][0-9]+)?)$' or coalesce(line->>'quantity','') !~ '^(|[0-9]+([.][0-9]+)?)$' then raise exception 'Quantity and weight must be numeric or blank';end if;
  product=catalog->item;line_id=gen_random_uuid()::text;description=coalesce(product->>'description',line->>'description','');
  draft=jsonb_build_object('lineId',line_id,'item',item,'description',description,'plant',coalesce(product->>'plant',''),'expectedEst',coalesce(product->>'plant',''),'verifiedAt','','verifiedEsts','[]'::jsonb,'note','','category',coalesce(product->>'category',''),'pack',coalesce(product->>'pack',''),'size',coalesce(product->>'size',''));
  if product is null then draft=draft||jsonb_build_object('importedProduct',jsonb_build_object('description',description,'plant','','category',''));end if;
  draft_rows=draft_rows||jsonb_build_array(draft);
  raw_rows=raw_rows||jsonb_build_array(jsonb_build_object('item',item,'description',coalesce(line->>'description',''),'quantity',coalesce(line->'quantity','""'::jsonb),'catchWeight',coalesce(line->'catchWeight','""'::jsonb),'weightUnit',coalesce(line->>'weightUnit',''),'reviewLineId',line_id));
 end loop;
 draft=jsonb_build_object('id',draft_id,'po',number,'customer',customer,'clientId',client_id,'savedAt',clock_timestamp(),'rows',draft_rows,'deliveryIntakeId',operation_id,'createdBy',uid,'updatedBy',uid);
 update public.inspection_po_workspaces w set workspace=jsonb_set(workdoc,'{invoices}',jsonb_build_array(draft)||coalesce(workdoc->'invoices','[]')),updated_at=clock_timestamp() where user_id=admin_id;
 insert into public.inspection_delivery_intakes values(operation_id,uid,admin_id,number,client_id,customer,delivery,left(coalesce(source_file,''),200),source_path,raw_rows,draft_id,null,clock_timestamp(),hash);
 return jsonb_build_object('id',operation_id,'draft_id',draft_id,'po_number',number);
end $$;
revoke all on function inspection_internal.submit_delivery_intake(uuid,text,uuid,text,text,text,jsonb) from public,anon;
grant execute on function inspection_internal.submit_delivery_intake(uuid,text,uuid,text,text,text,jsonb) to authenticated;
create function public.inspection_submit_delivery_intake(operation_id uuid,po_number text,client_id uuid,delivery_number text,source_file text,source_path text,source_rows jsonb) returns jsonb language sql set search_path='' as $$select inspection_internal.submit_delivery_intake(operation_id,po_number,client_id,delivery_number,source_file,source_path,source_rows)$$;
revoke all on function public.inspection_submit_delivery_intake(uuid,text,uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.inspection_submit_delivery_intake(uuid,text,uuid,text,text,text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION inspection_internal.save_delivery_v3(operation_id uuid, approved_id uuid, expected_po jsonb, delivery_number text, source_file text, source_rows jsonb, source_path text, expected_delivery jsonb DEFAULT NULL::jsonb, weight_unit text DEFAULT 'lb'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); p public.inspection_approved_pos%rowtype; d public.inspection_deliveries%rowtype; receipt inspection_internal.write_receipts%rowtype; hashed text; result jsonb; line jsonb; chosen jsonb; output_rows jsonb='[]'; number text=btrim(delivery_number); item text; email text; generation text; variants integer; ref_key text; status text; original_bucket text;
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

 original_bucket=null;
 if split_part(source_path,'/',2)=approved_id::text and exists(select 1 from storage.objects o where o.bucket_id='inspection-delivery-originals' and o.name=source_path and (split_part(source_path,'/',1)=uid::text or exists(select 1 from public.inspection_deliveries x where x.approved_po_id=approved_id and x.source_path=save_delivery_v3.source_path))) then original_bucket='inspection-delivery-originals';
 elsif exists(select 1 from public.inspection_delivery_intakes i join storage.objects o on o.name=i.source_path and o.bucket_id='inspection-delivery-intakes' where i.approved_po_id=approved_id and i.source_path=save_delivery_v3.source_path) then original_bucket='inspection-delivery-intakes';
 end if;
 if original_bucket is null then raise exception 'Upload an original file for this approved PO first' using errcode='42501';end if;
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
 insert into public.inspection_deliveries(approved_po_id,delivery_number,source_file,rows,po_snapshot,updated_by,updated_email,source_path,weight_unit,source_bucket)
 values(approved_id,number,left(coalesce(source_file,''),200),output_rows,p.snapshot,uid,email,source_path,left(coalesce(weight_unit,''),20),original_bucket)
 on conflict on constraint inspection_deliveries_approved_po_id_delivery_number_key do update set source_file=excluded.source_file,rows=excluded.rows,po_snapshot=excluded.po_snapshot,updated_by=excluded.updated_by,updated_email=excluded.updated_email,source_path=excluded.source_path,source_bucket=excluded.source_bucket,weight_unit=excluded.weight_unit,updated_at=clock_timestamp()
 returning * into d;
 result=jsonb_build_object('id',d.id,'delivery_number',d.delivery_number);
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);return result;
end $function$
;
CREATE OR REPLACE FUNCTION inspection_internal.approve_po(operation_id uuid, po_id text, expected_po jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); source jsonb; source_workspace jsonb; email text; hashed text; receipt inspection_internal.write_receipts%rowtype; output jsonb; key text; catalog jsonb; frozen_rows jsonb; intake public.inspection_delivery_intakes%rowtype; intake_rows jsonb;
begin
 if uid is null or not exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Only the administrator can approve a PO' using errcode='42501';end if;
 if operation_id is null or po_id is null or jsonb_typeof(expected_po)<>'object' then raise exception 'Invalid approval';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 hashed=md5(jsonb_build_array(po_id,expected_po)::text);
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=approve_po.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 select records->'inspection-data-hub-catalog-overrides-v1' into catalog from public.inspection_official_state where id='official' for update;
 select workspace into source_workspace from public.inspection_po_workspaces where user_id=uid for update;
 select value into source from jsonb_array_elements(source_workspace->'invoices') where value->>'id'=po_id;
 if source is null then raise exception 'Private PO not found';end if;
 if source is distinct from expected_po then raise exception 'The PO changed on another device. Refresh and review before approving.' using errcode='40001';end if;
 if jsonb_array_length(source->'rows')=0 or exists(select 1 from jsonb_array_elements(source->'rows') p where coalesce(btrim(p->>'plant'),'')='') then raise exception 'Every Item needs a selected EST / Plant before approval';end if;
 key=lower(btrim(source->>'po'));
 if exists(select 1 from public.inspection_approved_pos a where a.po_key=key) then raise exception 'This PO number is already approved';end if;
 select p.email into email from public.inspection_profiles p where p.user_id=uid;
 select jsonb_agg(line.value || jsonb_build_object('pack',coalesce(line.value->'pack',catalog->(line.value->>'item')->'pack','""'),'size',coalesce(line.value->'size',catalog->(line.value->>'item')->'size','""'),'category',coalesce(line.value->'category',catalog->(line.value->>'item')->'category','""')) order by line.ord) into frozen_rows from jsonb_array_elements(source->'rows') with ordinality line(value,ord); source=jsonb_set(source,'{rows}',frozen_rows); insert into public.inspection_approved_pos(id,po_key,snapshot,approved_by,approved_email) values(operation_id,key,source,uid,email);

 select * into intake from public.inspection_delivery_intakes where draft_id=po_id and administrator_id=uid for update;
 if found then
  update public.inspection_delivery_intakes set approved_po_id=operation_id where id=intake.id;
  select jsonb_agg(r.value||jsonb_build_object('association',case when exists(select 1 from jsonb_array_elements(source->'rows') p where p->>'lineId'=r.value->>'reviewLineId' and upper(btrim(p->>'item'))=upper(btrim(r.value->>'item'))) then r.value->>'reviewLineId' else null end) order by r.ord) into intake_rows from jsonb_array_elements(intake.source_rows) with ordinality r(value,ord);
  perform inspection_internal.save_delivery_v3(gen_random_uuid(),operation_id,source,intake.delivery_number,intake.source_file,intake_rows,intake.source_path,null,'');
 end if;
 -- Replace matching drafts in every account with the official snapshot.
 update public.inspection_po_workspaces w set workspace=jsonb_set(w.workspace,'{invoices}',coalesce((select jsonb_agg(p) from jsonb_array_elements(w.workspace->'invoices') p where lower(btrim(p->>'po'))<>key),'[]')),updated_at=clock_timestamp() where exists(select 1 from jsonb_array_elements(w.workspace->'invoices') p where lower(btrim(p->>'po'))=key);
 output=jsonb_build_object('id',operation_id,'approved_email',email);
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,output);
 return output;
end $function$
;


create function inspection_internal.approved_legacy_photo(path text) returns boolean language sql security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.inspection_official_state s,
 lateral jsonb_each(coalesce(s.records->'inspection-data-hub-photos-v1','{}')) groups,
 lateral jsonb_array_elements(case when jsonb_typeof(groups.value)='array' then groups.value else '[]'::jsonb end) photo
 where s.id='official' and photo->>'path'=path and photo->>'bucket'='inspection-photo-requests')
$$;
revoke all on function inspection_internal.approved_legacy_photo(text) from public,anon;
grant execute on function inspection_internal.approved_legacy_photo(text) to authenticated;
alter policy inspection_approved_pending_photo_read on storage.objects using(bucket_id='inspection-photo-requests' and inspection_internal.approved_legacy_photo(name));
