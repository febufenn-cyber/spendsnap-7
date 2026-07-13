-- Spendsnap Phase 2: prevent stale report assembly and claim/snapshot races.
begin;

revoke all on function public.add_claim_to_expense_report(uuid, uuid, text) from authenticated, public;
revoke all on function public.remove_claim_from_expense_report(uuid, uuid, text) from authenticated, public;
drop function public.add_claim_to_expense_report(uuid, uuid, text);
drop function public.remove_claim_from_expense_report(uuid, uuid, text);

create or replace function public.add_claim_to_expense_report(
  p_report_id uuid,
  p_claim_id uuid,
  p_expected_version integer,
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
  if report.employee_id <> current_user_id then
    raise exception 'Only the owning employee may change report items'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' then
    raise exception 'Only draft reports may be changed' using errcode = 'check_violation';
  end if;
  if report.version <> p_expected_version then
    raise exception 'Expense report version conflict' using errcode = 'serialization_failure';
  end if;

  select * into claim from public.expense_claims where id = p_claim_id for update;
  if not found then raise exception 'Expense claim not found' using errcode = 'no_data_found'; end if;
  if claim.employee_id <> current_user_id or report.company_id <> claim.company_id then
    raise exception 'Report and claim must belong to the authenticated employee and company'
      using errcode = 'insufficient_privilege';
  end if;
  if claim.status <> 'draft' then
    raise exception 'Only draft claims may be assembled' using errcode = 'check_violation';
  end if;

  select coalesce(max(position), 0) + 1 into next_position
  from public.expense_report_items where report_id = report.id;
  insert into public.expense_report_items (report_id, claim_id, company_id, position, added_by)
  values (report.id, claim.id, report.company_id, next_position, current_user_id);

  update public.expense_reports set version = version + 1
  where id = report.id returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, expense_report_id,
    event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, claim.receipt_id, claim.id, report.id,
    'expense.report_item_added', p_request_id,
    jsonb_build_object('position', next_position, 'version', report.version)
  );
  return jsonb_build_object(
    'reportId', report.id,
    'claimId', claim.id,
    'position', next_position,
    'version', report.version
  );
end;
$$;

create or replace function public.remove_claim_from_expense_report(
  p_report_id uuid,
  p_claim_id uuid,
  p_expected_version integer,
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
  if report.employee_id <> current_user_id then
    raise exception 'Only the owning employee may change report items'
      using errcode = 'insufficient_privilege';
  end if;
  if report.status <> 'draft' then
    raise exception 'Only draft reports may be changed' using errcode = 'check_violation';
  end if;
  if report.version <> p_expected_version then
    raise exception 'Expense report version conflict' using errcode = 'serialization_failure';
  end if;

  select * into claim from public.expense_claims where id = p_claim_id;
  if not found then raise exception 'Expense claim not found' using errcode = 'no_data_found'; end if;
  if claim.employee_id <> current_user_id then
    raise exception 'Only the owning employee may change report items'
      using errcode = 'insufficient_privilege';
  end if;

  delete from public.expense_report_items
  where report_id = report.id and claim_id = claim.id;
  if not found then raise exception 'Claim is not attached to this report' using errcode = 'no_data_found'; end if;

  update public.expense_reports set version = version + 1
  where id = report.id returning * into report;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, expense_claim_id, expense_report_id,
    event_type, request_id, payload
  ) values (
    report.company_id, current_user_id, claim.receipt_id, claim.id, report.id,
    'expense.report_item_removed', p_request_id,
    jsonb_build_object('version', report.version)
  );
  return jsonb_build_object(
    'reportId', report.id,
    'claimId', claim.id,
    'removed', true,
    'version', report.version
  );
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

  -- Lock every attached claim in deterministic order. A concurrent claim edit must
  -- finish before readiness is evaluated, or wait until submission changes it to submitted.
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

grant execute on function public.add_claim_to_expense_report(uuid, uuid, integer, text) to authenticated;
grant execute on function public.remove_claim_from_expense_report(uuid, uuid, integer, text) to authenticated;
revoke all on function public.add_claim_to_expense_report(uuid, uuid, integer, text) from public;
revoke all on function public.remove_claim_from_expense_report(uuid, uuid, integer, text) from public;

commit;
