# Phase 3 Policy Engine Runbook

## Purpose

Provision and validate deterministic policy rules, report previews, scoped exceptions, and submission-time enforcement.

## Required migrations

Apply in order after all Phase 1 and Phase 2 migrations:

1. `202607130009_deterministic_policy_engine.sql`
2. `202607130010_policy_submission_integration.sql`

Use a non-production Supabase project first. Keep a database backup before applying migrations to an existing environment.

## Smoke procedure

1. Create two isolated companies and users for employee, manager, finance, and admin roles.
2. Create a verified receipt, claim, and draft report for company A.
3. Create a blocking `max_amount` rule through `POST /v1/policies/rules`.
4. Preview with `POST /v1/policies/reports/:reportId/evaluate`.
5. Confirm the evaluation records rule/version, claim evidence, explanation, and policy hash.
6. Attempt report submission and confirm the response is `blocked` while the evaluation remains queryable.
7. Change the rule by creating a new version; confirm the old row remains immutable and inactive.
8. Create a `requires_exception` result and request an exception.
9. Confirm Phase 3 does not allow an employee to approve it.
10. Confirm an exception for an older report or claim version does not waive a new evaluation.
11. Repeat all reads and mutation attempts using company B credentials; every cross-company action must fail.
12. Run two concurrent operations: policy version creation and report submission. Confirm the company policy lock yields one coherent policy snapshot.

## API surface

- `GET /v1/policies/rules?companyId=...&active=true`
- `POST /v1/policies/rules`
- `POST /v1/policies/rules/:ruleId/deactivate`
- `POST /v1/policies/reports/:reportId/evaluate`
- `GET /v1/policies/reports/:reportId`
- `POST /v1/policies/results/:resultId/exceptions`
- `POST /v1/policies/exceptions/:exceptionId/resolve`

The final exception-resolution route exists for the authenticated manager/finance workflow introduced in Phase 4. Database role checks remain authoritative.

## Operational alerts

Investigate:

- repeated policy evaluation failures;
- incomplete runs where `outcome` remains null;
- unusually high block rates after a rule version change;
- exception requests that remain pending beyond the company's review target;
- duplicate policy codes or unexpected inactive rules;
- policy hashes changing without a corresponding versioned rule event.

## Rollback and recovery

Policy rules are immutable versions. Do not edit an old rule to repair a mistake. Deactivate it and create a corrected version. Evaluation and submission snapshots must never be rewritten.

Schema rollback is not safe after production policy evidence exists. Prefer a forward migration. A blocked report remains draft and can be re-evaluated after a rule correction or approved exception.

## Validation status

Repository artifacts, tests, routes, and migrations are committed. Live migrations, RLS verification, concurrent database tests, and deployment require external Supabase/Cloudflare credentials and have not been performed in this build environment.
