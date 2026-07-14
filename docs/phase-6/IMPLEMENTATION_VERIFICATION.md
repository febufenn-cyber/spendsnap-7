# Phase 6 — Implementation Verification

## Checkpoint

- Command: `build`
- Main head before preflight: `bf63148bddbda2edeef73775e0baa972dffda27b`
- Prior phase: Phase 5 repository complete; live accounting validation blocked.
- Migration reserved: `202607140014_production_admin_security.sql`

## Outcome

Spendsnap has production-grade tenant administration, secure invitation/role changes, retention controls, deletion workflow, temporary support access, security-event evidence, audit export, security headers, origin controls, readiness reporting, and an admin console.

Explicit exclusions: destructive automatic production deletion, SSO/SAML, legal compliance certification, and provider-specific backup automation.

## Decisions

- Invitation tokens are returned once and only their SHA-256 digests are stored.
- The last active admin cannot remove or demote themselves.
- Support access is explicit, company-approved, time-bounded, purpose-limited, and audited.
- Retention and deletion are request/plan workflows; irreversible execution requires service-role operations and operator confirmation.
- Audit export is deterministic JSON evidence, not a database dump.
- CORS uses an explicit origin allowlist; browser secrets remain forbidden.
- Security events are append-only.

## Security/concurrency threats

- Token replay, invitation enumeration, role-escalation races, last-admin removal, expired support grants, deletion during active financial workflows, stale settings updates, oversized requests, permissive origins, and missing request IDs.
- Admin mutations lock company/membership/invitation rows.
- Idempotency keys are required where retries can duplicate effects.

## Implementation slices

1. Administration/security schema and RPCs.
2. Security middleware, readiness, admin repository/routes.
3. Authenticated admin web console.
4. Security and contract tests.
5. Production checklist/runbook.

## Validation limits

Repository checks can validate contracts. Live invitation delivery, backup restore, destructive retention, provider monitoring, and penetration testing require infrastructure and are not claimed.

## Decision

`GO WITH DESTRUCTIVE/LIVE OPERATIONS BLOCKED`
