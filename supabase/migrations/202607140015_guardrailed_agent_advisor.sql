-- Spendsnap Phase 7: advisory-only agent runs, proposals, confirmation, and feedback.
begin;

create type public.agent_task as enum (
  'suggest_category','suggest_business_purpose','missing_context','summarize_exceptions',
  'group_claims','draft_reviewer_reminder','summarize_finance_review'
);
create type public.agent_run_status as enum ('running','succeeded','failed');
create type public.agent_proposal_status as enum ('proposed','accepted','rejected','expired');

create table public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  task public.agent_task not null,
  entity_type text not null check(entity_type in ('receipt','claim','report','workflow','company')),
  entity_id uuid,
  status public.agent_run_status not null,
  provider text not null,
  model text not null,
  prompt_version text not null,
  context_hash text not null check(context_hash ~ '^[a-f0-9]{64}$'),
  context_snapshot jsonb not null,
  input_warnings jsonb not null default '[]'::jsonb,
  raw_response jsonb,
  error_code text,
  error_message text,
  request_id text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint agent_run_completion check(
    (status='running' and completed_at is null)
    or (status='succeeded' and completed_at is not null and error_code is null)
    or (status='failed' and completed_at is not null and error_code is not null)
  )
);
create index agent_runs_company_created_idx on public.agent_runs(company_id,created_at desc);
create index agent_runs_requester_created_idx on public.agent_runs(requested_by,created_at desc);

create table public.agent_proposals (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.agent_runs(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  proposal_type text not null check(proposal_type ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  title text not null check(char_length(trim(title)) between 1 and 200),
  rationale text not null check(char_length(trim(rationale)) between 3 and 2000),
  proposed_payload jsonb not null,
  evidence jsonb not null default '[]'::jsonb,
  confidence numeric(5,4) not null check(confidence between 0 and 1),
  risk_level text not null check(risk_level in ('low','medium','high')),
  requires_confirmation boolean not null default true,
  status public.agent_proposal_status not null default 'proposed',
  expires_at timestamptz not null default now()+interval '30 days',
  created_at timestamptz not null default now()
);
create index agent_proposals_run_idx on public.agent_proposals(run_id,created_at);
create index agent_proposals_company_status_idx on public.agent_proposals(company_id,status,created_at desc);

create table public.agent_confirmations (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null unique references public.agent_proposals(id) on delete restrict,
  run_id uuid not null references public.agent_runs(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check(decision in ('accept','reject')),
  note text check(note is null or char_length(note)<=2000),
  request_id text,
  created_at timestamptz not null default now()
);

create table public.agent_feedback (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.agent_runs(id) on delete restrict,
  proposal_id uuid references public.agent_proposals(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  rating integer not null check(rating between 1 and 5),
  reason_code text,
  comment text check(comment is null or char_length(comment)<=2000),
  created_at timestamptz not null default now()
);

alter table public.audit_events add column agent_run_id uuid references public.agent_runs(id) on delete restrict;

create or replace function public.validate_agent_scope()
returns trigger language plpgsql security invoker set search_path=public as $$
declare run_company uuid; run_status public.agent_run_status;
begin
  if tg_table_name='agent_runs' then return new; end if;
  select company_id,status into run_company,run_status from public.agent_runs where id=new.run_id;
  if run_company is distinct from new.company_id then raise exception 'Agent evidence company mismatch' using errcode='check_violation'; end if;
  if tg_table_name='agent_proposals' and run_status<>'succeeded' then raise exception 'Proposals require a successful run' using errcode='check_violation'; end if;
  return new;
end;
$$;
create trigger agent_proposals_validate before insert on public.agent_proposals for each row execute function public.validate_agent_scope();
create trigger agent_confirmations_validate before insert on public.agent_confirmations for each row execute function public.validate_agent_scope();
create trigger agent_feedback_validate before insert on public.agent_feedback for each row execute function public.validate_agent_scope();

create or replace function public.protect_agent_evidence()
returns trigger language plpgsql security invoker as $$ begin raise exception 'Agent evidence is append-only' using errcode='check_violation'; end; $$;
create trigger agent_runs_no_delete before delete on public.agent_runs for each row execute function public.protect_agent_evidence();
create trigger agent_proposals_no_update_delete before update or delete on public.agent_proposals for each row execute function public.protect_agent_evidence();
create trigger agent_confirmations_append_only before update or delete on public.agent_confirmations for each row execute function public.protect_agent_evidence();
create trigger agent_feedback_append_only before update or delete on public.agent_feedback for each row execute function public.protect_agent_evidence();

create or replace function public.record_agent_run(
  p_company_id uuid,p_task public.agent_task,p_entity_type text,p_entity_id uuid,
  p_provider text,p_model text,p_prompt_version text,p_context_hash text,p_context_snapshot jsonb,
  p_input_warnings jsonb,p_raw_response jsonb,p_proposals jsonb,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); run_id uuid; proposal jsonb; count_proposals integer:=0;
begin
  if actor is null or not public.is_company_member(p_company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  if jsonb_typeof(p_proposals)<>'array' or jsonb_array_length(p_proposals)>10 then raise exception 'Proposals must be an array of at most 10 items' using errcode='check_violation'; end if;
  insert into public.agent_runs(company_id,requested_by,task,entity_type,entity_id,status,provider,model,prompt_version,context_hash,context_snapshot,input_warnings,raw_response,request_id,completed_at)
  values(p_company_id,actor,p_task,p_entity_type,p_entity_id,'succeeded',p_provider,p_model,p_prompt_version,p_context_hash,p_context_snapshot,coalesce(p_input_warnings,'[]'::jsonb),p_raw_response,p_request_id,now()) returning id into run_id;
  for proposal in select value from jsonb_array_elements(p_proposals) loop
    insert into public.agent_proposals(run_id,company_id,proposal_type,title,rationale,proposed_payload,evidence,confidence,risk_level,requires_confirmation)
    values(run_id,p_company_id,proposal->>'proposalType',proposal->>'title',proposal->>'rationale',coalesce(proposal->'payload','{}'::jsonb),coalesce(proposal->'evidence','[]'::jsonb),greatest(0,least(1,(proposal->>'confidence')::numeric)),coalesce(proposal->>'riskLevel','medium'),true);
    count_proposals:=count_proposals+1;
  end loop;
  insert into public.audit_events(company_id,actor_user_id,agent_run_id,event_type,request_id,payload)
  values(p_company_id,actor,run_id,'agent.run_completed',p_request_id,jsonb_build_object('task',p_task,'proposalCount',count_proposals,'promptVersion',p_prompt_version));
  return jsonb_build_object('runId',run_id,'proposalCount',count_proposals,'status','succeeded');
end;
$$;

create or replace function public.record_failed_agent_run(
  p_company_id uuid,p_task public.agent_task,p_entity_type text,p_entity_id uuid,p_provider text,p_model text,p_prompt_version text,p_context_hash text,p_context_snapshot jsonb,p_input_warnings jsonb,p_error_code text,p_error_message text,p_request_id text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); run_id uuid;
begin
  if actor is null or not public.is_company_member(p_company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  insert into public.agent_runs(company_id,requested_by,task,entity_type,entity_id,status,provider,model,prompt_version,context_hash,context_snapshot,input_warnings,error_code,error_message,request_id,completed_at)
  values(p_company_id,actor,p_task,p_entity_type,p_entity_id,'failed',p_provider,p_model,p_prompt_version,p_context_hash,p_context_snapshot,coalesce(p_input_warnings,'[]'::jsonb),p_error_code,left(p_error_message,2000),p_request_id,now()) returning id into run_id;
  return run_id;
end;
$$;

create or replace function public.confirm_agent_proposal(p_proposal_id uuid,p_decision text,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); proposal public.agent_proposals%rowtype; confirmation_id uuid;
begin
  select * into proposal from public.agent_proposals where id=p_proposal_id for update;
  if not found then raise exception 'Agent proposal not found' using errcode='no_data_found'; end if;
  if not public.is_company_member(proposal.company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  if proposal.expires_at<=now() then raise exception 'Agent proposal has expired' using errcode='check_violation'; end if;
  if p_decision not in ('accept','reject') then raise exception 'Decision must be accept or reject' using errcode='check_violation'; end if;
  insert into public.agent_confirmations(proposal_id,run_id,company_id,actor_user_id,decision,note,request_id)
  values(proposal.id,proposal.run_id,proposal.company_id,actor,p_decision,nullif(trim(p_note),''),p_request_id) returning id into confirmation_id;
  update public.agent_proposals set status=case when p_decision='accept' then 'accepted' else 'rejected' end where id=proposal.id;
  insert into public.audit_events(company_id,actor_user_id,agent_run_id,event_type,request_id,payload)
  values(proposal.company_id,actor,proposal.run_id,'agent.proposal_confirmed',p_request_id,jsonb_build_object('proposalId',proposal.id,'decision',p_decision,'confirmationId',confirmation_id));
  return jsonb_build_object('proposalId',proposal.id,'confirmationId',confirmation_id,'decision',p_decision,'applied',false);
end;
$$;

alter table public.agent_runs enable row level security;
alter table public.agent_proposals enable row level security;
alter table public.agent_confirmations enable row level security;
alter table public.agent_feedback enable row level security;
create policy agent_runs_member_select on public.agent_runs for select to authenticated using(public.is_company_member(company_id));
create policy agent_proposals_member_select on public.agent_proposals for select to authenticated using(public.is_company_member(company_id));
create policy agent_confirmations_member_select on public.agent_confirmations for select to authenticated using(public.is_company_member(company_id));
create policy agent_feedback_member_select on public.agent_feedback for select to authenticated using(public.is_company_member(company_id));
grant select on public.agent_runs,public.agent_proposals,public.agent_confirmations,public.agent_feedback to authenticated;
grant all on public.agent_runs,public.agent_proposals,public.agent_confirmations,public.agent_feedback to service_role;
grant execute on function public.record_agent_run(uuid,public.agent_task,text,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb,text),public.record_failed_agent_run(uuid,public.agent_task,text,uuid,text,text,text,text,jsonb,jsonb,text,text,text),public.confirm_agent_proposal(uuid,text,text,text) to authenticated;
revoke all on function public.record_agent_run(uuid,public.agent_task,text,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb,text),public.record_failed_agent_run(uuid,public.agent_task,text,uuid,text,text,text,text,jsonb,jsonb,text,text,text),public.confirm_agent_proposal(uuid,text,text,text) from public;

commit;
