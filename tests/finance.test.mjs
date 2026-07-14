import assert from 'node:assert/strict';
import test from 'node:test';
import { csvCell, evaluateGstReadiness, tallyCsv } from '../dist/domain/finance.js';

test('GST-free receipt is labeled not applicable without claiming eligibility', () => {
  assert.equal(evaluateGstReadiness({}).status, 'not_applicable');
});

test('complete GST fields receive cautious complete label', () => {
  const result = evaluateGstReadiness({
    gstin: '33ABCDE1234F1Z5', invoice_number: 'INV-1', invoice_date: '2026-07-01',
    taxable_value: '1000', cgst: '90', sgst: '90', igst: '0',
  });
  assert.equal(result.status, 'complete');
  assert.match(result.label, /eligibility still requires professional review/);
});

test('mixed IGST and CGST flags review', () => {
  const result = evaluateGstReadiness({ gstin: '33ABCDE1234F1Z5', invoice_number: '1', invoice_date: '2026-07-01', taxable_value: '100', cgst: '9', sgst: '9', igst: '18' });
  assert.ok(result.issues.includes('igst_and_cgst_sgst_both_present'));
});

test('CSV escapes quotes commas newlines and spreadsheet formulas', () => {
  assert.equal(csvCell('A,"B"'), '"A,""B"""');
  assert.equal(csvCell('=2+2'), '"\'=2+2"');
  const csv = tallyCsv([{ voucherDate: '2026-07-01', voucherType: 'Payment', ledger: 'Travel', vendor: '+Danger', reference: 'A,1', amount: '100.0000', currency: 'INR', costCentre: null, project: null, narration: 'Client\nvisit', gstin: null, taxableValue: null, cgst: null, sgst: null, igst: null, gstReadiness: 'not_applicable' }]);
  assert.ok(csv.endsWith('\r\n'));
  assert.match(csv, /"'\+Danger"/);
  assert.match(csv, /"A,1"/);
});
