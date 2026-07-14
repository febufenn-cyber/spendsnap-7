import assert from 'node:assert/strict';
import test from 'node:test';
import { delegationIsActive, evaluateApprovalTransition } from '../dist/domain/approval.js';

const base = {
  status: 'manager_review',
  stage: 'manager',
  action: 'approve',
  actorId: 'manager',
  employeeId: 'employee',
  note: null,
};

test('manager approval advances to finance review', () => {
  assert.deepEqual(evaluateApprovalTransition(base), {
    allowed: true, nextStatus: 'finance_review', nextStage: 'finance', issue: null,
  });
});

test('finance approval closes the workflow', () => {
  const result = evaluateApprovalTransition({ ...base, status: 'finance_review', stage: 'finance' });
  assert.equal(result.nextStatus, 'finance_approved');
  assert.equal(result.nextStage, null);
});

test('self approval is forbidden', () => {
  assert.equal(evaluateApprovalTransition({ ...base, actorId: 'employee' }).issue, 'self_approval_forbidden');
});

test('change and reject decisions require a reason', () => {
  assert.equal(evaluateApprovalTransition({ ...base, action: 'request_changes', note: '' }).issue, 'reason_required');
  assert.equal(evaluateApprovalTransition({ ...base, action: 'reject', note: 'No' }).issue, 'reason_required');
});

test('delegation start is inclusive and end is exclusive', () => {
  assert.equal(delegationIsActive('2026-07-14T08:00:00Z', '2026-07-15T08:00:00Z', '2026-07-14T08:00:00Z'), true);
  assert.equal(delegationIsActive('2026-07-14T08:00:00Z', '2026-07-15T08:00:00Z', '2026-07-15T08:00:00Z'), false);
});
