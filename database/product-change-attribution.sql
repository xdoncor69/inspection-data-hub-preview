-- Applied to Supabase by migration product_change_request_attribution.
-- Product history records the requesting account and approving administrator.
alter table public.inspection_change_history add column if not exists requested_by uuid, add column if not exists approved_by uuid, add column if not exists request_id uuid;
create or replace function inspection_internal.attribute_product_change() returns trigger language plpgsql security definer set search_path='' as $$
declare rid uuid=nullif(current_setting('inspection.review_request_id',true),'')::uuid; r public.inspection_change_requests%rowtype;
begin
 new.requested_by=new.actor_id;new.approved_by=new.actor_id;new.request_id=null;
 if rid is not null and auth.uid() is not null and exists(select 1 from public.inspection_admins where user_id=auth.uid()) then
  select * into r from public.inspection_change_requests where id=rid and status='pending';
  if found and exists(select 1 from jsonb_array_elements(r.payload->'operations') op where op->'path'->>0='inspection-data-hub-'||new.domain||'-v1' and op->'path'->>1=new.entity) then
   new.requested_by=r.submitted_by;new.approved_by=auth.uid();new.request_id=rid;
  end if;
 end if;
 return new;
end $$;
revoke all on function inspection_internal.attribute_product_change() from public,anon,authenticated;
create trigger inspection_attribute_product_change before insert on public.inspection_change_history for each row execute function inspection_internal.attribute_product_change();
CREATE OR REPLACE FUNCTION inspection_internal.review_request(request_id uuid, decision text, expected_revision bigint, review_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.inspection_change_requests%rowtype; s public.inspection_official_state%rowtype; nextrecords jsonb; op jsonb; path text[]; v jsonb; pos jsonb; p jsonb; rowsout jsonb; x jsonb; i integer;
begin
 if auth.uid() is null or not exists(select 1 from public.inspection_admins where user_id=auth.uid()) then raise exception 'Administrator permission required' using errcode='42501';end if;
 if decision not in ('approve','reject') then raise exception 'Invalid review decision';end if;
 select * into s from public.inspection_official_state where id='official' for update;
 select * into r from public.inspection_change_requests where id=request_id for update;
 if not found or r.status<>'pending' then raise exception 'Request has already been reviewed or does not exist';end if;
 if decision='approve' then
  if s.revision<>expected_revision then raise exception 'Database changed. Refresh before approving.' using errcode='40001';end if;
  nextrecords=s.records;
  for op in select value from jsonb_array_elements(r.payload->'operations') loop
   select array_agg(value order by ord) into path from jsonb_array_elements_text(op->'path') with ordinality t(value,ord);
   if coalesce(s.records#>path,'null')<>op->'before' then raise exception 'Conflict: the official value changed after this request. Review the current value before requesting again.' using errcode='40001';end if;
   if op->'after'='null' then nextrecords=nextrecords#-path;
   else
    if nextrecords->path[1] is null then nextrecords=jsonb_set(nextrecords,array[path[1]],'{}');end if;
    nextrecords=jsonb_set(nextrecords,path,op->'after',true);
   end if;
  end loop;
  -- Physical PO confirmations become official only after the related observation is approved.
  pos=coalesce(nextrecords->'inspection-data-hub-po-workspace-v1'->'invoices','[]');
  for v in select value from jsonb_array_elements(coalesce(r.payload->'po_verifications','[]')) loop
   for i in 0..jsonb_array_length(pos)-1 loop
    p=pos->i;
    if p->>'id'=v->>'po_id' then
     rowsout='[]';
     for x in select value from jsonb_array_elements(p->'rows') loop
      if x->>'item'=v->>'item' then
       if x->>'plant'<>v->>'plant' then raise exception 'PO Item changed after the verification request' using errcode='40001';end if;
       x=x||jsonb_build_object('verifiedAt',v->'verifiedAt','verifiedEsts',v->'verifiedEsts','changeFrom',case when coalesce(x->>'expectedEst','')<>v->>'plant' then coalesce(x->>'expectedEst','') else '' end,'changeTo',case when coalesce(x->>'expectedEst','')<>v->>'plant' then v->>'plant' else '' end);
      end if;
      rowsout=rowsout||jsonb_build_array(x);
     end loop;
     pos=jsonb_set(pos,array[i::text,'rows'],rowsout);
    end if;
   end loop;
  end loop;
  if nextrecords ? 'inspection-data-hub-po-workspace-v1' then nextrecords=jsonb_set(nextrecords,'{inspection-data-hub-po-workspace-v1,invoices}',pos);end if;
  perform set_config('inspection.review_request_id',r.id::text,true);
  update public.inspection_official_state set records=nextrecords,revision=revision+1,updated_at=now() where id='official' returning * into s;
  perform set_config('inspection.review_request_id','',true);
 end if;
 update public.inspection_change_requests set status=case when decision='approve' then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),review_note=left(coalesce(review_request.review_note,''),1000) where id=request_id;
 return jsonb_build_object('status',case when decision='approve' then 'approved' else 'rejected' end,'revision',s.revision);
end $function$
;
update public.inspection_change_history h set requested_by=h.actor_id,approved_by=h.actor_id where requested_by is null and approved_by is null;
update public.inspection_change_history h set requested_by=r.submitted_by,approved_by=r.reviewed_by,request_id=r.id from public.inspection_change_requests r where r.status='approved' and h.changed_at=r.reviewed_at and h.actor_id=r.reviewed_by and exists(select 1 from jsonb_array_elements(r.payload->'operations') op where op->'path'->>0='inspection-data-hub-'||h.domain||'-v1' and op->'path'->>1=h.entity);
