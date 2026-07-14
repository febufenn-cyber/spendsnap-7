# Deployment and Rollback Guide

## Environments

Use separate Supabase projects, Cloudflare Workers/Queues, storage buckets, web origins, secrets, billing webhook secrets, and customer data for development, staging, and production. Production access must be least privilege and audited.

## Database deployment

1. Restore the latest backup into a disposable environment and apply every migration in filename order.
2. Run schema-contract, tenant-isolation, concurrency, approval, export, invitation, agent, and billing tests.
3. Review migration locks, runtime, backfill volume, rollback strategy, and destructive risk.
4. Record migration filenames and checksums in the change ticket.
5. Apply to staging, complete end-to-end smoke tests, then apply to production during an approved window.
6. Prefer forward repairs. Never roll back by deleting immutable financial evidence.

## Worker deployment

Required secrets include Supabase keys, Anthropic key/model, receipt bucket, prompt versions, origin allowlist, size limits, and—when enabled—billing webhook secret. Deploy with a build SHA and verify `/health`, `/ready`, authenticated APIs, queue publication/consumption, and provider timeouts.

Rollback by redeploying the previous known-good Worker version. Do not roll back code below already-applied schema requirements without a compatibility review.

## Web deployment

Install dependencies in `web/`, run typecheck/build, and verify the artifact contains:

- `index.html`
- `finance.html`
- `admin.html`
- `agent.html`
- `commercial.html`

Configure environment variables at build time, CSP at the static host, correct Supabase redirect URLs, HTTPS, cache rules for hashed assets, and no-cache for HTML. Search generated files and source maps for secrets before publication.

## Post-deploy smoke test

Use synthetic tenants and receipts to complete:

`sign in → upload → extraction → verification → claim → report → policy → approval → finance review → export → audit evidence`

Also test denied cross-company access, invalid origin, stale version, self-approval, expired delegation, locked period, duplicate billing event, invalid webhook signature, agent prohibited-action prompt, and sign-out/session expiry.

## Rollback decision

Rollback immediately for cross-tenant access, exposed secrets, corrupted evidence, unauthorized decisions/exports/billing, or severe authentication failure. For schema/data integrity incidents, pause affected routes and use a reviewed forward repair instead of attempting destructive reversal.
