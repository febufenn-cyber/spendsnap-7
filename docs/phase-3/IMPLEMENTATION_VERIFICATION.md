# Phase 3 — Implementation Verification

## Invocation

- User command: `build`
- Execution mode: all remaining phases
- Verification date: 2026-07-14

## Repository checkpoint

- Repository: `febufenn-cyber/spendsnap-7`
- Branch: `main`
- Main head before preflight: `0eff95c32b237dcb18aeca1a49b2c1e49f9801a2`
- Phase 3 commits inspected: `4c22e50`, `dc71e11`, `ae98414`, `7a0741d`, `18ad0f9`, `4ba3e1b`
- Concurrent changes detected: none in the latest main history inspected
- Publication: direct commits to `main`; no force push

## Prior-phase gate

Phase 2 is code-complete but infrastructure validation remains blocked by missing Supabase and Cloudflare credentials. This does not block safe repository implementation. Phase 3 must not claim live database execution.

## Product outcome

A company can define deterministic expense rules; an employee can preview policy results and request a scoped exception; report submission re-evaluates under locks and persists exact policy evidence.

Explicit exclusions: approval decisions, notification delivery, reimbursement, export, AI policy interpretation.

## Existing implementation inspected

- `docs/phase-3/README.md`
- `src/domain/policy.ts`
- `src/repositories/policy-repository.ts`
- Phase 3 schema and report-submission integration commits
- `src/app.ts`, `src/routes/expenses.ts`, `src/errors.ts`
- Phase 2 report lifecycle and immutable submission model

## Assumptions

| Assumption | Status | Consequence |
|---|---|---|
| PostgreSQL RPCs remain authoritative | confirmed | API repository delegates mutations to RPCs |
| Policy preview may be stale | confirmed | submission always re-evaluates under locks |
| Manager exception approval belongs to Phase 4 | confirmed | Phase 3 supports pending exceptions and read APIs only |
| Live service credentials are available | rejected | no deployment or live integration claims |

## Architecture

- User-scoped Supabase client for policy reads and RPCs.
- Hono routes under `/v1/policies`.
- Zod validates rule configurations before RPC invocation.
- Domain tests establish reference semantics; migration-contract tests assert lock/version/snapshot invariants.
- No service-role policy mutation from browser-facing routes.

## Security and concurrency

- Finance/admin role checks remain in security-definer database functions.
- RLS controls reads; cross-company links are rejected in SQL.
- Rule changes and report submission serialize through company/report locks.
- Exceptions are scoped to rule, claim, and report versions.
- Blocked evaluation records must survive failed submission attempts.
- Receipt text is never interpreted as policy instructions.

## Official guidance checked

- Supabase React/Auth guidance confirms browser use of the publishable/anon key with user sessions and RLS; service-role keys stay server-side.
- Cloudflare queue guidance remains compatible with explicit acknowledgement/retry and idempotent consumers.

## Implementation slices

1. Verify Phase 3 boundary.
2. Implement policy repository and API routes.
3. Add domain and migration-contract tests.
4. Commit Phase 3 runbook and status.

## Validation

- TypeScript typecheck where runnable.
- Node domain tests.
- Schema-contract tests.
- Readback of every committed file and final `main` SHA.

## Exit-gate mapping

The repository can satisfy API wiring, versioning, semantic parity, locked re-evaluation, persisted blocks, warnings, stale-exception protection, submission evidence, tests, and documentation. Live migration application and tenant integration testing remain externally blocked.

## Decision

`GO WITH EXTERNAL VALIDATION BLOCKED`
