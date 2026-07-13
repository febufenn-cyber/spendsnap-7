-- Spendsnap Phase 1: immutable extraction, correction, duplicate and audit history.
begin;

create table public.extraction_runs (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  status public.extraction_status not null default 'running',
  attempt integer not null check (attempt > 0),
  provider text not null check (char_length(provider) between 1 and 80),
  model text not null check (char_length(model) between 1 and 160),
  prompt_version text not null check (char_length(prompt_version) between 1 and 120),
  request_id text,
  raw_response jsonb,
  input_sha256 text check (input_sha256 is null or input_sha256 ~ '^[a-f0-9]{64}$'),
  error_code text,
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  unique (receipt_id, attempt),
  constraint extraction_run_completion_check check (
    (status = 'running' and finished_at is null)
    or (status in ('succeeded', 'failed') and finished_at is not null)
  )
);

create index extraction_runs_receipt_created_idx
  on public.extraction_runs (receipt_id, created_at desc);
create index extraction_runs_company_status_idx
  on public.extraction_runs (company_id, status, created_at desc);

alter table public.receipts
  add column latest_extraction_run_id uuid references public.extraction_runs(id) on delete set null;

create table public.extracted_fields (
  id uuid primary key default gen_random_uuid(),
  extraction_run_id uuid not null references public.extraction_runs(id) on delete restrict,
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  field_name text not null check (field_name ~ '^[a-z][a-z0-9_]{1,79}$'),
  value_json jsonb,
  normalized_text text,
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  evidence text,
  review_status public.field_review_status not null,
  is_critical boolean not null default false,
  validation_warnings text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (extraction_run_id, field_name)
);

create index extracted_fields_receipt_field_idx
  on public.extracted_fields (receipt_id, field_name, created_at desc);
create index extracted_fields_review_queue_idx
  on public.extracted_fields (company_id, review_status, created_at)
  where review_status = 'requires_review';

create table public.field_corrections (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  field_name text not null check (field_name ~ '^[a-z][a-z0-9_]{1,79}$'),
  previous_field_id uuid references public.extracted_fields(id) on delete restrict,
  corrected_value jsonb,
  reason text check (reason is null or char_length(reason) <= 1000),
  status public.correction_status not null default 'pending',
  submitted_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint correction_review_check check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status in ('accepted', 'rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);

create index field_corrections_receipt_field_idx
  on public.field_corrections (receipt_id, field_name, created_at desc);
create index field_corrections_company_pending_idx
  on public.field_corrections (company_id, created_at) where status = 'pending';

create table public.duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  possible_duplicate_receipt_id uuid not null references public.receipts(id) on delete restrict,
  kind public.duplicate_kind not null,
  score numeric(5,4) not null check (score between 0 and 1),
  reason jsonb not null default '{}'::jsonb,
  resolution public.duplicate_resolution not null default 'open',
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint duplicate_distinct_receipts_check check (receipt_id <> possible_duplicate_receipt_id),
  constraint duplicate_resolution_check check (
    (resolution = 'open' and resolved_by is null and resolved_at is null)
    or (resolution <> 'open' and resolved_by is not null and resolved_at is not null)
  )
);

create unique index duplicate_candidates_unique_pair_idx
  on public.duplicate_candidates (
    company_id,
    least(receipt_id, possible_duplicate_receipt_id),
    greatest(receipt_id, possible_duplicate_receipt_id),
    kind
  );
create index duplicate_candidates_open_idx
  on public.duplicate_candidates (company_id, created_at) where resolution = 'open';

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  receipt_id uuid references public.receipts(id) on delete restrict,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{2,119}$'),
  request_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_events_company_created_idx
  on public.audit_events (company_id, created_at desc);
create index audit_events_receipt_created_idx
  on public.audit_events (receipt_id, created_at desc) where receipt_id is not null;

commit;
