import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration = await readFile('supabase/migrations/202607140012_finance_gst_export.sql', 'utf8');
const repair = await readFile('supabase/migrations/202607140013_export_batch_parent_fix.sql', 'utf8');
const routes = await readFile('src/routes/finance.ts', 'utf8');
const portal = await readFile('web/src/FinancePortal.tsx', 'utf8');

test('export requires finance approval, role, unlocked period and idempotency', () => {
  assert.match(migration, /workflow\.status<>'finance_approved'/);
  assert.match(migration, /Finance role required/);
  assert.match(migration, /report period is locked/);
  assert.match(migration, /unique\(company_id,idempotency_key\)/);
});

test('export evidence has stable checksum and immutable snapshots', () => {
  assert.match(migration, /digest\(convert_to\(body,'UTF8'\),'sha256'\)/);
  assert.match(migration, /Completed accounting export evidence is immutable/);
  assert.match(migration, /mapping_snapshot/);
  assert.match(migration, /gst_snapshot/);
});

test('export rows and parent batch are atomic', () => {
  assert.match(repair, /deferrable initially deferred/);
});

test('download is authenticated and marked nosniff', () => {
  assert.match(routes, /Authorization/);
  assert.match(routes, /X-Content-Type-Options/);
  assert.match(routes, /Content-Disposition/);
});

test('finance UI uses cautious GST language and immutable export history', () => {
  assert.match(portal, /not tax-credit eligibility advice/);
  assert.match(portal, /Export history/);
  assert.match(portal, /checksum_sha256/);
});
