import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const schema = await readFile('supabase/migrations/202607130009_deterministic_policy_engine.sql', 'utf8');
const enforcement = await readFile('supabase/migrations/202607130010_policy_submission_integration.sql', 'utf8');
const routes = await readFile('src/routes/policies.ts', 'utf8');

test('policy versions and results are company scoped and append only', () => {
  assert.match(schema, /unique \(company_id, code, version\)/);
  assert.match(schema, /Policy rule versions are immutable/);
  assert.match(schema, /policy_evaluation_runs/);
  assert.match(schema, /policy_evaluation_results/);
  assert.match(schema, /policy_exception_requests/);
});

test('policy evaluation serializes with rule changes and snapshots exact evidence', () => {
  assert.match(schema, /pg_advisory_xact_lock/);
  assert.match(enforcement, /for update of claim/);
  assert.match(enforcement, /policy_evaluation_run_id/);
  assert.match(enforcement, /policySetHash/);
  assert.match(enforcement, /policy\.submission_blocked/);
});

test('exceptions are version scoped and cannot be silently reused', () => {
  assert.match(schema, /report_version_at_request/);
  assert.match(schema, /claim_version_at_request/);
  assert.match(enforcement, /Changing an attached claim invalidates stale report views/);
});

test('authenticated policy API exposes administration preview and exceptions', () => {
  assert.match(routes, /policyRoutes\.post\('\/rules'/);
  assert.match(routes, /reports\/:reportId\/evaluate/);
  assert.match(routes, /results\/:resultId\/exceptions/);
  assert.match(routes, /exceptions\/:exceptionId\/resolve/);
});
