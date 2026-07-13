# Phase 3 — Deterministic Policy Engine

> Evaluate every draft expense report against versioned company rules, explain every result, and block submission only through auditable database decisions.

Phase 1 establishes receipt truth. Phase 2 turns verified receipts into employee-confirmed claims and immutable report submissions. Phase 3 adds the policy layer between those stages:

```text
verified receipt evidence
  → employee claim and draft report
  → deterministic policy evaluation
  → warnings / hard blocks / exception-required findings
  → explicit exception request and review
  → locked re-evaluation at submission
  → immutable report + policy snapshot
```

## Core invariant

A policy decision must be reproducible from a specific rule version and a specific report/claim state. A preview never authorizes submission by itself: submission re-evaluates the current report against the current effective policy set inside the same database transaction that creates the immutable report snapshot.

## Implemented boundary

Phase 3 implements:

- immutable, versioned company policy rules;
- finance/admin rule creation, supersession, and deactivation;
- effective-date handling;
- deterministic, typed rule configuration;
- report-level and claim-level evaluation results;
- plain-language explanations and structured evidence;
- three enforcement severities: `warning`, `block`, and `requires_exception`;
- employee policy previews;
- employee exception requests for exceptionable findings;
- finance/admin exception approval or rejection;
- stale-exception invalidation when a report or claim changes;
- submission-time policy re-evaluation under locks;
- immutable policy snapshots attached to report submissions;
- audit events for policy administration, evaluation, exceptions, and blocked submissions;
- tenant isolation and cross-table scope enforcement.

Explicitly deferred:

- manager approval/rejection of the complete report;
- configurable approval chains;
- AI interpretation of free-form policy documents;
- exchange-rate conversion;
- mileage and per-diem rules;
- merchant reputation or fraud scoring;
- reimbursement, payroll, accounting export, and money movement;
- tax-credit eligibility decisions.

## Rule model

Rules are append-only versions. Updating a rule creates a new row and closes the previous version. Historical evaluations continue to point to the exact rule that produced them.

Every rule contains:

- company scope;
- stable code;
- human-readable name and description;
- rule type;
- enforcement severity;
- validated JSON configuration;
- version number;
- effective-from and optional effective-to timestamps;
- superseded-rule reference;
- creator and timestamps.

Policy changes and report evaluations use the same company-scoped transaction advisory lock. This prevents a submission from observing a partially changed policy set.

## Supported deterministic rules

### `max_amount`

Configuration:

```json
{
  "currency": "INR",
  "amount": "5000.00",
  "categoryId": null
}
```

Fails when an applicable claim exceeds the configured exact-decimal amount. A category may be supplied to narrow the rule.

### `expense_age_days`

```json
{ "maxDays": 30 }
```

Fails when the incurred date is more than the configured number of days before evaluation.

### `weekend_requires_note`

```json
{ "minimumNoteLength": 20 }
```

Fails when a Saturday/Sunday claim lacks a sufficiently descriptive note.

### `category_blocked`

```json
{ "categoryId": "<company category UUID>" }
```

Fails every claim assigned to the configured category.

### `project_required`

```json
{ "categoryId": null }
```

Fails applicable claims with no project. An optional category narrows the rule.

### `cost_centre_required`

```json
{ "categoryId": null }
```

Fails applicable claims with no cost centre.

### `gstin_required`

```json
{ "categoryId": null }
```

Fails applicable claims whose verified receipt facts do not contain a non-empty GSTIN. This is a document-completeness signal, not a tax-credit eligibility decision.

## Enforcement semantics

| Severity | Failed result | Submission behavior |
|---|---|---|
| `warning` | Visible warning | Submission allowed |
| `block` | Hard policy violation | Submission blocked |
| `requires_exception` | Exceptionable violation | Blocked until a valid approved exception exists |

An approved exception is valid only when:

- it belongs to the same report, rule version, and claim;
- the report version still matches the request;
- the claim version still matches the request;
- the exception is approved;
- the rule is still the effective rule being evaluated.

Changing a claim, report composition, or policy version therefore makes an earlier exception unusable without deleting its audit history.

## Policy evaluation lifecycle

```text
report preview request
  → lock report and attached claims
  → lock company policy revision
  → select effective rules
  → create evaluation run
  → create one result per applicable rule/claim
  → derive pass / warning / blocked outcome
  → return explanations and evidence
```

Results are append-only. A new evaluation creates a new run rather than rewriting previous conclusions.

## Submission behavior

Submission still performs all Phase 2 readiness and duplicate checks. It then runs policy evaluation before creating the report submission:

1. lock report;
2. verify expected report version;
3. lock all attached claims in deterministic order;
4. perform Phase 2 readiness checks;
5. acquire the company policy advisory lock;
6. evaluate current effective rules;
7. if blocked, persist the evaluation and return a blocked result without submitting;
8. if pass/warning, create an immutable submission containing the policy run and result snapshot;
9. transition claims/report to submitted.

The API converts a persisted blocked submission result into HTTP `409`, while the policy evaluation remains available for the employee to inspect.

## Exception workflow

```text
failed `requires_exception` result
  → employee supplies business justification
  → pending exception request
  → finance/admin approves or rejects
  → future evaluation marks matching result `waived` only if versions still match
```

A hard `block` cannot be bypassed through this exception workflow. A `warning` requires no exception.

## API

All routes require a valid Supabase Bearer token.

### Rule administration

- `GET /v1/policies/rules?companyId=...&active=true`
- `POST /v1/policies/rules`
- `POST /v1/policies/rules/:ruleId/deactivate`

Rule creation supports `supersedesRuleId` to create the next immutable version.

### Evaluation and exceptions

- `POST /v1/expenses/reports/:reportId/evaluate-policy`
- `GET /v1/expenses/reports/:reportId/policy`
- `POST /v1/policies/exceptions`
- `POST /v1/policies/exceptions/:exceptionId/resolve`

### Report submission

`POST /v1/expenses/reports/:reportId/submit` retains its Phase 2 request shape. It now returns a conflict when current policy blocks submission and includes the persisted policy run details.

## Security and integrity

- Direct authenticated writes to policy, evaluation, and exception tables are not granted.
- Security-definer RPCs perform explicit role, ownership, state, and tenant checks.
- Rule configurations are validated both at the API boundary and in PostgreSQL.
- Policy rules are immutable after insertion except controlled deactivation/supersession metadata.
- Evaluation runs and results are append-only.
- Employees may request exceptions only from the latest evaluation for the current report version.
- Only finance/admin may resolve exceptions or administer rules.
- The evaluator never executes arbitrary expressions, SQL, JavaScript, or model-generated logic.
- Rule and evaluation links are protected by company-scope triggers.
- Advisory locks serialize policy mutation with evaluation for each company.

## Phase 3 exit gate

Phase 3 is ready for live validation only when:

1. migrations apply cleanly after Phases 1 and 2;
2. policy rules cannot reference another company's categories;
3. rule supersession creates a new immutable version;
4. concurrent rule changes cannot produce a partial evaluation set;
5. every supported rule passes deterministic fixture tests;
6. warning rules do not block submission;
7. hard-block rules cannot be bypassed;
8. approved exceptions waive only the exact current report/claim/rule version;
9. claim or report edits invalidate prior exceptions;
10. blocked submissions preserve their evaluation without creating a report submission;
11. successful submissions contain the exact policy snapshot used;
12. tenant isolation and authorization tests pass in a non-production Supabase project;
13. a finance operator can understand every explanation without reading rule code.
