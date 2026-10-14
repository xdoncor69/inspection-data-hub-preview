-- Simplify current master fields only; preserve approved documents and all real evidence.
do $$
declare before_state jsonb; after_state jsonb; compact jsonb; administrator uuid; fingerprint text;
begin
 select a.user_id into administrator from public.inspection_admins a join auth.users u on u.id=a.user_id where lower(u.email)='david.rodriguez@hapcor.com';
 if administrator is null then raise exception 'Expected administrator not found';end if;
 select records into before_state from public.inspection_official_state where id='official' for update;
 if before_state is null then raise exception 'Official catalog is not configured';end if;
 select md5(coalesce(jsonb_agg(v order by k)::text,'')) into fingerprint from (
  select 'po:'||id::text k,to_jsonb(p) v from public.inspection_approved_pos p union all
  select 'delivery:'||id::text,to_jsonb(d) from public.inspection_deliveries d union all
  select 'workspace:'||user_id::text,to_jsonb(w) from public.inspection_po_workspaces w union all
  select 'validation:'||item||':'||est,to_jsonb(v) from public.inspection_catalog_validations v
 ) protected;
 select coalesce(jsonb_object_agg(key,(value-'producer'-'salesUnit'-'size')||jsonb_build_object('pack',coalesce((
  select string_agg(part,' · ' order by first_n) from (
   select (array_agg(btrim(v) order by n))[1] part,min(n) first_n
   from unnest(string_to_array(coalesce(value->>'pack',''),' · ')||string_to_array(coalesce(value->>'size',''),' · ')) with ordinality t(v,n)
   where btrim(v)<>'' group by lower(btrim(v))
  ) parts
 ),''))),'{}') into compact
 from jsonb_each(before_state->'inspection-data-hub-catalog-overrides-v1');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',administrator,'role','authenticated')::text,true);
 perform set_config('request.headers',jsonb_build_object('x-inspection-catalog-generation',before_state->'inspection-data-hub-catalog-import-v1'->>'generation')::text,true);
 if compact is distinct from before_state->'inspection-data-hub-catalog-overrides-v1' then
  update public.inspection_official_state set records=jsonb_set(records,'{inspection-data-hub-catalog-overrides-v1}',compact),revision=revision+1,updated_at=clock_timestamp() where id='official';
 end if;
 select records into after_state from public.inspection_official_state where id='official';
 if (after_state-'inspection-data-hub-catalog-overrides-v1') is distinct from (before_state-'inspection-data-hub-catalog-overrides-v1') then raise exception 'Unrelated official data changed';end if;
 if exists(select 1 from jsonb_each(after_state->'inspection-data-hub-catalog-overrides-v1') a where
 (a.value-'pack') is distinct from ((before_state->'inspection-data-hub-catalog-overrides-v1'->a.key)-'pack'-'size'-'producer'-'salesUnit')
 or a.value ?| array['size','salesUnit','producer']) then raise exception 'Catalog invariant failed';end if;
 if fingerprint is distinct from (select md5(coalesce(jsonb_agg(v order by k)::text,'')) from (
  select 'po:'||id::text k,to_jsonb(p) v from public.inspection_approved_pos p union all
  select 'delivery:'||id::text,to_jsonb(d) from public.inspection_deliveries d union all
  select 'workspace:'||user_id::text,to_jsonb(w) from public.inspection_po_workspaces w union all
  select 'validation:'||item||':'||est,to_jsonb(v) from public.inspection_catalog_validations v
 ) protected) then raise exception 'Protected records changed';end if;
end $$;
select count(*) items,count(*) filter(where value ?| array['producer','salesUnit','size']) retired_fields_remaining,
 count(*) filter(where coalesce(value->>'pack','')<>'') combined_pack_items
from public.inspection_official_state,jsonb_each(records->'inspection-data-hub-catalog-overrides-v1') where id='official';