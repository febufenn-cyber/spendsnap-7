import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration = await readFile('supabase/migrations/202607140017_commercial_operating_system.sql', 'utf8');
const grantRepair = await readFile('supabase/migrations/202607140018_billing_service_grant.sql', 'utf8');
const webhook = await readFile('src/routes/billing-webhooks.ts', 'utf8');
const vite = await readFile('web/vite.config.ts', 'utf8');
const portal = await readFile('web/src/CommercialPortal.tsx', 'utf8');

test('plans trials entitlements and usage are provider neutral and versioned', () => {
  assert.match(migration, /product_plans/);
  assert.match(migration, /company_subscriptions/);
  assert.match(migration, /trialing/);
  assert.match(migration, /company_has_feature/);
  assert.match(migration, /unique\(company_id,event_key\)/);
});

test('billing events are idempotent hashed and service-role only', () => {
  assert.match(migration, /unique\(provider,provider_event_id\)/);
  assert.match(migration, /payload_hash/);
  assert.match(migration, /signature_verified boolean not null/);
  assert.match(grantRepair, /to service_role/);
  assert.match(webhook, /verifyBillingSignature/);
  assert.match(webhook, /X-Spendsnap-Event-ID/);
});

test('product analytics removes sensitive property names', () => {
  assert.match(migration, /-'receiptText'-'rawResponse'-'email'-'token'-'secret'/);
});

test('commercial UI labels pricing as hypothesis', () => {
  assert.match(portal, /prices are current product hypotheses/);
  assert.match(portal, /not a binding offer/);
});

test('Vite production build includes every product entry point', () => {
  for (const entry of ['index.html', 'finance.html', 'admin.html', 'agent.html', 'commercial.html']) {
    assert.match(vite, new RegExp(entry.replace('.', '\\.')));
  }
});
