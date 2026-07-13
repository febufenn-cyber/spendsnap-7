import assert from 'node:assert/strict';
import test from 'node:test';
import { decideFieldReview } from '../dist/domain/confidence.js';
import { semanticFingerprint, sha256Hex } from '../dist/domain/fingerprint.js';
import { detectImageMediaType } from '../dist/domain/image.js';
import { canTransition } from '../dist/domain/lifecycle.js';
import { validateReceiptArithmetic } from '../dist/domain/money.js';

test('receipt lifecycle permits only explicit transitions', () => {
  assert.equal(canTransition('upload_pending', 'received'), true);
  assert.equal(canTransition('received', 'queued'), true);
  assert.equal(canTransition('queued', 'extracting'), true);
  assert.equal(canTransition('extracting', 'needs_review'), true);
  assert.equal(canTransition('needs_review', 'verified'), true);

  assert.equal(canTransition('upload_pending', 'verified'), false);
  assert.equal(canTransition('verified', 'extracting'), false);
  assert.equal(canTransition('archived', 'queued'), false);
});

test('critical financial fields always require human review', () => {
  const total = decideFieldReview({
    fieldName: 'total',
    confidence: 1,
    value: '1250.00',
  });

  assert.equal(total.isCritical, true);
  assert.equal(total.reviewStatus, 'requires_review');
});

test('high-confidence contextual fields may be auto accepted', () => {
  const merchant = decideFieldReview({
    fieldName: 'merchant_name',
    confidence: 0.99,
    value: 'Acme Hotel',
  });

  assert.equal(merchant.isCritical, false);
  assert.equal(merchant.reviewStatus, 'auto_accepted');
});

test('warnings force contextual fields into review', () => {
  const merchant = decideFieldReview({
    fieldName: 'merchant_name',
    confidence: 1,
    value: 'Acme Hotel',
    warnings: ['conflicting_merchant_names'],
  });

  assert.equal(merchant.reviewStatus, 'requires_review');
});

test('receipt arithmetic uses exact scaled decimal math', () => {
  const result = validateReceiptArithmetic({
    subtotal: '1000.00',
    cgst: '90.00',
    sgst: '90.00',
    total: '1180.00',
  });

  assert.deepEqual(result, { valid: true, warnings: [] });
});

test('receipt arithmetic flags inconsistent totals', () => {
  const result = validateReceiptArithmetic({
    subtotal: '1000.00',
    cgst: '90.00',
    sgst: '90.00',
    total: '1280.00',
  });

  assert.equal(result.valid, false);
  assert.ok(result.warnings.includes('subtotal_plus_tax_does_not_match_total'));
});

test('semantic fingerprints normalize formatting differences', async () => {
  const first = await semanticFingerprint({
    merchantName: 'Acme Foods Pvt. Ltd.',
    invoiceNumber: ' INV-001 ',
    invoiceDate: '2026-07-13',
    currency: 'inr',
    total: '1,180.00',
  });
  const second = await semanticFingerprint({
    merchantName: 'ACME FOODS PVT LTD',
    invoiceNumber: 'INV-001',
    invoiceDate: '2026/07/13',
    currency: 'INR',
    total: '1180.00',
  });

  assert.equal(first, second);
});

test('semantic fingerprint refuses weak identities', async () => {
  const fingerprint = await semanticFingerprint({
    merchantName: 'Unknown',
    invoiceNumber: null,
    invoiceDate: null,
    currency: 'INR',
    total: '100.00',
  });

  assert.equal(fingerprint, null);
});

test('server SHA-256 is deterministic', async () => {
  const bytes = new TextEncoder().encode('same receipt').buffer;
  assert.equal(
    await sha256Hex(bytes),
    '0496571c842c93adc543999f13d6d7f1e3e1a04ae76f2e5c7794867919b4e02b',
  );
});

test('image signatures override filename claims', () => {
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).buffer;
  const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0]).buffer;
  const webp = new TextEncoder().encode('RIFF0000WEBP').buffer;
  const unknown = new TextEncoder().encode('not an image').buffer;

  assert.equal(detectImageMediaType(png), 'image/png');
  assert.equal(detectImageMediaType(jpeg), 'image/jpeg');
  assert.equal(detectImageMediaType(webp), 'image/webp');
  assert.equal(detectImageMediaType(unknown), null);
});
