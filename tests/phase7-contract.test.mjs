import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration=await readFile('supabase/migrations/202607140015_guardrailed_agent_advisor.sql','utf8');
const repair=await readFile('supabase/migrations/202607140016_agent_proposal_status_fix.sql','utf8');
const advisor=await readFile('src/agent/advisor.ts','utf8');
const portal=await readFile('web/src/AgentPortal.tsx','utf8');

test('agent evidence records model prompt context hash and proposals',()=>{
  assert.match(migration,/context_hash text not null/);
  assert.match(migration,/prompt_version text not null/);
  assert.match(migration,/raw_response jsonb/);
  assert.match(migration,/agent_confirmations/);
});

test('advisor uses forced typed tool output and treats context as untrusted',()=>{
  assert.match(advisor,/tool_choice:\{type:'tool',name:'submit_advice'\}/);
  assert.match(advisor,/CONTEXT_UNTRUSTED/);
  assert.match(advisor,/Never approve, reject, pay, reimburse/);
});

test('proposal content remains immutable while confirmation status is controlled',()=>{
  assert.match(repair,/Agent proposal content is immutable/);
  assert.match(repair,/old\.status='proposed'/);
  assert.match(migration,/applied',false/);
});

test('UI clearly labels advisory and non-mutating behavior',()=>{
  assert.match(portal,/Advisory only/);
  assert.match(portal,/does not silently mutate/);
  assert.match(portal,/Accept as advice/);
});
