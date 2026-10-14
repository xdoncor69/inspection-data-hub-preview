-- Safe order-directory metadata only. No catalog, workspace or evidence records are modified.
create or replace function inspection_internal.read_order_directory()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare uid uuid=auth.uid(); draft_ids text[]; result jsonb;
begin
 if uid is null then raise exception 'Login required' using errcode='42501';end if;
 select coalesce(array_agg(p->>'id'),'{}'::text[]) into draft_ids
 from public.inspection_po_workspaces w cross join lateral jsonb_array_elements(coalesce(w.workspace->'invoices','[]')) p
 where w.user_id=inspection_internal.shared_draft_owner();
 select jsonb_build_object(
 'deliveries',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'approved_po_id',d.approved_po_id,'delivery_number',d.delivery_number) order by d.id),'[]')
 from public.inspection_deliveries d where exists(select 1 from public.inspection_approved_pos a where a.id=d.approved_po_id)),
 'intakes',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'draft_id',i.draft_id,'approved_po_id',i.approved_po_id,'po_number',i.po_number,'delivery_number',i.delivery_number,'customer_name',i.customer_name,'has_supplied_po',i.has_supplied_po) order by i.id),'[]')
 from public.inspection_delivery_intakes i where i.draft_id=any(draft_ids)
 or exists(select 1 from public.inspection_approved_pos a where a.id=i.approved_po_id)
 or i.created_by=uid or exists(select 1 from public.inspection_admins a where a.user_id=uid))
 ) into result;
 return result;
end $$;
revoke all on function inspection_internal.read_order_directory() from public,anon;
grant execute on function inspection_internal.read_order_directory() to authenticated,service_role;

create or replace function public.inspection_read_order_directory()
returns jsonb language sql stable security invoker set search_path=''
as $$select inspection_internal.read_order_directory()$$;
revoke all on function public.inspection_read_order_directory() from public,anon;
grant execute on function public.inspection_read_order_directory() to authenticated,service_role;
