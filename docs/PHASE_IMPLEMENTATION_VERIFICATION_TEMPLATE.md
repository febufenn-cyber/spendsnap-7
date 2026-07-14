# Phase N — Implementation Verification

> This file must be completed from the live repository state and committed before Phase N implementation begins.

## 1. Invocation

- User command:
- Requested phase:
- Execution mode: `single phase` / `all remaining phases`
- Verification date:

## 2. Repository checkpoint

- Repository: `febufenn-cyber/spendsnap-7`
- Default branch: `main`
- Main head SHA before preflight:
- Latest relevant commits inspected:
- Existing pull requests or branch protections affecting publication:
- Concurrent changes detected:

## 3. Prior-phase gate

- Prior phase:
- Prior phase exit gate result: `pass` / `partial` / `blocked`
- Evidence inspected:
- Required prerequisite fixes:
- Unperformed infrastructure operations that affect this phase:

## 4. Product outcome

- Primary user outcome:
- Roles involved:
- Start state:
- Successful end state:
- Explicit exclusions:
- User-visible failure states:

## 5. Existing implementation inspected

List every relevant file, migration, API route, domain object, test, and document actually inspected.

- Files:
- Database objects:
- APIs:
- UI surfaces:
- Tests:
- Runbooks:

## 6. Assumption ledger

| Assumption | Evidence | Status | Consequence |
|---|---|---|---|
| | | confirmed / rejected / unresolved | |

Unresolved assumptions must be handled with the narrowest reversible implementation and documented as such.

## 7. Architecture decision

- Chosen architecture:
- Why it fits existing repository conventions:
- Alternatives rejected:
- Migration strategy:
- Rollback strategy:
- Compatibility strategy:

## 8. Data and financial integrity

- New entities:
- Ownership rules:
- Tenant-scope rules:
- Immutable snapshots:
- Legal state transitions:
- Decimal/currency treatment:
- Historical records preserved:
- Retention/deletion implications:

## 9. Security review

- Authentication boundary:
- Authorization roles:
- RLS changes:
- Service-role operations:
- Cross-company integrity checks:
- Replay/idempotency controls:
- Input validation:
- Prompt-injection exposure:
- Sensitive logging review:
- Signed-link or webhook verification:

## 10. Concurrency and failure review

- Records requiring optimistic versions:
- Records requiring database locks:
- Double-submit threat:
- Queue/webhook duplicate-delivery threat:
- Partial failure behavior:
- Retry behavior:
- Recovery path:
- Stale decision invalidation:

## 11. Dependency and external-service verification

For unstable dependencies, verify current official documentation before implementation.

| Dependency/service | Official source checked | Version/contract decision | Credentials available |
|---|---|---|---|
| | | | yes / no / not required |

## 12. Implementation slices

| Order | Intended commit | Scope | Verification after commit |
|---:|---|---|---|
| 1 | Verify Phase N implementation boundary | Preflight document | Main head and file readback |
| 2 | Define Phase N architecture | Docs/threat model | Documentation review |
| 3 | Add Phase N schema | Migrations/integrity | Contract and migration review |
| 4 | Implement Phase N domain | Domain/persistence | Type/domain tests |
| 5 | Expose Phase N API | Routes/repositories | API contract tests |
| 6 | Add Phase N web experience | UI/client | UI tests and smoke checks |
| 7 | Harden Phase N concurrency | Locks/versions/idempotency | Race regression tests |
| 8 | Add Phase N checks | Tests/CI/evals | Strongest available check |
| 9 | Complete Phase N runbook | Docs/status | Final main verification |

Adjust the sequence when a slice is not relevant, but explain why.

## 13. Test plan

- Domain tests:
- API tests:
- Migration-contract tests:
- Database integration tests:
- Tenant/role matrix tests:
- Concurrency tests:
- Golden-file tests:
- UI component/browser tests:
- End-to-end tests:
- Security/adversarial tests:
- Manual validation:

## 14. Exit gate

Copy the roadmap exit gate for this phase and map each item to evidence.

| Exit requirement | Evidence expected | Result |
|---|---|---|
| | | pending / pass / blocked |

## 15. Stop and pivot conditions

- Destructive production decision required:
- Missing credential or paid service:
- Existing schema conflict:
- Unsupported external contract:
- Security condition that prevents safe implementation:
- Evidence that the phase boundary should change:

Routine implementation choices are not stop conditions.

## 16. Publication protocol

- Publication path: direct commits to `main` while permitted; otherwise checked phase branch and PR.
- Force push: forbidden.
- Final merge required: yes / no.
- Final confirmation must include:
  - phase commits;
  - tests executed;
  - failures fixed;
  - migrations added;
  - operations performed;
  - operations not performed;
  - final confirmed `main` SHA.

## 17. Preflight decision

- Decision: `GO` / `GO WITH REPAIRS` / `BLOCKED`
- Required repairs before feature implementation:
- Reason:
- Preflight commit SHA:
