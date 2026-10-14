-- Rollback-only fixtures. No products or physical observations are created.
begin;
select set_config('request.headers',jsonb_build_object('x-inspection-catalog-generation',(select records->'inspection-data-hub-catalog-import-v1'->>'generation' from public.inspection_official_state where id='official'))::text,true);
select set_config('inspection.test_admin',(select user_id::text from public.inspection_admins a join auth.users u on u.id=a.user_id where lower(u.email)='david.rodriguez@hapcor.com'),true);
select set_config('inspection.test_user',(select id::text from auth.users where lower(email)='ariadna.cabeza@hapcor.com'),true);
select set_config('inspection.test_id','shared-test-'||gen_random_uuid(),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('inspection.test_user'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare p jsonb;w jsonb;other jsonb;latest jsonb;operation uuid=gen_random_uuid();body jsonb;outcome jsonb;po_key text='inspection-data-hub-po-workspace-v1';begin
 p=jsonb_build_object('id',current_setting('inspection.test_id'),'po','000-SHARED-FIXTURE','customer','Shared workflow fixture','savedAt',clock_timestamp(),'createdBy',current_setting('inspection.test_admin'),'rows',jsonb_build_array(jsonb_build_object('lineId','fixture-line','item','000-FIXTURE-ITEM','description','Fixture','plant','TEST-EST','importedProduct',jsonb_build_object('plant','TEST-EST'),'verifiedAt','FORGED','verifiedBy','FORGED','verifiedEsts',jsonb_build_array('FORGED'))));
 body=jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(p)));
 outcome=public.inspection_queued_commit(operation,'{}',body);
 if public.inspection_queued_commit(operation,'{}',body)<>outcome then raise exception 'Queued retry was not idempotent';end if;
 select workspace into w from public.inspection_read_draft_workspace();
 select value into latest from jsonb_array_elements(w->'invoices') where value->>'id'=p->>'id';
 if latest->>'createdBy'<>auth.uid()::text or w::text~'FORGED|verifiedAt|verifiedBy|verifiedEsts|expectedEst|changeFrom|changeTo' then raise exception 'Creator spoof or verification leak';end if;
 select value into other from jsonb_array_elements(w->'invoices') where value->>'createdBy'=current_setting('inspection.test_admin') limit 1;
 begin perform public.inspection_queued_commit(gen_random_uuid(),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(other))),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(jsonb_set(other,'{customer}','"Forbidden edit"')))));raise exception 'Foreign draft edit was allowed';exception when insufficient_privilege then null;end;
 begin perform public.inspection_approve_po(gen_random_uuid(),p->>'id',latest);raise exception 'Normal approval was allowed';exception when insufficient_privilege then null;end;
 begin perform public.inspection_queued_commit(gen_random_uuid(),'{}',jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(jsonb_set(p,'{id}','"different-fixture-id"')))));raise exception 'Duplicate number was allowed';exception when unique_violation then null;end;
 perform public.inspection_queued_commit(gen_random_uuid(),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(latest))),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(jsonb_set(latest,'{rows,0,description}','"Updated fixture"')))));
 begin perform public.inspection_queued_commit(gen_random_uuid(),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(latest))),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(jsonb_set(latest,'{rows,0,description}','"Stale fixture"')))));raise exception 'Stale edit was allowed';exception when serialization_failure then null;end;
 select workspace into w from public.inspection_read_draft_workspace();select value into latest from jsonb_array_elements(w->'invoices') where value->>'id'=p->>'id';
 perform public.inspection_queued_commit(gen_random_uuid(),jsonb_build_object(po_key,jsonb_build_object('invoices',jsonb_build_array(latest))),jsonb_build_object(po_key,jsonb_build_object('invoices','[]'::jsonb)));
 select workspace into w from public.inspection_read_draft_workspace();if exists(select 1 from jsonb_array_elements(w->'invoices') x where x->>'id'=p->>'id') then raise exception 'Own draft deletion failed';end if;
 perform public.inspection_queued_commit(gen_random_uuid(),'{}',body);
 if (select count(*) from public.inspection_po_workspaces)<>0 then raise exception 'Raw workspace visible to normal user';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('inspection.test_admin'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare w jsonb;p jsonb;outcome jsonb;begin
 select workspace into w from public.inspection_read_draft_workspace();select value into p from jsonb_array_elements(w->'invoices') where value->>'id'=current_setting('inspection.test_id');
 if p is null or p->>'createdBy'<>current_setting('inspection.test_user') or p::text like '%FORGED%' then raise exception 'Admin cannot see creator draft, or forged evidence was retained';end if;
 outcome=public.inspection_approve_po(gen_random_uuid(),p->>'id',p);
 select workspace into w from public.inspection_read_draft_workspace();if exists(select 1 from jsonb_array_elements(w->'invoices') x where x->>'id'=p->>'id') then raise exception 'Approved draft was not retired';end if;
 if not exists(select 1 from jsonb_array_elements(public.inspection_read_approved_pos()) x where x->>'id'=outcome->>'id' and x->'snapshot'->>'id'=p->>'id') then raise exception 'Shared draft approval failed';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('inspection.test_user'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare w jsonb;a jsonb;begin
 a=public.inspection_read_approved_pos();if a::text~'verifiedAt|verifiedBy|verifiedEsts|changeFrom|changeTo' or not exists(select 1 from jsonb_array_elements(a) x where x->'snapshot'->>'id'=current_setting('inspection.test_id')) then raise exception 'Approved PO not visible safely to normal user';end if;
 select workspace into w from public.inspection_read_draft_workspace();if exists(select 1 from jsonb_array_elements(w->'invoices') x where x->>'id'=current_setting('inspection.test_id')) then raise exception 'Normal view still contains approved draft';end if;
end $$;
reset role;
rollback;
select 'PASS: shared create/read, actual creator attribution, no evidence forgery/leak, foreign edit denial, normal approval denial, duplicate number rejection, idempotent retry, stale edit rejection, own deletion and cross-account administrator approval; fixtures rolled back' as result;
