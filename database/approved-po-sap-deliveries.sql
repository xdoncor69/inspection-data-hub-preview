-- Approved PO SAP delivery storage and server-side EST matching.
-- New deployment schema. Existing delivery RPC v1 is preserved on the running project.
create table public.inspection_deliveries (
 id uuid primary key default gen_random_uuid(),
 approved_po_id uuid not null references public.inspection_approved_pos(id) on delete cascade,
 delivery_number text not null check(length(btrim(delivery_number)) between 1 and 90),
 source_file text not null default '',
 rows jsonb not null check(jsonb_typeof(rows)='array'),
 po_snapshot jsonb not null,
 updated_by uuid not null references auth.users(id),
 updated_email text not null default '',
 customer_number text not null default '',
 updated_at timestamptz not null default clock_timestamp(),
 unique(approved_po_id,delivery_number)
);
alter table public.inspection_deliveries enable row level security;
revoke all on public.inspection_deliveries from anon,authenticated;
grant select on public.inspection_deliveries to authenticated;
create policy read_deliveries_of_approved_pos on public.inspection_deliveries for select to authenticated using(exists(select 1 from public.inspection_approved_pos p where p.id=approved_po_id));
create index inspection_deliveries_po_updated_idx on public.inspection_deliveries(approved_po_id,updated_at desc);
create index inspection_deliveries_updated_by_idx on public.inspection_deliveries(updated_by);
create or replace function inspection_internal.save_delivery_v2(operation_id uuid,approved_id uuid,expected_po jsonb,delivery_number text,source_file text,source_rows jsonb,expected_delivery jsonb default null,customer_number text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); p public.inspection_approved_pos%rowtype; d public.inspection_deliveries%rowtype; receipt inspection_internal.write_receipts%rowtype; hashed text; result jsonb; line jsonb; matched jsonb; output_rows jsonb='[]'; number text=btrim(delivery_number); item text; email text; generation text; prior_rows jsonb;
begin
 if uid is null or not exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Only the administrator can create or update a delivery' using errcode='42501';end if;
 if operation_id is null or approved_id is null or coalesce(btrim(customer_number),'')='' or length(btrim(customer_number))>90 or number is null or length(number) not between 1 and 90 or jsonb_typeof(source_rows) is distinct from 'array' or jsonb_array_length(source_rows) not between 1 and 5000 or octet_length(source_rows::text)>4000000 then raise exception 'Delivery number and valid Item rows required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 hashed=md5(jsonb_build_array(approved_id,expected_po,number,source_file,source_rows,expected_delivery,customer_number)::text);
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=save_delivery_v2.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 select records->'inspection-data-hub-catalog-import-v1'->>'generation' into generation from public.inspection_official_state where id='official';
 if (nullif(current_setting('request.headers',true),'')::jsonb->>'x-inspection-catalog-generation') is distinct from generation then raise exception 'Catalog changed. Refresh first.';end if;
 select * into p from public.inspection_approved_pos where id=approved_id for update;
 if not found then raise exception 'Approved PO not found';end if;
 if p.snapshot is distinct from expected_po then raise exception 'The approved PO changed. Reload and review the delivery.' using errcode='40001';end if;
 select * into d from public.inspection_deliveries where approved_po_id=approved_id and inspection_deliveries.delivery_number=number for update;
 if found then if expected_delivery is null or to_jsonb(d) is distinct from expected_delivery then raise exception 'This delivery changed. Reload before replacing it.' using errcode='40001';end if;
 elsif expected_delivery is not null then raise exception 'Delivery was removed. Reload first.' using errcode='40001';end if;
 for line in select value from jsonb_array_elements(source_rows) loop
  item=btrim(line->>'item');
  if coalesce(item,'')='' or length(item)>90 or jsonb_typeof(line) is distinct from 'object' then raise exception 'Invalid delivery Item';end if;
  if coalesce(line->>'catchWeight','') !~ '^(|[0-9]+([.][0-9]+)?)$' or coalesce(line->>'quantity','') !~ '^(|[0-9]+([.][0-9]+)?)$' then raise exception 'Quantity and Catch Weight must be numbers or blank';end if;
  select value into matched from jsonb_array_elements(p.snapshot->'rows') r where upper(btrim(r->>'item'))=upper(item);
  output_rows=output_rows||jsonb_build_array(jsonb_build_object('item',item,'description',left(coalesce(line->>'description',''),1000),'catchWeight',coalesce(line->'catchWeight','""'::jsonb),'receivedQuantity',coalesce(line->'quantity','""'::jsonb),'plant',case when matched is null then '' else coalesce(matched->>'plant','') end,'matched',matched is not null));
 end loop;
 select coalesce(u.email,'') into email from auth.users u where u.id=uid;
 insert into public.inspection_deliveries(approved_po_id,delivery_number,source_file,rows,po_snapshot,updated_by,updated_email,customer_number)
 values(approved_id,number,left(coalesce(source_file,''),200),output_rows,p.snapshot,uid,email,btrim(customer_number))
 on conflict on constraint inspection_deliveries_approved_po_id_delivery_number_key do update set customer_number=excluded.customer_number,source_file=excluded.source_file,rows=excluded.rows,po_snapshot=excluded.po_snapshot,updated_by=excluded.updated_by,updated_email=excluded.updated_email,updated_at=clock_timestamp()
 returning * into d;
 result=jsonb_build_object('id',d.id,'delivery_number',d.delivery_number);
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);
 return result;
end $$;
revoke all on function inspection_internal.save_delivery_v2(uuid,uuid,jsonb,text,text,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function inspection_internal.save_delivery_v2(uuid,uuid,jsonb,text,text,jsonb,jsonb,text) to authenticated;
create or replace function public.inspection_save_delivery_v2(operation_id uuid,approved_id uuid,expected_po jsonb,delivery_number text,source_file text,source_rows jsonb,expected_delivery jsonb default null,customer_number text default '')
returns jsonb language sql set search_path='' as $$select inspection_internal.save_delivery_v2(operation_id,approved_id,expected_po,delivery_number,source_file,source_rows,expected_delivery,customer_number)$$;
revoke all on function public.inspection_save_delivery_v2(uuid,uuid,jsonb,text,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.inspection_save_delivery_v2(uuid,uuid,jsonb,text,text,jsonb,jsonb,text) to authenticated;
