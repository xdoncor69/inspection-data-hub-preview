-- All fixtures are rolled back. No products, inspections, or live notifications are retained.
begin;
select set_config('request.headers',jsonb_build_object('x-inspection-catalog-generation',(select records->'inspection-data-hub-catalog-import-v1'->>'generation' from public.inspection_official_state where id='official'))::text,true);
do $$
declare normal_id uuid; admin_id uuid; draft_id text='notification-test-'||gen_random_uuid(); event_count integer; aid uuid=gen_random_uuid(); iid uuid=gen_random_uuid(); customer_id uuid; snapshot jsonb;
begin
 select id into normal_id from auth.users where lower(email)='ariadna.cabeza@hapcor.com';
 select user_id into admin_id from public.inspection_admins limit 1;
 select id into customer_id from public.inspection_clients where deleted_at is null limit 1;
 update public.inspection_po_workspaces set workspace=jsonb_set(workspace,'{invoices}',coalesce(workspace->'invoices','[]')||jsonb_build_array(jsonb_build_object('id',draft_id,'po','000-PUSH-TEST','customer','Notification fixture','rows',jsonb_build_array(jsonb_build_object('item','fixture'))))) where user_id=normal_id;
 update public.inspection_po_workspaces set updated_at=clock_timestamp() where user_id=normal_id;
 select count(*) into event_count from public.inspection_notifications where recipient_id=admin_id and event_key='draft:'||normal_id||':'||draft_id;
 if event_count<>1 then raise exception 'Draft notice must be generated once, got %',event_count;end if;
 if exists(select 1 from public.inspection_notifications where event_key='draft:'||normal_id||':'||draft_id and (body not like '%000-PUSH-TEST%' or body not like '%Notification fixture%')) then raise exception 'Draft notice missing reference';end if;
 insert into public.inspection_delivery_intakes(id,created_by,administrator_id,po_number,client_id,customer_name,delivery_number,source_file,source_path,source_rows,draft_id,payload_hash,has_supplied_po)
 values(iid,normal_id,admin_id,'D000-DELIVERY',customer_id,'Notification fixture','000-DELIVERY','fixture.xls','fixture',jsonb_build_array(jsonb_build_object('item','fixture')),draft_id,'fixture',false);
 if not exists(select 1 from public.inspection_notifications where event_key='intake:'||iid and po_number is null and delivery_number='000-DELIVERY') then raise exception 'Delivery-only pending notice failed';end if;
 snapshot=jsonb_build_object('id',draft_id,'po','D000-DELIVERY','customer','Notification fixture','rows',jsonb_build_array(jsonb_build_object('item','fixture','plant','fixture')));
 insert into public.inspection_approved_pos(id,po_key,snapshot,approved_by,approved_email) values(aid,'notification-fixture-'||aid,snapshot,admin_id,'fixture');
 update public.inspection_delivery_intakes set approved_po_id=aid where id=iid;
 insert into public.inspection_deliveries(approved_po_id,delivery_number,source_file,rows,po_snapshot,updated_by,updated_email)
 values(aid,'000-DELIVERY','fixture.xls',jsonb_build_array(jsonb_build_object('item','fixture','receivedQuantity','','match_status','matched')),snapshot,admin_id,'fixture');
 set constraints all immediate;
 if not exists(select 1 from public.inspection_notifications where event_key like 'approved:'||aid||':%' and recipient_id=normal_id and po_number is null and delivery_number='000-DELIVERY' and body like '%Notification fixture%') then raise exception 'Combined approval notice did not resolve delivery-only reference';end if;
 if exists(select 1 from public.inspection_notifications where event_key like 'delivery:%' and delivery_number='000-DELIVERY') then raise exception 'Combined approval emitted duplicate delivery notice';end if;
end $$;
rollback;
select 'PASS: pending draft deduplication, delivery-only naming, approval with associated delivery, no duplicate notification; fixtures rolled back' as result;
