begin;
do $$
declare before_hash text=(select md5(records::text) from public.inspection_official_state where id='official'); uid uuid; is_admin boolean; state jsonb; c jsonb; approved jsonb; drafts jsonb; d jsonb; a record;
begin
 for a in select u.id,exists(select 1 from public.inspection_admins x where x.user_id=u.id) admin from auth.users u where lower(u.email) in ('david.rodriguez@hapcor.com','ariadna.cabeza@hapcor.com') loop
  uid=a.id;is_admin=a.admin;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  state=public.inspection_read_official_state()->0->'records';
  c=public.inspection_read_catalog();approved=public.inspection_read_approved_pos();
  select workspace into drafts from public.inspection_read_draft_workspace();
  if not is_admin then
   if state ?| array['inspection-data-hub-observations-v1','inspection-data-hub-po-observations-v1','inspection-data-hub-initial-review-v1'] then raise exception 'Private inspection domain leaked';end if;
   if exists(select 1 from jsonb_each(state->'inspection-data-hub-est-references-v1') where value ? 'trend') or exists(select 1 from jsonb_each(c->'references') where value ? 'trend') then raise exception 'Reference trend leaked';end if;
   if approved::text~'"(verifiedAt|verifiedEsts|verifiedBy|verified_by|changeFrom|changeTo|observations)"' or drafts::text~'"(verifiedAt|verifiedEsts|verifiedBy|verified_by|changeFrom|changeTo|observations)"' then raise exception 'Snapshot evidence leaked';end if;
   for d in select to_jsonb(id) from public.inspection_approved_pos loop
    if public.inspection_read_deliveries((d#>>'{}')::uuid)::text~'"(verifiedAt|verifiedEsts|verifiedBy|verified_by|changeFrom|changeTo|observations)"' then raise exception 'Delivery evidence leaked';end if;
   end loop;
   if has_column_privilege('authenticated','public.inspection_approved_pos','snapshot','select') or has_column_privilege('authenticated','public.inspection_deliveries','po_snapshot','select') then raise exception 'Private snapshot direct read enabled';end if;
  elsif not state ? 'inspection-data-hub-observations-v1' then raise exception 'Administrator internal evidence was lost';end if;
  execute 'reset role';
 end loop;
 if (select md5(records::text) from public.inspection_official_state where id='official')<>before_hash then raise exception 'Stored official records changed';end if;
end $$;
rollback;
select 'PASS: normal APIs contain no observations, markers or reference trends; admin internal evidence and official records retained; snapshot direct reads remain blocked.' as result;