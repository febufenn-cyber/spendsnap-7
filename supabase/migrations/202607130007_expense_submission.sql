-- Spendsnap Phase 2: employee claims, report assembly, immutable submissions.
begin;

create type public.expense_claim_status as enum ('draft', 'submitted', 'archived');
create type public.expense_report_status as enum ('draft', 'submitted', 'withdrawn', 'archived');

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,39}$'),
  name text not null check (char_length(trim(name)) between 1 and 100),
  active boolean not null default true,
  system_default boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code)
);

create table public.expense_projects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  name text not null check (char_length(trim(name)) between 1 and 120),
  active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code)
);

create table public.expense_cost_centres (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$'),
  name text not null check (char_length(trim(name)) between 1 and 120),
  active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code)
);

create table public.expense_reports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  employee_id uuid not null references auth.users(id) on delete restrict,
  status public.expense_report_status not null default 'draft',
  title text not null check (char_length(trim(title)) between 1 and 160),
  period_start date not null,
  period_end date not null,
  version integer not null default 1 check (version > 0),
  submitted_at timestamptz,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expense_report_period_check check (
    period_end >= period_start and period_end <= period_start + 366
  ),
  constraint expense_report_timestamps_check check (
    (status = 'draft' and submitted_at is null and withdrawn_at is null)
    or (status = 'submitted' and submitted_at is not null and withdrawn_at is null)
    or (status = 'withdrawn' and submitted_at is not null and withdrawn_at is not null)
    or status = 'archived'
  )
);

create table public.expense_claims (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  employee_id uuid not null references auth.users(id) on delete restrict,
  receipt_id uuid not null unique references public.receipts(id) on delete restrict,
  status public.expense_claim_status not null default 'draft',
  category_id uuid not null references public.expense_categories(id) on delete restrict,
  project_id uuid references public.expense_projects(id) on delete restrict,
  cost_centre_id uuid references public.expense_cost_centres(id) on delete restrict,
  merchant_name text check (merchant_name is null or char_length(trim(merchant_name)) between 1 and 200),
  incurred_on date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(18,4) not null check (amount > 0),
  business_purpose text not null check (char_length(trim(business_purpose)) between 3 and 1000),
  notes text check (notes is null or char_length(notes) <= 2000),
  receipt_facts jsonb not null,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expense_report_items (
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  claim_id uuid not null references public.expense_claims(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  position integer not null check (position > 0),
  added_by uuid not null references auth.users(id) on delete restrict,
  added_at timestamptz not null default now(),
  primary key (report_id, claim_id),
  unique (claim_id),
  unique (report_id, position)
);

create table public.expense_report_submissions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  submission_number integer not null check (submission_number > 0),
  snapshot jsonb not null,
  totals_by_currency jsonb not null,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (report_id, submission_number)
);

create index expense_categories_company_active_idx on public.expense_categories (company_id, active, name);
create index expense_projects_company_active_idx on public.expense_projects (company_id, active, name);
create index expense_cost_centres_company_active_idx on public.expense_cost_centres (company_id, active, name);
create index expense_claims_employee_status_idx on public.expense_claims (employee_id, status, created_at desc);
create index expense_claims_company_status_idx on public.expense_claims (company_id, status, created_at desc);
create index expense_reports_employee_status_idx on public.expense_reports (employee_id, status, created_at desc);
create index expense_reports_company_status_idx on public.expense_reports (company_id, status, created_at desc);
create index expense_report_items_report_position_idx on public.expense_report_items (report_id, position);
create index expense_report_submissions_report_created_idx on public.expense_report_submissions (report_id, created_at desc);

alter table public.audit_events
  add column expense_claim_id uuid references public.expense_claims(id) on delete restrict,
  add column expense_report_id uuid references public.expense_reports(id) on delete restrict;
create index audit_events_claim_created_idx on public.audit_events (expense_claim_id, created_at desc)
  where expense_claim_id is not null;
create index audit_events_report_created_idx on public.audit_events (expense_report_id, created_at desc)
  where expense_report_id is not null;

create trigger expense_categories_set_updated_at before update on public.expense_categories
for each row execute function public.set_updated_at();
create trigger expense_projects_set_updated_at before update on public.expense_projects
for each row execute function public.set_updated_at();
create trigger expense_cost_centres_set_updated_at before update on public.expense_cost_centres
for each row execute function public.set_updated_at();
create trigger expense_reports_set_updated_at before update on public.expense_reports
for each row execute function public.set_updated_at();
create trigger expense_claims_set_updated_at before update on public.expense_claims
for each row execute function public.set_updated_at();

create or replace function public.try_date(value text)
returns date language plpgsql immutable security invoker as $$
begin
  return value::date;
exception when others then
  return null;
end;
$$;

create or replace function public.validate_expense_report_status_transition()
returns trigger language plpgsql security invoker set search_path = public as $$
declare allowed boolean := false;
begin
  if new.status = old.status then return new; end if;
  allowed := case old.status
    when 'draft' then new.status in ('submitted', 'archived')
    when 'submitted' then new.status in ('withdrawn', 'archived')
    when 'withdrawn' then new.status = 'archived'
    else false
  end;
  if not allowed then
    raise exception 'Illegal expense report status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger expense_reports_validate_status_transition
before update of status on public.expense_reports
for each row execute function public.validate_expense_report_status_transition();

create or replace function public.validate_expense_claim_status_transition()
returns trigger language plpgsql security invoker set search_path = public as $$
declare allowed boolean := false;
begin
  if new.status = old.status then return new; end if;
  allowed := case old.status
    when 'draft' then new.status in ('submitted', 'archived')
    when 'submitted' then new.status in ('draft', 'archived')
    else false
  end;
  if not allowed then
    raise exception 'Illegal expense claim status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger expense_claims_validate_status_transition
before update of status on public.expense_claims
for each row execute function public.validate_expense_claim_status_transition();

create or replace function public.validate_expense_claim_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  receipt_company uuid;
  receipt_submitter uuid;
  receipt_state public.receipt_status;
  category_company uuid;
  project_company uuid;
  centre_company uuid;
begin
  select company_id, submitted_by, status
    into receipt_company, receipt_submitter, receipt_state
  from public.receipts where id = new.receipt_id;

  if receipt_company is distinct from new.company_id
     or receipt_submitter is distinct from new.employee_id then
    raise exception 'Claim receipt scope does not match company and employee'
      using errcode = 'check_violation';
  end if;
  if receipt_state <> 'verified' then
    raise exception 'A claim must be backed by a verified receipt'
      using errcode = 'check_violation';
  end if;

  select company_id into category_company from public.expense_categories where id = new.category_id;
  if category_company is distinct from new.company_id then
    raise exception 'Claim category is outside company scope' using errcode = 'check_violation';
  end if;

  if new.project_id is not null then
    select company_id into project_company from public.expense_projects where id = new.project_id;
    if project_company is distinct from new.company_id then
      raise exception 'Claim project is outside company scope' using errcode = 'check_violation';
    end if;
  end if;

  if new.cost_centre_id is not null then
    select company_id into centre_company from public.expense_cost_centres where id = new.cost_centre_id;
    if centre_company is distinct from new.company_id then
      raise exception 'Claim cost centre is outside company scope' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger expense_claims_validate_scope
before insert or update of company_id, employee_id, receipt_id, category_id, project_id, cost_centre_id
on public.expense_claims for each row execute function public.validate_expense_claim_scope();

create or replace function public.validate_expense_report_item_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  report_company uuid;
  report_employee uuid;
  report_state public.expense_report_status;
  claim_company uuid;
  claim_employee uuid;
  claim_state public.expense_claim_status;
begin
  select company_id, employee_id, status
    into report_company, report_employee, report_state
  from public.expense_reports where id = new.report_id;
  select company_id, employee_id, status
    into claim_company, claim_employee, claim_state
  from public.expense_claims where id = new.claim_id;

  if report_company is distinct from new.company_id
     or claim_company is distinct from new.company_id
     or report_employee is distinct from claim_employee then
    raise exception 'Report item scope does not match company and employee'
      using errcode = 'check_violation';
  end if;
  if report_state <> 'draft' or claim_state <> 'draft' then
    raise exception 'Only draft reports and claims may be assembled'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger expense_report_items_validate_scope
before insert or update on public.expense_report_items
for each row execute function public.validate_expense_report_item_scope();

create or replace function public.validate_expense_submission_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare report_company uuid;
begin
  select company_id into report_company from public.expense_reports where id = new.report_id;
  if report_company is distinct from new.company_id then
    raise exception 'Submission company does not match report company'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger expense_report_submissions_validate_scope
before insert or update on public.expense_report_submissions
for each row execute function public.validate_expense_submission_scope();

create or replace function public.validate_audit_event_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare parent_company_id uuid;
begin
  if new.receipt_id is not null then
    select company_id into parent_company_id from public.receipts where id = new.receipt_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit receipt company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  if new.expense_claim_id is not null then
    select company_id into parent_company_id from public.expense_claims where id = new.expense_claim_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit claim company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  if new.expense_report_id is not null then
    select company_id into parent_company_id from public.expense_reports where id = new.expense_report_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit report company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.seed_default_expense_categories()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.expense_categories (company_id, code, name, system_default, created_by)
  values
    (new.id, 'travel', 'Travel', true, new.created_by),
    (new.id, 'meals', 'Meals', true, new.created_by),
    (new.id, 'lodging', 'Lodging', true, new.created_by),
    (new.id, 'fuel', 'Fuel', true, new.created_by),
    (new.id, 'software', 'Software', true, new.created_by),
    (new.id, 'office', 'Office supplies', true, new.created_by),
    (new.id, 'other', 'Other', true, new.created_by)
  on conflict (company_id, code) do nothing;
  return new;
end;
$$;
create trigger companies_seed_expense_categories
after insert on public.companies for each row execute function public.seed_default_expense_categories();

insert into public.expense_categories (company_id, code, name, system_default, created_by)
select company.id, category.code, category.name, true, company.created_by
from public.companies company
cross join (values
  ('travel', 'Travel'),
  ('meals', 'Meals'),
  ('lodging', 'Lodging'),
  ('fuel', 'Fuel'),
  ('software', 'Software'),
  ('office', 'Office supplies'),
  ('other', 'Other')
) as category(code, name)
on conflict (company_id, code) do nothing;

create or replace function public.can_view_expense_report(target_report_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.expense_reports report
    where report.id = target_report_id
      and (
        report.employee_id = auth.uid()
        or public.has_company_role(
          report.company_id,
          array['manager', 'finance', 'admin', 'auditor']::public.company_role[]
        )
      )
  );
$$;

create or replace function public.verified_receipt_facts(p_receipt_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with target as (
    select id, latest_extraction_run_id from public.receipts
    where id = p_receipt_id and status = 'verified'
  ),
  latest_resolution as (
    select distinct on (resolution.field_name)
      resolution.field_name, resolution.resolved_value
    from public.field_resolutions resolution
    join target on target.id = resolution.receipt_id
    order by resolution.field_name, resolution.created_at desc
  ),
  facts as (
    select field.field_name,
      case when resolution.field_name is not null
        then resolution.resolved_value else field.value_json end as value
    from public.extracted_fields field
    join target on target.latest_extraction_run_id = field.extraction_run_id
    left join latest_resolution resolution on resolution.field_name = field.field_name
  )
  select coalesce(jsonb_object_agg(field_name, value), '{}'::jsonb) from facts;
$$;

create or replace function public.create_expense_claim_from_receipt(
  p_receipt_id uuid,
  p_category_id uuid,
  p_project_id uuid,
  p_cost_centre_id uuid,
  p_business_purpose text,
  p_notes text,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  current_receipt public.receipts%rowtype;
  facts jsonb;
  total_text text;
  currency_text text;
  merchant_text text;
  incurred_date date;
  claim public.expense_claims%rowtype;
  active_reference boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into current_receipt from public.receipts where id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found' using errcode = 'no_data_found'; end if;
  if current_receipt.submitted_by <> current_user_id
     or not public.is_company_member(current_receipt.company_id) then
    raise exception 'Receipt is not owned by the authenticated employee'
      using errcode = 'insufficient_privilege';
  end if;
  if current_receipt.status <> 'verified' then
    raise exception 'Receipt must be verified before creating a claim'
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.expense_claims where receipt_id = p_receipt_id) then
    raise exception 'A claim already exists for this receipt' using errcode = 'unique_violation';
  end if;

  select active into active_reference from public.expense_categories
  where id = p_category_id and company_id = current_receipt.company_id;
  if active_reference is distinct from true then
    raise exception 'An active company category is required' using errcode = 'check_violation';
  end if;
  if p_project_id is not null then
    select active into active_reference from public.expense_projects
    where id = p_project_id and company_id = current_receipt.company_id;
    if active_reference is distinct from true then
      raise exception 'Project is inactive or outside company scope' using errcode = 'check_violation';
    end if;
  end if;
  if p_cost_centre_id is not null then
    select active into active_reference from public.expense_cost_centres
    where id = p_cost_centre_id and company_id = current_receipt.company_id;
    if active_reference is distinct from true then
      raise exception 'Cost centre is inactive or outside company scope' using errcode = 'check_violation';
    end if;
  end if;
  if char_length(trim(p_business_purpose)) not between 3 and 1000 then
    raise exception 'Business purpose must contain 3 to 1000 characters'
      using errcode = 'check_violation';
  end if;
  if p_notes is not null and char_length(p_notes) > 2000 then
    raise exception 'Notes must not exceed 2000 characters' using errcode = 'check_violation';
  end if;

  facts := public.verified_receipt_facts(p_receipt_id);
  total_text := facts->>'total';
  currency_text := upper(trim(coalesce(facts->>'currency', '')));
  merchant_text := nullif(trim(coalesce(facts->>'merchant_name', '')), '');
  incurred_date := public.try_date(facts->>'invoice_date');
  if incurred_date is null then
    incurred_date := coalesce(current_receipt.captured_at::date, current_receipt.created_at::date);
  end if;

  if total_text is null or total_text !~ '^\d+(\.\d{1,4})?$' or total_text::numeric <= 0 then
    raise exception 'Verified total is missing or invalid' using errcode = 'check_violation';
  end if;
  if currency_text !~ '^[A-Z]{3}$' then
    raise exception 'Verified currency is missing or invalid' using errcode = 'check_violation';
  end if;

  insert into public.expense_claims (
    company_id, employee_id, receipt_id, category_id, project_id, cost_centre_id,
    merchant_name, incurred_on, currency, amount, business_purpose, notes, receipt_facts
  ) values (
    current_receipt.company_id, current_user_id, current_receipt.id, p_category_id,
    p_project_id, p_cost_centre_id, merchant_text, incurred_date, currency_text,
    total_text::numeric(18,4), trim(p_business_purpose), nullif(trim(p_notes), ''), facts
  ) returning * into claim;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, event_type, request_id, payload
  ) values (
    claim.company_id, current_user_id, claim.receipt_id, claim.id,
    'expense.claim_created', p_request_id,
    jsonb_build_object('amount', claim.amount::text, 'currency', claim.currency)
  );

  return to_jsonb(claim);
end;
$$;

create or replace function public.update_expense_claim(
  p_claim_id uuid,
  p_expected_version integer,
  p_patch jsonb,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  claim public.expense_claims%rowtype;
  category_value uuid;
  project_value uuid;
  centre_value uuid;
  purpose_value text;
  notes_value text;
  active_reference boolean;
  unknown_key text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Claim patch must be an object' using errcode = 'check_violation';
  end if;
  select key into unknown_key from jsonb_object_keys(p_patch) as key
  where key not in ('categoryId', 'projectId', 'costCentreId', 'businessPurpose', 'notes') limit 1;
  if unknown_key is not null then
    raise exception 'Unsupported claim patch field: %', unknown_key using errcode = 'check_violation';
  end if;

  select * into claim from public.expense_claims where id = p_claim_id for update;
  if not found then raise exception 'Expense claim not found' using errcode = 'no_data_found'; end if;
  if claim.employee_id <> current_user_id then
    raise exception 'Only the owning employee may edit this claim'
      using errcode = 'insufficient_privilege';
  end if;
  if claim.status <> 'draft' then
    raise exception 'Only draft claims may be edited' using errcode = 'check_violation';
  end if;
  if claim.version <> p_expected_version then
    raise exception 'Expense claim version conflict' using errcode = 'serialization_failure';
  end if;

  category_value := claim.category_id;
  project_value := claim.project_id;
  centre_value := claim.cost_centre_id;
  purpose_value := claim.business_purpose;
  notes_value := claim.notes;

  if p_patch ? 'categoryId' then
    category_value := (p_patch->>'categoryId')::uuid;
    select active into active_reference from public.expense_categories
    where id = category_value and company_id = claim.company_id;
    if active_reference is distinct from true then
      raise exception 'An active company category is required' using errcode = 'check_violation';
    end if;
  end if;
  if p_patch ? 'projectId' then
    project_value := case when p_patch->'projectId' = 'null'::jsonb then null
      else (p_patch->>'projectId')::uuid end;
    if project_value is not null then
      select active into active_reference from public.expense_projects
      where id = project_value and company_id = claim.company_id;
      if active_reference is distinct from true then
        raise exception 'Project is inactive or outside company scope' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  if p_patch ? 'costCentreId' then
    centre_value := case when p_patch->'costCentreId' = 'null'::jsonb then null
      else (p_patch->>'costCentreId')::uuid end;
    if centre_value is not null then
      select active into active_reference from public.expense_cost_centres
      where id = centre_value and company_id = claim.company_id;
      if active_reference is distinct from true then
        raise exception 'Cost centre is inactive or outside company scope' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  if p_patch ? 'businessPurpose' then
    purpose_value := trim(coalesce(p_patch->>'businessPurpose', ''));
    if char_length(purpose_value) not between 3 and 1000 then
      raise exception 'Business purpose must contain 3 to 1000 characters'
        using errcode = 'check_violation';
    end if;
  end if;
  if p_patch ? 'notes' then
    notes_value := nullif(trim(coalesce(p_patch->>'notes', '')), '');
    if notes_value is not null and char_length(notes_value) > 2000 then
      raise exception 'Notes must not exceed 2000 characters' using errcode = 'check_violation';
    end if;
  end if;

  update public.expense_claims set
    category_id = category_value,
    project_id = project_value,
    cost_centre_id = centre_value,
    business_purpose = purpose_value,
    notes = notes_value,
    version = version + 1
  where id = claim.id returning * into claim;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, event_type, request_id, payload
  ) values (
    claim.company_id, current_user_id, claim.receipt_id, claim.id,
    'expense.claim_updated', p_request_id,
    jsonb_build_object('version', claim.version, 'changedFields', p_patch)
  );

  return to_jsonb(claim);
end;
$$;

create or replace function public.create_expense_report(
  p_company_id uuid,
  p_title text,
  p_period_start date,
  p_period_end date,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  report public.expense_reports%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if not public.is_company_member(p_company_id) then
    raise exception 'Company membership required' using errcode = 'insufficient_privilege';
  end if;
  if char_length(trim(p_title)) not between 1 and 160 then
    raise exception 'Report title is invalid' using errcode = 'check_violation';
  end if;
  if p_period_end < p_period_start or p_period_end > p_period_start + 366 then
    raise exception 'Report period is invalid' using errcode = 'check_violation';
  end if;

  insert into public.expense_reports (company_id, employee_id, title, period_start, period_end)
  values (p_company_id, current_user_id, trim(p_title), p_period_start, p_period_end)
  returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, expense_report_id, event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, report.id, 'expense.report_created', p_request_id,
    jsonb_build_object('periodStart', report.period_start, 'periodEnd', report.period_end)
  );
  return to_jsonb(report);
end;
$$;

create or replace function public.add_claim_to_expense_report(
  p_report_id uuid,
  p_claim_id uuid,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  report public.expense_reports%rowtype;
  claim public.expense_claims%rowtype;
  next_position integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  select * into report from public.expense_reports where id = p_report_id for update;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  select * into claim from public.expense_claims where id = p_claim_id for update;
  if not found then raise exception 'Expense claim not found' using errcode = 'no_data_found'; end if;
  if report.employee_id <> current_user_id or claim.employee_id <> current_user_id
     or report.company_id <> claim.company_id then
    raise exception 'Report and claim must belong to the authenticated employee and company'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' or claim.status <> 'draft' then
    raise exception 'Only draft reports and claims may be assembled'
      using errcode = 'check_violation';
  end if;

  select coalesce(max(position), 0) + 1 into next_position
  from public.expense_report_items where report_id = report.id;
  insert into public.expense_report_items (report_id, claim_id, company_id, position, added_by)
  values (report.id, claim.id, report.company_id, next_position, current_user_id);

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, expense_report_id,
    event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, claim.receipt_id, claim.id, report.id,
    'expense.report_item_added', p_request_id, jsonb_build_object('position', next_position)
  );
  return jsonb_build_object('reportId', report.id, 'claimId', claim.id, 'position', next_position);
end;
$$;

create or replace function public.remove_claim_from_expense_report(
  p_report_id uuid,
  p_claim_id uuid,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  report public.expense_reports%rowtype;
  claim public.expense_claims%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  select * into report from public.expense_reports where id = p_report_id for update;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  select * into claim from public.expense_claims where id = p_claim_id;
  if not found then raise exception 'Expense claim not found' using errcode = 'no_data_found'; end if;
  if report.employee_id <> current_user_id or claim.employee_id <> current_user_id then
    raise exception 'Only the owning employee may change report items'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' then
    raise exception 'Only draft reports may be changed' using errcode = 'check_violation';
  end if;

  delete from public.expense_report_items
  where report_id = report.id and claim_id = claim.id;
  if not found then raise exception 'Claim is not attached to this report' using errcode = 'no_data_found'; end if;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, expense_report_id,
    event_type, request_id
  ) values (
    report.company_id, current_user_id, claim.receipt_id, claim.id, report.id,
    'expense.report_item_removed', p_request_id
  );
  return jsonb_build_object('reportId', report.id, 'claimId', claim.id, 'removed', true);
end;
$$;

create or replace function public.submit_expense_report(
  p_report_id uuid,
  p_expected_version integer,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  report public.expense_reports%rowtype;
  invalid_count integer;
  item_count integer;
  open_duplicates integer;
  item_snapshot jsonb;
  totals jsonb;
  submission_number integer;
  submission_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  select * into report from public.expense_reports where id = p_report_id for update;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  if report.employee_id <> current_user_id then
    raise exception 'Only the owning employee may submit this report'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' then
    raise exception 'Only draft reports may be submitted' using errcode = 'check_violation';
  end if;
  if report.version <> p_expected_version then
    raise exception 'Expense report version conflict' using errcode = 'serialization_failure';
  end if;

  select count(*) into item_count from public.expense_report_items where report_id = report.id;
  if item_count = 0 then
    raise exception 'At least one expense claim is required' using errcode = 'check_violation';
  end if;

  select count(*) into invalid_count
  from public.expense_report_items item
  join public.expense_claims claim on claim.id = item.claim_id
  join public.receipts receipt on receipt.id = claim.receipt_id
  join public.expense_categories category on category.id = claim.category_id
  left join public.expense_projects project on project.id = claim.project_id
  left join public.expense_cost_centres centre on centre.id = claim.cost_centre_id
  where item.report_id = report.id
    and (
      item.company_id <> report.company_id
      or claim.company_id <> report.company_id
      or claim.employee_id <> report.employee_id
      or claim.status <> 'draft'
      or receipt.status <> 'verified'
      or category.company_id <> report.company_id
      or category.active is not true
      or (claim.project_id is not null and (project.company_id <> report.company_id or project.active is not true))
      or (claim.cost_centre_id is not null and (centre.company_id <> report.company_id or centre.active is not true))
      or char_length(trim(claim.business_purpose)) < 3
      or claim.amount <= 0
      or claim.currency !~ '^[A-Z]{3}$'
      or claim.incurred_on < report.period_start
      or claim.incurred_on > report.period_end
    );
  if invalid_count > 0 then
    raise exception 'Report contains % claim(s) that are not ready for submission', invalid_count
      using errcode = 'check_violation';
  end if;

  select count(*) into open_duplicates
  from public.expense_report_items item
  join public.expense_claims claim on claim.id = item.claim_id
  join public.duplicate_candidates candidate
    on candidate.resolution = 'open'
   and (candidate.receipt_id = claim.receipt_id
     or candidate.possible_duplicate_receipt_id = claim.receipt_id)
  where item.report_id = report.id;
  if open_duplicates > 0 then
    raise exception 'Open duplicate candidates block report submission'
      using errcode = 'check_violation';
  end if;

  select jsonb_agg(jsonb_build_object(
    'position', item.position,
    'claimId', claim.id,
    'receiptId', claim.receipt_id,
    'merchantName', claim.merchant_name,
    'incurredOn', claim.incurred_on,
    'currency', claim.currency,
    'amount', claim.amount::text,
    'businessPurpose', claim.business_purpose,
    'notes', claim.notes,
    'category', jsonb_build_object('id', category.id, 'code', category.code, 'name', category.name),
    'project', case when project.id is null then null else
      jsonb_build_object('id', project.id, 'code', project.code, 'name', project.name) end,
    'costCentre', case when centre.id is null then null else
      jsonb_build_object('id', centre.id, 'code', centre.code, 'name', centre.name) end,
    'receiptFacts', claim.receipt_facts,
    'claimVersion', claim.version
  ) order by item.position)
  into item_snapshot
  from public.expense_report_items item
  join public.expense_claims claim on claim.id = item.claim_id
  join public.expense_categories category on category.id = claim.category_id
  left join public.expense_projects project on project.id = claim.project_id
  left join public.expense_cost_centres centre on centre.id = claim.cost_centre_id
  where item.report_id = report.id;

  select coalesce(jsonb_object_agg(currency, total_text), '{}'::jsonb) into totals
  from (
    select claim.currency, sum(claim.amount)::text as total_text
    from public.expense_report_items item
    join public.expense_claims claim on claim.id = item.claim_id
    where item.report_id = report.id
    group by claim.currency
    order by claim.currency
  ) grouped_totals;

  select coalesce(max(existing.submission_number), 0) + 1 into submission_number
  from public.expense_report_submissions existing where existing.report_id = report.id;

  insert into public.expense_report_submissions (
    report_id, company_id, submission_number, snapshot, totals_by_currency, submitted_by
  ) values (
    report.id,
    report.company_id,
    submission_number,
    jsonb_build_object(
      'report', jsonb_build_object(
        'id', report.id,
        'companyId', report.company_id,
        'employeeId', report.employee_id,
        'title', report.title,
        'periodStart', report.period_start,
        'periodEnd', report.period_end,
        'version', report.version
      ),
      'items', item_snapshot
    ),
    totals,
    current_user_id
  ) returning id into submission_id;

  update public.expense_claims claim set status = 'submitted'
  from public.expense_report_items item
  where item.report_id = report.id and item.claim_id = claim.id;

  update public.expense_reports set
    status = 'submitted', submitted_at = now(), version = version + 1
  where id = report.id returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, expense_report_id, event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, report.id, 'expense.report_submitted', p_request_id,
    jsonb_build_object(
      'submissionId', submission_id,
      'submissionNumber', submission_number,
      'itemCount', item_count,
      'totalsByCurrency', totals,
      'version', report.version
    )
  );

  return jsonb_build_object(
    'reportId', report.id,
    'submissionId', submission_id,
    'submissionNumber', submission_number,
    'itemCount', item_count,
    'totalsByCurrency', totals,
    'version', report.version,
    'status', report.status
  );
end;
$$;

create or replace function public.withdraw_expense_report(
  p_report_id uuid,
  p_expected_version integer,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  report public.expense_reports%rowtype;
  released_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  select * into report from public.expense_reports where id = p_report_id for update;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  if report.employee_id <> current_user_id then
    raise exception 'Only the owning employee may withdraw this report'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'submitted' then
    raise exception 'Only submitted reports may be withdrawn' using errcode = 'check_violation';
  end if;
  if report.version <> p_expected_version then
    raise exception 'Expense report version conflict' using errcode = 'serialization_failure';
  end if;

  update public.expense_claims claim set status = 'draft'
  from public.expense_report_items item
  where item.report_id = report.id and item.claim_id = claim.id;
  get diagnostics released_count = row_count;

  delete from public.expense_report_items where report_id = report.id;
  update public.expense_reports set
    status = 'withdrawn', withdrawn_at = now(), version = version + 1
  where id = report.id returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, expense_report_id, event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, report.id, 'expense.report_withdrawn', p_request_id,
    jsonb_build_object('releasedClaimCount', released_count, 'version', report.version)
  );

  return jsonb_build_object(
    'reportId', report.id,
    'status', report.status,
    'releasedClaimCount', released_count,
    'version', report.version
  );
end;
$$;

alter table public.expense_categories enable row level security;
alter table public.expense_projects enable row level security;
alter table public.expense_cost_centres enable row level security;
alter table public.expense_claims enable row level security;
alter table public.expense_reports enable row level security;
alter table public.expense_report_items enable row level security;
alter table public.expense_report_submissions enable row level security;

create policy expense_categories_select_member on public.expense_categories
for select to authenticated using (public.is_company_member(company_id));
create policy expense_categories_insert_finance on public.expense_categories
for insert to authenticated with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
  and created_by = auth.uid()
);
create policy expense_categories_update_finance on public.expense_categories
for update to authenticated using (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
) with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
);

create policy expense_projects_select_member on public.expense_projects
for select to authenticated using (public.is_company_member(company_id));
create policy expense_projects_insert_finance on public.expense_projects
for insert to authenticated with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
  and created_by = auth.uid()
);
create policy expense_projects_update_finance on public.expense_projects
for update to authenticated using (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
) with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
);

create policy expense_cost_centres_select_member on public.expense_cost_centres
for select to authenticated using (public.is_company_member(company_id));
create policy expense_cost_centres_insert_finance on public.expense_cost_centres
for insert to authenticated with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
  and created_by = auth.uid()
);
create policy expense_cost_centres_update_finance on public.expense_cost_centres
for update to authenticated using (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
) with check (
  public.has_company_role(company_id, array['finance', 'admin']::public.company_role[])
);

create policy expense_claims_select_visible on public.expense_claims
for select to authenticated using (
  employee_id = auth.uid()
  or public.has_company_role(
    company_id,
    array['manager', 'finance', 'admin', 'auditor']::public.company_role[]
  )
);
create policy expense_reports_select_visible on public.expense_reports
for select to authenticated using (
  employee_id = auth.uid()
  or public.has_company_role(
    company_id,
    array['manager', 'finance', 'admin', 'auditor']::public.company_role[]
  )
);
create policy expense_report_items_select_visible on public.expense_report_items
for select to authenticated using (public.can_view_expense_report(report_id));
create policy expense_report_submissions_select_visible on public.expense_report_submissions
for select to authenticated using (public.can_view_expense_report(report_id));

revoke all on public.expense_claims, public.expense_reports,
  public.expense_report_items, public.expense_report_submissions from authenticated;
grant select on public.expense_claims, public.expense_reports,
  public.expense_report_items, public.expense_report_submissions to authenticated;
grant select, insert, update on public.expense_categories,
  public.expense_projects, public.expense_cost_centres to authenticated;
grant all on public.expense_categories, public.expense_projects, public.expense_cost_centres,
  public.expense_claims, public.expense_reports, public.expense_report_items,
  public.expense_report_submissions to service_role;

grant execute on function public.create_expense_claim_from_receipt(uuid, uuid, uuid, uuid, text, text, text)
  to authenticated;
grant execute on function public.update_expense_claim(uuid, integer, jsonb, text) to authenticated;
grant execute on function public.create_expense_report(uuid, text, date, date, text) to authenticated;
grant execute on function public.add_claim_to_expense_report(uuid, uuid, text) to authenticated;
grant execute on function public.remove_claim_from_expense_report(uuid, uuid, text) to authenticated;
grant execute on function public.submit_expense_report(uuid, integer, text) to authenticated;
grant execute on function public.withdraw_expense_report(uuid, integer, text) to authenticated;

revoke all on function public.verified_receipt_facts(uuid) from public, authenticated;
revoke all on function public.create_expense_claim_from_receipt(uuid, uuid, uuid, uuid, text, text, text) from public;
revoke all on function public.update_expense_claim(uuid, integer, jsonb, text) from public;
revoke all on function public.create_expense_report(uuid, text, date, date, text) from public;
revoke all on function public.add_claim_to_expense_report(uuid, uuid, text) from public;
revoke all on function public.remove_claim_from_expense_report(uuid, uuid, text) from public;
revoke all on function public.submit_expense_report(uuid, integer, text) from public;
revoke all on function public.withdraw_expense_report(uuid, integer, text) from public;

commit;
