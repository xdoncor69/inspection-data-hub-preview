-- Reference for migrations already applied to kyhecrvsllableoymqfe. Do not run blindly.
-- Signing and worker secrets were generated separately and stored in Vault. No secret values are in this file.
-- Incremental notification infrastructure. No historical backfill or inspection data changes.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

create table inspection_internal.push_settings (
 singleton boolean primary key default true check(singleton),
 certificate_user_id uuid references auth.users(id),
 public_key text not null
);
alter table inspection_internal.push_settings enable row level security;

create table public.inspection_push_subscriptions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null unique check(length(endpoint) between 20 and 4096),
 subscription jsonb not null,
 device_label text not null default '',
 enabled boolean not null default true,
 activated_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
create index inspection_push_owner_idx on public.inspection_push_subscriptions(user_id);
alter table public.inspection_push_subscriptions enable row level security;
create policy push_own_read on public.inspection_push_subscriptions for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.inspection_push_subscriptions from public,anon,authenticated;
grant select on public.inspection_push_subscriptions to authenticated;
revoke all on public.inspection_push_subscriptions from anon;

create table public.inspection_notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 event_key text not null,
 kind text not null check(kind in ('pending','approved','delivery')),
 title text not null,
 body text not null,
 po_number text,
 delivery_number text,
 customer_name text not null,
 created_at timestamptz not null default clock_timestamp(),
 dismissed_at timestamptz,
 unique(recipient_id,event_key)
);
create index inspection_notifications_owner_idx on public.inspection_notifications(recipient_id,created_at desc);
alter table public.inspection_notifications enable row level security;
create policy notification_own_read on public.inspection_notifications for select to authenticated using(recipient_id=(select auth.uid()));
revoke all on public.inspection_notifications from public,anon,authenticated;
grant select on public.inspection_notifications to authenticated;
revoke all on public.inspection_notifications from anon;

create table inspection_internal.push_deliveries (
 notification_id uuid not null references public.inspection_notifications(id) on delete cascade,
 subscription_id uuid not null references public.inspection_push_subscriptions(id) on delete cascade,
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default clock_timestamp(),
 lease_id uuid,
 lease_until timestamptz,
 sent_at timestamptz,
 last_status integer,
 primary key(notification_id,subscription_id)
);
alter table inspection_internal.push_deliveries enable row level security;
revoke all on inspection_internal.push_settings,inspection_internal.push_deliveries from public,anon,authenticated;

create function inspection_internal.push_eligible(uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select uid is not null and (exists(select 1 from public.inspection_admins a where a.user_id=uid)
 or exists(select 1 from inspection_internal.push_settings s where s.certificate_user_id=uid))
$$;
revoke all on function inspection_internal.push_eligible(uuid) from public,anon,authenticated;

create function inspection_internal.push_status() returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); admin boolean;
begin
 if uid is null then raise exception 'Login required' using errcode='42501';end if;
 admin=exists(select 1 from public.inspection_admins where user_id=uid);
 return jsonb_build_object('eligible',inspection_internal.push_eligible(uid),'administrator',admin,
 'role',case when admin then 'administrator' when inspection_internal.push_eligible(uid) then 'certificates' else 'none' end,
 'publicKey',(select public_key from inspection_internal.push_settings),
 'devices',coalesce((select jsonb_agg(jsonb_build_object('endpoint',endpoint,'enabled',enabled,'label',device_label)) from public.inspection_push_subscriptions where user_id=uid),'[]'),
 'certificateUser',case when admin then (select certificate_user_id from inspection_internal.push_settings) else null end,
 'accounts',case when admin then coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'name',coalesce(nullif(p.display_name,''),p.email),'email',p.email) order by p.email) from public.inspection_profiles p join auth.users u on u.id=p.user_id),'[]') else '[]'::jsonb end);
end $$;

create function inspection_internal.push_subscribe(subscription jsonb,device_label text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); endpoint text=subscription->>'endpoint'; existing public.inspection_push_subscriptions%rowtype;
begin
 if not inspection_internal.push_eligible(uid) then raise exception 'Order notifications are available to the administrator and certificate preparer' using errcode='42501';end if;
 if jsonb_typeof(subscription) is distinct from 'object' or octet_length(subscription::text)>8192
 or endpoint !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-zA-Z0-9.-]+[.]push[.]apple[.]com|[a-zA-Z0-9.-]+[.]notify[.]windows[.]com)/[^[:space:]]+$'
 or coalesce(subscription->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$'
 or coalesce(subscription->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{22}={0,2}$'
 then raise exception 'Unsupported or invalid push subscription';end if;
 perform pg_advisory_xact_lock(hashtextextended(endpoint,0));
 select * into existing from public.inspection_push_subscriptions s where s.endpoint=push_subscribe.endpoint;
 if found and existing.user_id<>uid then raise exception 'This browser subscription belongs to another account. Disable it before switching accounts.' using errcode='42501';end if;
 insert into public.inspection_push_subscriptions(user_id,endpoint,subscription,device_label)
 values(uid,endpoint,subscription,left(device_label,80))
 on conflict(endpoint) do update set subscription=excluded.subscription,device_label=excluded.device_label,enabled=true,
 activated_at=case when inspection_push_subscriptions.enabled then inspection_push_subscriptions.activated_at else clock_timestamp() end,updated_at=clock_timestamp();
 return jsonb_build_object('enabled',true);
end $$;

create function inspection_internal.push_disable(endpoint text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 update public.inspection_push_subscriptions s set enabled=false,updated_at=clock_timestamp() where s.user_id=auth.uid() and s.endpoint=push_disable.endpoint;
 return jsonb_build_object('enabled',false);
end $$;

create function inspection_internal.notification_close(notification_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 update public.inspection_notifications set dismissed_at=clock_timestamp() where id=notification_id and recipient_id=auth.uid();
end $$;

create function inspection_internal.notification_inbox() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 if not inspection_internal.push_eligible(auth.uid()) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(n) order by created_at desc) from (select id,kind,title,body,po_number,delivery_number,customer_name,created_at from public.inspection_notifications where recipient_id=auth.uid() and dismissed_at is null order by created_at desc limit 100) n),'[]');
end $$;

create function inspection_internal.notification_set_certificate_user(user_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.inspection_admins where inspection_admins.user_id=auth.uid()) then raise exception 'Administrator permission required' using errcode='42501';end if;
 if user_id is not null and not exists(select 1 from auth.users u join public.inspection_profiles p on p.user_id=u.id where u.id=notification_set_certificate_user.user_id) then raise exception 'Choose an existing account';end if;
 update inspection_internal.push_settings set certificate_user_id=notification_set_certificate_user.user_id;
 update public.inspection_push_subscriptions s set enabled=false where not inspection_internal.push_eligible(s.user_id);
end $$;

create function public.inspection_push_status() returns jsonb language sql set search_path='' as $$select inspection_internal.push_status()$$;
create function public.inspection_push_subscribe(subscription jsonb,device_label text default '') returns jsonb language sql set search_path='' as $$select inspection_internal.push_subscribe(subscription,device_label)$$;
create function public.inspection_push_disable(endpoint text) returns jsonb language sql set search_path='' as $$select inspection_internal.push_disable(endpoint)$$;
create function public.inspection_notification_close(notification_id uuid) returns void language sql set search_path='' as $$select inspection_internal.notification_close(notification_id)$$;
create function public.inspection_notification_inbox() returns jsonb language sql set search_path='' as $$select inspection_internal.notification_inbox()$$;
create function public.inspection_notification_set_certificate_user(user_id uuid) returns void language sql set search_path='' as $$select inspection_internal.notification_set_certificate_user(user_id)$$;

create function inspection_internal.enqueue_order_notice(event_key text,kind text,po text,delivery text,customer text,recipient uuid) returns void
language plpgsql security definer set search_path='' as $$
declare ids text=concat_ws(' · ',case when nullif(po,'') is not null then 'PO '||po end,case when nullif(delivery,'') is not null then 'Delivery '||delivery end);
begin
 if recipient is null then return;end if;
 insert into public.inspection_notifications(recipient_id,event_key,kind,title,body,po_number,delivery_number,customer_name)
 values(recipient,event_key,kind,case when kind='pending' then 'Pending approval' when kind='approved' then 'Approved · ready to process' else 'Delivery available · ready to process' end,
 ids||' · '||coalesce(customer,'')||' — '||case when kind='pending' then 'pending approval' when kind='approved' then 'approved, ready to process' else 'available with approved PO ESTs, ready to process' end,nullif(po,''),nullif(delivery,''),coalesce(customer,''))
 on conflict(recipient_id,event_key) do nothing;
end $$;

create function inspection_internal.notify_draft_upload() returns trigger
language plpgsql security definer set search_path='' as $$
declare draft jsonb; prior jsonb; admin uuid;
begin
 if exists(select 1 from public.inspection_admins where user_id=new.user_id) then return new;end if;
 for draft in select value from jsonb_array_elements(coalesce(new.workspace->'invoices','[]')) loop
  if coalesce(draft->>'id','')='' or coalesce(draft->>'deliveryIntakeId','')<>'' or jsonb_array_length(coalesce(draft->'rows','[]'))=0 then continue;end if;
  prior=null;if tg_op='UPDATE' then select value into prior from jsonb_array_elements(coalesce(old.workspace->'invoices','[]')) where value->>'id'=draft->>'id';end if;
  if prior is not null and jsonb_array_length(coalesce(prior->'rows','[]'))>0 then continue;end if;
  for admin in select user_id from public.inspection_admins loop
   perform inspection_internal.enqueue_order_notice('draft:'||new.user_id||':'||(draft->>'id'),'pending',draft->>'po',null,draft->>'customer',admin);
  end loop;
 end loop;return new;
end $$;
create trigger inspection_notify_draft_upload after insert or update on public.inspection_po_workspaces for each row execute function inspection_internal.notify_draft_upload();

create function inspection_internal.notify_intake_upload() returns trigger
language plpgsql security definer set search_path='' as $$
declare shown_po text=new.po_number;
begin
 -- The existing intake workflow uses D + delivery as an internal placeholder when no PO was supplied.
 if shown_po='D'||new.delivery_number then shown_po=null;end if;
 perform inspection_internal.enqueue_order_notice('intake:'||new.id,'pending',shown_po,new.delivery_number,new.customer_name,new.administrator_id);return new;
end $$;
create trigger inspection_notify_intake_upload after insert on public.inspection_delivery_intakes for each row execute function inspection_internal.notify_intake_upload();

create function inspection_internal.notify_po_approval() returns trigger
language plpgsql security definer set search_path='' as $$
declare recipient uuid; delivery text; po text=new.snapshot->>'po';
begin
 if tg_op='UPDATE' and new.approved_at is not distinct from old.approved_at then return new;end if;
 select certificate_user_id into recipient from inspection_internal.push_settings;
 select d.delivery_number into delivery from public.inspection_deliveries d where d.approved_po_id=new.id and d.po_snapshot=new.snapshot
 and not exists(select 1 from jsonb_array_elements(d.rows) r where coalesce(nullif(r->>'receivedQuantity','')::numeric,1)<>0 and coalesce(r->>'match_status','')<>'matched') order by d.updated_at desc limit 1;
 if exists(select 1 from public.inspection_delivery_intakes i where i.approved_po_id=new.id and i.po_number='D'||i.delivery_number) then po=null;end if;
 perform inspection_internal.enqueue_order_notice('approved:'||new.id||':'||new.approved_at::text,'approved',po,delivery,new.snapshot->>'customer',recipient);return new;
end $$;
-- Deferred: a delivery-first approval creates its associated delivery in the same transaction.
create constraint trigger inspection_notify_po_approval after insert or update on public.inspection_approved_pos deferrable initially deferred for each row execute function inspection_internal.notify_po_approval();

create function inspection_internal.notify_delivery_ready() returns trigger
language plpgsql security definer set search_path='' as $$
declare a public.inspection_approved_pos%rowtype; recipient uuid; po text;
begin
 select * into a from public.inspection_approved_pos where id=new.approved_po_id;
 if not found or a.snapshot is distinct from new.po_snapshot or a.approved_at>=transaction_timestamp() then return new;end if;
 if exists(select 1 from jsonb_array_elements(new.rows) r where coalesce(nullif(r->>'receivedQuantity','')::numeric,1)<>0 and coalesce(r->>'match_status','')<>'matched') then return new;end if;
 if tg_op='UPDATE' and old.rows=new.rows and old.po_snapshot=new.po_snapshot and old.source_path is not distinct from new.source_path then return new;end if;
 select certificate_user_id into recipient from inspection_internal.push_settings;po=a.snapshot->>'po';
 if exists(select 1 from public.inspection_delivery_intakes i where i.approved_po_id=a.id and i.po_number='D'||i.delivery_number) then po=null;end if;
 perform inspection_internal.enqueue_order_notice('delivery:'||new.id||':'||new.updated_at::text,'delivery',po,new.delivery_number,a.snapshot->>'customer',recipient);return new;
end $$;
create constraint trigger inspection_notify_delivery_ready after insert or update on public.inspection_deliveries deferrable initially deferred for each row execute function inspection_internal.notify_delivery_ready();

create function inspection_internal.push_worker_config() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Worker only' using errcode='42501';end if;
 return jsonb_build_object('publicKey',(select public_key from inspection_internal.push_settings),
 'privateKey',(select decrypted_secret from vault.decrypted_secrets where name='inspection_push_vapid_private'),
 'workerSecret',(select decrypted_secret from vault.decrypted_secrets where name='inspection_push_worker_secret'));
end $$;

create function inspection_internal.push_claim_jobs() returns jsonb
language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Worker only' using errcode='42501';end if;
 insert into inspection_internal.push_deliveries(notification_id,subscription_id)
 select n.id,s.id from public.inspection_notifications n join public.inspection_push_subscriptions s on s.user_id=n.recipient_id and s.enabled
 where n.dismissed_at is null and n.created_at>=s.activated_at and n.created_at>clock_timestamp()-interval '1 day' and inspection_internal.push_eligible(s.user_id)
 on conflict do nothing;
 with picked as (select d.notification_id,d.subscription_id from inspection_internal.push_deliveries d
 join public.inspection_push_subscriptions s on s.id=d.subscription_id and s.enabled
 join public.inspection_notifications n on n.id=d.notification_id and n.dismissed_at is null
 where d.sent_at is null and d.attempts<8 and d.next_attempt_at<=clock_timestamp() and (d.lease_until is null or d.lease_until<clock_timestamp()) and inspection_internal.push_eligible(s.user_id)
 order by d.next_attempt_at for update of d skip locked limit 30),
 claimed as (update inspection_internal.push_deliveries d set attempts=d.attempts+1,lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes' from picked p where d.notification_id=p.notification_id and d.subscription_id=p.subscription_id returning d.*)
 select coalesce(jsonb_agg(jsonb_build_object('notificationId',d.notification_id,'subscriptionId',d.subscription_id,'leaseId',d.lease_id,'subscription',s.subscription,'payload',jsonb_build_object('id',n.id,'recipient',n.recipient_id,'title',n.title,'body',n.body,'po',n.po_number,'delivery',n.delivery_number,'customer',n.customer_name))), '[]') into jobs
 from claimed d join public.inspection_push_subscriptions s on s.id=d.subscription_id join public.inspection_notifications n on n.id=d.notification_id;
 return jobs;
end $$;

create function inspection_internal.push_finish_job(notification_id uuid,subscription_id uuid,lease_id uuid,status integer) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Worker only' using errcode='42501';end if;
 update inspection_internal.push_deliveries d set sent_at=case when status between 200 and 299 or status in (404,410) then clock_timestamp() else null end,
 last_status=status,lease_until=null,next_attempt_at=clock_timestamp()+make_interval(secs=>least(3600,30*(2^least(d.attempts,7))::integer))
 where d.notification_id=push_finish_job.notification_id and d.subscription_id=push_finish_job.subscription_id and d.lease_id=push_finish_job.lease_id;
 if found and status in (404,410) then update public.inspection_push_subscriptions set enabled=false where id=push_finish_job.subscription_id;end if;
end $$;

create function public.inspection_push_worker_config() returns jsonb language sql set search_path='' as $$select inspection_internal.push_worker_config()$$;
create function public.inspection_push_claim_jobs() returns jsonb language sql set search_path='' as $$select inspection_internal.push_claim_jobs()$$;
create function public.inspection_push_finish_job(notification_id uuid,subscription_id uuid,lease_id uuid,status integer) returns void language sql set search_path='' as $$select inspection_internal.push_finish_job(notification_id,subscription_id,lease_id,status)$$;

create function inspection_internal.dispatch_push_worker() returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.inspection_notifications n join public.inspection_push_subscriptions s on s.user_id=n.recipient_id and s.enabled left join inspection_internal.push_deliveries d on d.notification_id=n.id and d.subscription_id=s.id where n.dismissed_at is null and n.created_at>=s.activated_at and n.created_at>clock_timestamp()-interval '1 day' and (d.notification_id is null or (d.sent_at is null and d.attempts<8 and d.next_attempt_at<=clock_timestamp() and (d.lease_until is null or d.lease_until<clock_timestamp())))) then return;end if;
 perform net.http_post(url:='https://kyhecrvsllableoymqfe.supabase.co/functions/v1/inspection-push',headers:=jsonb_build_object('Content-Type','application/json','x-inspection-worker',(select decrypted_secret from vault.decrypted_secrets where name='inspection_push_worker_secret')),body:='{}',timeout_milliseconds:=20000);
end $$;

-- Default-deny all new privileged functions; expose only explicit authenticated wrappers.
do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='inspection_internal' and p.proname in ('push_eligible','push_status','push_subscribe','push_disable','notification_close','notification_inbox','notification_set_certificate_user','enqueue_order_notice','notify_draft_upload','notify_intake_upload','notify_po_approval','notify_delivery_ready','push_worker_config','push_claim_jobs','push_finish_job','dispatch_push_worker'))
 or (n.nspname='public' and p.proname in ('inspection_push_status','inspection_push_subscribe','inspection_push_disable','inspection_notification_close','inspection_notification_inbox','inspection_notification_set_certificate_user','inspection_push_worker_config','inspection_push_claim_jobs','inspection_push_finish_job'))
 loop execute format('revoke all on function %s from public,anon,authenticated',f.signature);end loop;
end $$;
grant execute on function inspection_internal.push_status(),inspection_internal.push_subscribe(jsonb,text),inspection_internal.push_disable(text),inspection_internal.notification_close(uuid),inspection_internal.notification_inbox(),inspection_internal.notification_set_certificate_user(uuid) to authenticated;
grant execute on function public.inspection_push_status(),public.inspection_push_subscribe(jsonb,text),public.inspection_push_disable(text),public.inspection_notification_close(uuid),public.inspection_notification_inbox(),public.inspection_notification_set_certificate_user(uuid) to authenticated;
grant usage on schema inspection_internal to service_role;
grant execute on function inspection_internal.push_worker_config(),inspection_internal.push_claim_jobs(),inspection_internal.push_finish_job(uuid,uuid,uuid,integer) to service_role;
grant execute on function public.inspection_push_worker_config(),public.inspection_push_claim_jobs(),public.inspection_push_finish_job(uuid,uuid,uuid,integer) to service_role;
select cron.schedule('inspection-push-dispatch','* * * * *',$$select inspection_internal.dispatch_push_worker()$$);

insert into inspection_internal.push_settings(singleton,certificate_user_id,public_key) values(true,(select id from auth.users where lower(email)='ariadna.cabeza@hapcor.com'), 'BMEMPeWFP-gHa-FWvR6Ic0XA3Uk82Uzi_M-j6HEBjGOlDEfFcrjckGpExZkZjoyhysD7-Zd6V5ggWucYEEWEu1E');

-- Hold external sending pending explicit authorization.
alter table inspection_internal.push_settings add column delivery_enabled boolean not null default false;
create function inspection_internal.push_delivery_enabled() returns boolean language sql stable security definer set search_path='' as $$select coalesce((select delivery_enabled from inspection_internal.push_settings),false)$$;
revoke all on function inspection_internal.push_delivery_enabled() from public,anon,authenticated;
grant execute on function inspection_internal.push_delivery_enabled() to authenticated;
create or replace function public.inspection_push_status() returns jsonb language sql set search_path='' as $$select inspection_internal.push_status() || jsonb_build_object('deliveryReady',inspection_internal.push_delivery_enabled())$$;
create or replace function inspection_internal.push_subscribe(subscription jsonb,device_label text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); endpoint text=subscription->>'endpoint'; existing public.inspection_push_subscriptions%rowtype;
begin
 if not inspection_internal.push_delivery_enabled() then raise exception 'Push delivery setup is awaiting authorization';end if;
 if not inspection_internal.push_eligible(uid) then raise exception 'Order notifications are available to the administrator and certificate preparer' using errcode='42501';end if;
 if jsonb_typeof(subscription) is distinct from 'object' or octet_length(subscription::text)>8192
 or endpoint !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-zA-Z0-9.-]+[.]push[.]apple[.]com|[a-zA-Z0-9.-]+[.]notify[.]windows[.]com)/[^[:space:]]+$'
 or coalesce(subscription->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$'
 or coalesce(subscription->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{22}={0,2}$'
 then raise exception 'Unsupported or invalid push subscription';end if;
 perform pg_advisory_xact_lock(hashtextextended(endpoint,0));
 select * into existing from public.inspection_push_subscriptions s where s.endpoint=push_subscribe.endpoint;
 if found and existing.user_id<>uid then raise exception 'This browser subscription belongs to another account. Disable it before switching accounts.' using errcode='42501';end if;
 insert into public.inspection_push_subscriptions(user_id,endpoint,subscription,device_label)
 values(uid,endpoint,subscription,left(device_label,80))
 on conflict(endpoint) do update set subscription=excluded.subscription,device_label=excluded.device_label,enabled=true,
 activated_at=case when inspection_push_subscriptions.enabled then inspection_push_subscriptions.activated_at else clock_timestamp() end,updated_at=clock_timestamp();
 return jsonb_build_object('enabled',true);
end $$;


create or replace function inspection_internal.dispatch_push_worker() returns void
language plpgsql security definer set search_path='' as $$
begin
 if not inspection_internal.push_delivery_enabled() then return;end if;
 if not exists(select 1 from public.inspection_notifications n join public.inspection_push_subscriptions s on s.user_id=n.recipient_id and s.enabled left join inspection_internal.push_deliveries d on d.notification_id=n.id and d.subscription_id=s.id where n.dismissed_at is null and n.created_at>=s.activated_at and n.created_at>clock_timestamp()-interval '1 day' and (d.notification_id is null or (d.sent_at is null and d.attempts<8 and d.next_attempt_at<=clock_timestamp() and (d.lease_until is null or d.lease_until<clock_timestamp())))) then return;end if;
 perform net.http_post(url:='https://kyhecrvsllableoymqfe.supabase.co/functions/v1/inspection-push',headers:=jsonb_build_object('Content-Type','application/json','x-inspection-worker',(select decrypted_secret from vault.decrypted_secrets where name='inspection_push_worker_secret')),body:='{}',timeout_milliseconds:=20000);
end $$;



-- Conflict qualification correction.
do $$begin
 execute replace(pg_get_functiondef('inspection_internal.enqueue_order_notice(text,text,text,text,text,uuid)'::regprocedure),'on conflict(recipient_id,event_key) do nothing','on conflict on constraint inspection_notifications_recipient_id_event_key_key do nothing');
 execute replace(pg_get_functiondef('inspection_internal.push_subscribe(jsonb,text)'::regprocedure),'on conflict(endpoint) do update','on conflict on constraint inspection_push_subscriptions_endpoint_key do update');
end $$;
-- Preserve whether an optional PO reference was actually entered.
alter table public.inspection_delivery_intakes add column has_supplied_po boolean;
do $$declare definition text;begin
 definition=pg_get_functiondef('inspection_internal.submit_delivery_intake(uuid,text,uuid,text,text,text,jsonb)'::regprocedure);
 definition=replace(definition,'insert into public.inspection_delivery_intakes values(','insert into public.inspection_delivery_intakes(id,created_by,administrator_id,po_number,client_id,customer_name,delivery_number,source_file,source_path,source_rows,draft_id,approved_po_id,created_at,payload_hash,has_supplied_po) values(');
 definition=replace(definition,'draft_id,null,clock_timestamp(),hash);','draft_id,null,clock_timestamp(),hash,coalesce(btrim(submit_delivery_intake.po_number),'''')<>'''');');
 execute definition;
 definition=pg_get_functiondef('inspection_internal.notify_intake_upload()'::regprocedure);
 execute replace(definition,'if shown_po=''D''||new.delivery_number then','if new.has_supplied_po is false then');
 definition=pg_get_functiondef('inspection_internal.notify_po_approval()'::regprocedure);
 execute replace(definition,'i.po_number=''D''||i.delivery_number','i.has_supplied_po is false');
 definition=pg_get_functiondef('inspection_internal.notify_delivery_ready()'::regprocedure);
 execute replace(definition,'i.po_number=''D''||i.delivery_number','i.has_supplied_po is false');
end $$;