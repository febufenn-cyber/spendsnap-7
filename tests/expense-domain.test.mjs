import assert from 'node:assert/strict';
import test from 'node:test';
import {
  computeTotalsByCurrency,
  evaluateClaimReadiness,
  formatDecimal4,
  normalizeCurrency,
  parseDecimal4,
} from '../dist/domain/expense.js';

test('exact decimal parsing and formatting avoids floating point drift', () => {
  assert.equal(parseDecimal4('10.125'), 101250n);
  assert.equal(formatDecimal4(101250n), '10.125');
  assert.equal(parseDecimal4('1.23456'), null);
});

test('currency totals are exact, normalized, and stable', () => {
  assert.deepEqual(computeTotalsByCurrency([
    { currency: 'inr', amount: '10.10' },
    { currency: 'INR', amount: '0.20' },
    { currency: 'usd', amount: '2' },
  ]), { INR: '10.3', USD: '2' });
});

test('readiness exposes every blocking issue instead of failing on the first one', () => {
  const result = evaluateClaimReadiness({
    receiptStatus: 'needs_review',
    businessPurpose: ' ',
    categoryActive: false,
    projectSelected: true,
    projectActive: false,
    costCentreSelected: true,
    costCentreActive: false,
    amount: '-1',
    currency: 'rupees',
    incurredOn: '2026-07-15',
    reportPeriodStart: '2026-07-01',
    reportPeriodEnd: '2026-07-10',
    openDuplicateCandidates: 1,
  });

  assert.equal(result.ready, false);
  assert.deepEqual(result.issues, [
    'receipt_not_verified',
    'business_purpose_missing',
    'category_inactive',
    'project_inactive',
    'cost_centre_inactive',
    'amount_invalid',
    'currency_invalid',
    'incurred_outside_report_period',
    'duplicate_review_open',
  ]);
});

test('a valid employee-confirmed claim is ready', () => {
  const result = evaluateClaimReadiness({
    receiptStatus: 'verified',
    businessPurpose: 'Client meeting lunch',
    categoryActive: true,
    projectSelected: false,
    projectActive: true,
    costCentreSelected: false,
    costCentreActive: true,
    amount: '1250.50',
    currency: 'inr',
    incurredOn: '2026-07-10',
    reportPeriodStart: '2026-07-01',
    reportPeriodEnd: '2026-07-31',
    openDuplicateCandidates: 0,
  });

  assert.deepEqual(result, { ready: true, issues: [] });
  assert.equal(normalizeCurrency(' inr '), 'INR');
});
