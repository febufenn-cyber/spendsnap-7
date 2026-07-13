-- Spendsnap Phase 3: deterministic, versioned expense policy evaluation.
begin;

create type public.policy_rule_type as enum (
  'max_amount',
  'expense_age_days',
  'weekend_requires_note',
  'category_blocked',
  'project_required',
  'cost_centre_required',
  'gstin_required'
);
create type public.policy_severity as enum ('warning', 'block', 'requires_exception');
create type public.policy_evaluation_outcome as enum ('pass', 'warning', 'blocked');
create type public.policy_result_outcome as enum ('pass', 'fail', 'not_applicable', 'waived');
create type public.policy_exception_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create table public.expense_policy_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_.-]{1,59}$'),
  name text not null check (char_length(trim(name)) between 1 and 140),
  description text check (description is null or char_length(description) <= 1000),
  rule_type public.policy_rule_type not null,
  severity public.policy_severity not null,
  config jsonb not null,
  version integer not null check (version > 0),
  active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  supersedes_rule_id uuid references public.expense_policy_rules(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code, version),
  constraint policy_effective_range_check check (
    effective_to is null or effective_to > effective_from
  )
);

create index expense_policy_rules_company_effective_idx
  on public.expense_policy_rules (company_id, active, effective_from, effective_to, code, version desc);
create index expense_policy_rules_supersedes_idx
  on public.expense_policy_rules (supersedes_rule_id) where supersedes_rule_id is not null;

create table public.policy_evaluation_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  report_version integer not null check (report_version > 0),
  evaluated_by uuid not null references auth.users(id) on delete restrict,
  evaluated_on date not null default current_date,
  rules_snapshot jsonb not null,
  policy_set_hash text not null check (policy_set_hash ~ '^[a-f0-9]{64}$'),
  outcome public.policy_evaluation_outcome,
  counts jsonb not null default '{}'::jsonb,
  request_id text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint policy_run_completion_check check (
    (outcome is null and completed_at is null)
    or (outcome is not null and completed_at is not null)
  )
);

create index policy_evaluation_runs_report_created_idx
  on public.policy_evaluation_runs (report_id, created_at desc);
create index policy_evaluation_runs_company_created_idx
  on public.policy_evaluation_runs (company_id, created_at desc);

create table public.policy_evaluation_results (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.policy_evaluation_runs(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  claim_id uuid references public.expense_claims(id) on delete restrict,
  rule_id uuid not null references public.expense_policy_rules(id) on delete restrict,
  rule_code text not null,
  rule_version integer not null check (rule_version > 0),
  severity public.policy_severity not null,
  outcome public.policy_result_outcome not null,
  explanation text not null check (char_length(explanation) between 1 and 2000),
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index policy_evaluation_results_run_idx
  on public.policy_evaluation_results (run_id, created_at, rule_code, claim_id);
create index policy_evaluation_results_report_idx
  on public.policy_evaluation_results (report_id, created_at desc);
create index policy_evaluation_results_failed_idx
  on public.policy_evaluation_results (report_id, severity, created_at desc)
  where outcome = 'fail';

create table public.policy_exception_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  claim_id uuid references public.expense_claims(id) on delete restrict,
  rule_id uuid not null references public.expense_policy_rules(id) on delete restrict,
  evaluation_result_id uuid not null unique references public.policy_evaluation_results(id) on delete restrict,
  employee_id uuid not null references auth.users(id) on delete restrict,
  report_version_at_request integer not null check (report_version_at_request > 0),
  claim_version_at_request integer check (claim_version_at_request is null or claim_version_at_request > 0),
  status public.policy_exception_status not null default 'pending',
  reason text not null check (char_length(trim(reason)) between 10 and 2000),
  reviewed_by uuid references auth.users(id) on delete restrict,
  review_note text check (review_note is null or char_length(review_note) <= 2000),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint policy_exception_review_check check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status in ('approved', 'rejected') and reviewed_by is not null and reviewed_at is not null)
    or status = 'cancelled'
  )
);

create index policy_exception_requests_report_status_idx
  on public.policy_exception_requests (report_id, status, created_at desc);
create index policy_exception_requests_company_status_idx
  on public.policy_exception_requests (company_id, status, created_at desc);
create index policy_exception_requests_match_idx
  on public.policy_exception_requests (
    report_id, rule_id, claim_id, report_version_at_request, claim_version_at_request, status
  );

alter table public.audit_events
  add column policy_rule_id uuid references public.expense_policy_rules(id) on delete restrict,
  add column policy_evaluation_run_id uuid references public.policy_evaluation_runs(id) on delete restrict,
  add column policy_exception_id uuid references public.policy_exception_requests(id) on delete restrict;

create index audit_events_policy_rule_created_idx
  on public.audit_events (policy_rule_id, created_at desc) where policy_rule_id is not null;
create index audit_events_policy_run_created_idx
  on public.audit_events (policy_evaluation_run_id, created_at desc)
  where policy_evaluation_run_id is not null;
create index audit_events_policy_exception_created_idx
  on public.audit_events (policy_exception_id, created_at desc)
  where policy_exception_id is not null;

create or replace function public.lock_company_policy(target_company_id uuid)
returns void language plpgsql security invoker set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('spendsnap-policy:' || target_company_id::text, 0));
end;
$$;

create or replace function public.assert_policy_rule_config(
  p_company_id uuid,
  p_rule_type public.policy_rule_type,
  p_config jsonb
)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  category_id uuid;
  amount_text text;
  integer_text text;
  allowed_keys text[];
  key_name text;
begin
  if jsonb_typeof(p_config) <> 'object' then
    raise exception 'Policy rule configuration must be a JSON object'
      using errcode = 'check_violation';
  end if;

  allowed_keys := case p_rule_type
    when 'max_amount' then array['currency', 'amount', 'categoryId']
    when 'expense_age_days' then array['maxDays']
    when 'weekend_requires_note' then array['minimumNoteLength']
    when 'category_blocked' then array['categoryId']
    when 'project_required' then array['categoryId']
    when 'cost_centre_required' then array['categoryId']
    when 'gstin_required' then array['categoryId']
  end;

  for key_name in select jsonb_object_keys(p_config)
  loop
    if not (key_name = any(allowed_keys)) then
      raise exception 'Unsupported configuration key for %: %', p_rule_type, key_name
        using errcode = 'check_violation';
    end if;
  end loop;

  if p_rule_type = 'max_amount' then
    if coalesce(p_config->>'currency', '') !~ '^[A-Z]{3}$' then
      raise exception 'max_amount requires a three-letter uppercase currency'
        using errcode = 'check_violation';
    end if;
    amount_text := p_config->>'amount';
    if amount_text is null or amount_text !~ '^\d+(\.\d{1,4})?$' or amount_text::numeric <= 0 then
      raise exception 'max_amount requires a positive exact-decimal amount'
        using errcode = 'check_violation';
    end if;
  elsif p_rule_type = 'expense_age_days' then
    integer_text := p_config->>'maxDays';
    if integer_text is null or integer_text !~ '^\d+$'
       or integer_text::integer not between 1 and 3650 then
      raise exception 'expense_age_days maxDays must be between 1 and 3650'
        using errcode = 'check_violation';
    end if;
  elsif p_rule_type = 'weekend_requires_note' then
    integer_text := p_config->>'minimumNoteLength';
    if integer_text is null or integer_text !~ '^\d+$'
       or integer_text::integer not between 1 and 1000 then
      raise exception 'weekend_requires_note minimumNoteLength must be between 1 and 1000'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_config ? 'categoryId' and p_config->'categoryId' <> 'null'::jsonb then
    category_id := public.try_uuid(p_config->>'categoryId');
    if category_id is null or not exists (
      select 1 from public.expense_categories category
      where category.id = category_id and category.company_id = p_company_id
    ) then
      raise exception 'Policy categoryId is invalid or outside company scope'
        using errcode = 'check_violation';
    end if;
  elsif p_rule_type = 'category_blocked' then
    raise exception 'category_blocked requires categoryId'
      using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function public.validate_policy_rule_row()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  superseded_company uuid;
  superseded_code text;
  superseded_version integer;
begin
  perform public.assert_policy_rule_config(new.company_id, new.rule_type, new.config);
  if new.supersedes_rule_id is not null then
    select company_id, code, version
      into superseded_company, superseded_code, superseded_version
    from public.expense_policy_rules where id = new.supersedes_rule_id;
    if superseded_company is distinct from new.company_id
       or superseded_code is distinct from new.code
       or new.version <> superseded_version + 1 then
      raise exception 'Superseded policy rule scope or version is invalid'
        using errcode = 'check_violation';
    end if;
  elsif new.version <> 1 then
    raise exception 'Initial policy rule version must be 1'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger expense_policy_rules_validate
before insert on public.expense_policy_rules
for each row execute function public.validate_policy_rule_row();

create or replace function public.protect_policy_rule_update()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.company_id is distinct from old.company_id
     or new.code is distinct from old.code
     or new.name is distinct from old.name
     or new.description is distinct from old.description
     or new.rule_type is distinct from old.rule_type
     or new.severity is distinct from old.severity
     or new.config is distinct from old.config
     or new.version is distinct from old.version
     or new.effective_from is distinct from old.effective_from
     or new.supersedes_rule_id is distinct from old.supersedes_rule_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Policy rule versions are immutable'
      using errcode = 'check_violation';
  end if;
  if old.active is false and new.active is true then
    raise exception 'A deactivated policy rule cannot be reactivated'
      using errcode = 'check_violation';
  end if;
  if old.effective_to is not null and new.effective_to is distinct from old.effective_to then
    raise exception 'A closed policy effective range cannot be changed'
      using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger expense_policy_rules_protect_update
before update on public.expense_policy_rules
for each row execute function public.protect_policy_rule_update();

create or replace function public.validate_policy_run_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  report_company uuid;
begin
  select company_id into report_company from public.expense_reports where id = new.report_id;
  if report_company is distinct from new.company_id then
    raise exception 'Policy evaluation run company does not match report company'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger policy_evaluation_runs_validate_scope
before insert on public.policy_evaluation_runs
for each row execute function public.validate_policy_run_scope();

create or replace function public.validate_policy_result_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  run_company uuid;
  run_report uuid;
  rule_company uuid;
  claim_company uuid;
  claim_report uuid;
begin
  select company_id, report_id into run_company, run_report
  from public.policy_evaluation_runs where id = new.run_id;
  select company_id into rule_company from public.expense_policy_rules where id = new.rule_id;
  if new.claim_id is not null then
    select claim.company_id, item.report_id into claim_company, claim_report
    from public.expense_claims claim
    left join public.expense_report_items item on item.claim_id = claim.id
    where claim.id = new.claim_id;
  end if;
  if run_company is distinct from new.company_id
     or run_report is distinct from new.report_id
     or rule_company is distinct from new.company_id
     or (new.claim_id is not null and claim_company is distinct from new.company_id)
     or (new.claim_id is not null and claim_report is distinct from new.report_id) then
    raise exception 'Policy evaluation result scope is invalid'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger policy_evaluation_results_validate_scope
before insert on public.policy_evaluation_results
for each row execute function public.validate_policy_result_scope();

create or replace function public.validate_policy_exception_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  result_record public.policy_evaluation_results%rowtype;
  report_company uuid;
  report_employee uuid;
  rule_company uuid;
  claim_company uuid;
  claim_employee uuid;
begin
  select * into result_record from public.policy_evaluation_results
  where id = new.evaluation_result_id;
  select company_id, employee_id into report_company, report_employee
  from public.expense_reports where id = new.report_id;
  select company_id into rule_company from public.expense_policy_rules where id = new.rule_id;
  if new.claim_id is not null then
    select company_id, employee_id into claim_company, claim_employee
    from public.expense_claims where id = new.claim_id;
  end if;
  if result_record.company_id is distinct from new.company_id
     or result_record.report_id is distinct from new.report_id
     or result_record.claim_id is distinct from new.claim_id
     or result_record.rule_id is distinct from new.rule_id
     or report_company is distinct from new.company_id
     or report_employee is distinct from new.employee_id
     or rule_company is distinct from new.company_id
     or (new.claim_id is not null and claim_company is distinct from new.company_id)
     or (new.claim_id is not null and claim_employee is distinct from new.employee_id) then
    raise exception 'Policy exception scope is invalid'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger policy_exception_requests_validate_scope
before insert on public.policy_exception_requests
for each row execute function public.validate_policy_exception_scope();

create or replace function public.prevent_append_only_change()
returns trigger language plpgsql security invoker as $$
begin
  raise exception 'This policy evidence record is append-only'
    using errcode = 'check_violation';
end;
$$;
create trigger policy_evaluation_runs_append_only
before update or delete on public.policy_evaluation_runs
for each row execute function public.prevent_append_only_change();
create trigger policy_evaluation_results_append_only
before update or delete on public.policy_evaluation_results
for each row execute function public.prevent_append_only_change();

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
  if new.policy_rule_id is not null then
    select company_id into parent_company_id from public.expense_policy_rules where id = new.policy_rule_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit policy rule company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  if new.policy_evaluation_run_id is not null then
    select company_id into parent_company_id from public.policy_evaluation_runs
    where id = new.policy_evaluation_run_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit policy run company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  if new.policy_exception_id is not null then
    select company_id into parent_company_id from public.policy_exception_requests
    where id = new.policy_exception_id;
    if parent_company_id is distinct from new.company_id then
      raise exception 'Audit policy exception company mismatch' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

alter table public.expense_policy_rules enable row level security;
alter table public.policy_evaluation_runs enable row level security;
alter table public.policy_evaluation_results enable row level security;
alter table public.policy_exception_requests enable row level security;

create policy expense_policy_rules_select_member on public.expense_policy_rules
for select to authenticated using (public.is_company_member(company_id));
create policy policy_evaluation_runs_select_report_viewer on public.policy_evaluation_runs
for select to authenticated using (public.can_view_expense_report(report_id));
create policy policy_evaluation_results_select_report_viewer on public.policy_evaluation_results
for select to authenticated using (public.can_view_expense_report(report_id));
create policy policy_exception_requests_select_report_viewer on public.policy_exception_requests
for select to authenticated using (public.can_view_expense_report(report_id));

revoke all on public.expense_policy_rules from authenticated;
revoke all on public.policy_evaluation_runs from authenticated;
revoke all on public.policy_evaluation_results from authenticated;
revoke all on public.policy_exception_requests from authenticated;
grant select on public.expense_policy_rules to authenticated;
grant select on public.policy_evaluation_runs to authenticated;
grant select on public.policy_evaluation_results to authenticated;
grant select on public.policy_exception_requests to authenticated;
grant all on public.expense_policy_rules to service_role;
grant all on public.policy_evaluation_runs to service_role;
grant all on public.policy_evaluation_results to service_role;
grant all on public.policy_exception_requests to service_role;

create or replace function public.create_expense_policy_rule(
  p_company_id uuid,
  p_code text,
  p_name text,
  p_description text,
  p_rule_type public.policy_rule_type,
  p_severity public.policy_severity,
  p_config jsonb,
  p_effective_from timestamptz,
  p_supersedes_rule_id uuid,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  start_at timestamptz := coalesce(p_effective_from, now());
  old_rule public.expense_policy_rules%rowtype;
  new_rule public.expense_policy_rules%rowtype;
  next_version integer := 1;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if not public.has_company_role(
    p_company_id, array['finance', 'admin']::public.company_role[]
  ) then
    raise exception 'Finance or admin role required' using errcode = 'insufficient_privilege';
  end if;
  if trim(p_code) !~ '^[a-z][a-z0-9_.-]{1,59}$'
     or char_length(trim(p_name)) not between 1 and 140
     or (p_description is not null and char_length(p_description) > 1000) then
    raise exception 'Policy rule identity is invalid' using errcode = 'check_violation';
  end if;
  perform public.lock_company_policy(p_company_id);
  perform public.assert_policy_rule_config(p_company_id, p_rule_type, p_config);

  if p_supersedes_rule_id is not null then
    select * into old_rule from public.expense_policy_rules
    where id = p_supersedes_rule_id for update;
    if not found then raise exception 'Policy rule to supersede was not found' using errcode = 'no_data_found'; end if;
    if old_rule.company_id <> p_company_id or old_rule.code <> trim(p_code) or old_rule.active is false then
      raise exception 'Only an active same-company rule with the same code may be superseded'
        using errcode = 'check_violation';
    end if;
    if start_at <= old_rule.effective_from then
      raise exception 'The new policy version must start after the previous version'
        using errcode = 'check_violation';
    end if;
    update public.expense_policy_rules
      set effective_to = start_at, updated_at = now()
    where id = old_rule.id;
    next_version := old_rule.version + 1;
  elsif exists (
    select 1 from public.expense_policy_rules existing
    where existing.company_id = p_company_id and existing.code = trim(p_code)
  ) then
    raise exception 'Policy code already exists; supersede its latest version instead'
      using errcode = 'unique_violation';
  end if;

  insert into public.expense_policy_rules (
    company_id, code, name, description, rule_type, severity, config, version,
    effective_from, supersedes_rule_id, created_by
  ) values (
    p_company_id, trim(p_code), trim(p_name), nullif(trim(p_description), ''),
    p_rule_type, p_severity, p_config, next_version, start_at,
    p_supersedes_rule_id, current_user_id
  ) returning * into new_rule;

  insert into public.audit_events (
    company_id, actor_user_id, policy_rule_id, event_type, request_id, payload
  ) values (
    p_company_id, current_user_id, new_rule.id, 'policy.rule_created', p_request_id,
    jsonb_build_object(
      'code', new_rule.code,
      'version', new_rule.version,
      'ruleType', new_rule.rule_type,
      'severity', new_rule.severity,
      'supersedesRuleId', new_rule.supersedes_rule_id
    )
  );
  return to_jsonb(new_rule);
end;
$$;

create or replace function public.deactivate_expense_policy_rule(
  p_rule_id uuid,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  rule public.expense_policy_rules%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  select * into rule from public.expense_policy_rules where id = p_rule_id for update;
  if not found then raise exception 'Policy rule not found' using errcode = 'no_data_found'; end if;
  if not public.has_company_role(
    rule.company_id, array['finance', 'admin']::public.company_role[]
  ) then
    raise exception 'Finance or admin role required' using errcode = 'insufficient_privilege';
  end if;
  perform public.lock_company_policy(rule.company_id);
  if rule.active then
    update public.expense_policy_rules
      set active = false,
          effective_to = case
            when effective_to is null or effective_to > now() then now() else effective_to end,
          updated_at = now()
    where id = rule.id returning * into rule;
  end if;
  insert into public.audit_events (
    company_id, actor_user_id, policy_rule_id, event_type, request_id, payload
  ) values (
    rule.company_id, current_user_id, rule.id, 'policy.rule_deactivated', p_request_id,
    jsonb_build_object('code', rule.code, 'version', rule.version)
  );
  return to_jsonb(rule);
end;
$$;

create or replace function public.evaluate_expense_report_policy_internal(
  p_report_id uuid,
  p_actor_user_id uuid,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  report public.expense_reports%rowtype;
  rules_snapshot jsonb;
  policy_hash text;
  run_id uuid;
  rule_record public.expense_policy_rules%rowtype;
  claim_record record;
  applies boolean;
  violated boolean;
  waived boolean;
  result_outcome public.policy_result_outcome;
  explanation text;
  evidence jsonb;
  category_filter uuid;
  hard_fail_count integer := 0;
  exception_fail_count integer := 0;
  warning_count integer := 0;
  waived_count integer := 0;
  pass_count integer := 0;
  result_count integer := 0;
  final_outcome public.policy_evaluation_outcome;
begin
  select * into report from public.expense_reports where id = p_report_id for update;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  if report.status <> 'draft' then
    raise exception 'Policy may be evaluated only for a draft report'
      using errcode = 'check_violation';
  end if;

  perform claim.id
  from public.expense_report_items item
  join public.expense_claims claim on claim.id = item.claim_id
  where item.report_id = report.id
  order by claim.id
  for update of claim;

  perform public.lock_company_policy(report.company_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rule.id,
    'code', rule.code,
    'name', rule.name,
    'description', rule.description,
    'ruleType', rule.rule_type,
    'severity', rule.severity,
    'config', rule.config,
    'version', rule.version,
    'effectiveFrom', rule.effective_from,
    'effectiveTo', rule.effective_to
  ) order by rule.code, rule.version), '[]'::jsonb)
  into rules_snapshot
  from public.expense_policy_rules rule
  where rule.company_id = report.company_id
    and rule.active = true
    and rule.effective_from <= now()
    and (rule.effective_to is null or rule.effective_to > now());

  policy_hash := encode(digest(rules_snapshot::text, 'sha256'), 'hex');
  insert into public.policy_evaluation_runs (
    company_id, report_id, report_version, evaluated_by, evaluated_on,
    rules_snapshot, policy_set_hash, request_id
  ) values (
    report.company_id, report.id, report.version, p_actor_user_id, current_date,
    rules_snapshot, policy_hash, p_request_id
  ) returning id into run_id;

  for rule_record in
    select * from public.expense_policy_rules rule
    where rule.company_id = report.company_id
      and rule.active = true
      and rule.effective_from <= now()
      and (rule.effective_to is null or rule.effective_to > now())
    order by rule.code, rule.version
  loop
    category_filter := case
      when rule_record.config ? 'categoryId'
       and rule_record.config->'categoryId' <> 'null'::jsonb
      then public.try_uuid(rule_record.config->>'categoryId') else null end;

    for claim_record in
      select claim.*, category.code as category_code, category.name as category_name,
             item.position
      from public.expense_report_items item
      join public.expense_claims claim on claim.id = item.claim_id
      join public.expense_categories category on category.id = claim.category_id
      where item.report_id = report.id
      order by item.position, claim.id
    loop
      applies := category_filter is null or claim_record.category_id = category_filter;
      violated := false;
      waived := false;
      explanation := '';
      evidence := jsonb_build_object(
        'claimId', claim_record.id,
        'position', claim_record.position,
        'categoryId', claim_record.category_id,
        'categoryCode', claim_record.category_code,
        'incurredOn', claim_record.incurred_on,
        'currency', claim_record.currency,
        'amount', claim_record.amount::text
      );

      if rule_record.rule_type = 'max_amount' then
        applies := applies and claim_record.currency = rule_record.config->>'currency';
        if applies then
          violated := claim_record.amount > (rule_record.config->>'amount')::numeric;
          explanation := case when violated
            then format('%s %s exceeds the policy limit of %s %s.',
              claim_record.currency, claim_record.amount::text,
              rule_record.config->>'currency', rule_record.config->>'amount')
            else format('%s %s is within the policy limit of %s %s.',
              claim_record.currency, claim_record.amount::text,
              rule_record.config->>'currency', rule_record.config->>'amount') end;
          evidence := evidence || jsonb_build_object(
            'limitCurrency', rule_record.config->>'currency',
            'limitAmount', rule_record.config->>'amount'
          );
        end if;
      elsif rule_record.rule_type = 'expense_age_days' then
        if applies then
          violated := current_date - claim_record.incurred_on > (rule_record.config->>'maxDays')::integer;
          explanation := case when violated
            then format('Expense is %s days old; policy allows %s days.',
              current_date - claim_record.incurred_on, rule_record.config->>'maxDays')
            else format('Expense age of %s days is within the %s-day policy.',
              current_date - claim_record.incurred_on, rule_record.config->>'maxDays') end;
          evidence := evidence || jsonb_build_object(
            'ageDays', current_date - claim_record.incurred_on,
            'maxDays', (rule_record.config->>'maxDays')::integer,
            'evaluatedOn', current_date
          );
        end if;
      elsif rule_record.rule_type = 'weekend_requires_note' then
        applies := applies and extract(isodow from claim_record.incurred_on) in (6, 7);
        if applies then
          violated := char_length(trim(coalesce(claim_record.notes, '')))
            < (rule_record.config->>'minimumNoteLength')::integer;
          explanation := case when violated
            then format('Weekend expense requires a note of at least %s characters.',
              rule_record.config->>'minimumNoteLength')
            else 'Weekend expense contains the required explanatory note.' end;
          evidence := evidence || jsonb_build_object(
            'noteLength', char_length(trim(coalesce(claim_record.notes, ''))),
            'minimumNoteLength', (rule_record.config->>'minimumNoteLength')::integer,
            'dayOfWeek', extract(isodow from claim_record.incurred_on)::integer
          );
        end if;
      elsif rule_record.rule_type = 'category_blocked' then
        if applies then
          violated := true;
          explanation := format('Expense category %s is blocked by company policy.', claim_record.category_name);
        end if;
      elsif rule_record.rule_type = 'project_required' then
        if applies then
          violated := claim_record.project_id is null;
          explanation := case when violated
            then 'A project is required for this expense.'
            else 'The expense has the required project.' end;
          evidence := evidence || jsonb_build_object('projectId', claim_record.project_id);
        end if;
      elsif rule_record.rule_type = 'cost_centre_required' then
        if applies then
          violated := claim_record.cost_centre_id is null;
          explanation := case when violated
            then 'A cost centre is required for this expense.'
            else 'The expense has the required cost centre.' end;
          evidence := evidence || jsonb_build_object('costCentreId', claim_record.cost_centre_id);
        end if;
      elsif rule_record.rule_type = 'gstin_required' then
        if applies then
          violated := nullif(trim(coalesce(claim_record.receipt_facts->>'gstin', '')), '') is null;
          explanation := case when violated
            then 'Verified receipt facts do not contain a GSTIN.'
            else 'Verified receipt facts contain a GSTIN.' end;
          evidence := evidence || jsonb_build_object('gstin', claim_record.receipt_facts->'gstin');
        end if;
      end if;

      if not applies then
        continue;
      end if;

      if violated and rule_record.severity = 'requires_exception' then
        select exists (
          select 1 from public.policy_exception_requests exception_request
          where exception_request.report_id = report.id
            and exception_request.rule_id = rule_record.id
            and exception_request.claim_id = claim_record.id
            and exception_request.status = 'approved'
            and exception_request.report_version_at_request = report.version
            and exception_request.claim_version_at_request = claim_record.version
        ) into waived;
      end if;

      result_outcome := case
        when not violated then 'pass'::public.policy_result_outcome
        when waived then 'waived'::public.policy_result_outcome
        else 'fail'::public.policy_result_outcome
      end;
      if waived then
        explanation := explanation || ' An approved exception applies to this exact report and claim version.';
      end if;

      insert into public.policy_evaluation_results (
        run_id, company_id, report_id, claim_id, rule_id, rule_code,
        rule_version, severity, outcome, explanation, evidence
      ) values (
        run_id, report.company_id, report.id, claim_record.id, rule_record.id,
        rule_record.code, rule_record.version, rule_record.severity,
        result_outcome, explanation, evidence
      );
      result_count := result_count + 1;

      if result_outcome = 'pass' then pass_count := pass_count + 1;
      elsif result_outcome = 'waived' then waived_count := waived_count + 1;
      elsif rule_record.severity = 'warning' then warning_count := warning_count + 1;
      elsif rule_record.severity = 'block' then hard_fail_count := hard_fail_count + 1;
      else exception_fail_count := exception_fail_count + 1;
      end if;
    end loop;
  end loop;

  final_outcome := case
    when hard_fail_count + exception_fail_count > 0 then 'blocked'::public.policy_evaluation_outcome
    when warning_count + waived_count > 0 then 'warning'::public.policy_evaluation_outcome
    else 'pass'::public.policy_evaluation_outcome
  end;

  update public.policy_evaluation_runs set
    outcome = final_outcome,
    counts = jsonb_build_object(
      'results', result_count,
      'passed', pass_count,
      'warnings', warning_count,
      'hardBlocks', hard_fail_count,
      'exceptionRequired', exception_fail_count,
      'waived', waived_count
    ),
    completed_at = now()
  where id = run_id;

  insert into public.audit_events (
    company_id, actor_user_id, expense_report_id, policy_evaluation_run_id,
    event_type, request_id, payload
  ) values (
    report.company_id, p_actor_user_id, report.id, run_id,
    'policy.report_evaluated', p_request_id,
    jsonb_build_object(
      'reportVersion', report.version,
      'outcome', final_outcome,
      'policySetHash', policy_hash,
      'counts', jsonb_build_object(
        'results', result_count,
        'passed', pass_count,
        'warnings', warning_count,
        'hardBlocks', hard_fail_count,
        'exceptionRequired', exception_fail_count,
        'waived', waived_count
      )
    )
  );

  return jsonb_build_object(
    'runId', run_id,
    'reportId', report.id,
    'reportVersion', report.version,
    'outcome', final_outcome,
    'policySetHash', policy_hash,
    'counts', jsonb_build_object(
      'results', result_count,
      'passed', pass_count,
      'warnings', warning_count,
      'hardBlocks', hard_fail_count,
      'exceptionRequired', exception_fail_count,
      'waived', waived_count
    )
  );
end;
$$;
revoke all on function public.evaluate_expense_report_policy_internal(uuid, uuid, text)
  from public, authenticated;

create or replace function public.evaluate_expense_report_policy(
  p_report_id uuid,
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
  select * into report from public.expense_reports where id = p_report_id;
  if not found then raise exception 'Expense report not found' using errcode = 'no_data_found'; end if;
  if report.employee_id <> current_user_id and not public.has_company_role(
    report.company_id,
    array['manager', 'finance', 'admin', 'auditor']::public.company_role[]
  ) then
    raise exception 'Report policy evaluation is not permitted'
      using errcode = 'insufficient_privilege';
  end if;
  return public.evaluate_expense_report_policy_internal(
    report.id, current_user_id, p_request_id
  );
end;
$$;

create or replace function public.request_policy_exception(
  p_evaluation_result_id uuid,
  p_reason text,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  result_record public.policy_evaluation_results%rowtype;
  run_record public.policy_evaluation_runs%rowtype;
  report public.expense_reports%rowtype;
  claim public.expense_claims%rowtype;
  exception_request public.policy_exception_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if char_length(trim(p_reason)) not between 10 and 2000 then
    raise exception 'Exception reason must contain 10 to 2000 characters'
      using errcode = 'check_violation';
  end if;

  select * into result_record from public.policy_evaluation_results
  where id = p_evaluation_result_id;
  if not found then raise exception 'Policy evaluation result not found' using errcode = 'no_data_found'; end if;
  select * into run_record from public.policy_evaluation_runs where id = result_record.run_id;
  select * into report from public.expense_reports where id = result_record.report_id for update;
  if report.employee_id <> current_user_id then
    raise exception 'Only the owning employee may request an exception'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' or run_record.report_version <> report.version then
    raise exception 'The policy evaluation is stale; evaluate the current report again'
      using errcode = 'serialization_failure';
  end if;
  if result_record.severity <> 'requires_exception' or result_record.outcome <> 'fail' then
    raise exception 'Only failed exception-required results may request an exception'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.policy_evaluation_runs newer
    where newer.report_id = report.id and newer.created_at > run_record.created_at
  ) then
    raise exception 'Use the latest policy evaluation result'
      using errcode = 'serialization_failure';
  end if;

  if result_record.claim_id is not null then
    select * into claim from public.expense_claims where id = result_record.claim_id;
  end if;

  insert into public.policy_exception_requests (
    company_id, report_id, claim_id, rule_id, evaluation_result_id, employee_id,
    report_version_at_request, claim_version_at_request, reason
  ) values (
    result_record.company_id, report.id, result_record.claim_id, result_record.rule_id,
    result_record.id, current_user_id, report.version,
    case when result_record.claim_id is null then null else claim.version end,
    trim(p_reason)
  ) returning * into exception_request;

  insert into public.audit_events (
    company_id, actor_user_id, expense_claim_id, expense_report_id,
    policy_rule_id, policy_evaluation_run_id, policy_exception_id,
    event_type, request_id, payload
  ) values (
    exception_request.company_id, current_user_id, exception_request.claim_id,
    exception_request.report_id, exception_request.rule_id, result_record.run_id,
    exception_request.id, 'policy.exception_requested', p_request_id,
    jsonb_build_object(
      'reportVersion', exception_request.report_version_at_request,
      'claimVersion', exception_request.claim_version_at_request
    )
  );
  return to_jsonb(exception_request);
end;
$$;

create or replace function public.resolve_policy_exception(
  p_exception_id uuid,
  p_status public.policy_exception_status,
  p_review_note text,
  p_request_id text
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  current_user_id uuid := auth.uid();
  exception_request public.policy_exception_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = 'insufficient_privilege';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'Exception resolution must be approved or rejected'
      using errcode = 'check_violation';
  end if;
  if p_review_note is not null and char_length(p_review_note) > 2000 then
    raise exception 'Exception review note must not exceed 2000 characters'
      using errcode = 'check_violation';
  end if;

  select * into exception_request from public.policy_exception_requests
  where id = p_exception_id for update;
  if not found then raise exception 'Policy exception not found' using errcode = 'no_data_found'; end if;
  if not public.has_company_role(
    exception_request.company_id, array['finance', 'admin']::public.company_role[]
  ) then
    raise exception 'Finance or admin role required' using errcode = 'insufficient_privilege';
  end if;
  if exception_request.status <> 'pending' then
    raise exception 'Only a pending exception may be resolved'
      using errcode = 'check_violation';
  end if;

  update public.policy_exception_requests set
    status = p_status,
    reviewed_by = current_user_id,
    review_note = nullif(trim(p_review_note), ''),
    reviewed_at = now(),
    updated_at = now()
  where id = exception_request.id returning * into exception_request;

  insert into public.audit_events (
    company_id, actor_user_id, expense_claim_id, expense_report_id,
    policy_rule_id, policy_exception_id, event_type, request_id, payload
  ) values (
    exception_request.company_id, current_user_id, exception_request.claim_id,
    exception_request.report_id, exception_request.rule_id, exception_request.id,
    'policy.exception_resolved', p_request_id,
    jsonb_build_object('status', exception_request.status)
  );
  return to_jsonb(exception_request);
end;
$$;

grant execute on function public.create_expense_policy_rule(
  uuid, text, text, text, public.policy_rule_type, public.policy_severity,
  jsonb, timestamptz, uuid, text
) to authenticated;
grant execute on function public.deactivate_expense_policy_rule(uuid, text) to authenticated;
grant execute on function public.evaluate_expense_report_policy(uuid, text) to authenticated;
grant execute on function public.request_policy_exception(uuid, text, text) to authenticated;
grant execute on function public.resolve_policy_exception(
  uuid, public.policy_exception_status, text, text
) to authenticated;

revoke all on function public.create_expense_policy_rule(
  uuid, text, text, text, public.policy_rule_type, public.policy_severity,
  jsonb, timestamptz, uuid, text
) from public;
revoke all on function public.deactivate_expense_policy_rule(uuid, text) from public;
revoke all on function public.evaluate_expense_report_policy(uuid, text) from public;
revoke all on function public.request_policy_exception(uuid, text, text) from public;
revoke all on function public.resolve_policy_exception(
  uuid, public.policy_exception_status, text, text
) from public;

commit;
