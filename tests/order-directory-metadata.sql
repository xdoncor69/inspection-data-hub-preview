begin;
do $$
declare uid uuid; result jsonb;
begin
 foreach uid in array array[(select id from auth.users where lower(email)='david.rodriguez@hapcor.com'),(select id from auth.users where lower(email)='ariadna.cabeza@hapcor.com')] loop
  if uid is null then raise exception 'Expected account missing';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result=public.inspection_read_order_directory();
  if exists(select 1 from jsonb_array_elements(result->'deliveries') d cross join lateral jsonb_object_keys(d) k where k not in ('id','approved_po_id','delivery_number')) then raise exception 'Unexpected delivery field';end if;
  if exists(select 1 from jsonb_array_elements(result->'intakes') d cross join lateral jsonb_object_keys(d) k where k not in ('id','draft_id','approved_po_id','po_number','delivery_number','customer_name','has_supplied_po')) then raise exception 'Unexpected intake field';end if;
  execute 'reset role';
 end loop;
 if has_function_privilege('anon','public.inspection_read_order_directory()','execute') then raise exception 'Anonymous access must be blocked';end if;
end $$;
rollback;
select 'PASS: both authenticated accounts can read the directory; strict field whitelists contain no evidence; anonymous execution denied.' as result;