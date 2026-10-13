-- Applied incrementally: retain imported EST / Plant suggestions for unknown Items in private drafts.
-- Existing catalog values and prior draft selections retain precedence. No catalog writes or physical verifications are created.
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
   insert into public.inspection_po_workspaces(user_id) values(uid) on conflict do nothing;
   select w.workspace into curval from public.inspection_po_workspaces w where user_id=uid for update;
   select coalesce(jsonb_object_agg(value->>'id',value),'{}') into current_map from jsonb_array_elements(coalesce(curval->'invoices','[]'));
   select coalesce(jsonb_object_agg(value->>'id',value),'{}') into base_map from jsonb_array_elements(coalesce(baseval->'invoices','[]'));
   select coalesce(jsonb_object_agg(value->>'id',value),'{}') into next_map from jsonb_array_elements(coalesce(nextval->'invoices','[]'));
   -- A delayed device job must never recreate a draft replaced by an approved PO.
   select coalesce(jsonb_object_agg(key,value),'{}') into current_map from jsonb_each(current_map) where not exists(select 1 from public.inspection_approved_pos a where a.po_key=lower(btrim(value->>'po')));
   select coalesce(jsonb_object_agg(key,value),'{}') into base_map from jsonb_each(base_map) where not exists(select 1 from public.inspection_approved_pos a where a.po_key=lower(btrim(value->>'po')));
   select coalesce(jsonb_object_agg(key,value),'{}') into next_map from jsonb_each(next_map) where not exists(select 1 from public.inspection_approved_pos a where a.po_key=lower(btrim(value->>'po')));
   merged_map=inspection_internal.merge_pending(current_map,base_map,next_map);
   authored='[]';
   for onepo in select value from jsonb_each(merged_map) order by value->>'savedAt' desc loop
    if coalesce(length(onepo->>'id'),0)=0 or coalesce(length(btrim(onepo->>'po')),0)=0 or coalesce(length(btrim(onepo->>'customer')),0)=0 or jsonb_typeof(onepo->'rows')<>'array' or jsonb_array_length(onepo->'rows')>5000 then raise exception 'Invalid PO draft';end if;
    select value into oldpo from jsonb_array_elements(curval->'invoices') where value->>'id'=onepo->>'id';
    rowsout='[]';
    for line in select value from jsonb_array_elements(onepo->'rows') loop
     if jsonb_typeof(line)<>'object' or coalesce(length(line->>'item'),0)=0 then raise exception 'Invalid draft Item';end if;
     if not is_admin then
      select value into priorline from jsonb_array_elements(coalesce(oldpo->'rows','[]')) where value->>'item'=line->>'item';
      line=(line-array['verifiedAt','verifiedEsts','changeFrom','changeTo','expectedEst'])||jsonb_build_object('plant',coalesce(priorline->'plant',s.records->'inspection-data-hub-catalog-overrides-v1'->(line->>'item')->'plant',case when not (coalesce(s.records->'inspection-data-hub-catalog-overrides-v1','{}'::jsonb) ? (line->>'item')) then to_jsonb(nullif(line->'importedProduct'->>'plant','')) end,'""'),'verifiedAt',coalesce(priorline->'verifiedAt','""'),'verifiedEsts',coalesce(priorline->'verifiedEsts','[]'),'expectedEst',coalesce(priorline->'expectedEst',s.records->'inspection-data-hub-catalog-overrides-v1'->(line->>'item')->'plant',case when not (coalesce(s.records->'inspection-data-hub-catalog-overrides-v1','{}'::jsonb) ? (line->>'item')) then to_jsonb(nullif(line->'importedProduct'->>'plant','')) end,'""'));
     end if;
     rowsout=rowsout||jsonb_build_array(line);
    end loop;
    onepo=jsonb_set(onepo,'{rows}',rowsout);
    onepo=(onepo-array['approvedBy','approvedAt','status'])||jsonb_build_object('createdBy',coalesce(oldpo->'createdBy',to_jsonb(uid)),'updatedBy',uid);
    authored=authored||jsonb_build_array(onepo);
   end loop;
   if jsonb_array_length(authored)>500 then raise exception 'Too many drafts';end if;
   if exists(select 1 from jsonb_array_elements(authored) p group by lower(btrim(p->>'po')) having count(*)>1) then raise exception 'Duplicate draft PO number';end if;
   private_workspace=jsonb_build_object('invoices',authored,'draft',coalesce(inspection_internal.merge_pending(curval->'draft',baseval->'draft',nextval->'draft'),'[]'));
   if jsonb_typeof(private_workspace->'draft')<>'array' or jsonb_array_length(private_workspace->'draft')>5000 or octet_length(private_workspace::text)>8000000 then raise exception 'Invalid draft workspace';end if;
   update public.inspection_po_workspaces w set workspace=private_workspace,updated_at=clock_timestamp() where user_id=uid;
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
;
