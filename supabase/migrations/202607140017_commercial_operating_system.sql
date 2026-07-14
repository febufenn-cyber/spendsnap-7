-- Spendsnap Phase 8: plans, subscriptions, onboarding, usage, billing events, product metrics.
begin;

create type public.subscription_status as enum ('trialing','active','past_due','cancelled','expired');
create type public.billing_event_status as enum ('received','processed','ignored','failed');

create table public.product_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check(code ~ '^[a-z][a-z0-9_-]{1,39}$'),
  name text not null,
  description text not null,
  monthly_price_minor integer not null check(monthly_price_minor>=0),
  currency text not null default 'INR' check(currency ~ '^[A-Z]{3}$'),
  included_receipts integer not null check(included_receipts>=0),
  included_active_users integer not null check(included_active_users>=0),
  features jsonb not null check(jsonb_typeof(features)='array'),
  version integer not null default 1 check(version>0),
  active boolean not null default true,
  public boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  plan_id uuid not null references public.product_plans(id) on delete restrict,
  status public.subscription_status not null,
  provider text not null default 'manual',
  provider_customer_ref text,
  provider_subscription_ref text,
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  version integer not null default 1 check(version>0),
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_period_check check(current_period_end>current_period_start)
);
create unique index company_one_current_subscription_idx on public.company_subscriptions(company_id)
  where status in ('trialing','active','past_due');
create unique index provider_subscription_ref_unique on public.company_subscriptions(provider,provider_subscription_ref)
  where provider_subscription_ref is not null;

create table public.company_onboarding_steps (
  company_id uuid not null references public.companies(id) on delete cascade,
  step_code text not null,
  required boolean not null default true,
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete restrict,
  evidence jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(company_id,step_code)
);

create table public.usage_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  event_key text not null,
  metric text not null check(metric in ('receipt_uploaded','report_submitted','agent_run','accounting_export','active_user')),
  quantity integer not null default 1 check(quantity>0),
  actor_user_id uuid references auth.users(id) on delete restrict,
  source_type text,
  source_id uuid,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(company_id,event_key)
);
create index usage_events_company_metric_time_idx on public.usage_events(company_id,metric,occurred_at);

create table public.billing_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  payload_hash text not null check(payload_hash ~ '^[a-f0-9]{64}$'),
  payload jsonb not null,
  signature_verified boolean not null,
  status public.billing_event_status not null default 'received',
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(provider,provider_event_id)
);

create table public.product_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  session_id text,
  event_name text not null check(event_name in (
    'onboarding_started','onboarding_step_completed','receipt_upload_started','receipt_verified',
    'claim_created','report_submitted','approval_completed','export_created','agent_proposal_accepted',
    'pricing_viewed','trial_started','subscription_changed'
  )),
  properties jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index product_events_company_name_time_idx on public.product_events(company_id,event_name,occurred_at);

create table public.customer_health_snapshots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  snapshot_date date not null,
  score integer not null check(score between 0 and 100),
  metrics jsonb not null,
  risk_flags jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique(company_id,snapshot_date)
);

alter table public.audit_events add column subscription_id uuid references public.company_subscriptions(id) on delete restrict;
create trigger company_subscriptions_updated before update on public.company_subscriptions for each row execute function public.set_updated_at();

insert into public.product_plans(code,name,description,monthly_price_minor,currency,included_receipts,included_active_users,features,version)
values
 ('starter','Starter','Verified receipt and report workflow for small teams.',299900,'INR',200,10,'["receipt_truth","employee_reports","policy_engine","approvals"]',1),
 ('growth','Growth','Finance review, GST readiness, export, administration, and advisor.',799900,'INR',1000,50,'["receipt_truth","employee_reports","policy_engine","approvals","finance_export","tenant_admin","agent_advisor"]',1),
 ('verified','Verified Service','Growth software plus contracted human verification service.',1499900,'INR',2000,100,'["receipt_truth","employee_reports","policy_engine","approvals","finance_export","tenant_admin","agent_advisor","human_verification"]',1)
on conflict(code) do nothing;

create or replace function public.seed_company_commercial_state()
returns trigger language plpgsql security definer set search_path=public as $$
declare starter_id uuid;
begin
  select id into starter_id from public.product_plans where code='starter' and active order by version desc limit 1;
  insert into public.company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,trial_ends_at,created_by)
  values(new.id,starter_id,'trialing',now(),now()+interval '14 days',now()+interval '14 days',new.created_by);
  insert into public.company_onboarding_steps(company_id,step_code,required) values
    (new.id,'invite_team',true),(new.id,'configure_policy',true),(new.id,'configure_approvers',true),
    (new.id,'upload_first_receipt',true),(new.id,'submit_first_report',true),(new.id,'configure_accounting',false);
  return new;
end;
$$;
create trigger companies_seed_commercial after insert on public.companies for each row execute function public.seed_company_commercial_state();

insert into public.company_subscriptions(company_id,plan_id,status,current_period_start,current_period_end,trial_ends_at,created_by)
select c.id,p.id,'trialing',now(),now()+interval '14 days',now()+interval '14 days',c.created_by
from public.companies c cross join lateral(select id from public.product_plans where code='starter' order by version desc limit 1)p
where not exists(select 1 from public.company_subscriptions s where s.company_id=c.id and s.status in ('trialing','active','past_due'));
insert into public.company_onboarding_steps(company_id,step_code,required)
select c.id,s.code,s.required from public.companies c cross join(values('invite_team',true),('configure_policy',true),('configure_approvers',true),('upload_first_receipt',true),('submit_first_report',true),('configure_accounting',false))s(code,required)
on conflict do nothing;

create or replace function public.record_usage_event(p_company_id uuid,p_event_key text,p_metric text,p_quantity integer,p_actor_user_id uuid,p_source_type text,p_source_id uuid,p_metadata jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare usage_id uuid;
begin
  insert into public.usage_events(company_id,event_key,metric,quantity,actor_user_id,source_type,source_id,metadata)
  values(p_company_id,p_event_key,p_metric,p_quantity,p_actor_user_id,p_source_type,p_source_id,coalesce(p_metadata,'{}'::jsonb))
  on conflict(company_id,event_key) do update set event_key=excluded.event_key returning id into usage_id;
  return usage_id;
end;
$$;

create or replace function public.meter_receipt_insert() returns trigger language plpgsql security definer set search_path=public as $$ begin perform public.record_usage_event(new.company_id,'receipt:'||new.id,'receipt_uploaded',1,new.submitted_by,'receipt',new.id,'{}');return new;end;$$;
create trigger receipts_meter_usage after insert on public.receipts for each row execute function public.meter_receipt_insert();
create or replace function public.meter_report_submission() returns trigger language plpgsql security definer set search_path=public as $$ begin perform public.record_usage_event(new.company_id,'submission:'||new.id,'report_submitted',1,new.submitted_by,'submission',new.id,'{}');return new;end;$$;
create trigger report_submissions_meter_usage after insert on public.expense_report_submissions for each row execute function public.meter_report_submission();
create or replace function public.meter_agent_run() returns trigger language plpgsql security definer set search_path=public as $$ begin perform public.record_usage_event(new.company_id,'agent:'||new.id,'agent_run',1,new.requested_by,'agent_run',new.id,jsonb_build_object('task',new.task));return new;end;$$;
create trigger agent_runs_meter_usage after insert on public.agent_runs for each row execute function public.meter_agent_run();
create or replace function public.meter_export() returns trigger language plpgsql security definer set search_path=public as $$ begin perform public.record_usage_event(new.company_id,'export:'||new.id,'accounting_export',1,new.created_by,'export',new.id,'{}');return new;end;$$;
create trigger export_batches_meter_usage after insert on public.accounting_export_batches for each row execute function public.meter_export();

create or replace function public.company_has_feature(p_company_id uuid,p_feature text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.company_subscriptions s join public.product_plans p on p.id=s.plan_id
    where s.company_id=p_company_id and s.status in ('trialing','active') and s.current_period_end>now() and p.features ? p_feature);
$$;

create or replace function public.complete_onboarding_step(p_company_id uuid,p_step_code text,p_evidence jsonb,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); step public.company_onboarding_steps%rowtype;
begin
  if not public.is_company_member(p_company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  update public.company_onboarding_steps set completed_at=coalesce(completed_at,now()),completed_by=coalesce(completed_by,actor),evidence=coalesce(p_evidence,'{}'::jsonb),updated_at=now()
  where company_id=p_company_id and step_code=p_step_code returning * into step;
  if not found then raise exception 'Onboarding step not found' using errcode='no_data_found'; end if;
  insert into public.product_events(company_id,actor_user_id,event_name,properties) values(p_company_id,actor,'onboarding_step_completed',jsonb_build_object('stepCode',p_step_code));
  return to_jsonb(step);
end;
$$;

create or replace function public.select_subscription_plan(p_company_id uuid,p_plan_code text,p_expected_version integer,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); subscription public.company_subscriptions%rowtype; plan public.product_plans%rowtype;
begin
  if not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then raise exception 'Admin role required' using errcode='insufficient_privilege'; end if;
  select * into subscription from public.company_subscriptions where company_id=p_company_id and status in ('trialing','active','past_due') for update;
  if subscription.version<>p_expected_version then raise exception 'Subscription version conflict' using errcode='serialization_failure'; end if;
  select * into plan from public.product_plans where code=p_plan_code and active order by version desc limit 1;
  if not found then raise exception 'Plan not found' using errcode='no_data_found'; end if;
  update public.company_subscriptions set plan_id=plan.id,status='active',provider='manual',current_period_start=now(),current_period_end=now()+interval '1 month',trial_ends_at=null,version=version+1 where id=subscription.id returning * into subscription;
  insert into public.audit_events(company_id,actor_user_id,subscription_id,event_type,request_id,payload) values(p_company_id,actor,subscription.id,'billing.subscription_changed',p_request_id,jsonb_build_object('planCode',plan.code,'version',subscription.version));
  insert into public.product_events(company_id,actor_user_id,event_name,properties) values(p_company_id,actor,'subscription_changed',jsonb_build_object('planCode',plan.code));
  return jsonb_build_object('subscription',to_jsonb(subscription),'plan',to_jsonb(plan));
end;
$$;

create or replace function public.record_product_event(p_company_id uuid,p_session_id text,p_event_name text,p_properties jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare event_id uuid; actor uuid:=auth.uid(); sanitized jsonb;
begin
  if p_company_id is not null and not public.is_company_member(p_company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  sanitized:=coalesce(p_properties,'{}'::jsonb)-'receiptText'-'rawResponse'-'email'-'token'-'secret';
  insert into public.product_events(company_id,actor_user_id,session_id,event_name,properties) values(p_company_id,actor,left(p_session_id,160),p_event_name,sanitized) returning id into event_id;
  return event_id;
end;
$$;

create or replace function public.apply_billing_event(p_provider text,p_provider_event_id text,p_event_type text,p_payload_hash text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare event public.billing_events%rowtype; company_id uuid; plan public.product_plans%rowtype; subscription public.company_subscriptions%rowtype; new_status public.subscription_status;
begin
  insert into public.billing_events(provider,provider_event_id,event_type,payload_hash,payload,signature_verified,status)
  values(p_provider,p_provider_event_id,p_event_type,p_payload_hash,p_payload,true,'received')
  on conflict(provider,provider_event_id) do update set provider_event_id=excluded.provider_event_id returning * into event;
  if event.status='processed' then return jsonb_build_object('eventId',event.id,'status','processed','duplicate',true); end if;
  company_id:=public.try_uuid(p_payload->>'companyId');
  if company_id is null then update public.billing_events set status='ignored',processed_at=now() where id=event.id;return jsonb_build_object('eventId',event.id,'status','ignored');end if;
  select * into plan from public.product_plans where code=p_payload->>'planCode' and active order by version desc limit 1;
  if not found then raise exception 'Billing event plan not found' using errcode='no_data_found'; end if;
  new_status:=coalesce((p_payload->>'status')::public.subscription_status,'active');
  select * into subscription from public.company_subscriptions where company_id=company_id and status in ('trialing','active','past_due') for update;
  update public.company_subscriptions set plan_id=plan.id,status=new_status,provider=p_provider,provider_customer_ref=p_payload->>'customerRef',provider_subscription_ref=p_payload->>'subscriptionRef',current_period_start=coalesce((p_payload->>'periodStart')::timestamptz,now()),current_period_end=coalesce((p_payload->>'periodEnd')::timestamptz,now()+interval '1 month'),version=version+1 where id=subscription.id;
  update public.billing_events set status='processed',processed_at=now() where id=event.id;
  return jsonb_build_object('eventId',event.id,'status','processed','duplicate',false);
exception when others then update public.billing_events set status='failed',error_message=left(sqlerrm,2000),processed_at=now() where id=event.id;raise;
end;
$$;

alter table public.product_plans enable row level security;
alter table public.company_subscriptions enable row level security;
alter table public.company_onboarding_steps enable row level security;
alter table public.usage_events enable row level security;
alter table public.billing_events enable row level security;
alter table public.product_events enable row level security;
alter table public.customer_health_snapshots enable row level security;
create policy product_plans_public_select on public.product_plans for select to authenticated using(active and public);
create policy subscriptions_member_select on public.company_subscriptions for select to authenticated using(public.is_company_member(company_id));
create policy onboarding_member_select on public.company_onboarding_steps for select to authenticated using(public.is_company_member(company_id));
create policy usage_privileged_select on public.usage_events for select to authenticated using(public.has_company_role(company_id,array['admin','finance','auditor']::public.company_role[]));
create policy product_events_privileged_select on public.product_events for select to authenticated using(company_id is null or public.has_company_role(company_id,array['admin','auditor']::public.company_role[]));
create policy health_privileged_select on public.customer_health_snapshots for select to authenticated using(public.has_company_role(company_id,array['admin']::public.company_role[]));
grant select on public.product_plans,public.company_subscriptions,public.company_onboarding_steps to authenticated;
grant select on public.usage_events,public.product_events,public.customer_health_snapshots to authenticated;
grant all on public.product_plans,public.company_subscriptions,public.company_onboarding_steps,public.usage_events,public.billing_events,public.product_events,public.customer_health_snapshots to service_role;
grant execute on function public.complete_onboarding_step(uuid,text,jsonb,text),public.select_subscription_plan(uuid,text,integer,text),public.record_product_event(uuid,text,text,jsonb) to authenticated;
revoke all on function public.complete_onboarding_step(uuid,text,jsonb,text),public.select_subscription_plan(uuid,text,integer,text),public.record_product_event(uuid,text,text,jsonb),public.apply_billing_event(text,text,text,text,jsonb) from public;

commit;
