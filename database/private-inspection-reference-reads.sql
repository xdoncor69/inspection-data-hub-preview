-- Remove inspection-derived reference trend text from normal-account reads. Underlying records and administrator reads remain intact.
CREATE OR REPLACE FUNCTION inspection_internal.read_official_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare admin boolean;result jsonb;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select exists(select 1 from public.inspection_admins where user_id=auth.uid()) into admin;
 select jsonb_build_array(jsonb_build_object('id',s.id,'revision',s.revision,'updated_at',s.updated_at,'records',case when admin then s.records else jsonb_set((s.records-'inspection-data-hub-observations-v1'-'inspection-data-hub-po-observations-v1'-'inspection-data-hub-po-workspace-v1'-'inspection-data-hub-initial-review-v1'),'{inspection-data-hub-est-references-v1}',(select coalesce(jsonb_object_agg(key,value-'trend'),'{}') from jsonb_each(coalesce(s.records->'inspection-data-hub-est-references-v1','{}')))) end)) into result from public.inspection_official_state s where id='official';
 return coalesce(result,'[]');
end $function$;

CREATE OR REPLACE FUNCTION inspection_internal.read_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 return jsonb_build_object('revision',s.revision,'catalog',coalesce(s.records->'inspection-data-hub-catalog-overrides-v1','{}'),'references',case when exists(select 1 from public.inspection_admins where user_id=auth.uid()) then coalesce(s.records->'inspection-data-hub-est-references-v1','{}') else (select coalesce(jsonb_object_agg(key,value-'trend'),'{}') from jsonb_each(coalesce(s.records->'inspection-data-hub-est-references-v1','{}'))) end,'generation',s.records->'inspection-data-hub-catalog-import-v1'->>'generation','validations',validations,'deliveries',deliveries);
end $function$
;
