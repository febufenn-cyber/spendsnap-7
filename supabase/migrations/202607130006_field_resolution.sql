-- Spendsnap Phase 1: append-only field resolution and duplicate review.
begin;

create type public.field_resolution_source as enum ('prediction', 'correction');

create table public.field_resolutions (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  field_name text not null check (field_name ~ '^[a-z][a-z0-9_]{1,79}$'),
  source public.field_resolution_source not null,
  extracted_field_id uuid references public.extracted_fields(id) on delete restrict,
  correction_id uuid references public.field_corrections(id) on delete restrict,
  resolved_value jsonb,
  resolved_by uuid not null references auth.users(id) on delete restrict,
  request_id text,
  created_at timestamptz not null default now(),
  constraint field_resolution_source_check check (
    (source = 'prediction' and extracted_field_id is not null and correction_id is null)
    or (source = 'correction' and correction_id is not null and extracted_field_id is null)
  )
);

create index field_resolutions_receipt_field_created_idx
  on public.field_resolutions (receipt_id, field_name, created_at desc);
create index field_resolutions_company_created_idx
  on public.field_resolutions (company_id, created_at desc);
create unique index field_resolutions_prediction_once_idx
  on public.field_resolutions (receipt_id, field_name, extracted_field_id)
  where source = 'prediction';
create unique index field_resolutions_correction_once_idx
  on public.field_resolutions (receipt_id, field_name, correction_id)
  where source = 'correction';

create or replace function public.validate_field_correction_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  parent_company_id uuid;
  latest_run_id uuid;
  parent_status public.receipt_status;
  previous_receipt_id uuid;
  previous_company_id uuid;
  previous_field_name text;
  previous_run_id uuid;
begin
  select company_id, latest_extraction_run_id, status
  into parent_company_id, latest_run_id, parent_status
  from public.receipts where id = new.receipt_id;

  if parent_company_id is distinct from new.company_id then
    raise exception 'Correction company does not match receipt company'
      using errcode = 'check_violation';
  end if;
  if parent_status not in ('extracted', 'needs_review') then
    raise exception 'Receipt is not open for correction'
      using errcode = 'check_violation';
  end if;
  if new.previous_field_id is null then
    raise exception 'A correction must reference the predicted field'
      using errcode = 'check_violation';
  end if;

  select receipt_id, company_id, field_name, extraction_run_id
  into previous_receipt_id, previous_company_id, previous_field_name, previous_run_id
  from public.extracted_fields where id = new.previous_field_id;

  if previous_receipt_id is distinct from new.receipt_id
     or previous_company_id is distinct from new.company_id
     or previous_field_name is distinct from new.field_name
     or previous_run_id is distinct from latest_run_id then
    raise exception 'Correction does not match the latest predicted field'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace function public.validate_field_resolution_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  parent_company_id uuid;
  latest_run_id uuid;
  source_receipt_id uuid;
  source_company_id uuid;
  source_field_name text;
  source_run_id uuid;
begin
  select company_id, latest_extraction_run_id
  into parent_company_id, latest_run_id
  from public.receipts where id = new.receipt_id;

  if parent_company_id is distinct from new.company_id then
    raise exception 'Resolution company does not match receipt company'
      using errcode = 'check_violation';
  end if;

  if new.source = 'prediction' then
    select receipt_id, company_id, field_name, extraction_run_id
    into source_receipt_id, source_company_id, source_field_name, source_run_id
    from public.extracted_fields where id = new.extracted_field_id;
  else
    select receipt_id, company_id, field_name, null::uuid
    into source_receipt_id, source_company_id, source_field_name, source_run_id
    from public.field_corrections where id = new.correction_id;
  end if;

  if source_receipt_id is distinct from new.receipt_id
     or source_company_id is distinct from new.company_id
     or source_field_name is distinct from new.field_name then
    raise exception 'Resolution source does not match receipt field'
      using errcode = 'check_violation';
  end if;

  if new.source = 'prediction' and source_run_id is distinct from latest_run_id then
    raise exception 'Resolution must reference the latest extraction run'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger field_resolutions_validate_scope
before insert or update on public.field_resolutions
for each row execute function public.validate_field_resolution_scope();

alter table public.field_resolutions enable row level security;
create policy field_resolutions_select_member on public.field_resolutions for select to authenticated
using (public.is_company_member(company_id));

grant select on public.field_resolutions to authenticated;
grant all on public.field_resolutions to service_role;

create or replace function public.resolve_receipt_fields(
  p_receipt_id uuid,
  p_decisions jsonb,
  p_finalize boolean,
  p_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_receipt public.receipts%rowtype;
  decision jsonb;
  decision_field text;
  decision_source public.field_resolution_source;
  decision_source_id uuid;
  prediction public.extracted_fields%rowtype;
  correction public.field_corrections%rowtype;
  unresolved_required integer;
  open_duplicates integer;
  inserted_count integer := 0;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into current_receipt from public.receipts
  where id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found' using errcode = 'no_data_found'; end if;

  if not public.has_company_role(
    current_receipt.company_id,
    array['finance', 'admin']::public.company_role[]
  ) then
    raise exception 'Finance or admin role required' using errcode = 'insufficient_privilege';
  end if;
  if current_receipt.status not in ('extracted', 'needs_review') then
    raise exception 'Receipt is not open for field resolution' using errcode = 'check_violation';
  end if;
  if jsonb_typeof(p_decisions) <> 'array' then
    raise exception 'Decisions must be an array' using errcode = 'check_violation';
  end if;

  for decision in select value from jsonb_array_elements(p_decisions)
  loop
    decision_field := decision->>'fieldName';
    decision_source := (decision->>'source')::public.field_resolution_source;
    decision_source_id := (decision->>'sourceId')::uuid;

    if decision_field !~ '^[a-z][a-z0-9_]{1,79}$' then
      raise exception 'Invalid field name' using errcode = 'check_violation';
    end if;

    if decision_source = 'prediction' then
      select * into prediction from public.extracted_fields
      where id = decision_source_id
        and receipt_id = current_receipt.id
        and extraction_run_id = current_receipt.latest_extraction_run_id
        and field_name = decision_field;
      if not found then
        raise exception 'Prediction source not found for field %', decision_field
          using errcode = 'no_data_found';
      end if;

      insert into public.field_resolutions (
        receipt_id, company_id, field_name, source, extracted_field_id,
        resolved_value, resolved_by, request_id
      ) values (
        current_receipt.id, current_receipt.company_id, decision_field, 'prediction',
        prediction.id, prediction.value_json, current_user_id, p_request_id
      ) on conflict do nothing;

      update public.field_corrections
      set status = 'rejected', reviewed_by = current_user_id, reviewed_at = now()
      where receipt_id = current_receipt.id
        and field_name = decision_field
        and status = 'pending';
    else
      select * into correction from public.field_corrections
      where id = decision_source_id
        and receipt_id = current_receipt.id
        and field_name = decision_field
        and status in ('pending', 'accepted');
      if not found then
        raise exception 'Correction source not found for field %', decision_field
          using errcode = 'no_data_found';
      end if;

      update public.field_corrections
      set status = 'accepted', reviewed_by = current_user_id, reviewed_at = now()
      where id = correction.id and status = 'pending';

      update public.field_corrections
      set status = 'rejected', reviewed_by = current_user_id, reviewed_at = now()
      where receipt_id = current_receipt.id
        and field_name = decision_field
        and id <> correction.id
        and status = 'pending';

      insert into public.field_resolutions (
        receipt_id, company_id, field_name, source, correction_id,
        resolved_value, resolved_by, request_id
      ) values (
        current_receipt.id, current_receipt.company_id, decision_field, 'correction',
        correction.id, correction.corrected_value, current_user_id, p_request_id
      ) on conflict do nothing;
    end if;

    inserted_count := inserted_count + 1;
  end loop;

  if p_finalize then
    select count(*) into unresolved_required
    from public.extracted_fields field
    where field.extraction_run_id = current_receipt.latest_extraction_run_id
      and field.review_status = 'requires_review'
      and not exists (
        select 1 from public.field_resolutions resolution
        where resolution.receipt_id = current_receipt.id
          and resolution.field_name = field.field_name
      );

    if unresolved_required > 0 then
      raise exception 'Required review fields remain unresolved: %', unresolved_required
        using errcode = 'check_violation';
    end if;

    select count(*) into open_duplicates
    from public.duplicate_candidates candidate
    where candidate.company_id = current_receipt.company_id
      and candidate.resolution = 'open'
      and (
        candidate.receipt_id = current_receipt.id
        or candidate.possible_duplicate_receipt_id = current_receipt.id
      );

    if open_duplicates > 0 then
      raise exception 'Open duplicate candidates must be resolved before verification'
        using errcode = 'check_violation';
    end if;

    update public.receipts set status = 'verified' where id = current_receipt.id;
  end if;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, event_type, request_id, payload
  ) values (
    current_receipt.company_id,
    current_user_id,
    current_receipt.id,
    case when p_finalize then 'receipt.verified' else 'receipt.fields_resolved' end,
    p_request_id,
    jsonb_build_object('decisionCount', inserted_count, 'finalized', p_finalize)
  );

  return jsonb_build_object(
    'receiptId', current_receipt.id,
    'decisionCount', inserted_count,
    'finalized', p_finalize
  );
end;
$$;

create or replace function public.resolve_duplicate_candidate(
  p_candidate_id uuid,
  p_resolution public.duplicate_resolution,
  p_note text,
  p_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  candidate public.duplicate_candidates%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if p_resolution = 'open' then
    raise exception 'A final duplicate resolution is required' using errcode = 'check_violation';
  end if;

  select * into candidate from public.duplicate_candidates
  where id = p_candidate_id for update;
  if not found then raise exception 'Duplicate candidate not found' using errcode = 'no_data_found'; end if;

  if not public.has_company_role(
    candidate.company_id,
    array['finance', 'admin']::public.company_role[]
  ) then
    raise exception 'Finance or admin role required' using errcode = 'insufficient_privilege';
  end if;

  if candidate.resolution = 'open' then
    update public.duplicate_candidates
    set resolution = p_resolution,
        resolved_by = current_user_id,
        resolved_at = now(),
        reason = reason || jsonb_build_object('reviewNote', nullif(left(p_note, 1000), ''))
    where id = candidate.id;
  end if;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, event_type, request_id, payload
  ) values (
    candidate.company_id,
    current_user_id,
    candidate.receipt_id,
    'receipt.duplicate_resolved',
    p_request_id,
    jsonb_build_object(
      'candidateId', candidate.id,
      'otherReceiptId', candidate.possible_duplicate_receipt_id,
      'resolution', p_resolution
    )
  );

  return jsonb_build_object('candidateId', candidate.id, 'resolution', p_resolution);
end;
$$;

revoke execute on function public.resolve_receipt_fields(uuid, jsonb, boolean, text) from public;
revoke execute on function public.resolve_duplicate_candidate(uuid, public.duplicate_resolution, text, text) from public;
grant execute on function public.resolve_receipt_fields(uuid, jsonb, boolean, text) to authenticated;
grant execute on function public.resolve_duplicate_candidate(uuid, public.duplicate_resolution, text, text) to authenticated;

commit;
