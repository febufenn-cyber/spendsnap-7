-- Spendsnap Phase 1: atomic service-only extraction lifecycle operations.
begin;

create or replace function public.assert_service_role()
returns void language plpgsql stable security definer set search_path = public, auth as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

create or replace function public.begin_receipt_extraction(
  p_receipt_id uuid,
  p_company_id uuid,
  p_provider text,
  p_model text,
  p_prompt_version text,
  p_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_receipt public.receipts%rowtype;
  active_run public.extraction_runs%rowtype;
  next_attempt integer;
  new_run public.extraction_runs%rowtype;
begin
  perform public.assert_service_role();

  select * into current_receipt
  from public.receipts
  where id = p_receipt_id and company_id = p_company_id
  for update;

  if not found then
    raise exception 'Receipt not found' using errcode = 'no_data_found';
  end if;

  if current_receipt.status in ('extracted', 'needs_review', 'verified', 'rejected', 'archived') then
    return jsonb_build_object('started', false, 'alreadyProcessed', true);
  end if;

  if current_receipt.status = 'extracting' then
    select * into active_run
    from public.extraction_runs
    where receipt_id = p_receipt_id and status = 'running'
    order by attempt desc
    limit 1;

    return jsonb_build_object(
      'started', false,
      'alreadyProcessed', false,
      'runId', active_run.id,
      'attempt', active_run.attempt
    );
  end if;

  if current_receipt.status = 'failed' then
    update public.receipts set status = 'queued' where id = p_receipt_id;
  elsif current_receipt.status = 'received' then
    update public.receipts set status = 'queued' where id = p_receipt_id;
  elsif current_receipt.status <> 'queued' then
    raise exception 'Receipt is not ready for extraction: %', current_receipt.status
      using errcode = 'check_violation';
  end if;

  update public.receipts set status = 'extracting' where id = p_receipt_id;

  select coalesce(max(attempt), 0) + 1 into next_attempt
  from public.extraction_runs where receipt_id = p_receipt_id;

  insert into public.extraction_runs (
    receipt_id, company_id, status, attempt, provider, model, prompt_version, request_id
  ) values (
    p_receipt_id, p_company_id, 'running', next_attempt,
    p_provider, p_model, p_prompt_version, p_request_id
  ) returning * into new_run;

  update public.receipts
  set latest_extraction_run_id = new_run.id
  where id = p_receipt_id;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, event_type, request_id, payload
  ) values (
    p_company_id, null, p_receipt_id, 'receipt.extraction_started', p_request_id,
    jsonb_build_object(
      'runId', new_run.id,
      'attempt', next_attempt,
      'provider', p_provider,
      'model', p_model,
      'promptVersion', p_prompt_version
    )
  );

  return jsonb_build_object(
    'started', true,
    'alreadyProcessed', false,
    'runId', new_run.id,
    'attempt', new_run.attempt
  );
end;
$$;

create or replace function public.complete_receipt_extraction(
  p_run_id uuid,
  p_server_sha256 text,
  p_actual_size_bytes integer,
  p_semantic_fingerprint text,
  p_raw_response jsonb,
  p_fields jsonb,
  p_needs_review boolean,
  p_warnings jsonb
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_run public.extraction_runs%rowtype;
  current_receipt public.receipts%rowtype;
  field_item jsonb;
  exact_duplicate_id uuid;
  semantic_duplicate_id uuid;
  next_status public.receipt_status;
begin
  perform public.assert_service_role();

  if p_server_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid server SHA-256' using errcode = 'check_violation';
  end if;
  if p_actual_size_bytes not between 1 and 7500000 then
    raise exception 'Invalid receipt byte size' using errcode = 'check_violation';
  end if;
  if jsonb_typeof(p_fields) <> 'array' or jsonb_array_length(p_fields) = 0 then
    raise exception 'Extraction fields must be a non-empty array' using errcode = 'check_violation';
  end if;

  select * into current_run
  from public.extraction_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'Extraction run not found' using errcode = 'no_data_found';
  end if;
  if current_run.status = 'succeeded' then
    return;
  end if;
  if current_run.status <> 'running' then
    raise exception 'Extraction run is not active' using errcode = 'check_violation';
  end if;

  select * into current_receipt
  from public.receipts
  where id = current_run.receipt_id
  for update;

  if current_receipt.status <> 'extracting' then
    raise exception 'Receipt is not extracting' using errcode = 'check_violation';
  end if;

  for field_item in select value from jsonb_array_elements(p_fields)
  loop
    insert into public.extracted_fields (
      extraction_run_id,
      receipt_id,
      company_id,
      field_name,
      value_json,
      normalized_text,
      confidence,
      evidence,
      review_status,
      is_critical,
      validation_warnings
    ) values (
      current_run.id,
      current_run.receipt_id,
      current_run.company_id,
      field_item->>'fieldName',
      field_item->'valueJson',
      nullif(field_item->>'normalizedText', ''),
      (field_item->>'confidence')::numeric,
      nullif(field_item->>'evidence', ''),
      (field_item->>'reviewStatus')::public.field_review_status,
      coalesce((field_item->>'isCritical')::boolean, false),
      array(
        select jsonb_array_elements_text(
          coalesce(field_item->'validationWarnings', '[]'::jsonb)
        )
      )
    );
  end loop;

  update public.extraction_runs
  set status = 'succeeded',
      raw_response = p_raw_response,
      input_sha256 = p_server_sha256,
      finished_at = now()
  where id = current_run.id;

  next_status := case when p_needs_review then 'needs_review' else 'extracted' end;

  update public.receipts
  set actual_size_bytes = p_actual_size_bytes,
      server_sha256 = p_server_sha256,
      semantic_fingerprint = p_semantic_fingerprint,
      latest_extraction_run_id = current_run.id,
      status = next_status
  where id = current_run.receipt_id;

  select id into exact_duplicate_id
  from public.receipts
  where company_id = current_run.company_id
    and id <> current_run.receipt_id
    and server_sha256 = p_server_sha256
  order by created_at asc
  limit 1;

  if exact_duplicate_id is not null then
    insert into public.duplicate_candidates (
      company_id, receipt_id, possible_duplicate_receipt_id, kind, score, reason
    ) values (
      current_run.company_id,
      current_run.receipt_id,
      exact_duplicate_id,
      'exact_content',
      1,
      jsonb_build_object('serverSha256', p_server_sha256)
    ) on conflict do nothing;
  end if;

  if p_semantic_fingerprint is not null then
    select id into semantic_duplicate_id
    from public.receipts
    where company_id = current_run.company_id
      and id <> current_run.receipt_id
      and semantic_fingerprint = p_semantic_fingerprint
      and id is distinct from exact_duplicate_id
    order by created_at asc
    limit 1;

    if semantic_duplicate_id is not null then
      insert into public.duplicate_candidates (
        company_id, receipt_id, possible_duplicate_receipt_id, kind, score, reason
      ) values (
        current_run.company_id,
        current_run.receipt_id,
        semantic_duplicate_id,
        'semantic_match',
        0.92,
        jsonb_build_object('semanticFingerprint', p_semantic_fingerprint)
      ) on conflict do nothing;
    end if;
  end if;

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, event_type, request_id, payload
  ) values (
    current_run.company_id,
    null,
    current_run.receipt_id,
    'receipt.extraction_completed',
    current_run.request_id,
    jsonb_build_object(
      'runId', current_run.id,
      'attempt', current_run.attempt,
      'status', next_status,
      'serverSha256', p_server_sha256,
      'warnings', coalesce(p_warnings, '[]'::jsonb)
    )
  );
end;
$$;

create or replace function public.fail_receipt_extraction(
  p_run_id uuid,
  p_error_code text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare current_run public.extraction_runs%rowtype;
begin
  perform public.assert_service_role();

  select * into current_run
  from public.extraction_runs
  where id = p_run_id
  for update;

  if not found then return; end if;
  if current_run.status <> 'running' then return; end if;

  update public.extraction_runs
  set status = 'failed',
      error_code = left(coalesce(p_error_code, 'unknown'), 120),
      error_message = left(coalesce(p_error_message, 'Unknown extraction failure'), 2000),
      finished_at = now()
  where id = current_run.id;

  update public.receipts
  set status = 'failed', latest_extraction_run_id = current_run.id
  where id = current_run.receipt_id and status = 'extracting';

  insert into public.audit_events (
    company_id, actor_user_id, receipt_id, event_type, request_id, payload
  ) values (
    current_run.company_id,
    null,
    current_run.receipt_id,
    'receipt.extraction_failed',
    current_run.request_id,
    jsonb_build_object(
      'runId', current_run.id,
      'attempt', current_run.attempt,
      'errorCode', left(coalesce(p_error_code, 'unknown'), 120)
    )
  );
end;
$$;

revoke execute on function public.assert_service_role() from public;
revoke execute on function public.begin_receipt_extraction(uuid, uuid, text, text, text, text) from public;
revoke execute on function public.complete_receipt_extraction(uuid, text, integer, text, jsonb, jsonb, boolean, jsonb) from public;
revoke execute on function public.fail_receipt_extraction(uuid, text, text) from public;

grant execute on function public.assert_service_role() to service_role;
grant execute on function public.begin_receipt_extraction(uuid, uuid, text, text, text, text) to service_role;
grant execute on function public.complete_receipt_extraction(uuid, text, integer, text, jsonb, jsonb, boolean, jsonb) to service_role;
grant execute on function public.fail_receipt_extraction(uuid, text, text) to service_role;

commit;
