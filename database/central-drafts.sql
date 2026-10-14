-- Reference for migration centralize_drafts_with_admin_only_evidence already applied to Supabase; do not run blindly.
-- Central draft workspace. Keeps original per-account records as a server-side compatibility archive.
create function inspection_internal.shared_draft_owner() returns uuid
language sql stable security definer set search_path='' as $$
 select a.user_id from public.inspection_admins a join auth.users u on u.id=a.user_id where lower(u.email)='david.rodriguez@hapcor.com'
$$;
revoke all on function inspection_internal.shared_draft_owner() from public,anon,authenticated;

-- Whitelist: no physical verification dates, authors, notes, indicators or observations.
create function inspection_internal.public_draft(value jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select case when value is null then null else jsonb_build_object(
 'id',value->'id','po',value->'po','customer',value->'customer','clientId',value->'clientId','savedAt',value->'savedAt',
 'createdBy',value->'createdBy','updatedBy',value->'updatedBy','deliveryIntakeId',value->'deliveryIntakeId',
 'rows',coalesce((select jsonb_agg(jsonb_build_object('lineId',r->'lineId','item',r->'item','description',r->'description','category',r->'category','plant',r->'plant','pack',r->'pack','size',r->'size',
 'importedProduct',case when jsonb_typeof(r->'importedProduct')='object' then (select jsonb_object_agg(key,val) from jsonb_each(r->'importedProduct') x(key,val) where key in ('item','description','brand','category','family','pack','size','salesUnit','producer','plant')) else null end) order by ord) from jsonb_array_elements(coalesce(value->'rows','[]')) with ordinality x(r,ord)),'[]')) end
$$;
revoke all on function inspection_internal.public_draft(jsonb) from public,anon,authenticated;

-- Migrate by ID, preserving every saved line and its authentic evidence. Abort on ambiguous IDs/numbers.
do $$declare root uuid=inspection_internal.shared_draft_owner(); combined jsonb;doc jsonb;begin
 if root is null then raise exception 'Inspection administrator is not configured';end if;
 if exists(select 1 from public.inspection_po_workspaces w cross join lateral jsonb_array_elements(coalesce(w.workspace->'invoices','[]')) p group by p->>'id' having count(*)>1)
 or exists(select 1 from public.inspection_po_workspaces w cross join lateral jsonb_array_elements(coalesce(w.workspace->'invoices','[]')) p group by lower(btrim(p->>'po')) having count(*)>1) then raise exception 'Existing drafts have duplicate IDs or PO numbers. Review them before centralization.';end if;
 select coalesce(jsonb_agg(p||jsonb_build_object('createdBy',coalesce(nullif(p->'createdBy','null'::jsonb),to_jsonb(w.user_id)),'updatedBy',coalesce(nullif(p->'updatedBy','null'::jsonb),to_jsonb(w.user_id))) order by p->>'savedAt' desc),'[]') into combined
 from public.inspection_po_workspaces w cross join lateral jsonb_array_elements(coalesce(w.workspace->'invoices','[]')) p;
 insert into public.inspection_po_workspaces(user_id) values(root) on conflict do nothing;
 select workspace into doc from public.inspection_po_workspaces where user_id=root for update;
 update public.inspection_po_workspaces set workspace=jsonb_set(doc,'{invoices}',combined),updated_at=clock_timestamp() where user_id=root;
end $$;

drop policy inspection_own_po_workspace on public.inspection_po_workspaces;
create policy inspection_admin_raw_workspace on public.inspection_po_workspaces for select to authenticated
 using(exists(select 1 from public.inspection_admins a where a.user_id=(select auth.uid())));

create function inspection_internal.read_draft_workspace() returns table(workspace jsonb,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare admin boolean;begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 admin=exists(select 1 from public.inspection_admins where user_id=auth.uid());
 return query select case when admin then w.workspace else jsonb_build_object('draft','[]'::jsonb,'invoices',coalesce((select jsonb_agg(inspection_internal.public_draft(p) order by ord) from jsonb_array_elements(w.workspace->'invoices') with ordinality x(p,ord)),'[]')) end,w.updated_at
 from public.inspection_po_workspaces w where user_id=inspection_internal.shared_draft_owner();
end $$;
create function inspection_internal.draft_workspace_stamp() returns table(updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 return query select w.updated_at from public.inspection_po_workspaces w where user_id=inspection_internal.shared_draft_owner();
end $$;
create function public.inspection_read_draft_workspace() returns table(workspace jsonb,updated_at timestamptz) language sql set search_path='' as $$select * from inspection_internal.read_draft_workspace()$$;
create function public.inspection_draft_workspace_stamp() returns table(updated_at timestamptz) language sql set search_path='' as $$select * from inspection_internal.draft_workspace_stamp()$$;
revoke all on function inspection_internal.read_draft_workspace(),inspection_internal.draft_workspace_stamp(),public.inspection_read_draft_workspace(),public.inspection_draft_workspace_stamp() from public,anon,authenticated;
grant execute on function inspection_internal.read_draft_workspace(),inspection_internal.draft_workspace_stamp(),public.inspection_read_draft_workspace(),public.inspection_draft_workspace_stamp() to authenticated;

create function inspection_internal.merge_shared_drafts(actor uuid,current_workspace jsonb,base_value jsonb,next_value jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare admin boolean;current_map jsonb;base_map jsonb;next_map jsonb;ids text[];key text;prior jsonb;basepo jsonb;nextpo jsonb;merged jsonb;rowsout jsonb;line jsonb;oldline jsonb;ord bigint;catalog jsonb;output jsonb;selected_plant jsonb;
begin
 if actor is null or actor is distinct from auth.uid() then raise exception 'Login required' using errcode='42501';end if;
 admin=exists(select 1 from public.inspection_admins where user_id=actor);
 if jsonb_typeof(next_value)<>'object' or jsonb_typeof(next_value->'invoices') is distinct from 'array' or octet_length(next_value::text)>8000000 then raise exception 'Invalid draft workspace';end if;
 if exists(select 1 from jsonb_array_elements(next_value->'invoices') p group by p->>'id' having count(*)>1) then raise exception 'Duplicate draft ID';end if;
 select records->'inspection-data-hub-catalog-overrides-v1' into catalog from public.inspection_official_state where id='official';
 select coalesce(jsonb_object_agg(p->>'id',p),'{}') into current_map from jsonb_array_elements(coalesce(current_workspace->'invoices','[]')) p where not exists(select 1 from public.inspection_approved_pos a where a.po_key=lower(btrim(p->>'po')));
 select coalesce(jsonb_object_agg(p->>'id',p),'{}') into base_map from jsonb_array_elements(coalesce(base_value->'invoices','[]')) p;
 select coalesce(jsonb_object_agg(p->>'id',p),'{}') into next_map from jsonb_array_elements(next_value->'invoices') p;
 select array_agg(k) into ids from (select jsonb_object_keys(base_map) k union select jsonb_object_keys(next_map) k) t;
 foreach key in array coalesce(ids,array[]::text[]) loop
  prior=current_map->key;basepo=base_map->key;nextpo=next_map->key;
  if exists(select 1 from public.inspection_approved_pos a where a.po_key=lower(btrim(coalesce(nextpo->>'po',basepo->>'po')))) then continue;end if;
  if (case when admin then basepo else inspection_internal.public_draft(basepo) end) is not distinct from (case when admin then nextpo else inspection_internal.public_draft(nextpo) end) then continue;end if;
  if prior is not null and not admin and coalesce(prior->>'createdBy','')<>actor::text then raise exception 'You can view all drafts, but only edit or delete drafts you created' using errcode='42501';end if;
  if prior is null and basepo is not null then raise exception 'Draft was removed or approved. Refresh before editing.' using errcode='40001';end if;
  if nextpo is null then
   if (case when admin then prior else inspection_internal.public_draft(prior) end) is distinct from (case when admin then basepo else inspection_internal.public_draft(basepo) end) then raise exception 'Draft changed before deletion. Refresh first.' using errcode='40001';end if;
   current_map=current_map-key;continue;
  end if;
  if admin then merged=inspection_internal.merge_pending(prior,basepo,nextpo);
  else
   merged=inspection_internal.merge_pending(inspection_internal.public_draft(prior),inspection_internal.public_draft(basepo),inspection_internal.public_draft(nextpo));
   rowsout='[]';
   for line,ord in select value,n from jsonb_array_elements(merged->'rows') with ordinality x(value,n) loop
    oldline=null;
    if coalesce(line->>'lineId','')<>'' then select value into oldline from jsonb_array_elements(coalesce(prior->'rows','[]')) where value->>'lineId'=line->>'lineId';end if;
    -- Preserve authentic fields on legacy rows lacking technical line IDs; this does not assign ESTs between different items.
    if oldline is null and prior->'rows'->(ord::integer-1)->>'item'=line->>'item' and coalesce(prior->'rows'->(ord::integer-1)->>'lineId','')='' then oldline=prior->'rows'->(ord::integer-1);end if;
    selected_plant=case when oldline->>'item'=line->>'item' then oldline->'plant' else coalesce(catalog->(line->>'item')->'plant',line->'importedProduct'->'plant','""'::jsonb) end;
    line=coalesce(oldline,'{}')||line||jsonb_build_object('plant',coalesce(selected_plant,'""'::jsonb));
    if oldline is null or oldline->>'item' is distinct from line->>'item' then line=line-array['verifiedAt','verifiedBy','verifiedEsts','changeFrom','changeTo','expectedEst'];end if;
    rowsout=rowsout||jsonb_build_array(line);
   end loop;
   merged=coalesce(prior,'{}')||jsonb_set(merged,'{rows}',rowsout);
  end if;
  if coalesce(length(merged->>'id'),0)=0 or merged->>'id'<>key or coalesce(length(btrim(merged->>'po')),0) not between 1 and 90 or coalesce(length(btrim(merged->>'customer')),0) not between 1 and 120 or jsonb_typeof(merged->'rows') is distinct from 'array' or jsonb_array_length(merged->'rows')>5000 then raise exception 'Invalid PO draft';end if;
  if exists(select 1 from jsonb_array_elements(merged->'rows') r where jsonb_typeof(r)<>'object' or coalesce(length(r->>'item'),0)=0) then raise exception 'Invalid draft Item';end if;
  merged=(merged-array['approvedBy','approvedAt','status'])||jsonb_build_object('createdBy',coalesce(prior->'createdBy',to_jsonb(actor)),'updatedBy',actor);
  current_map=jsonb_set(current_map,array[key],merged);
 end loop;
 if exists(select 1 from jsonb_each(current_map) p group by lower(btrim(p.value->>'po')) having count(*)>1) then raise exception 'That PO number already exists. Open the existing draft or choose a different PO number.' using errcode='23505';end if;
 select coalesce(jsonb_agg(value order by value->>'savedAt' desc),'[]') into output from jsonb_each(current_map);
 if jsonb_array_length(output)>500 or octet_length(output::text)>8000000 then raise exception 'Draft workspace limit reached';end if;
 if next_value ? 'draft' and coalesce(next_value->'draft','[]')<>coalesce(base_value->'draft','[]') and coalesce(next_value->'draft','[]')<>'[]'::jsonb then raise exception 'An old Item-by-Item log is pending. Review that pending send; shared orders must be imported as drafts.';end if;
 return jsonb_set(current_workspace,'{invoices}',output);
end $$;
revoke all on function inspection_internal.merge_shared_drafts(uuid,jsonb,jsonb,jsonb) from public,anon,authenticated;

-- The original queued_commit is patched below: same operation receipts, same catalog permissions and lock order.

create or replace function inspection_internal.notify_draft_upload() returns trigger
language plpgsql security definer set search_path='' as $$
declare draft jsonb; prior jsonb; admin uuid;
begin
 if auth.uid() is null or new.user_id is distinct from inspection_internal.shared_draft_owner() or exists(select 1 from public.inspection_admins where user_id=auth.uid()) then return new;end if;
 for draft in select value from jsonb_array_elements(coalesce(new.workspace->'invoices','[]')) loop
  if coalesce(draft->>'id','')='' or coalesce(draft->>'deliveryIntakeId','')<>'' or jsonb_array_length(coalesce(draft->'rows','[]'))=0 then continue;end if;
  prior=null;if tg_op='UPDATE' then select value into prior from jsonb_array_elements(coalesce(old.workspace->'invoices','[]')) where value->>'id'=draft->>'id';end if;
  if prior is not null and jsonb_array_length(coalesce(prior->'rows','[]'))>0 then continue;end if;
  for admin in select user_id from public.inspection_admins loop perform inspection_internal.enqueue_order_notice('draft:'||(draft->>'createdBy')||':'||(draft->>'id'),'pending',draft->>'po',null,draft->>'customer',admin);end loop;
 end loop;return new;
end $$;

CREATE OR REPLACE FUNCTION inspection_internal.queued_commit(operation_id uuid, base_records jsonb, changed_records jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); s public.inspection_official_state%rowtype; receipt inspection_internal.write_receipts%rowtype; hashed text; changes jsonb='{}'; k text; nextval jsonb; curval jsonb; baseval jsonb; current_map jsonb; base_map jsonb; next_map jsonb; merged_map jsonb; private_workspace jsonb; output jsonb; is_admin boolean; onepo jsonb; oldpo jsonb; authored jsonb; rowsout jsonb; line jsonb; priorline jsonb;
begin
 if uid is null then raise exception 'Login required' using errcode='42501';end if;
 if operation_id is null or jsonb_typeof(base_records)<>'object' or jsonb_typeof(changed_records)<>'object' or octet_length(changed_records::text)>12000000 then raise exception 'Invalid queued operation';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 hashed=md5(jsonb_build_array(base_records,changed_records)::text);
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=queued_commit.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused with different values';end if;return receipt.result;end if;
 select exists(select 1 from public.inspection_admins where user_id=uid) into is_admin;
 if not is_admin and exists(select 1 from jsonb_object_keys(changed_records) key where key<>'inspection-data-hub-po-workspace-v1') then raise exception 'Only administrator may modify catalog, EST, brands or photos' using errcode='42501';end if;
 -- Same lock order as approval: official state, then user workspace.
 select * into s from public.inspection_official_state where id='official' for update;
 for k in select jsonb_object_keys(changed_records) loop
  baseval=base_records->k;nextval=changed_records->k;
  if k='inspection-data-hub-po-workspace-v1' then
   insert into public.inspection_po_workspaces(user_id) values(inspection_internal.shared_draft_owner()) on conflict do nothing;
   select w.workspace into curval from public.inspection_po_workspaces w where user_id=inspection_internal.shared_draft_owner() for update;
   private_workspace=inspection_internal.merge_shared_drafts(uid,curval,baseval,nextval);
   if private_workspace is distinct from curval then update public.inspection_po_workspaces w set workspace=private_workspace,updated_at=clock_timestamp() where user_id=inspection_internal.shared_draft_owner();end if;
  else
   curval=s.records->k;nextval=inspection_internal.merge_pending(curval,baseval,nextval);
   changes=jsonb_set(changes,array[k],coalesce(nextval,'null'));
  end if;
 end loop;
 if changes<>'{}'::jsonb then perform public.inspection_commit(s.revision,changes);select revision into s.revision from public.inspection_official_state where id='official';end if;
 output=jsonb_build_object('revision',s.revision,'operation_id',operation_id);
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,output);
 return output;
end $function$
