-- Reference for migration catalog_initial_validation_and_complete_safe_read, already applied 2026-10-13.
-- Do not run blindly against an existing database. Initialization is an explicit administrator RPC.
-- Initial administrative validation is NOT an inspection or receipt event.
create table public.inspection_catalog_validations (
 item text not null,
 est text not null check (est ~ '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'),
 validated_at timestamptz not null default clock_timestamp(),
 validated_by uuid not null references auth.users(id),
 validation_kind text not null default 'administrator_initial' check (validation_kind='administrator_initial'),
 primary key(item,est)
);
alter table public.inspection_catalog_validations enable row level security;
revoke all on public.inspection_catalog_validations from public,anon,authenticated;
grant select on public.inspection_catalog_validations to authenticated;
create policy initial_validation_read on public.inspection_catalog_validations for select to authenticated using ((select auth.uid()) is not null);
create index inspection_catalog_validations_actor_idx on public.inspection_catalog_validations(validated_by);

create function inspection_internal.catalog_associations() returns table(item text,est text)
language sql stable set search_path='' as $$
 with catalog as (
 select c.key item,c.value product,s.records->'inspection-data-hub-est-references-v1'->c.key refs
 from public.inspection_official_state s cross join lateral jsonb_each(s.records->'inspection-data-hub-catalog-overrides-v1') c where s.id='official'
 ), candidates as (
 select item,btrim(product->>'plant') est from catalog
 union select item,btrim(refs->>'primary') from catalog
 union select item,btrim(v.value) from catalog cross join lateral jsonb_array_elements_text(case when jsonb_typeof(refs->'others')='array' then refs->'others' else '[]'::jsonb end) v
 ) select item,est from candidates where est ~ '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'
$$;
revoke all on function inspection_internal.catalog_associations() from public,anon,authenticated;

create function inspection_internal.initialize_catalog_validation() returns jsonb
language plpgsql security definer set search_path='' as $$
declare inserted integer;
begin
 if auth.uid() is null or not exists(select 1 from public.inspection_admins where user_id=auth.uid()) then raise exception 'Administrator required' using errcode='42501';end if;
 perform 1 from public.inspection_official_state where id='official' for share;
 insert into public.inspection_catalog_validations(item,est,validated_by)
 select item,est,auth.uid() from inspection_internal.catalog_associations()
 on conflict(item,est) do nothing;
 get diagnostics inserted=row_count;
 return jsonb_build_object('inserted',inserted,'total',(select count(*) from public.inspection_catalog_validations));
end $$;
revoke all on function inspection_internal.initialize_catalog_validation() from public,anon;
grant execute on function inspection_internal.initialize_catalog_validation() to authenticated;
create function public.inspection_initialize_catalog_validation() returns jsonb
language sql set search_path='' as $$select inspection_internal.initialize_catalog_validation()$$;
revoke all on function public.inspection_initialize_catalog_validation() from public,anon;
grant execute on function public.inspection_initialize_catalog_validation() to authenticated;

-- A scalar JSON response contains the complete catalog, independent of REST row limits.
-- Deliberately excludes observations, PO snapshots and per-line verification evidence.
create function inspection_internal.read_catalog() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.inspection_official_state; validations jsonb; deliveries jsonb;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select * into s from public.inspection_official_state where id='official';
 if not found then raise exception 'Official catalog is not configured';end if;
 select coalesce(jsonb_agg(jsonb_build_object('item',v.item,'est',v.est,'validated_at',v.validated_at,'validated_by',v.validated_by,'validation_kind',v.validation_kind)),'[]') into validations
 from public.inspection_catalog_validations v join inspection_internal.catalog_associations() a on a.item=v.item and a.est=v.est;
 -- Upload timestamp is labelled as such, never a physical receipt date.
 select coalesce(jsonb_object_agg(item,jsonb_build_object('delivery_number',delivery_number,'recorded_at',updated_at)),'{}') into deliveries from (
 select distinct on(r->>'item') r->>'item' item,d.delivery_number,d.updated_at
 from public.inspection_deliveries d cross join lateral jsonb_array_elements(d.rows) r
 where coalesce(r->>'item','')<>'' and
 case when coalesce(r->>'receivedQuantity','') ~ '^[0-9]+([.][0-9]+)?$' then (r->>'receivedQuantity')::numeric>0
 else case when coalesce(r->>'catchWeight','') ~ '^[0-9]+([.][0-9]+)?$' then (r->>'catchWeight')::numeric>0 else false end end
 order by r->>'item',d.updated_at desc,d.id
 ) q;
 return jsonb_build_object('revision',s.revision,'catalog',coalesce(s.records->'inspection-data-hub-catalog-overrides-v1','{}'),'references',coalesce(s.records->'inspection-data-hub-est-references-v1','{}'),'generation',s.records->'inspection-data-hub-catalog-import-v1'->>'generation','validations',validations,'deliveries',deliveries);
end $$;
revoke all on function inspection_internal.read_catalog() from public,anon;
grant execute on function inspection_internal.read_catalog() to authenticated;
create function public.inspection_read_catalog() returns jsonb
language sql stable set search_path='' as $$select inspection_internal.read_catalog()$$;
revoke all on function public.inspection_read_catalog() from public,anon;
grant execute on function public.inspection_read_catalog() to authenticated;
