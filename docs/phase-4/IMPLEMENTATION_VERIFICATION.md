# Phase 4 — Implementation Verification

## Invocation and checkpoint

- Command: `build`
- Mode: all remaining phases
- Main head before preflight: `cc8cfd8a6dff259db1ffdde3e40c07d4b186ebc8`
- Prior phase: Phase 3 repository implementation complete; live infrastructure gate partial.
- Migration reserved: `202607140011_approval_exception_outbox.sql`

## Product outcome

Employees can use a responsive authenticated web application to upload and review receipts, assemble claims/reports, preview policy, request exceptions, and submit. Managers and finance users receive deterministic queues and make immutable decisions.

Explicit exclusions: reimbursement payment and accounting export.

## Existing implementation inspected

- Phase 1 receipt routes and verification workflow
- Phase 2 expense claims/reports and immutable submission snapshots
- Phase 3 policy rules, evaluations, and exception requests
- `src/app.ts`, `src/routes/expenses.ts`, policy routes and repositories
- Supabase Auth/RLS model
- Current Worker/Queue environment

## Assumptions

| Assumption | Status | Consequence |
|---|---|---|
| One responsive web application is preferable | confirmed by roadmap | create `web/` React/Vite app |
| Public approval links are acceptable | rejected | all decisions require Supabase session |
| Email credentials exist | rejected | implement durable outbox and local/no-op adapter |
| Manager can approve own report | rejected | database prevents self-approval |
| Employee edits may reuse approvals | rejected | changes create a new submission cycle |

## Architecture

- React/Vite TypeScript application in `web/`, deployed independently as static assets.
- Browser contains only Supabase URL/publishable key and API base URL.
- Approval workflow is database-authoritative through versioned RPCs.
- Decisions are append-only and tied to immutable submission IDs.
- Notification outbox uses unique event keys and idempotent leasing.
- A change request returns the report to a new employee revision cycle without altering the old submission.

## Security and concurrency

- Authenticated role checks in SQL and RLS.
- Self-approval and cross-company decisions rejected.
- Decision idempotency keys are unique per company.
- Report and assignment rows locked before decisions.
- Delegations have explicit time ranges and cannot broaden role authority.
- No service-role or provider secrets in the web app.

## Official guidance

- Supabase React Auth official guidance supports a Vite React client with publishable/anon key, session restoration, OTP login, and RLS.
- Static frontend remains separate from Worker secrets.

## Implementation slices

1. Approval/outbox schema and RPCs.
2. Approval repository/routes and workflow domain tests.
3. React/Vite application shell and critical employee/manager/finance screens.
4. UI/API contract checks and Phase 4 runbook.

## Validation

- Domain transition tests.
- Migration-contract tests for self-approval, immutable decisions, idempotency, delegation expiry, and outbox uniqueness.
- Web TypeScript/build scripts committed; actual dependency installation may remain externally blocked.
- Keyboard/accessibility structure review.

## Decision

`GO WITH LIVE AUTH/DELIVERY VALIDATION BLOCKED`
