# Phase 8 — Commercial Launch and Operating System

## Delivered

- Versioned, provider-neutral product plans.
- Automatic 14-day starter trial and onboarding checklist for new companies.
- Company subscriptions with optimistic versions and server-side feature entitlements.
- Append-only, idempotent usage metering for receipts, reports, agent runs, and exports.
- HMAC-SHA256 signed billing webhook with constant-time verification, body limits, payload hashing, provider-event idempotency, and service-role processing.
- Product-event allowlist with sensitive-property removal.
- Authenticated onboarding, usage, and plan console at `/commercial.html`.
- Current prices explicitly labeled as hypotheses, not binding terms.

## Apply

Apply in order after all earlier migrations:

1. `202607140017_commercial_operating_system.sql`
2. `202607140018_billing_service_grant.sql`
3. `202607140019_last_admin_lock_fix.sql`

Configure `BILLING_WEBHOOK_SECRET` only in Worker secrets. The billing provider must send:

- `X-Spendsnap-Provider`
- `X-Spendsnap-Event-ID`
- `X-Spendsnap-Event-Type`
- `X-Spendsnap-Signature`: lowercase or uppercase hexadecimal HMAC-SHA256 of the exact raw request body

Endpoint: `POST /webhooks/billing`.

## Commercial validation

Before charging customers:

1. Interview at least five qualified buyers about the pricing unit and thresholds.
2. Obtain at least one paid pilot or signed commercial commitment.
3. Publish final terms, tax treatment, cancellation, refund, overage, and service-level language.
4. Integrate a billing provider through the generic signed-event adapter.
5. Verify duplicate, reordered, delayed, invalid-signature, unknown-plan, past-due, cancellation, and retry events.
6. Confirm usage totals against source records for a full billing period.
7. Verify entitlements under trial, active, expired, past-due, cancelled, and manual-plan states.
8. Do not collect payment-card data directly.

## Current plan hypotheses

- Starter: ₹2,999/month, 200 receipts, 10 active users.
- Growth: ₹7,999/month, 1,000 receipts, 50 active users.
- Verified Service: ₹14,999/month, 2,000 receipts, 100 active users, subject to a separate human-review service agreement.

These rows are product experiments. Update them through a versioned migration after customer evidence; do not rewrite historical plan records.

## External blockers

No billing account, domain, email provider, deployed Worker, deployed web assets, legal review, buyer interviews, paid pilot, or live webhook verification was available. The repository is launch-ready in structure, not commercially live.
