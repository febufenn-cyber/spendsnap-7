-- Spendsnap Phase 1: row-level security, grants and private receipt storage.
begin;

alter table public.companies enable row level security;
alter table public.company_memberships enable row level security;
alter table public.receipts enable row level security;
alter table public.receipt_pages enable row level security;
alter table public.extraction_runs enable row level security;
alter table public.extracted_fields enable row level security;
alter table public.field_corrections enable row level security;
alter table public.duplicate_candidates enable row level security;
alter table public.audit_events enable row level security;

create policy companies_select_member on public.companies for select to authenticated
using (public.is_company_member(id));
create policy companies_update_admin on public.companies for update to authenticated
using (public.has_company_role(id, array['admin']::public.company_role[]))
with check (public.has_company_role(id, array['admin']::public.company_role[]));

create policy memberships_select_authorized on public.company_memberships for select to authenticated
using (
  user_id = auth.uid()
  or public.has_company_role(
    company_id, array['manager', 'finance', 'admin', 'auditor']::public.company_role[]
  )
);
create policy memberships_insert_admin on public.company_memberships for insert to authenticated
with check (public.has_company_role(company_id, array['admin']::public.company_role[]));
create policy memberships_update_admin on public.company_memberships for update to authenticated
using (public.has_company_role(company_id, array['admin']::public.company_role[]))
with check (public.has_company_role(company_id, array['admin']::public.company_role[]));

create policy receipts_select_member on public.receipts for select to authenticated
using (public.is_company_member(company_id));
create policy receipts_insert_member_self on public.receipts for insert to authenticated
with check (
  submitted_by = auth.uid()
  and status = 'upload_pending'
  and public.is_company_member(company_id)
);

create policy receipt_pages_select_member on public.receipt_pages for select to authenticated
using (
  exists (
    select 1 from public.receipts receipt
    where receipt.id = receipt_pages.receipt_id
      and public.is_company_member(receipt.company_id)
  )
);
create policy extraction_runs_select_member on public.extraction_runs for select to authenticated
using (public.is_company_member(company_id));
create policy extracted_fields_select_member on public.extracted_fields for select to authenticated
using (public.is_company_member(company_id));

create policy field_corrections_select_member on public.field_corrections for select to authenticated
using (public.is_company_member(company_id));
create policy field_corrections_insert_member_self on public.field_corrections for insert to authenticated
with check (
  submitted_by = auth.uid()
  and status = 'pending'
  and public.is_company_member(company_id)
  and exists (
    select 1 from public.receipts receipt
    where receipt.id = field_corrections.receipt_id
      and receipt.company_id = field_corrections.company_id
  )
);

create policy duplicate_candidates_select_finance on public.duplicate_candidates for select to authenticated
using (
  public.has_company_role(
    company_id, array['finance', 'admin', 'auditor']::public.company_role[]
  )
);
create policy audit_events_select_finance on public.audit_events for select to authenticated
using (
  public.has_company_role(
    company_id, array['finance', 'admin', 'auditor']::public.company_role[]
  )
);

revoke execute on function public.is_company_member(uuid) from public;
revoke execute on function public.has_company_role(uuid, public.company_role[]) from public;
revoke execute on function public.try_uuid(text) from public;
revoke execute on function public.create_company_with_admin(text) from public;

grant usage on schema public to authenticated, service_role;
grant select, update on public.companies to authenticated;
grant select, insert, update on public.company_memberships to authenticated;
grant select, insert on public.receipts to authenticated;
grant select on public.receipt_pages, public.extraction_runs, public.extracted_fields to authenticated;
grant select, insert on public.field_corrections to authenticated;
grant select on public.duplicate_candidates, public.audit_events to authenticated;
grant execute on function public.is_company_member(uuid) to authenticated, service_role;
grant execute on function public.has_company_role(uuid, public.company_role[]) to authenticated, service_role;
grant execute on function public.try_uuid(text) to authenticated, service_role;
grant execute on function public.create_company_with_admin(text) to authenticated;

grant all on public.companies, public.company_memberships, public.receipts,
  public.receipt_pages, public.extraction_runs, public.extracted_fields,
  public.field_corrections, public.duplicate_candidates, public.audit_events
  to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts', 'receipts', false, 7500000,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy receipt_objects_select_company_member on storage.objects for select to authenticated
using (
  bucket_id = 'receipts'
  and public.is_company_member(public.try_uuid((storage.foldername(name))[1]))
);
create policy receipt_objects_delete_admin on storage.objects for delete to authenticated
using (
  bucket_id = 'receipts'
  and public.has_company_role(
    public.try_uuid((storage.foldername(name))[1]),
    array['admin']::public.company_role[]
  )
);

commit;
