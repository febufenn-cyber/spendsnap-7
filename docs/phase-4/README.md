# Phase 4 — Product UI, Approval, and Exception Workflow

## Delivered

- Responsive React/Vite application in `web/`.
- Supabase OTP authentication, session restoration, workspace selection, and role-aware navigation.
- Employee receipt upload, claim creation, report assembly, policy preview, and report submission.
- Authenticated manager/finance review queue and immutable decisions.
- Automatic workflow creation from immutable submission IDs.
- Deterministic approver fallback and time-bounded delegation.
- Self-approval prevention.
- Change-request revision workflow that preserves prior submissions and approvals.
- Append-only approval decisions with company-scoped idempotency keys.
- Notification outbox with unique event keys and skip-locked leasing.
- Employee-facing status, error, conflict, empty, mobile, and keyboard-focus states.

## Provisioning

1. Apply migration `202607140011_approval_exception_outbox.sql` after Phase 3 migrations.
2. Configure at least one manager and finance/admin member in each company.
3. Optionally create `company_approval_settings`; otherwise deterministic role fallback is used.
4. Configure `web/.env.local` from `web/.env.example`.
5. Install and build the web application:

```bash
cd web
npm install
npm run typecheck
npm run build
```

6. Deploy the static `web/dist` output to a static host and set the Supabase redirect URL.
7. Configure an outbox consumer. Until an email provider is selected, in-app outbox records remain durable and inspectable.

## Live validation matrix

- Employee submits a policy-passing report and receives manager assignment.
- Employee cannot see another company's workflow.
- Employee cannot approve their own report.
- Manager approval creates a finance assignment exactly once.
- Repeated decision with the same idempotency key returns the existing decision.
- Request changes requires a reason and allows the employee to create a revision.
- New submission creates a new workflow; old decisions remain tied to the old submission.
- Expired delegation is ignored.
- Outbox retry does not duplicate the event.
- Keyboard-only user can sign in, select a workspace, upload a receipt, assemble a report, and review a queue.

## Known external blockers

This repository build did not install web dependencies, run a browser, apply Supabase migrations, configure auth redirect URLs, provision an email provider, or deploy static assets because credentials and external network access were unavailable. Repository code and contract tests are committed; live exit-gate items require an environment.
