-- Spendsnap Phase 3: controlled policy finalization and submission-time enforcement.
begin;

alter table public.expense_report_submissions
  add column policy_evaluation_run_id uuid
    references public.policy_evaluation_runs(id) on delete restrict;
create index expense_report_submissions_policy_run_idx
  on public.expense_report_submissions (policy_evaluation_run_id)
  where policy_evaluation_run_id is not null;

-- A run is append-only after one controlled running -> completed transition.
drop trigger if exists policy_evaluation_runs_append_only on public.policy_evaluation_runs;
create or replace function public.protect_policy_evaluation_run_change()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Policy evaluation runs cannot be deleted'
      using errcode = 'check_violation';
  end if;
  if old.outcome is not null then
    raise exception 'Completed policy evaluation runs are immutable'
      using errcode = 'check_violation';
  end if;
  if new.id is distinct from old.id
     or new.company_id is distinct from old.company_id
     or new.report_id is distinct from old.report_id
     or new.report_version is distinct from old.report_version
     or new.evaluated_by is distinct from old.evaluated_by
     or new.evaluated_on is distinct from old.evaluated_on
     or new.rules_snapshot is distinct from old.rules_snapshot
     or new.policy_set_hash is distinct from old.policy_set_hash
     or new.request_id is distinct from old.request_id
     or new.created_at is distinct from old.created_at
     or new.outcome is null
     or new.completed_at is null then
    raise exception 'Only policy run completion fields may be finalized'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger policy_evaluation_runs_protect_change
before update or delete on public.policy_evaluation_runs
for each row execute function public.protect_policy_evaluation_run_change();

-- Rule effective ranges may be shortened, never extended or rewritten.
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
  if old.effective_to is not null
     and (new.effective_to is null or new.effective_to > old.effective_to) then
    raise exception 'A policy effective range cannot be extended after it is closed'
      using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_policy_exception_update()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.id is distinct from old.id
     or new.company_id is distinct from old.company_id
     or new.report_id is distinct from old.report_id
     or new.claim_id is distinct from old.claim_id
     or new.rule_id is distinct from old.rule_id
     or new.evaluation_result_id is distinct from old.evaluation_result_id
     or new.employee_id is distinct from old.employee_id
     or new.report_version_at_request is distinct from old.report_version_at_request
     or new.claim_version_at_request is distinct from old.claim_version_at_request
     or new.reason is distinct from old.reason
     or new.created_at is distinct from old.created_at then
    raise exception 'Policy exception request identity and evidence are immutable'
      using errcode = 'check_violation';
  end if;
  if old.status <> 'pending' then
    raise exception 'Resolved policy exception requests are immutable'
      using errcode = 'check_violation';
  end if;
  if new.status not in ('approved', 'rejected')
     or new.reviewed_by is null or new.reviewed_at is null then
    raise exception 'A pending exception may only be approved or rejected'
      using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger policy_exception_requests_protect_update
before update on public.policy_exception_requests
for each row execute function public.protect_policy_exception_update();

-- Changing an attached claim invalidates stale report views and exception versions.
create or replace function public.touch_draft_report_after_claim_edit()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  attached_report_id uuid;
begin
  if new.version = old.version then return new; end if;
  select item.report_id into attached_report_id
  from public.expense_report_items item
  join public.expense_reports report on report.id = item.report_id
  where item.claim_id = new.id and report.status = 'draft';
  if attached_report_id is not null then
    update public.expense_reports
      set version = version + 1
    where id = attached_report_id and status = 'draft';
  end if;
  return new;
end;
$$;
create trigger expense_claims_touch_attached_report
before update of version on public.expense_claims
for each row execute function public.touch_draft_report_after_claim_edit();

create or replace function public.validate_expense_submission_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare
  report_company uuid;
  policy_company uuid;
  policy_report uuid;
begin
  select company_id into report_company from public.expense_reports where id = new.report_id;
  if report_company is distinct from new.company_id then
    raise exception 'Submission company does not match report company'
      using errcode = 'check_violation';
  end if;
  if new.policy_evaluation_run_id is not null then
    select company_id, report_id into policy_company, policy_report
    from public.policy_evaluation_runs where id = new.policy_evaluation_run_id;
    if policy_company is distinct from new.company_id
       or policy_report is distinct from new.report_id then
      raise exception 'Submission policy evaluation does not match report scope'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
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
  policy_result jsonb;
  policy_run_id uuid;
  policy_snapshot jsonb;
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

  select count(*) into item_count
  from public.expense_report_items where report_id = report.id;
  if item_count = 0 then
    raise exception 'At least one expense claim is required' using errcode = 'check_violation';
  end if;

  perform claim.id
  from public.expense_report_items item
  join public.expense_claims claim on claim.id = item.claim_id
  where item.report_id = report.id
  order by claim.id
  for update of claim;

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
      or (claim.project_id is not null and
        (project.company_id <> report.company_id or project.active is not true))
      or (claim.cost_centre_id is not null and
        (centre.company_id <> report.company_id or centre.active is not true))
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

  policy_result := public.evaluate_expense_report_policy_internal(
    report.id, current_user_id, p_request_id
  );
  policy_run_id := (policy_result->>'runId')::uuid;

  if policy_result->>'outcome' = 'blocked' then
    insert into public.audit_events (
      company_id, actor_user_id, expense_report_id, policy_evaluation_run_id,
      event_type, request_id, payload
    ) values (
      report.company_id, current_user_id, report.id, policy_run_id,
      'policy.submission_blocked', p_request_id,
      jsonb_build_object('reportVersion', report.version, 'policy', policy_result)
    );
    return jsonb_build_object(
      'reportId', report.id,
      'status', 'blocked',
      'version', report.version,
      'policy', policy_result
    );
  end if;

  select jsonb_build_object(
    'run', jsonb_build_object(
      'id', run.id,
      'reportVersion', run.report_version,
      'evaluatedOn', run.evaluated_on,
      'policySetHash', run.policy_set_hash,
      'outcome', run.outcome,
      'counts', run.counts,
      'rules', run.rules_snapshot,
      'createdAt', run.created_at,
      'completedAt', run.completed_at
    ),
    'results', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', result.id,
        'claimId', result.claim_id,
        'ruleId', result.rule_id,
        'ruleCode', result.rule_code,
        'ruleVersion', result.rule_version,
        'severity', result.severity,
        'outcome', result.outcome,
        'explanation', result.explanation,
        'evidence', result.evidence
      ) order by result.rule_code, result.claim_id, result.created_at)
      from public.policy_evaluation_results result
      where result.run_id = run.id
    ), '[]'::jsonb)
  ) into policy_snapshot
  from public.policy_evaluation_runs run where run.id = policy_run_id;

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
    'category', jsonb_build_object(
      'id', category.id, 'code', category.code, 'name', category.name),
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
    report_id, company_id, submission_number, snapshot, totals_by_currency,
    submitted_by, policy_evaluation_run_id
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
      'items', item_snapshot,
      'policy', policy_snapshot
    ),
    totals,
    current_user_id,
    policy_run_id
  ) returning id into submission_id;

  update public.expense_claims claim set status = 'submitted'
  from public.expense_report_items item
  where item.report_id = report.id and item.claim_id = claim.id;

  update public.expense_reports set
    status = 'submitted', submitted_at = now(), version = version + 1
  where id = report.id returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, expense_report_id, policy_evaluation_run_id,
    event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, report.id, policy_run_id,
    'expense.report_submitted', p_request_id,
    jsonb_build_object(
      'submissionId', submission_id,
      'submissionNumber', submission_number,
      'itemCount', item_count,
      'totalsByCurrency', totals,
      'policyOutcome', policy_result->>'outcome',
      'policySetHash', policy_result->>'policySetHash',
      'version', report.version
    )
  );

  return jsonb_build_object(
    'reportId', report.id,
    'submissionId', submission_id,
    'submissionNumber', submission_number,
    'itemCount', item_count,
    'totalsByCurrency', totals,
    'policy', policy_result,
    'version', report.version,
    'status', report.status
  );
end;
$$;

commit;
