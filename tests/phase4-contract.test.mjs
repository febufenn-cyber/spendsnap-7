import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration = await readFile('supabase/migrations/202607140011_approval_exception_outbox.sql', 'utf8');
const app = await readFile('web/src/App.tsx', 'utf8');
const apiClient = await readFile('web/src/lib/api.ts', 'utf8');

test('approval decisions are submission scoped append only and idempotent', () => {
  assert.match(migration, /submission_id uuid not null/);
  assert.match(migration, /Approval decisions are append-only/);
  assert.match(migration, /unique \(company_id, idempotency_key\)/);
});

test('self approval and expired delegation are blocked in the database', () => {
  assert.match(migration, /Self approval is forbidden/);
  assert.match(migration, /starts_at <= p_at and delegation\.ends_at > p_at/);
});

test('notification outbox has unique event keys and skip-locked leasing', () => {
  assert.match(migration, /unique \(company_id, event_key, channel\)/);
  assert.match(migration, /for update skip locked/);
});

test('web app restores authenticated session and never embeds service credentials', () => {
  assert.match(app, /getSession\(\)/);
  assert.match(app, /onAuthStateChange/);
  assert.doesNotMatch(app, /SERVICE_ROLE/);
  assert.doesNotMatch(apiClient, /SUPABASE_SERVICE_ROLE_KEY/);
});

test('web app exposes employee and reviewer critical paths', () => {
  assert.match(app, /Upload receipt/);
  assert.match(app, /Create claim/);
  assert.match(app, /Preview policy/);
  assert.match(app, /Approval queue/);
  assert.match(app, /Request changes/);
});
