# Spendsnap Autonomous Build Roadmap

> This document is the execution contract for completing Spendsnap from the current Phase 3 checkpoint through commercial launch.

## How many phases remain?

The repository has completed Phase 1 and Phase 2. Phase 3 is currently in progress.

| Phase | Name | Current status |
|---|---|---|
| 0 | Discovery and validation framework | Documented; real customer validation still required |
| 1 | Receipt Truth Engine | Code complete; infrastructure not deployed |
| 2 | Employee Submission and Report Assembly | Code complete; infrastructure not deployed |
| 3 | Deterministic Policy Engine | In progress |
| 4 | Product UI, Approval, and Exception Workflow | Not started |
| 5 | Finance Review, GST Readiness, and Accounting Export | Not started |
| 6 | Production Hardening and Tenant Administration | Not started as a dedicated phase; some foundations already exist |
| 7 | Guardrailed Agentic Automation | Not started |
| 8 | Commercial Launch and Operating System | Not started |

There are **five phases after Phase 3**. Counting the unfinished Phase 3 checkpoint, **six implementation phases remain**.

## Meaning of the command `build`

When the user sends the exact command **`build`**, execute the remaining roadmap autonomously in dependency order:

```text
finish Phase 3
  → verify Phase 3 exit gate
  → build Phase 4
  → verify Phase 4 exit gate
  → build Phase 5
  → verify Phase 5 exit gate
  → build Phase 6
  → verify Phase 6 exit gate
  → build Phase 7
  → verify Phase 7 exit gate
  → build Phase 8
  → final repository verification
```

Do not ask routine implementation questions. Resolve ordinary architectural choices using this document, the existing repository conventions, official documentation, security principles, and the narrowest reversible design.

A command such as `build phase 5` limits execution to that phase and its required prerequisite fixes.

If a true external blocker prevents completion—such as missing credentials, inaccessible infrastructure, branch protection, unavailable paid services, or a destructive production decision—complete every safe repository artifact possible, document the blocker precisely, and do not claim the blocked operation was performed.

## Global execution protocol

Before implementing **every phase**, create or update:

```text
docs/phase-N/IMPLEMENTATION_VERIFICATION.md
```

That verification document must record:

1. current `main` head SHA;
2. prior phase exit-gate status;
3. repository files and migrations inspected;
4. assumptions confirmed or rejected;
5. current official dependency/runtime guidance checked where temporally unstable;
6. migration number reserved for the phase;
7. security and concurrency threats considered;
8. exact implementation slices and intended commit messages;
9. tests and validation commands required;
10. external operations that are available or unavailable;
11. explicit exclusions;
12. stop or pivot conditions.

The implementation may begin only after this preflight has been written and checked against the actual repository state.

## Git and publication protocol

The user has authorized commits to the repository's `main` branch.

For each phase:

1. Fetch the latest `main` head immediately before writing.
2. Never force-push or rewrite published history.
3. Make bounded, intentional commits rather than one unreviewable mega-commit.
4. Re-read affected files after each write.
5. Re-check the remote `main` head before the next sequential write.
6. If another writer changes `main`, rebase the plan conceptually by re-reading the new state; never overwrite their work blindly.
7. Run the strongest available validation before declaring the phase complete.
8. Commit the phase status and runbook as the final phase commit.
9. Confirm that the final commit is visible on `main`.
10. Report commit SHAs, checks executed, failures fixed, and operations not performed.

When changes are committed directly to `main`, there is no separate branch to merge. The final confirmation must say that direct mainline commits made a PR merge unnecessary. If branch protection later requires a pull request, create a phase branch, run checks, merge only after success, and then confirm the resulting `main` SHA.

## Global engineering invariants

These rules apply to every remaining phase:

- The database, not the client, owns financial state transitions.
- Financial totals use exact decimal or database numeric arithmetic, never binary floating point.
- AI output is evidence or suggestion, never an unreviewable accepted fact.
- Every meaningful decision has an actor, timestamp, reason, request ID, and immutable history.
- Tenant boundaries are enforced by RLS plus explicit cross-table integrity checks.
- Submitted, approved, and exported records are immutable snapshots.
- Changes after submission invalidate downstream decisions and require a new version or workflow cycle.
- Public or reusable approval links are forbidden.
- Receipt and invoice text is untrusted input and may contain prompt injection.
- Tax readiness signals are not tax advice or guaranteed input-tax-credit eligibility.
- Duplicate detection creates candidates, not fraud accusations.
- No phase may silently add money movement, card issuing, tax filing, or autonomous approval.
- Unsupported states fail visibly rather than being guessed into completion.
- Every queue consumer and externally retried operation must be idempotent.
- Every new mutation path must be tested for stale-version and double-submit races.
- Raw customer documents, secrets, and identifiable finance records must never enter the public repository.

## Product-interface correction

The current repository is primarily a backend. A product cannot be validated with APIs alone.

The remaining phases therefore add one Cloudflare-compatible TypeScript web application progressively:

- Phase 4: application shell, employee report experience, manager approval experience;
- Phase 5: finance review and export console;
- Phase 6: company administration, members, roles, retention, and operational controls;
- Phase 7: agent-assistance surfaces with explicit confirmation;
- Phase 8: onboarding, billing, plan management, demo workspace, and commercial analytics.

Before choosing exact frontend package versions, verify current official compatibility. Prefer a single maintainable web application over separate employee, manager, and finance codebases.

---

# Phase 3 — Deterministic Policy Engine

## Objective

Evaluate company expense rules deterministically, explain every result, permit scoped exception requests, and make report submission use the exact locked policy state persisted into the final report snapshot.

## Current checkpoint

Phase 3 work is already partially committed. Before continuing, inspect the actual mainline state rather than assuming these files are complete:

- `docs/phase-3/README.md`
- `src/domain/policy.ts`
- Phase 3 policy migrations
- policy repository and route files, if present
- report submission integration
- README and test status

## Required capabilities

### Policy administration

Finance/admin users can create, update, activate, deactivate, and version deterministic rules.

Initial supported rule families:

- amount limit;
- receipt-age limit;
- weekend-reason requirement;
- required business purpose;
- category allowed or blocked;
- project or cost-centre requirement where explicitly configured.

Each rule must contain:

- company scope;
- stable identity;
- immutable version;
- severity: `warning` or `block`;
- machine-readable parameters;
- employee-facing explanation template;
- active dates and enabled status;
- creator and updater history.

### Evaluation

- Preview evaluates draft claims and reports.
- Submission re-evaluates inside the database under locks.
- Every outcome records rule ID, version, input facts, outcome, severity, explanation, and policy-set hash.
- Warnings do not block submission unless company configuration explicitly promotes them.
- Blocks require resolution or a valid exception.
- A blocked evaluation must remain visible after the failed submission attempt.

### Exceptions

- Employees may request an exception with a reason and supporting context.
- Exceptions are scoped to claim version, rule version, and report version.
- Editing the claim, changing the report, or updating the rule invalidates stale exceptions.
- Exception approval belongs to an authorized manager/finance workflow completed in Phase 4.
- Phase 3 may represent pending exceptions and submission blocks, but must not invent approval authority.

### API

Provide authenticated routes for:

- listing active policy rules;
- finance/admin rule creation and versioned updates;
- policy preview for a claim or draft report;
- creating and reading exception requests;
- reading persisted evaluations.

### Tests

- every rule family;
- warning versus block behavior;
- exact amount boundary behavior;
- date/time-zone and weekend behavior;
- inactive and future rules;
- policy hash stability;
- stale exception invalidation;
- preview/submission semantic parity;
- blocked evaluation persistence;
- tenant isolation;
- concurrent policy update versus report submission.

## Phase 3 exit gate

Phase 3 is complete only when:

1. the full policy API is wired;
2. policy rules are versioned and tenant-safe;
3. preview and submit use equivalent rule semantics;
4. submission re-evaluates under locks;
5. blocks prevent report submission;
6. warnings and explanations are visible;
7. stale exceptions cannot bypass new policy or claim versions;
8. policy results are embedded in immutable submission evidence;
9. domain, migration-contract, type, and repository checks pass where runnable;
10. documentation and a Phase 3 runbook are committed;
11. final Phase 3 commit is confirmed on `main`.

Explicitly excluded: manager approval decisions, notification delivery, reimbursement, accounting export, and AI policy interpretation.

---

# Phase 4 — Product UI, Approval, and Exception Workflow

## Objective

Turn the backend into a usable product and route submitted reports through authenticated, auditable manager and finance decisions.

## Required capabilities

### Web application foundation

Create one responsive TypeScript web application with:

- Supabase authentication and session restoration;
- company/workspace selection;
- role-aware navigation;
- accessible loading, empty, failure, and conflict states;
- mobile-friendly employee capture/report screens;
- desktop-oriented manager and finance queues;
- safe API client with request IDs and stale-version handling;
- no secrets embedded in browser code.

### Employee experience

Expose the already-built workflow:

- receipt upload and processing status;
- field-review and correction experience;
- claim creation from verified receipts;
- business purpose, category, project, and cost centre;
- report assembly and exact per-currency totals;
- policy preview with clear warnings and blocks;
- exception request creation;
- submission, changes requested, and withdrawal history.

### Approval model

Add explicit workflow states such as:

```text
submitted
  → manager_review
  → manager_changes_requested | manager_approved
  → finance_review
  → finance_changes_requested | finance_approved
```

The exact database enum names may differ, but transitions must be explicit and legal.

### Approval behavior

- Company-level approver assignment with a deterministic fallback.
- Report-level and line-level decisions.
- Approve, reject, request changes, and comment.
- Exception decisions tied to the exact policy outcome and report submission.
- A manager cannot approve their own report unless a documented company rule explicitly delegates it to another authorized reviewer.
- Any employee edit after changes are requested creates a new submission version and invalidates old approvals.
- Finance cannot silently edit employee evidence; adjustments require an explicit recorded action or return to employee.
- Approver delegation is time-bounded and audited.
- Decision endpoints are authenticated and idempotent.

### Notifications

Implement an outbox pattern for:

- report submitted;
- review assigned;
- changes requested;
- exception awaiting decision;
- manager approved;
- finance approved.

Email delivery may be implemented when credentials exist. Missing provider credentials must not prevent committing the outbox, templates, retry strategy, and local adapter.

### Tests

- legal and illegal workflow transitions;
- self-approval prevention;
- line decision and report decision consistency;
- stale submission invalidating approval;
- duplicate notification idempotency;
- delegation expiry;
- role and tenant isolation;
- UI critical-path component or browser tests where tooling permits;
- mobile and desktop layout smoke checks.

## Phase 4 exit gate

1. A real user can complete the Phase 1–3 employee workflow through the web UI.
2. A submitted report enters a deterministic manager queue.
3. Manager and finance decisions are authenticated and immutable.
4. Exception requests can be approved or denied by the correct role.
5. Changes create a new submission version and invalidate stale decisions.
6. Self-approval and cross-company access are blocked.
7. Notification outbox operations are idempotent.
8. Core UI is keyboard accessible and usable on mobile for employees.
9. Tests and documentation pass at the strongest available level.
10. Final Phase 4 commit is confirmed on `main`.

Explicitly excluded: reimbursement payment and accounting export.

---

# Phase 5 — Finance Review, GST Readiness, and Accounting Export

## Objective

Convert finance-approved reports into reviewable accounting evidence and one dependable export path, initially optimized for Indian SMB workflows.

## Required capabilities

### Finance console

- Queue of manager-approved reports.
- Filters by employee, period, project, category, cost centre, currency, warning, and GST completeness.
- Receipt image and accepted fact comparison.
- Policy and approval timeline.
- Explicit finance comments and return-to-employee action.
- Final finance approval.

### GST readiness

Provide structured review signals for:

- GSTIN present and format plausibility;
- invoice number present;
- invoice date present;
- taxable value present;
- CGST/SGST versus IGST consistency;
- arithmetic consistency;
- vendor normalization candidate;
- missing or questionable invoice fields.

Product language must say `GST readiness`, `GST completeness`, or `requires tax review`. It must not claim guaranteed compliance or eligibility for input-tax credit.

### Accounting dimensions

- Company chart/ledger mappings.
- Category-to-ledger mapping.
- Vendor mapping.
- Project and cost-centre export mapping.
- Voucher type configuration.
- Immutable mapping snapshot used for each export.

### First export

Implement one dependable configurable export, preferably Tally-compatible CSV unless Phase 0 evidence or actual repository decisions select another target.

The export system requires:

- export batch and immutable export-item tables;
- deterministic ordering;
- exact values and per-currency handling;
- export version and schema version;
- idempotency key;
- checksum;
- downloadable generated file;
- failed-row diagnostics;
- re-export as a new batch rather than rewriting history;
- reconciliation status and finance notes;
- accounting-period lock behavior.

### Tests

- GST completeness rules;
- export escaping and encoding;
- exact totals;
- stable ordering and checksum;
- idempotent repeated export request;
- mapping changes not rewriting prior exports;
- period lock;
- tenant isolation;
- failure and retry behavior;
- golden-file tests for the first export format.

## Phase 5 exit gate

1. Finance can review and approve through the web console.
2. GST readiness signals are explainable and carefully worded.
3. One real historical report can produce the selected accounting file.
4. Golden-file tests prove deterministic output.
5. Export retries cannot duplicate or rewrite a completed batch.
6. Accounting mappings and export snapshots are immutable historically.
7. Period locks are enforced.
8. No payment or tax-filing claim is introduced.
9. Runbook and sample anonymized export are committed.
10. Final Phase 5 commit is confirmed on `main`.

---

# Phase 6 — Production Hardening and Tenant Administration

## Objective

Make the system safe and operable for multiple real companies. This phase completes foundations introduced earlier; it does not assume existing RLS is sufficient.

## Required capabilities

### Company administration UI

- company onboarding;
- member invitations;
- role assignment;
- manager assignment;
- finance/admin separation;
- membership deactivation and offboarding;
- project, cost-centre, category, policy, and export settings;
- least-privilege defaults.

### Security hardening

- complete RLS policy matrix tests for every table and role;
- cross-company foreign-key/integrity tests;
- service-role call review;
- rate limiting and abuse controls;
- safe CORS and security headers;
- CSRF analysis for chosen auth flow;
- signed URL expiry and replay review;
- secret rotation instructions;
- dependency and supply-chain checks;
- prompt-injection regression suite;
- no sensitive values in logs;
- security-event audit types.

### Reliability

- queue idempotency and dead-letter handling;
- bounded retries with jitter;
- scheduled recovery for stuck receipts, notifications, and exports;
- database migration dry-run instructions;
- backup and restore procedure;
- health, readiness, and dependency probes;
- structured logs, metrics, and alert thresholds;
- request tracing across API, queue, model, notification, and export operations;
- operational dashboard definitions;
- SLOs and error budgets appropriate for an early SaaS.

### Data governance

- retention settings;
- legal hold capability where appropriate;
- controlled deletion workflow;
- user offboarding behavior;
- receipt/export retention distinction;
- audit export;
- data processing and model-training controls;
- explicit handling of customer deletion requests;
- documented region/data-residency assumptions.

### Tests

- complete role/tenant matrix;
- offboarding and revoked access;
- deletion and retention behavior;
- queue replay;
- double delivery;
- partial third-party outage;
- backup/restore rehearsal documentation;
- migration ordering and clean database application;
- load and rate-limit smoke tests.

## Phase 6 exit gate

1. A second company can be onboarded without code changes.
2. Automated tests prove tenant isolation across the full schema.
3. Offboarded users lose access without destroying historical attribution.
4. Recovery exists for every asynchronous workflow.
5. Retention and deletion behavior is explicit and tested.
6. Logs and metrics reveal failures without leaking sensitive data.
7. All migrations apply cleanly to a fresh non-production project.
8. A deployment and rollback runbook exists.
9. Infrastructure that cannot be provisioned is clearly listed rather than implied.
10. Final Phase 6 commit is confirmed on `main`.

---

# Phase 7 — Guardrailed Agentic Automation

## Objective

Reduce user effort with AI assistance while keeping deterministic systems and humans responsible for financial decisions.

## Permitted agent responsibilities

- group unassigned claims into suggested reports;
- suggest categories, project, and cost centre;
- draft a business-purpose description from employee-provided context;
- ask targeted clarification questions;
- summarize policy warnings and exceptions;
- prepare a concise manager review summary;
- explain unusual patterns without accusing fraud;
- suggest vendor and ledger mappings;
- prioritize finance review queues;
- remind users about incomplete work.

## Forbidden agent responsibilities

The agent may not independently:

- change receipt totals or accepted financial facts;
- approve or deny a report or exception;
- declare tax-credit eligibility;
- mark reimbursement paid;
- finalize or transmit an accounting export without explicit authorized confirmation;
- delete evidence;
- modify company policy;
- accuse an employee of fraud;
- bypass role, version, or tenant checks.

## Architecture

- Tool-based agent with a strict allowlist.
- Read tools separated from proposal tools.
- Mutating proposals require a human confirmation token or explicit UI action.
- Server revalidates authorization and versions after confirmation.
- Prompt and model versions are stored.
- Receipt, policy, email, and comment text is treated as untrusted data.
- Cost, token, latency, and retry budgets are enforced.
- Deterministic fallback remains available when the model fails.
- Agent activity has a complete audit trail.

## Evaluation

Create a versioned evaluation corpus covering:

- correct category and dimension suggestions;
- missing-context questions;
- policy explanation fidelity;
- manager summary factuality;
- prompt injection;
- unsupported tax claims;
- attempted tool overreach;
- cross-tenant information requests;
- hallucinated totals, people, vendors, or approvals;
- cost and latency regression.

## Phase 7 exit gate

1. Every agent mutation is a proposal requiring explicit authorized confirmation.
2. Tool allowlists and server authorization prevent privilege escalation.
3. Prompt injection tests pass.
4. Agent output cites the internal evidence it used.
5. Deterministic workflow remains functional when the model is unavailable.
6. Evaluation thresholds are defined and met for enabled features.
7. Cost and latency budgets are observable.
8. No autonomous financial approval, payment, tax decision, or evidence deletion exists.
9. Agent runbook and model-change procedure are committed.
10. Final Phase 7 commit is confirmed on `main`.

---

# Phase 8 — Commercial Launch and Operating System

## Objective

Turn the product into a sellable, supportable SaaS without weakening the financial trust model.

## Required capabilities

### Customer onboarding

- guided company setup;
- invitation and role setup;
- policy setup wizard;
- categories/projects/cost-centre import;
- accounting mapping setup;
- sample/demo workspace clearly separated from real data;
- first receipt-to-report walkthrough;
- onboarding progress and recovery.

### Billing and usage

Before selecting a provider or SDK version, verify current official documentation.

Implement:

- company subscription state;
- plans and entitlements;
- trial behavior;
- usage metering based on the validated pricing unit;
- invoice/customer references;
- webhook signature verification;
- idempotent webhook handling;
- grace period and read-only behavior;
- cancellation and data-retention behavior;
- billing audit events;
- no deletion or concealment of financial history because a subscription lapses.

### Commercial operations

- privacy notice and terms placeholders reviewed as non-legal templates;
- security and data-processing overview;
- support contact and in-product issue reporting;
- customer-visible status page link/configuration;
- product analytics with sensitive-field exclusion;
- activation, processing-time, approval-time, correction-rate, and export-success metrics;
- feedback capture;
- feature flags;
- release checklist;
- incident-response and customer-communication templates.

### Product polish

- coherent design system;
- responsive layouts;
- accessibility review;
- helpful empty/error states;
- demo data;
- CSV imports where needed;
- performance budgets;
- browser compatibility check;
- production configuration validation.

## Phase 8 exit gate

1. A new company can sign up or be provisioned, configure the workspace, and complete the core workflow.
2. Plan entitlements are enforced server-side.
3. Billing webhooks are verified and idempotent.
4. Cancellation never destroys required financial history.
5. Sensitive fields are excluded from analytics.
6. Core product metrics are observable.
7. Support, incident, deployment, rollback, and launch checklists exist.
8. A release candidate passes the full end-to-end workflow in a non-production environment.
9. Any unavailable live deployment, DNS, billing, email, or vendor operation is disclosed exactly.
10. Final Phase 8 and roadmap-completion commits are confirmed on `main`.

---

# Mandatory verification matrix before every phase

Use this matrix in each `IMPLEMENTATION_VERIFICATION.md`:

| Area | Required verification |
|---|---|
| Repository | current main SHA, prior commits, relevant files, migration ordering |
| Product | user outcome, roles, state transitions, exclusions |
| Data | entities, ownership, immutability, retention, migration safety |
| Security | auth, RLS, service role, cross-tenant links, replay, injection |
| Concurrency | versions, locks, idempotency, duplicate delivery, stale decisions |
| Money | decimal handling, currency behavior, snapshot and reconciliation rules |
| AI | allowed actions, forbidden actions, evidence, evaluation, fallback |
| UI | role flows, mobile/desktop needs, errors, accessibility, conflict handling |
| Integrations | official docs, credentials, retries, signatures, outage behavior |
| Tests | domain, API, migration contract, integration, UI, golden files, E2E |
| Operations | logs, metrics, runbook, deployment, rollback, external blockers |
| Git | planned commits, direct-main/PR path, final main verification |

# Standard phase commit sequence

Prefer the following sequence, combining slices only when the diff is genuinely small:

1. `Verify Phase N implementation boundary`
2. `Define Phase N architecture and threat model`
3. `Add Phase N schema and integrity controls`
4. `Implement Phase N domain and persistence`
5. `Expose Phase N authenticated API`
6. `Add or extend Phase N web experience`
7. `Harden Phase N concurrency and idempotency`
8. `Add Phase N regression and integration checks`
9. `Document Phase N operations and update status`

Each commit must be independently understandable and based on the latest mainline parent.

# Final completion report after `build`

The final response must include:

- phases attempted and completed;
- exact mainline commit SHAs grouped by phase;
- tests executed and their results;
- CI state if visible;
- migrations added;
- security/concurrency blind spots found and fixed;
- infrastructure or vendor operations actually performed;
- operations not performed;
- final confirmed `main` SHA;
- an honest production-readiness assessment.

Never use the words `deployed`, `live`, `production-ready`, `merged`, or `tested` unless the corresponding operation was actually verified.
