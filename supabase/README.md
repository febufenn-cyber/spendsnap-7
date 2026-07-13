# Supabase setup

## Apply the schema

1. Create or select a non-production Supabase project.
2. Link the local repository with the Supabase CLI.
3. Review the ordered files in `migrations/`.
4. Apply migrations with `supabase db push`.
5. Create the first company through the `create_company_with_admin` RPC while authenticated.
6. Add Worker secrets with Wrangler; never place the service-role key in client code.

## Required Worker secrets

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`

## Security verification before production

Test with two real Supabase Auth users and two companies:

- a member can read receipts in their own company;
- the same member receives no rows for another company;
- changing a receipt UUID does not bypass RLS;
- an employee cannot update receipt status directly;
- an employee cannot read duplicate candidates or audit events;
- a finance/admin member can read review queues for their company only;
- storage reads are restricted by the first company UUID path segment;
- malformed storage paths do not cause policy exceptions;
- cross-company foreign keys are rejected by integrity triggers;
- service-role secrets are absent from browser bundles and logs.

## Storage path contract

Receipt objects use:

```text
<company_uuid>/<receipt_uuid>/<sanitized_filename>
```

The database enforces the same prefix on the receipt record. The Worker creates the path and signs the upload; the client must not invent it.

## Operational notes

- The service-role key bypasses RLS. Every service-role query must use a receipt/company identifier already authorized through the user-scoped request or an internal queue job.
- RLS protects table access; database triggers separately protect lifecycle and cross-table tenant integrity.
- Raw extraction responses can contain sensitive information and should not be exposed in ordinary employee API responses.
- Apply future migrations through reviewed files rather than dashboard-only changes so the security model remains reproducible.
