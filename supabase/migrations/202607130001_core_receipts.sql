-- Spendsnap Phase 1: tenant and receipt evidence tables.
begin;

create extension if not exists pgcrypto;

create type public.company_role as enum ('employee', 'manager', 'finance', 'admin', 'auditor');
create type public.receipt_status as enum (
  'upload_pending', 'received', 'queued', 'extracting', 'extracted',
  'needs_review', 'verified', 'failed', 'rejected', 'archived'
);
create type public.receipt_source as enum (
  'camera', 'gallery', 'email', 'slack', 'whatsapp', 'bulk_upload'
);
create type public.extraction_status as enum ('running', 'succeeded', 'failed');
create type public.field_review_status as enum (
  'auto_accepted', 'requires_review', 'confirmed', 'corrected', 'rejected'
);
create type public.correction_status as enum ('pending', 'accepted', 'rejected');
create type public.duplicate_kind as enum ('exact_content', 'semantic_match', 'near_image');
create type public.duplicate_resolution as enum (
  'open', 'confirmed_duplicate', 'not_duplicate', 'allowed_exception'
);

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.company_memberships (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.company_role not null default 'employee',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

create index company_memberships_user_active_idx
  on public.company_memberships (user_id, active, company_id);

create table public.receipts (
  id uuid primary key,
  company_id uuid not null references public.companies(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  status public.receipt_status not null default 'upload_pending',
  storage_path text not null unique,
  original_filename text not null check (char_length(original_filename) between 1 and 180),
  media_type text not null check (media_type in ('image/jpeg', 'image/png', 'image/webp')),
  declared_size_bytes integer not null check (declared_size_bytes between 1 and 7500000),
  actual_size_bytes integer check (actual_size_bytes is null or actual_size_bytes between 1 and 7500000),
  client_sha256 text check (client_sha256 is null or client_sha256 ~ '^[a-f0-9]{64}$'),
  server_sha256 text check (server_sha256 is null or server_sha256 ~ '^[a-f0-9]{64}$'),
  semantic_fingerprint text,
  source public.receipt_source not null,
  captured_at timestamptz,
  upload_completed_at timestamptz,
  extraction_queued_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint receipt_storage_path_scope_check check (
    storage_path like company_id::text || '/' || id::text || '/%'
  )
);

create index receipts_company_created_idx on public.receipts (company_id, created_at desc);
create index receipts_submitter_created_idx on public.receipts (submitted_by, created_at desc);
create index receipts_company_status_idx on public.receipts (company_id, status);
create index receipts_company_server_sha_idx
  on public.receipts (company_id, server_sha256) where server_sha256 is not null;
create index receipts_company_semantic_fingerprint_idx
  on public.receipts (company_id, semantic_fingerprint) where semantic_fingerprint is not null;

create table public.receipt_pages (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  page_number integer not null check (page_number between 1 and 20),
  storage_path text not null unique,
  media_type text not null check (media_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes integer not null check (size_bytes between 1 and 7500000),
  server_sha256 text not null check (server_sha256 ~ '^[a-f0-9]{64}$'),
  width_pixels integer check (width_pixels is null or width_pixels > 0),
  height_pixels integer check (height_pixels is null or height_pixels > 0),
  created_at timestamptz not null default now(),
  unique (receipt_id, page_number)
);

commit;
