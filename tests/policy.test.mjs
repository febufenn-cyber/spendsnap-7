import assert from 'node:assert/strict';
import test from 'node:test';
import { evaluatePolicy, validatePolicyRuleConfig } from '../dist/domain/policy.js';

const claim = {
  id: '11111111-1111-4111-8111-111111111111',
  version: 3,
  categoryId: '22222222-2222-4222-8222-222222222222',
  categoryName: 'Meals',
  projectId: null,
  costCentreId: null,
  incurredOn: '2026-07-11',
  currency: 'INR',
  amount: '1000.0000',
  notes: null,
  gstin: null,
};

function rule(overrides = {}) {
  return {
    id: '33333333-3333-4333-8333-333333333333',
    code: 'meal-limit',
    version: 1,
    ruleType: 'max_amount',
    severity: 'block',
    config: { currency: 'INR', amount: '1000.0000' },
    ...overrides,
  };
}

test('exact amount boundary passes without floating point drift', () => {
  const result = evaluatePolicy({
    reportVersion: 4,
    evaluatedOn: '2026-07-14',
    rules: [rule()],
    claims: [claim],
  });
  assert.equal(result.outcome, 'pass');
  assert.equal(result.results[0].outcome, 'pass');
});

test('one ten-thousandth above limit blocks', () => {
  const result = evaluatePolicy({
    reportVersion: 4,
    evaluatedOn: '2026-07-14',
    rules: [rule()],
    claims: [{ ...claim, amount: '1000.0001' }],
  });
  assert.equal(result.outcome, 'blocked');
  assert.equal(result.counts.hardBlocks, 1);
});

test('weekend rule uses date-only UTC semantics', () => {
  const result = evaluatePolicy({
    reportVersion: 4,
    evaluatedOn: '2026-07-14',
    rules: [rule({
      code: 'weekend-note',
      ruleType: 'weekend_requires_note',
      severity: 'warning',
      config: { minimumNoteLength: 10 },
    })],
    claims: [claim],
  });
  assert.equal(result.outcome, 'warning');
  assert.match(result.results[0].explanation, /Weekend expense/);
});

test('approved exception only waives the exact report and claim versions', () => {
  const exceptionRule = rule({ severity: 'requires_exception' });
  const input = {
    reportVersion: 4,
    evaluatedOn: '2026-07-14',
    rules: [exceptionRule],
    claims: [{ ...claim, amount: '1200' }],
  };
  const approvedExceptions = [{
    ruleId: exceptionRule.id,
    claimId: claim.id,
    reportVersion: 4,
    claimVersion: 3,
  }];
  assert.equal(evaluatePolicy({ ...input, approvedExceptions }).results[0].outcome, 'waived');
  assert.equal(evaluatePolicy({ ...input, reportVersion: 5, approvedExceptions }).results[0].outcome, 'fail');
  assert.equal(evaluatePolicy({
    ...input,
    claims: [{ ...claim, version: 4, amount: '1200' }],
    approvedExceptions,
  }).results[0].outcome, 'fail');
});

test('invalid policy configurations fail before persistence', () => {
  assert.deepEqual(validatePolicyRuleConfig('max_amount', { currency: 'inr', amount: '10' }), ['currency_invalid']);
  assert.ok(validatePolicyRuleConfig('category_blocked', {}).includes('category_id_required'));
});
