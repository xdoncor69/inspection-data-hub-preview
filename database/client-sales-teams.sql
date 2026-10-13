-- Applied migration: client_sales_teams_and_safe_deletion. Do not rerun blindly.
-- Deleted clients retain historical identity; no assigned teams were inferred.
alter table public.inspection_clients add column sales_team text, add column deleted_at timestamptz;
alter table public.inspection_clients add constraint inspection_clients_sales_team_check check (sales_team is null or sales_team in ('1','2','3','4','5','6','7','CSR1'));
drop index public.inspection_clients_normalized_name;
create unique index inspection_clients_normalized_name on public.inspection_clients (lower(regexp_replace(btrim(name),'[[:space:]]+',' ','g'))) where deleted_at is null;
create policy clients_active_read on public.inspection_clients as restrictive for select to authenticated using (deleted_at is null);
create function inspection_internal.manage_client_v2(operation_id uuid, client_id uuid, client_name text, sales_team text, delete_client boolean default false, expected_client jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); old public.inspection_clients%rowtype; result jsonb; receipt inspection_internal.write_receipts%rowtype;
hashed text=md5(jsonb_build_array('client-v2',client_id,client_name,sales_team,delete_client,expected_client)::text);
begin
 if uid is null or not exists(select 1 from public.inspection_admins where user_id=uid) then raise exception 'Administrator required' using errcode='42501';end if;
 if operation_id is null then raise exception 'Operation ID required';end if;
 if not delete_client and (coalesce(length(btrim(client_name)),0) not between 1 and 120 or sales_team is null or sales_team not in ('1','2','3','4','5','6','7','CSR1')) then raise exception 'Client name and a valid Sales team are required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||operation_id::text,0));
 select * into receipt from inspection_internal.write_receipts where user_id=uid and write_receipts.operation_id=manage_client_v2.operation_id;
 if found then if receipt.payload_hash<>hashed then raise exception 'Operation ID reused';end if;return receipt.result;end if;
 if client_id is null then
  if delete_client then raise exception 'Client required';end if;
  insert into public.inspection_clients(name,sales_team,updated_by) values(btrim(client_name),sales_team,uid) returning to_jsonb(inspection_clients.*) into result;
 else
  select * into old from public.inspection_clients where id=client_id for update;
  if not found or old.deleted_at is not null or to_jsonb(old) is distinct from expected_client then raise exception 'Client changed. Refresh first.' using errcode='40001';end if;
  if delete_client then
   update public.inspection_clients set deleted_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by=uid where id=client_id returning to_jsonb(inspection_clients.*) into result;
  else
   update public.inspection_clients set name=btrim(client_name),sales_team=manage_client_v2.sales_team,updated_at=clock_timestamp(),updated_by=uid where id=client_id returning to_jsonb(inspection_clients.*) into result;
  end if;
 end if;
 insert into inspection_internal.write_receipts(user_id,operation_id,payload_hash,result) values(uid,operation_id,hashed,result);
 return result;
end $$;
revoke all on function inspection_internal.manage_client_v2(uuid,uuid,text,text,boolean,jsonb) from public,anon;
grant execute on function inspection_internal.manage_client_v2(uuid,uuid,text,text,boolean,jsonb) to authenticated;
create function public.inspection_manage_client_v2(operation_id uuid,client_id uuid,client_name text,sales_team text,delete_client boolean default false,expected_client jsonb default null)
returns jsonb language sql set search_path='' as $$ select inspection_internal.manage_client_v2(operation_id,client_id,client_name,sales_team,delete_client,expected_client) $$;
revoke all on function public.inspection_manage_client_v2(uuid,uuid,text,text,boolean,jsonb) from public,anon;
grant execute on function public.inspection_manage_client_v2(uuid,uuid,text,text,boolean,jsonb) to authenticated;
