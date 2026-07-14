# Phase 5 — Implementation Verification

## Checkpoint

- Command: `build`
- Main head before preflight: `ce8e8ba40fbac500f886d3caf7da2b0565cafd41`
- Prior phase: Phase 4 repository implementation complete; live UI/auth/provider checks blocked.
- Migration reserved: `202607140012_finance_gst_export.sql`

## Outcome

Finance users review manager-approved submissions, inspect GST completeness signals, apply immutable accounting mappings, approve finance evidence, and generate deterministic Tally-compatible CSV export batches.

Explicit exclusions: tax filing, guaranteed input-tax-credit eligibility, reimbursement payment, bank payout, direct Tally network synchronization.

## Existing implementation inspected

- Finance-review workflow from Phase 4
- Verified receipt facts and arithmetic warnings
- Immutable report submissions and approval decisions
- Expense categories/projects/cost centres
- Current role/RLS and audit infrastructure
- React application finance role surface

## Decisions

- First export: configurable Tally-compatible UTF-8 CSV.
- Each export references a finance-approved approval workflow and immutable submission.
- Mapping snapshots, rows, generated content, checksum, and schema version are immutable.
- Re-export creates a new batch; it never overwrites history.
- Idempotency keys prevent accidental duplicate generation.
- GST evaluation is deterministic completeness review, not legal advice.
- Accounting periods may be locked; export is rejected for locked periods.

## Security and concurrency

- Finance/admin only for mappings, period locks, finance notes, and export generation.
- Workflow, report, submission, mapping, and period rows are locked before export.
- Export files contain no secrets and are served through authenticated API responses.
- CSV values are escaped and formula-prefixed text is neutralized.
- Cross-company mapping links are rejected.

## Implementation slices

1. Finance/GST/export schema and RPCs.
2. GST and CSV domain implementation.
3. Finance repository/routes.
4. Finance web console extension.
5. Golden-file and contract tests.
6. Phase 5 runbook and sample anonymized export.

## Validation

- GST completeness unit tests.
- CSV escaping/formula-neutralization tests.
- Stable ordering/checksum contract.
- Idempotency and period-lock migration checks.
- Live historical export remains blocked without Supabase data/credentials.

## Decision

`GO WITH LIVE ACCOUNTING VALIDATION BLOCKED`
