import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration=await readFile('supabase/migrations/202607140014_production_admin_security.sql','utf8');
const middleware=await readFile('src/middleware/security.ts','utf8');
const portal=await readFile('web/src/AdminPortal.tsx','utf8');

test('invitation stores only digest and validates authenticated email',()=>{
  assert.match(migration,/token_digest text not null unique/);
  assert.match(migration,/digest\(raw_token,'sha256'\)/);
  assert.match(migration,/Invitation email does not match authenticated user/);
});

test('last active admin cannot be removed or demoted',()=>{
  assert.match(migration,/The last active admin cannot be removed or demoted/);
  assert.match(migration,/for update/);
});

test('support access is explicit scoped and time bounded',()=>{
  assert.match(migration,/purpose text not null/);
  assert.match(migration,/scope text\[\] not null/);
  assert.match(migration,/starts_at<=now\(\) and g.ends_at>now\(\)/);
});

test('security events are append only and audit exports checksummed',()=>{
  assert.match(migration,/Security events are append-only/);
  assert.match(migration,/audit-json-v1/);
  assert.match(migration,/digest\(convert_to\(content::text,'UTF8'\),'sha256'\)/);
});

test('HTTP edge uses allowlist security headers and no-store API responses',()=>{
  assert.match(middleware,/Request origin is not allowed/);
  assert.match(middleware,/X-Content-Type-Options/);
  assert.match(middleware,/X-Frame-Options/);
  assert.match(middleware,/Cache-Control/);
});

test('admin UI explains one-time token handling',()=>{
  assert.match(portal,/database stores only its SHA-256 digest/);
  assert.doesNotMatch(portal,/SERVICE_ROLE/);
});
