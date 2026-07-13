import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const schema = readFileSync('supabase/migrations/202607130007_expense_submission.sql', 'utf8');
const hardening = readFileSync('supabase/migrations/202607130008_phase2_concurrency_hardening.sql', 'utf8');
const routes = readFileSync('src/routes/expenses.ts', 'utf8');
const app = readFileSync('src/app.ts', 'utf8');

test('claims are uniquely backed by verified receipt evidence', () => {
  assert.match(schema, /receipt_id uuid not null unique references public\.receipts/);
  assert.match(schema, /A claim must be backed by a verified receipt/);
  assert.match(schema, /public\.verified_receipt_facts/);
  assert.match(schema, /receipt_facts jsonb not null/);
});

test('submitted reports preserve immutable evidence and exact currency totals', () => {
  assert.match(schema, /create table public\.expense_report_submissions/);
  assert.match(schema, /snapshot jsonb not null/);
  assert.match(schema, /totals_by_currency jsonb not null/);
  assert.match(schema, /sum\(claim\.amount\)::text/);
  assert.match(schema, /grant select on public\.expense_claims, public\.expense_reports/);
  assert.doesNotMatch(schema, /grant (insert|update|delete).*expense_report_submissions.*authenticated/i);
});

test('report assembly and submission use optimistic concurrency and row locks', () => {
  assert.match(hardening, /p_expected_version integer/);
  assert.match(hardening, /Expense report version conflict/);
  assert.match(hardening, /for update of claim/);
  assert.match(hardening, /version = version \+ 1/);
});

test('authenticated Phase 2 routes are mounted and version-aware', () => {
  assert.match(app, /app\.route\('\/v1\/expenses', expenseRoutes\)/);
  assert.match(routes, /\/claims\/from-receipt/);
  assert.match(routes, /\/reports\/:reportId\/submit/);
  assert.match(routes, /expectedVersion/);
  assert.match(routes, /requireVersion\(context\.req\.query\('expectedVersion'\)\)/);
});
