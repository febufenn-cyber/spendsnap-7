# ADR-0007: Build receipt truth before workflow automation

- Status: Accepted
- Date: 2026-07-13

## Context

The original blueprint combines receipt capture, AI extraction, report assembly, approvals, and export. Building the entire workflow at once would hide extraction errors behind a polished product and make financial corrections difficult to audit.

## Decision

Phase 1 will implement the receipt truth engine first. Reports, approvals, policy automation, reimbursements, and accounting export remain downstream consumers.

The truth engine owns:

- original evidence;
- server-computed integrity hashes;
- immutable extraction runs;
- field-level predictions;
- deterministic validation;
- review state;
- corrections and audit history;
- duplicate candidates.

## Consequences

### Positive

- financial uncertainty is visible;
- model upgrades can be compared without overwriting history;
- later workflows consume accepted facts rather than raw AI output;
- failures can be retried safely;
- customer trust and auditability become architectural properties.

### Negative

- the first release looks less feature-complete;
- a review UI is required before full automation feels magical;
- more database entities and lifecycle rules exist earlier.
