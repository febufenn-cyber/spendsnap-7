# Phase 2 — Employee Submission and Report Assembly

> Convert verified receipt evidence into employee-confirmed expense claims and immutable submitted reports.

Phase 1 answers **what the receipt proves**. Phase 2 answers **what the employee is claiming and why**.

The workflow is intentionally narrower than approval, reimbursement, or accounting export:

```text
verified receipt
  → employee expense claim
  → business purpose and company dimensions
  → draft report
  → server readiness validation
  → immutable submission snapshot
  → finance-visible submitted report
```

## Core invariant

A submitted report is an immutable snapshot of employee-confirmed claims backed by verified receipts. The database computes totals and enforces submission readiness; the client never supplies authoritative totals or report state transitions.

## Implemented boundary

Phase 2 implements:

- one initial expense claim per verified receipt;
- employee ownership of claims and reports;
- company-configured categories, projects, and cost centres;
- business purpose and optional notes;
- draft report creation and claim attachment;
- report periods and ordered items;
- optimistic concurrency through record versions;
- server-side readiness checks;
- totals grouped by currency;
- immutable submission snapshots;
- finance/manager/admin/auditor visibility of submitted evidence;
- withdrawal that preserves the submitted snapshot and releases claims for a new report;
- append-only workflow audit events;
- tenant and cross-table integrity enforcement.

Explicitly deferred:

- splitting one receipt into personal and business lines;
- attaching multiple receipts to one claim;
- manager approval or rejection;
- policy evaluation and exception handling;
- exchange-rate conversion and home-currency totals;
- reimbursement payment;
- payroll/accounting export;
- card or bank transaction matching;
- mileage and per-diem claims;
- native mobile UI.

## Why one claim per verified receipt first

Allowing arbitrary line splitting before observing real customer receipts would multiply ambiguity around tax, personal items, partial reimbursement, and duplicate detection. Phase 2 preserves the narrowest auditable path. A later migration can add claim lines without weakening the receipt evidence model.

## Data model

### Company dimensions

- `expense_categories`
- `expense_projects`
- `expense_cost_centres`

These are company-scoped, soft-disableable reference records. Employees may select active values; finance and admins manage them.

### Expense claims

A claim snapshots the accepted receipt facts used when it was created:

- verified receipt ID;
- merchant;
- incurred date;
- currency;
- exact decimal amount;
- category;
- optional project and cost centre;
- business purpose;
- optional notes;
- immutable receipt-facts snapshot;
- employee and company ownership;
- optimistic-lock version.

The amount, currency, merchant, and date originate from verified receipt facts, not client input.

### Expense reports

A draft report contains ordered claim references. Submission creates an immutable record in `expense_report_submissions` containing:

- report metadata;
- complete item snapshots;
- category/project/cost-centre labels at submission time;
- original verified receipt-facts snapshots;
- totals grouped by currency;
- submitter and timestamp.

Reference-record renames after submission therefore cannot rewrite historical reports.

## Lifecycles

### Claim

```text
draft → submitted → draft after report withdrawal
  └──────────────────────────────→ archived (future)
```

Only draft claims can be edited or moved between draft reports.

### Report

```text
draft → submitted → withdrawn
  └────────────────→ archived (future)
```

A withdrawn report is final. Its claims are detached and returned to draft status, while its submission snapshot remains immutable.

## Submission readiness

The submit RPC locks the report and claims, then rejects submission unless:

- the report belongs to the authenticated employee;
- the report is still draft and its version matches;
- at least one claim is attached;
- every claim belongs to the same company and employee;
- every backing receipt is verified;
- every claim is draft;
- business purpose is present;
- category is active and company-scoped;
- selected project/cost centre is active and company-scoped;
- amount is positive and currency is a valid three-letter code;
- incurred date falls within the report period;
- no open duplicate candidate exists for a backing receipt.

The database computes totals with exact `numeric(18,4)` arithmetic and groups them by currency. Phase 2 does not invent exchange rates.

## API

All routes require a valid Supabase Bearer token.

### Claims

- `POST /v1/expenses/claims/from-receipt`
- `GET /v1/expenses/claims?companyId=...&status=draft`
- `GET /v1/expenses/claims/:claimId`
- `PATCH /v1/expenses/claims/:claimId`

### Reports

- `POST /v1/expenses/reports`
- `GET /v1/expenses/reports?companyId=...&status=draft`
- `GET /v1/expenses/reports/:reportId`
- `POST /v1/expenses/reports/:reportId/items`
- `DELETE /v1/expenses/reports/:reportId/items/:claimId`
- `POST /v1/expenses/reports/:reportId/submit`
- `POST /v1/expenses/reports/:reportId/withdraw`

## Security and integrity

- Workflow writes occur through security-definer RPCs with explicit role and ownership checks.
- User tokens and RLS control reads.
- Direct client inserts/updates are not granted on workflow tables.
- Cross-company category, project, cost-centre, report, claim, receipt, and submission links are rejected by database triggers.
- Expected-version checks prevent lost updates and double submission.
- Submitted snapshots are append-only and cannot be updated or deleted by authenticated users.
- Employees see their own claims and reports; manager, finance, admin, and auditor roles may read company reports.
- Audit events capture claim creation/editing, report creation/item changes, submission, and withdrawal.

## Phase 2 exit gate

Phase 2 is ready for live validation only when:

1. migrations apply cleanly to a non-production Supabase project;
2. two-company tenant-isolation tests pass;
3. a verified receipt can create exactly one claim;
4. concurrent edits produce a version conflict rather than silent overwrite;
5. invalid or out-of-period claims block submission;
6. report totals match exact expected values by currency;
7. submission snapshots remain unchanged after reference-data edits;
8. withdrawal preserves history and makes claims reusable;
9. automated type, domain, and schema-contract checks pass;
10. a real employee can complete a five-receipt historical report without spreadsheet entry.
