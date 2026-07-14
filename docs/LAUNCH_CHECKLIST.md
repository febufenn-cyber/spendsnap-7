# Spendsnap Production Launch Checklist

A checked repository box is not proof that a live environment passed. Record evidence, operator, timestamp, environment, and rollback owner for every item.

## Customer and commercial

- [ ] Initial customer segment and primary job are validated with real workflows.
- [ ] At least two design partners and one paid pilot are committed.
- [ ] Final pricing, overage, trial, cancellation, refund, GST, and support terms are approved.
- [ ] Terms of service, privacy notice, data-processing terms, and human-review disclosure are legally reviewed.
- [ ] Billing-provider account, tax configuration, webhook secret rotation, reconciliation, and failure procedures are tested.

## Supabase

- [ ] All migrations apply cleanly to a fresh non-production project in filename order.
- [ ] Migration checksums and production change ticket are recorded.
- [ ] Two-company RLS and cross-table tenant tests pass for every role.
- [ ] Storage bucket is private; signed upload and download paths are company scoped.
- [ ] PITR/backups are enabled and a restore test has succeeded.
- [ ] Auth redirect URLs, email templates, rate limits, password/OTP policy, and verified-email behavior are configured.
- [ ] Service-role key has been rotated and exists only as a Worker secret.

## Cloudflare

- [ ] Worker secrets are configured without plaintext repository copies.
- [ ] `ALLOWED_ORIGINS` contains only deployed application origins.
- [ ] Queue, dead-letter queue, retry policy, alarms, and backlog monitoring are configured.
- [ ] `/health` and `/ready` are monitored separately.
- [ ] Request-size, CPU, duration, provider timeout, rate-limit, and cost alerts are configured.
- [ ] Deployment rollback to the previous known-good version is rehearsed.

## Web application

- [ ] `npm run typecheck` and `npm run build` pass in `web/`.
- [ ] All five HTML entry points are present in the production artifact.
- [ ] Mobile, desktop, keyboard-only, screen-reader, empty, loading, error, conflict, and expired-session states are tested.
- [ ] No service-role, model, billing, or provider secret appears in JavaScript or source maps.
- [ ] CSP is configured at the static host with only required origins.
- [ ] Supabase redirect and sign-out URLs are correct for every environment.

## Financial controls

- [ ] Receipt corpus meets field-specific accuracy thresholds.
- [ ] Critical fields always follow the human-resolution policy.
- [ ] Duplicate, arithmetic, policy, exception, self-approval, delegation, period-lock, and concurrency cases pass.
- [ ] A real historical report completes employee → manager → finance → Tally import without spreadsheet re-entry.
- [ ] Export checksum matches downloaded bytes and accounting import result.
- [ ] GST wording has been reviewed by a qualified professional and does not claim eligibility.

## AI controls

- [ ] Adversarial evaluation has zero prohibited financial actions and zero sensitive-data leakage.
- [ ] Model and prompt versions are pinned and rollbackable.
- [ ] Agent endpoint can be disabled independently.
- [ ] Customer documents are not used for training without explicit permission.
- [ ] Human confirmation and non-mutating behavior are clear in the product.

## Operations

- [ ] Incident commander, security contact, privacy contact, support hours, and escalation rota are assigned.
- [ ] Incident, support, backup, retention, deletion, webhook, provider outage, and accounting export runbooks are rehearsed.
- [ ] Audit and security-event retention match contracts and law.
- [ ] Penetration test and independent security review findings are resolved or accepted in writing.
- [ ] Synthetic demo workspace is isolated from customer environments.
- [ ] Go/no-go decision and known residual risks are signed by the accountable owner.
