-- Spendsnap Phase 1: lifecycle and cross-table tenant integrity enforcement.
begin;

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger companies_set_updated_at before update on public.companies
for each row execute function public.set_updated_at();
create trigger company_memberships_set_updated_at before update on public.company_memberships
for each row execute function public.set_updated_at();
create trigger receipts_set_updated_at before update on public.receipts
for each row execute function public.set_updated_at();

create or replace function public.is_company_member(target_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.company_memberships membership
    where membership.company_id = target_company_id
      and membership.user_id = auth.uid()
      and membership.active = true
  );
$$;

create or replace function public.has_company_role(
  target_company_id uuid,
  allowed_roles public.company_role[]
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.company_memberships membership
    where membership.company_id = target_company_id
      and membership.user_id = auth.uid()
      and membership.active = true
      and membership.role = any(allowed_roles)
  );
$$;

create or replace function public.try_uuid(value text)
returns uuid language plpgsql immutable security invoker as $$
begin
  return value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create or replace function public.validate_receipt_status_transition()
returns trigger language plpgsql security invoker set search_path = public as $$
declare allowed boolean := false;
begin
  if new.status = old.status then return new; end if;
  allowed := case old.status
    when 'upload_pending' then new.status in ('received', 'rejected', 'archived')
    when 'received' then new.status in ('queued', 'rejected', 'archived')
    when 'queued' then new.status in ('extracting', 'failed', 'rejected', 'archived')
    when 'extracting' then new.status in ('extracted', 'needs_review', 'failed')
    when 'extracted' then new.status in ('needs_review', 'verified', 'failed', 'archived')
    when 'needs_review' then new.status in ('verified', 'rejected', 'archived')
    when 'failed' then new.status in ('queued', 'rejected', 'archived')
    when 'verified' then new.status = 'archived'
    when 'rejected' then new.status = 'archived'
    else false
  end;
  if not allowed then
    raise exception 'Illegal receipt status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger receipts_validate_status_transition before update of status on public.receipts
for each row execute function public.validate_receipt_status_transition();

create or replace function public.validate_receipt_page_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare parent_company_id uuid;
begin
  select company_id into parent_company_id from public.receipts where id = new.receipt_id;
  if parent_company_id is null then
    raise exception 'Receipt does not exist' using errcode = 'foreign_key_violation';
  end if;
  if new.storage_path not like parent_company_id::text || '/' || new.receipt_id::text || '/%' then
    raise exception 'Receipt page storage path is outside the receipt scope'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger receipt_pages_validate_scope before insert or update on public.receipt_pages
for each row execute function public.validate_receipt_page_scope();

create or replace function public.validate_extraction_run_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare parent_company_id uuid;
begin
  select company_id into parent_company_id from public.receipts where id = new.receipt_id;
  if parent_company_id is distinct from new.company_id then
    raise exception 'Extraction run company does not match receipt company'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger extraction_runs_validate_scope
before insert or update of receipt_id, company_id on public.extraction_runs
for each row execute function public.validate_extraction_run_scope();

create or replace function public.validate_latest_extraction_run_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare run_receipt_id uuid;
begin
  if new.latest_extraction_run_id is null then return new; end if;
  select receipt_id into run_receipt_id from public.extraction_runs where id = new.latest_extraction_run_id;
  if run_receipt_id is distinct from new.id then
    raise exception 'Latest extraction run does not belong to this receipt'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger receipts_validate_latest_extraction_run_scope
before insert or update of latest_extraction_run_id on public.receipts
for each row execute function public.validate_latest_extraction_run_scope();

create or replace function public.validate_extracted_field_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare run_receipt_id uuid; run_company_id uuid;
begin
  select receipt_id, company_id into run_receipt_id, run_company_id
  from public.extraction_runs where id = new.extraction_run_id;
  if run_receipt_id is distinct from new.receipt_id or run_company_id is distinct from new.company_id then
    raise exception 'Extracted field scope does not match its extraction run'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger extracted_fields_validate_scope
before insert or update of extraction_run_id, receipt_id, company_id on public.extracted_fields
for each row execute function public.validate_extracted_field_scope();

create or replace function public.validate_field_correction_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  parent_company_id uuid;
  previous_receipt_id uuid;
  previous_company_id uuid;
  previous_field_name text;
begin
  select company_id into parent_company_id from public.receipts where id = new.receipt_id;
  if parent_company_id is distinct from new.company_id then
    raise exception 'Correction company does not match receipt company'
      using errcode = 'check_violation';
  end if;
  if new.previous_field_id is not null then
    select receipt_id, company_id, field_name
    into previous_receipt_id, previous_company_id, previous_field_name
    from public.extracted_fields where id = new.previous_field_id;
    if previous_receipt_id is distinct from new.receipt_id
       or previous_company_id is distinct from new.company_id
       or previous_field_name is distinct from new.field_name then
      raise exception 'Correction does not match the referenced extracted field'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger field_corrections_validate_scope
before insert or update of receipt_id, company_id, field_name, previous_field_id
on public.field_corrections for each row execute function public.validate_field_correction_scope();

create or replace function public.validate_duplicate_candidate_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare first_company_id uuid; second_company_id uuid;
begin
  select company_id into first_company_id from public.receipts where id = new.receipt_id;
  select company_id into second_company_id from public.receipts where id = new.possible_duplicate_receipt_id;
  if first_company_id is distinct from new.company_id or second_company_id is distinct from new.company_id then
    raise exception 'Duplicate candidate receipts must belong to the same company'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger duplicate_candidates_validate_scope
before insert or update of company_id, receipt_id, possible_duplicate_receipt_id
on public.duplicate_candidates for each row execute function public.validate_duplicate_candidate_scope();

create or replace function public.validate_audit_event_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare parent_company_id uuid;
begin
  if new.receipt_id is null then return new; end if;
  select company_id into parent_company_id from public.receipts where id = new.receipt_id;
  if parent_company_id is distinct from new.company_id then
    raise exception 'Audit event company does not match receipt company'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger audit_events_validate_scope
before insert or update of company_id, receipt_id on public.audit_events
for each row execute function public.validate_audit_event_scope();

create or replace function public.create_company_with_admin(company_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_company_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if char_length(trim(company_name)) not between 1 and 160 then
    raise exception 'Company name is invalid' using errcode = 'check_violation';
  end if;
  insert into public.companies (name, created_by)
  values (trim(company_name), current_user_id) returning id into new_company_id;
  insert into public.company_memberships (company_id, user_id, role)
  values (new_company_id, current_user_id, 'admin');
  return new_company_id;
end;
$$;

commit;
