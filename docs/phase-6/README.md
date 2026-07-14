# Phase 6 — Production Hardening and Tenant Administration

## Delivered

- Versioned company security settings and retention policy.
- One-time company invitations with digest-only token storage.
- Admin membership changes with last-active-admin protection.
- Explicit time-bounded support-access grants.
- Deletion request workflow that separates request/approval from destructive execution.
- Append-only security events and deterministic checksummed audit evidence export.
- Explicit CORS allowlist, JSON body limits, security headers, no-store API responses, health and readiness endpoints.
- Authenticated admin API and `/admin.html` console.

## Environment

Set:

```text
ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com
MAX_JSON_BYTES=1000000
```

Never use `*` with credentialed browser requests. Keep Supabase service role, Anthropic keys, and all provider credentials in Worker secrets only.

## Apply and test

1. Apply `202607140014_production_admin_security.sql` in non-production.
2. Verify an invitation token is shown once, its digest is stored, an incorrect account cannot accept it, and a replay fails.
3. Concurrently demote two admins and confirm the last-admin invariant survives.
4. Verify support grants before start, during validity, after expiry, and after revocation.
5. Confirm cross-tenant admin reads and mutations fail.
6. Generate audit evidence twice and verify deterministic event ordering and checksums.
7. Test allowed and denied browser origins, oversized JSON, OPTIONS preflight, and all security headers.
8. Exercise backup and restore using provider-native tooling before production launch.
9. Perform an independent security review and penetration test.

## Destructive operations

The migration records deletion requests but intentionally does not automatically erase financial evidence. A service-role operator must verify legal retention, dependencies, period locks, audit obligations, and backups before a separately reviewed forward migration or controlled job executes deletion.

## Readiness

- `/health` indicates process availability.
- `/ready` checks mandatory configuration presence; it does not prove third-party availability.
- Provider dashboards must monitor Worker errors, queue backlog/dead letters, Supabase availability, storage usage, auth errors, and outbox failures.

## External blockers

This build did not apply migrations, send a real invitation, configure origins, run backup restoration, perform destructive deletion, deploy the admin console, or conduct penetration testing. Those remain required operational gates.
