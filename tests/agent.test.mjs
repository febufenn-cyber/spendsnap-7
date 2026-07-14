import assert from 'node:assert/strict';
import test from 'node:test';
import { redactAgentContext, validateAgentProposals } from '../dist/domain/agent.js';

test('agent context redacts email payment-like numbers and secrets',()=>{
  const result=redactAgentContext({email:'person@example.com',card:'4111 1111 1111 1111',note:'api_key=topsecret'});
  const text=JSON.stringify(result.value);
  assert.doesNotMatch(text,/person@example\.com/);
  assert.doesNotMatch(text,/4111 1111/);
  assert.doesNotMatch(text,/topsecret/);
  assert.deepEqual(result.warnings,['email_redacted','payment_number_redacted','secret_redacted']);
});

test('safe advisory proposal passes validation',()=>{
  assert.deepEqual(validateAgentProposals([{proposalType:'suggest.business_purpose',title:'Clarify client visit',rationale:'The report names a customer site but has no purpose.',payload:{suggestion:'Client site visit'},evidence:['businessPurpose missing'],confidence:.7,riskLevel:'low'}]),[]);
});

test('approval payment deletion tax eligibility and fraud proposals are rejected',()=>{
  for(const text of ['Approve this report','Pay reimbursement','Delete receipt evidence','Tax credit is eligible','Fraudulent employee']){
    const issues=validateAgentProposals([{proposalType:'unsafe.action',title:text,rationale:'unsafe proposal',payload:{action:text},evidence:[],confidence:.9,riskLevel:'high'}]);
    assert.ok(issues.some((issue)=>issue.endsWith('prohibited_action')),text);
  }
});
