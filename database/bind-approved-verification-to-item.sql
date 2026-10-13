-- Applied incrementally after inspecting the live function and migration history.
-- Prevent an approved line's verification from transferring to a different Item.
-- No historical observations or existing PO snapshots are rewritten.
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
   if prior is not null and upper(btrim(prior->>'item'))=upper(btrim(line->>'item')) and upper(btrim(prior->>'plant'))=upper(btrim(line->>'plant')) then
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
