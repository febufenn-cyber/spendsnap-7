import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationDirectory = new URL('../supabase/migrations/', import.meta.url);

async function migration(name) {
  return readFile(new URL(name, migrationDirectory), 'utf8');
}

test('receipt schema enforces company-scoped storage paths and hashes', async () => {
  const sql = await migration('202607130001_core_receipts.sql');
  assert.match(sql, /receipt_storage_path_scope_check/);
  assert.match(sql, /server_sha256 text check/);
  assert.match(sql, /company_id, server_sha256/);
});

test('database rejects illegal lifecycle transitions', async () => {
  const sql = await migration('202607130003_integrity_functions.sql');
  assert.match(sql, /validate_receipt_status_transition/);
  assert.match(sql, /Illegal receipt status transition/);
});

test('tenant isolation is enforced by RLS and cross-table scope triggers', async () => {
  const rls = await migration('202607130004_rls_and_storage.sql');
  const integrity = await migration('202607130003_integrity_functions.sql');

  assert.match(rls, /alter table public\.receipts enable row level security/);
  assert.match(rls, /receipts_select_member/);
  assert.match(rls, /receipt_objects_select_company_member/);
  assert.match(integrity, /validate_extracted_field_scope/);
  assert.match(integrity, /validate_duplicate_candidate_scope/);
});

test('extraction RPCs are restricted to the service role', async () => {
  const sql = await migration('202607130005_extraction_rpcs.sql');
  assert.match(sql, /perform public\.assert_service_role\(\)/);
  assert.match(sql, /grant execute on function public\.begin_receipt_extraction/);
  assert.match(sql, /to service_role/);
  assert.doesNotMatch(sql, /grant execute on function public\.begin_receipt_extraction[^;]+to authenticated/s);
});

test('model predictions and human corrections remain separate', async () => {
  const sql = await migration('202607130002_extraction_history.sql');
  assert.match(sql, /create table public\.extraction_runs/);
  assert.match(sql, /create table public\.extracted_fields/);
  assert.match(sql, /create table public\.field_corrections/);
  assert.match(sql, /unique \(extraction_run_id, field_name\)/);
});
