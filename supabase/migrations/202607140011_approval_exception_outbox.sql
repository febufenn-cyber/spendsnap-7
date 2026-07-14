-- Spendsnap Phase 4: authenticated approval, exception decisions, revisions, and outbox.
begin;

create type public.approval_stage as enum ('manager', 'finance');
create type public.approval_workflow_status as enum (
  'manager_review', 'manager_changes_requested', 'manager_approved',
  'finance_review', 'finance_changes_requested', 'finance_approved',
  'rejected', 'superseded'
);
create type public.approval_assignment_status as enum ('pending', 'completed', 'reassigned', 'cancelled');
create type public.approval_action as enum ('approve', 'request_changes', 'reject', 'comment');
create type public.outbox_status as enum ('pending', 'processing', 'delivered', 'failed', 'cancelled');

create table public.company_approval_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  manager_approver_id uuid references auth.users(id) on delete restrict,
  finance_approver_id uuid references auth.users(id) on delete restrict,
  manager_due_hours integer not null default 72 check (manager_due_hours between 1 and 720),
  finance_due_hours integer not null default 72 check (finance_due_hours between 1 and 720),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.approver_delegations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  delegator_id uuid not null references auth.users(id) on delete restrict,
  delegate_id uuid not null references auth.users(id) on delete restrict,
  stage public.approval_stage not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint delegation_range_check check (ends_at > starts_at),
  constraint delegation_distinct_users check (delegator_id <> delegate_id)
);
create index approver_delegations_active_idx
  on public.approver_delegations (company_id, delegator_id, stage, starts_at, ends_at)
  where revoked_at is null;

create table public.approval_workflows (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  report_id uuid not null references public.expense_reports(id) on delete restrict,
  submission_id uuid not null unique references public.expense_report_submissions(id) on delete restrict,
  submission_number integer not null check (submission_number > 0),
  employee_id uuid not null references auth.users(id) on delete restrict,
  status public.approval_workflow_status not null default 'manager_review',
  version integer not null default 1 check (version > 0),
  current_stage public.approval_stage,
  manager_approved_at timestamptz,
  finance_approved_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index approval_workflows_company_status_idx
  on public.approval_workflows (company_id, status, created_at desc);
create index approval_workflows_report_idx
  on public.approval_workflows (report_id, created_at desc);

create table public.approval_assignments (
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references public.approval_workflows(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  stage public.approval_stage not null,
  assigned_to uuid not null references auth.users(id) on delete restrict,
  assigned_by uuid references auth.users(id) on delete restrict,
  delegated_from uuid references auth.users(id) on delete restrict,
  status public.approval_assignment_status not null default 'pending',
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (workflow_id, stage, assigned_to, status)
);
create unique index approval_assignments_one_pending_stage_idx
  on public.approval_assignments (workflow_id, stage) where status = 'pending';
create index approval_assignments_user_pending_idx
  on public.approval_assignments (assigned_to, stage, created_at) where status = 'pending';

create table public.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references public.approval_workflows(id) on delete restrict,
  assignment_id uuid references public.approval_assignments(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  submission_id uuid not null references public.expense_report_submissions(id) on delete restrict,
  stage public.approval_stage not null,
  action public.approval_action not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  claim_id uuid references public.expense_claims(id) on delete restrict,
  note text check (note is null or char_length(note) <= 4000),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 160),
  workflow_version integer not null check (workflow_version > 0),
  request_id text,
  created_at timestamptz not null default now(),
  unique (company_id, idempotency_key)
);
create index approval_decisions_workflow_created_idx
  on public.approval_decisions (workflow_id, created_at, id);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  event_key text not null,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{2,119}$'),
  recipient_user_id uuid references auth.users(id) on delete restrict,
  recipient_address text,
  channel text not null default 'email' check (channel in ('email', 'in_app', 'webhook')),
  payload jsonb not null default '{}'::jsonb,
  status public.outbox_status not null default 'pending',
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  leased_until timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, event_key, channel)
);
create index notification_outbox_pending_idx
  on public.notification_outbox (available_at, created_at)
  where status in ('pending', 'failed');

alter table public.audit_events
  add column approval_workflow_id uuid references public.approval_workflows(id) on delete restrict,
  add column approval_decision_id uuid references public.approval_decisions(id) on delete restrict;

create trigger company_approval_settings_updated before update on public.company_approval_settings
for each row execute function public.set_updated_at();
create trigger approval_workflows_updated before update on public.approval_workflows
for each row execute function public.set_updated_at();
create trigger notification_outbox_updated before update on public.notification_outbox
for each row execute function public.set_updated_at();

create or replace function public.validate_approval_setting_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.manager_approver_id is not null and not exists (
    select 1 from public.company_memberships m where m.company_id = new.company_id
      and m.user_id = new.manager_approver_id and m.active
      and m.role in ('manager', 'finance', 'admin')
  ) then raise exception 'Manager approver must be an active authorized company member' using errcode='check_violation'; end if;
  if new.finance_approver_id is not null and not exists (
    select 1 from public.company_memberships m where m.company_id = new.company_id
      and m.user_id = new.finance_approver_id and m.active
      and m.role in ('finance', 'admin')
  ) then raise exception 'Finance approver must be an active finance/admin member' using errcode='check_violation'; end if;
  return new;
end;
$$;
create trigger company_approval_settings_validate before insert or update on public.company_approval_settings
for each row execute function public.validate_approval_setting_scope();

create or replace function public.validate_delegation_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if not exists (select 1 from public.company_memberships m where m.company_id=new.company_id and m.user_id=new.delegator_id and m.active) or
     not exists (select 1 from public.company_memberships m where m.company_id=new.company_id and m.user_id=new.delegate_id and m.active) then
    raise exception 'Delegation users must be active company members' using errcode='check_violation';
  end if;
  return new;
end;
$$;
create trigger approver_delegations_validate before insert or update on public.approver_delegations
for each row execute function public.validate_delegation_scope();

create or replace function public.validate_approval_scope()
returns trigger language plpgsql security invoker set search_path = public as $$
declare report_company uuid; submission_report uuid; workflow_company uuid; workflow_submission uuid;
begin
  if tg_table_name = 'approval_workflows' then
    select company_id into report_company from public.expense_reports where id=new.report_id;
    select report_id into submission_report from public.expense_report_submissions where id=new.submission_id;
    if report_company is distinct from new.company_id or submission_report is distinct from new.report_id then
      raise exception 'Approval workflow scope mismatch' using errcode='check_violation';
    end if;
  else
    select company_id, submission_id into workflow_company, workflow_submission
      from public.approval_workflows where id=new.workflow_id;
    if workflow_company is distinct from new.company_id then
      raise exception 'Approval child scope mismatch' using errcode='check_violation';
    end if;
    if tg_table_name = 'approval_decisions' and workflow_submission is distinct from new.submission_id then
      raise exception 'Decision submission mismatch' using errcode='check_violation';
    end if;
  end if;
  return new;
end;
$$;
create trigger approval_workflows_validate before insert or update on public.approval_workflows
for each row execute function public.validate_approval_scope();
create trigger approval_assignments_validate before insert or update on public.approval_assignments
for each row execute function public.validate_approval_scope();
create trigger approval_decisions_validate before insert on public.approval_decisions
for each row execute function public.validate_approval_scope();

create or replace function public.protect_approval_decision()
returns trigger language plpgsql security invoker as $$
begin raise exception 'Approval decisions are append-only' using errcode='check_violation'; end;
$$;
create trigger approval_decisions_append_only before update or delete on public.approval_decisions
for each row execute function public.protect_approval_decision();

create or replace function public.resolve_active_delegate(
  p_company_id uuid, p_approver uuid, p_stage public.approval_stage, p_at timestamptz
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('assignedTo', coalesce(d.delegate_id, p_approver), 'delegatedFrom', d.delegator_id)
  from (select 1) seed left join lateral (
    select delegation.delegate_id, delegation.delegator_id
    from public.approver_delegations delegation
    where delegation.company_id=p_company_id and delegation.delegator_id=p_approver
      and delegation.stage=p_stage and delegation.revoked_at is null
      and delegation.starts_at <= p_at and delegation.ends_at > p_at
    order by delegation.created_at desc limit 1
  ) d on true;
$$;

create or replace function public.choose_approver(
  p_company_id uuid, p_employee_id uuid, p_stage public.approval_stage
) returns uuid language plpgsql stable security definer set search_path=public as $$
declare chosen uuid; settings public.company_approval_settings%rowtype;
begin
  select * into settings from public.company_approval_settings where company_id=p_company_id;
  chosen := case when p_stage='manager' then settings.manager_approver_id else settings.finance_approver_id end;
  if chosen = p_employee_id then chosen := null; end if;
  if chosen is null then
    select m.user_id into chosen from public.company_memberships m
    where m.company_id=p_company_id and m.active and m.user_id<>p_employee_id
      and ((p_stage='manager' and m.role in ('manager','finance','admin'))
        or (p_stage='finance' and m.role in ('finance','admin')))
    order by case m.role when 'manager' then 1 when 'finance' then 2 else 3 end, m.created_at
    limit 1;
  end if;
  if chosen is null then raise exception 'No eligible % approver is configured', p_stage using errcode='check_violation'; end if;
  return chosen;
end;
$$;

create or replace function public.enqueue_notification(
  p_company_id uuid, p_event_key text, p_event_type text, p_user_id uuid, p_payload jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare outbox_id uuid;
begin
  insert into public.notification_outbox(company_id,event_key,event_type,recipient_user_id,channel,payload)
  values(p_company_id,p_event_key,p_event_type,p_user_id,'in_app',coalesce(p_payload,'{}'::jsonb))
  on conflict(company_id,event_key,channel) do update set event_key=excluded.event_key
  returning id into outbox_id;
  return outbox_id;
end;
$$;

create or replace function public.create_approval_workflow_for_submission()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare report public.expense_reports%rowtype; workflow_id uuid; manager_id uuid; assignment_user uuid; delegated_from uuid; delegation jsonb; due_hours integer:=72;
begin
  select * into report from public.expense_reports where id=new.report_id;
  manager_id := public.choose_approver(new.company_id, report.employee_id, 'manager');
  delegation := public.resolve_active_delegate(new.company_id,manager_id,'manager',now());
  assignment_user := (delegation->>'assignedTo')::uuid;
  delegated_from := public.try_uuid(delegation->>'delegatedFrom');
  select coalesce(manager_due_hours,72) into due_hours from public.company_approval_settings where company_id=new.company_id;

  insert into public.approval_workflows(company_id,report_id,submission_id,submission_number,employee_id,status,current_stage)
  values(new.company_id,new.report_id,new.id,new.submission_number,report.employee_id,'manager_review','manager')
  returning id into workflow_id;
  insert into public.approval_assignments(workflow_id,company_id,stage,assigned_to,delegated_from,due_at)
  values(workflow_id,new.company_id,'manager',assignment_user,delegated_from,now()+make_interval(hours=>due_hours));
  perform public.enqueue_notification(new.company_id,'approval:'||workflow_id||':manager','approval.review_assigned',assignment_user,
    jsonb_build_object('workflowId',workflow_id,'reportId',new.report_id,'submissionId',new.id,'stage','manager'));
  insert into public.audit_events(company_id,actor_user_id,expense_report_id,approval_workflow_id,event_type,payload)
  values(new.company_id,new.submitted_by,new.report_id,workflow_id,'approval.workflow_created',jsonb_build_object('submissionId',new.id));
  return new;
end;
$$;
create trigger expense_submissions_create_approval
after insert on public.expense_report_submissions
for each row execute function public.create_approval_workflow_for_submission();

create or replace function public.decide_approval_workflow(
  p_workflow_id uuid,
  p_expected_version integer,
  p_action public.approval_action,
  p_note text,
  p_claim_id uuid,
  p_idempotency_key text,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); workflow public.approval_workflows%rowtype; assignment public.approval_assignments%rowtype; decision_id uuid; next_user uuid; next_assignment uuid; settings public.company_approval_settings%rowtype; delegation jsonb; delegated_from uuid; due_hours integer:=72;
begin
  if actor is null then raise exception 'Authentication required' using errcode='insufficient_privilege'; end if;
  select * into workflow from public.approval_workflows where id=p_workflow_id for update;
  if not found then raise exception 'Approval workflow not found' using errcode='no_data_found'; end if;
  if workflow.version<>p_expected_version then raise exception 'Approval workflow version conflict' using errcode='serialization_failure'; end if;
  if workflow.employee_id=actor then raise exception 'Self approval is forbidden' using errcode='insufficient_privilege'; end if;
  if workflow.status not in ('manager_review','finance_review') then raise exception 'Workflow is not open for decision' using errcode='check_violation'; end if;
  select * into assignment from public.approval_assignments
    where workflow_id=workflow.id and stage=workflow.current_stage and status='pending' for update;
  if not found or assignment.assigned_to<>actor then raise exception 'Current approval assignment is not owned by this user' using errcode='insufficient_privilege'; end if;
  if exists(select 1 from public.approval_decisions where company_id=workflow.company_id and idempotency_key=p_idempotency_key) then
    return (select jsonb_build_object('workflowId',workflow_id,'decisionId',id,'status',workflow.status,'version',workflow.version)
      from public.approval_decisions where company_id=workflow.company_id and idempotency_key=p_idempotency_key);
  end if;
  if p_action in ('request_changes','reject') and char_length(trim(coalesce(p_note,'')))<3 then
    raise exception 'A reason is required' using errcode='check_violation';
  end if;
  insert into public.approval_decisions(workflow_id,assignment_id,company_id,submission_id,stage,action,actor_user_id,claim_id,note,idempotency_key,workflow_version,request_id)
  values(workflow.id,assignment.id,workflow.company_id,workflow.submission_id,workflow.current_stage,p_action,actor,p_claim_id,nullif(trim(p_note),''),p_idempotency_key,workflow.version,p_request_id)
  returning id into decision_id;
  if p_action='comment' then
    return jsonb_build_object('workflowId',workflow.id,'decisionId',decision_id,'status',workflow.status,'version',workflow.version);
  end if;
  update public.approval_assignments set status='completed',completed_at=now() where id=assignment.id;
  if p_action='request_changes' then
    update public.approval_workflows set status=case when current_stage='manager' then 'manager_changes_requested' else 'finance_changes_requested' end,
      current_stage=null,closed_at=now(),version=version+1 where id=workflow.id returning * into workflow;
    perform public.enqueue_notification(workflow.company_id,'approval:'||workflow.id||':changes:'||decision_id,'approval.changes_requested',workflow.employee_id,
      jsonb_build_object('workflowId',workflow.id,'decisionId',decision_id,'note',p_note));
  elsif p_action='reject' then
    update public.approval_workflows set status='rejected',current_stage=null,closed_at=now(),version=version+1 where id=workflow.id returning * into workflow;
    perform public.enqueue_notification(workflow.company_id,'approval:'||workflow.id||':rejected','approval.rejected',workflow.employee_id,jsonb_build_object('workflowId',workflow.id,'note',p_note));
  elsif workflow.current_stage='manager' then
    update public.approval_workflows set status='finance_review',current_stage='finance',manager_approved_at=now(),version=version+1 where id=workflow.id returning * into workflow;
    next_user:=public.choose_approver(workflow.company_id,workflow.employee_id,'finance');
    delegation:=public.resolve_active_delegate(workflow.company_id,next_user,'finance',now());
    delegated_from:=public.try_uuid(delegation->>'delegatedFrom'); next_user:=(delegation->>'assignedTo')::uuid;
    select coalesce(finance_due_hours,72) into due_hours from public.company_approval_settings where company_id=workflow.company_id;
    insert into public.approval_assignments(workflow_id,company_id,stage,assigned_to,delegated_from,due_at)
    values(workflow.id,workflow.company_id,'finance',next_user,delegated_from,now()+make_interval(hours=>due_hours)) returning id into next_assignment;
    perform public.enqueue_notification(workflow.company_id,'approval:'||workflow.id||':finance','approval.review_assigned',next_user,jsonb_build_object('workflowId',workflow.id,'stage','finance'));
  else
    update public.approval_workflows set status='finance_approved',current_stage=null,finance_approved_at=now(),closed_at=now(),version=version+1 where id=workflow.id returning * into workflow;
    perform public.enqueue_notification(workflow.company_id,'approval:'||workflow.id||':approved','approval.finance_approved',workflow.employee_id,jsonb_build_object('workflowId',workflow.id));
  end if;
  insert into public.audit_events(company_id,actor_user_id,expense_report_id,approval_workflow_id,approval_decision_id,event_type,request_id,payload)
  values(workflow.company_id,actor,workflow.report_id,workflow.id,decision_id,'approval.decision_recorded',p_request_id,jsonb_build_object('action',p_action,'stage',assignment.stage,'status',workflow.status,'version',workflow.version));
  return jsonb_build_object('workflowId',workflow.id,'decisionId',decision_id,'status',workflow.status,'version',workflow.version);
end;
$$;

create or replace function public.start_report_revision(
  p_workflow_id uuid, p_expected_version integer, p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); workflow public.approval_workflows%rowtype; old_report public.expense_reports%rowtype; new_report_id uuid; item record;
begin
  select * into workflow from public.approval_workflows where id=p_workflow_id for update;
  if not found then raise exception 'Approval workflow not found' using errcode='no_data_found'; end if;
  if workflow.employee_id<>actor then raise exception 'Only the owning employee may revise the report' using errcode='insufficient_privilege'; end if;
  if workflow.version<>p_expected_version then raise exception 'Approval workflow version conflict' using errcode='serialization_failure'; end if;
  if workflow.status not in ('manager_changes_requested','finance_changes_requested') then raise exception 'Changes were not requested' using errcode='check_violation'; end if;
  select * into old_report from public.expense_reports where id=workflow.report_id for update;
  insert into public.expense_reports(company_id,employee_id,status,title,period_start,period_end)
  values(old_report.company_id,old_report.employee_id,'draft',old_report.title||' — revision',old_report.period_start,old_report.period_end)
  returning id into new_report_id;
  for item in select i.claim_id,i.position from public.expense_report_items i where i.report_id=old_report.id order by i.position loop
    update public.expense_claims set status='draft',version=version+1 where id=item.claim_id;
    delete from public.expense_report_items where report_id=old_report.id and claim_id=item.claim_id;
    insert into public.expense_report_items(report_id,claim_id,company_id,position,added_by)
    values(new_report_id,item.claim_id,old_report.company_id,item.position,actor);
  end loop;
  update public.expense_reports set status='withdrawn',withdrawn_at=now(),version=version+1 where id=old_report.id;
  update public.approval_workflows set status='superseded',closed_at=now(),version=version+1 where id=workflow.id;
  insert into public.audit_events(company_id,actor_user_id,expense_report_id,approval_workflow_id,event_type,request_id,payload)
  values(old_report.company_id,actor,old_report.id,workflow.id,'approval.revision_started',p_request_id,jsonb_build_object('newReportId',new_report_id));
  return jsonb_build_object('oldReportId',old_report.id,'newReportId',new_report_id,'workflowId',workflow.id);
end;
$$;

create or replace function public.claim_notification_outbox(p_limit integer default 25)
returns setof public.notification_outbox language plpgsql security definer set search_path=public as $$
begin
  return query update public.notification_outbox o set status='processing',leased_until=now()+interval '5 minutes',attempt_count=attempt_count+1
  where o.id in (select id from public.notification_outbox where status in ('pending','failed') and available_at<=now()
    and (leased_until is null or leased_until<now()) order by created_at for update skip locked limit greatest(1,least(p_limit,100)))
  returning o.*;
end;
$$;

alter table public.company_approval_settings enable row level security;
alter table public.approver_delegations enable row level security;
alter table public.approval_workflows enable row level security;
alter table public.approval_assignments enable row level security;
alter table public.approval_decisions enable row level security;
alter table public.notification_outbox enable row level security;

create policy approval_settings_select on public.company_approval_settings for select to authenticated using(public.is_company_member(company_id));
create policy delegations_select on public.approver_delegations for select to authenticated using(public.is_company_member(company_id));
create policy workflows_select on public.approval_workflows for select to authenticated using(public.can_view_expense_report(report_id));
create policy assignments_select on public.approval_assignments for select to authenticated using(assigned_to=auth.uid() or public.is_company_member(company_id));
create policy decisions_select on public.approval_decisions for select to authenticated using(public.is_company_member(company_id));
create policy outbox_select_admin on public.notification_outbox for select to authenticated using(public.has_company_role(company_id,array['finance','admin']::public.company_role[]));

grant select on public.company_approval_settings,public.approver_delegations,public.approval_workflows,public.approval_assignments,public.approval_decisions to authenticated;
grant all on public.company_approval_settings,public.approver_delegations,public.approval_workflows,public.approval_assignments,public.approval_decisions,public.notification_outbox to service_role;
grant execute on function public.decide_approval_workflow(uuid,integer,public.approval_action,text,uuid,text,text) to authenticated;
grant execute on function public.start_report_revision(uuid,integer,text) to authenticated;
revoke all on function public.decide_approval_workflow(uuid,integer,public.approval_action,text,uuid,text,text) from public;
revoke all on function public.start_report_revision(uuid,integer,text) from public;

commit;
