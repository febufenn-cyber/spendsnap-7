# Phase 5 — Finance Review, GST Readiness, and Accounting Export

## Delivered

- Finance workspace and role-scoped APIs.
- Deterministic GST document-completeness checks with cautious labels.
- Company accounting ledgers, category mappings, vendor normalization, fallback ledger, and period locks.
- Transactional Tally-compatible UTF-8 CSV generation from immutable finance-approved submissions.
- CSV formula-injection neutralization, RFC-style quoting, deterministic row order, SHA-256 checksum, mapping/GST snapshots, and idempotency keys.
- Immutable export batches and rows; reconciliation adds evidence without rewriting content.
- Authenticated finance web console at `/finance.html`.
- Anonymized golden export example.

## Apply

Apply both Phase 5 migrations in order:

1. `202607140012_finance_gst_export.sql`
2. `202607140013_export_batch_parent_fix.sql`

The repair makes the export item foreign key transaction-deferred so rows and their parent batch commit atomically.

## Configure

1. Create company ledgers and map expense categories. Every company receives an `Unmapped Expenses` fallback ledger.
2. Add optional normalized vendor mappings.
3. Confirm voucher type and schema version in `accounting_export_settings`.
4. Create accounting period locks before closing a period.
5. Deploy the web build and expose `finance.html` only through the same authenticated application origin.

## Live validation

- A manager-only user cannot generate an export.
- A finance-approved workflow generates one batch for one idempotency key.
- Retry returns the same batch.
- Locked report periods reject export.
- CSV imports into the selected Tally process without manual field re-entry.
- Formula-like merchant and narration values are neutralized.
- Export checksum equals the downloaded bytes.
- Changing mappings after export does not alter historical rows.
- Reconciliation preserves content and checksum.
- Two-company isolation tests pass.

## GST boundary

`complete` means expected GST document fields appear internally complete. It is not a determination that input tax credit is legally available. `review_required` directs a finance or tax professional to inspect missing, malformed, or inconsistent fields. `not_applicable` means no GST evidence was detected; it does not prove the document should be outside GST review.

## External blockers

No migration was applied, no historical customer report was imported into Tally, no live RLS test ran, and no finance portal was deployed because credentials and customer artifacts were unavailable. These are mandatory before production use.
