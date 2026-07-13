import assert from 'node:assert/strict';
import test from 'node:test';
import { evaluateCorpus, normalizeEvaluationValue } from '../dist/evaluation/metrics.js';

test('evaluation normalizes money and uppercase identifiers', () => {
  assert.equal(normalizeEvaluationValue('total', '1,180.00'), '1180');
  assert.equal(normalizeEvaluationValue('currency', ' inr '), 'INR');
  assert.equal(normalizeEvaluationValue('gstin', ' 33abcde1234f1z5 '), '33ABCDE1234F1Z5');
});

test('evaluation reports coverage, accuracy, missing and extra receipts', () => {
  const report = evaluateCorpus(
    [
      { receiptId: 'one', fields: { total: '100.00', currency: 'INR', merchant_name: 'Cafe' } },
      { receiptId: 'two', fields: { total: '200.00', currency: 'INR' } },
    ],
    [
      { receiptId: 'one', fields: { total: '100', currency: 'inr', merchant_name: 'Wrong Cafe' } },
      { receiptId: 'extra', fields: { total: '10' } },
    ],
  );

  assert.deepEqual(report.missingReceipts, ['two']);
  assert.deepEqual(report.extraReceipts, ['extra']);
  assert.equal(report.overall.expected, 5);
  assert.equal(report.overall.present, 3);
  assert.equal(report.overall.matched, 2);
  assert.equal(report.overall.coverage, 0.6);
  assert.equal(report.overall.exactAccuracy, 0.4);
});
