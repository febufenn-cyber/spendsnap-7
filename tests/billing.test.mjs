import assert from 'node:assert/strict';
import test from 'node:test';
import { hmacSha256Hex, sha256Text, verifyBillingSignature } from '../dist/domain/billing.js';

test('valid billing signature verifies and payload hash is stable', async () => {
  const body = JSON.stringify({ companyId: '11111111-1111-4111-8111-111111111111', planCode: 'growth' });
  const signature = await hmacSha256Hex(body, 'test-secret');
  assert.equal(await verifyBillingSignature(body, signature, 'test-secret'), true);
  assert.equal(await verifyBillingSignature(`${body} `, signature, 'test-secret'), false);
  assert.equal(await sha256Text(body), await sha256Text(body));
});

test('malformed and wrong-length signatures fail without throwing', async () => {
  assert.equal(await verifyBillingSignature('{}', 'not-hex', 'test-secret'), false);
  assert.equal(await verifyBillingSignature('{}', '00', 'test-secret'), false);
});
