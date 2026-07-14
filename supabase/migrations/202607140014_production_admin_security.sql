-- Spendsnap Phase 6: tenant administration, retention, support access, security evidence.
begin;

create type public.deletion_request_status as enum ('requested','approved','scheduled','completed','rejected','cancelled');
create type public.invitation_status as enum ('pending','accepted','revoked','expired');

create table public.company_security_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  version integer not null default 1 check(version>0),
  allowed_email_domains text[] not null default '{}',
  receipt_retention_days integer not null default 2555 check(receipt_retention_days between 30 and 3650),
  audit_retention_days integer not null default 3650 check(audit_retention_days between 365 and 7300),
  require_verified_email boolean not null default true,
  support_access_enabled boolean not null default false,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.company_invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null check(position('@' in email)>1),
  role public.company_role not null,
  token_digest text not null unique check(token_digest ~ '^[a-f0-9]{64}$'),
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null,
  invited_by uuid not null references auth.users(id) on delete restrict,
  accepted_by uuid references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index company_invitations_pending_email_idx on public.company_invitations(company_id,lower(email)) where status='pending';

create table public.support_access_grants (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  support_user_id uuid not null references auth.users(id) on delete restrict,
  purpose text not null check(char_length(trim(purpose)) between 10 and 1000),
  scope text[] not null check(cardinality(scope)>0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  granted_by uuid not null references auth.users(id) on delete restrict,
  revoked_by uuid references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint support_access_range check(ends_at>starts_at)
);
create index support_access_active_idx on public.support_access_grants(company_id,support_user_id,starts_at,ends_at) where revoked_at is null;

create table public.data_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  subject_user_id uuid references auth.users(id) on delete restrict,
  scope text not null check(scope in ('user','company','receipt')),
  receipt_id uuid references public.receipts(id) on delete restrict,
  reason text not null check(char_length(trim(reason)) between 10 and 2000),
  status public.deletion_request_status not null default 'requested',
  requested_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid references auth.users(id) on delete restrict,
  review_note text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  scheduled_for timestamptz,
  completed_at timestamptz,
  execution_evidence jsonb
);
create index deletion_requests_company_status_idx on public.data_deletion_requests(company_id,status,requested_at);

create table public.security_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  event_type text not null check(event_type ~ '^[a-z][a-z0-9_.-]{2,119}$'),
  severity text not null check(severity in ('info','warning','critical')),
  request_id text,
  ip_hash text,
  user_agent_hash text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index security_events_company_created_idx on public.security_events(company_id,created_at desc);

create table public.audit_export_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  period_start timestamptz not null,
  period_end timestamptz not null,
  schema_version text not null default 'audit-json-v1',
  status text not null check(status in ('completed','failed')),
  content jsonb,
  checksum_sha256 text check(checksum_sha256 is null or checksum_sha256 ~ '^[a-f0-9]{64}$'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint audit_export_range check(period_end>period_start)
);

alter table public.audit_events add column security_event_id uuid references public.security_events(id) on delete restrict;
create trigger company_security_settings_updated before update on public.company_security_settings for each row execute function public.set_updated_at();

create or replace function public.seed_company_security_settings()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.company_security_settings(company_id,updated_by) values(new.id,new.created_by) on conflict do nothing;
  return new;
end;
$$;
create trigger companies_seed_security after insert on public.companies for each row execute function public.seed_company_security_settings();
insert into public.company_security_settings(company_id,updated_by) select id,created_by from public.companies on conflict do nothing;

create or replace function public.protect_security_event()
returns trigger language plpgsql security invoker as $$ begin raise exception 'Security events are append-only' using errcode='check_violation'; end; $$;
create trigger security_events_append_only before update or delete on public.security_events for each row execute function public.protect_security_event();

create or replace function public.is_active_support_user(p_company_id uuid,p_scope text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.support_access_grants g where g.company_id=p_company_id and g.support_user_id=auth.uid()
    and g.revoked_at is null and g.starts_at<=now() and g.ends_at>now() and p_scope=any(g.scope));
$$;

create or replace function public.update_company_security_settings(
  p_company_id uuid,p_expected_version integer,p_patch jsonb,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); settings public.company_security_settings%rowtype;
begin
  if not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then raise exception 'Admin role required' using errcode='insufficient_privilege'; end if;
  select * into settings from public.company_security_settings where company_id=p_company_id for update;
  if settings.version<>p_expected_version then raise exception 'Security settings version conflict' using errcode='serialization_failure'; end if;
  update public.company_security_settings set
    allowed_email_domains=case when p_patch?'allowedEmailDomains' then array(select lower(trim(value)) from jsonb_array_elements_text(p_patch->'allowedEmailDomains') value) else allowed_email_domains end,
    receipt_retention_days=coalesce((p_patch->>'receiptRetentionDays')::integer,receipt_retention_days),
    audit_retention_days=coalesce((p_patch->>'auditRetentionDays')::integer,audit_retention_days),
    require_verified_email=coalesce((p_patch->>'requireVerifiedEmail')::boolean,require_verified_email),
    support_access_enabled=coalesce((p_patch->>'supportAccessEnabled')::boolean,support_access_enabled),
    version=version+1,updated_by=actor where company_id=p_company_id returning * into settings;
  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(p_company_id,actor,'admin.security_settings_updated','warning',p_request_id,jsonb_build_object('version',settings.version));
  return to_jsonb(settings);
end;
$$;

create or replace function public.invite_company_member(
  p_company_id uuid,p_email text,p_role public.company_role,p_expires_hours integer,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); raw_token text:=encode(gen_random_bytes(32),'hex'); invitation_id uuid; expires timestamptz:=now()+make_interval(hours=>greatest(1,least(p_expires_hours,336))); settings public.company_security_settings%rowtype; domain text;
begin
  if not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then raise exception 'Admin role required' using errcode='insufficient_privilege'; end if;
  select * into settings from public.company_security_settings where company_id=p_company_id for update;
  domain:=lower(split_part(trim(p_email),'@',2));
  if cardinality(settings.allowed_email_domains)>0 and not domain=any(settings.allowed_email_domains) then raise exception 'Email domain is not allowed' using errcode='check_violation'; end if;
  insert into public.company_invitations(company_id,email,role,token_digest,expires_at,invited_by)
  values(p_company_id,lower(trim(p_email)),p_role,encode(digest(raw_token,'sha256'),'hex'),expires,actor) returning id into invitation_id;
  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(p_company_id,actor,'admin.member_invited','info',p_request_id,jsonb_build_object('invitationId',invitation_id,'role',p_role,'emailDomain',domain));
  return jsonb_build_object('invitationId',invitation_id,'token',raw_token,'expiresAt',expires);
end;
$$;

create or replace function public.accept_company_invitation(p_token text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); invitation public.company_invitations%rowtype; user_email text;
begin
  if actor is null then raise exception 'Authentication required' using errcode='insufficient_privilege'; end if;
  select email into user_email from auth.users where id=actor;
  select * into invitation from public.company_invitations where token_digest=encode(digest(p_token,'sha256'),'hex') for update;
  if not found or invitation.status<>'pending' or invitation.expires_at<=now() then raise exception 'Invitation is invalid or expired' using errcode='check_violation'; end if;
  if lower(user_email)<>lower(invitation.email) then raise exception 'Invitation email does not match authenticated user' using errcode='insufficient_privilege'; end if;
  insert into public.company_memberships(company_id,user_id,role,active) values(invitation.company_id,actor,invitation.role,true)
    on conflict(company_id,user_id) do update set role=excluded.role,active=true,updated_at=now();
  update public.company_invitations set status='accepted',accepted_by=actor,accepted_at=now() where id=invitation.id;
  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(invitation.company_id,actor,'admin.invitation_accepted','info',p_request_id,jsonb_build_object('invitationId',invitation.id,'role',invitation.role));
  return jsonb_build_object('companyId',invitation.company_id,'role',invitation.role);
end;
$$;

create or replace function public.change_company_member_role(
  p_company_id uuid,p_user_id uuid,p_role public.company_role,p_active boolean,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); member public.company_memberships%rowtype; admin_count integer;
begin
  if not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then raise exception 'Admin role required' using errcode='insufficient_privilege'; end if;
  select * into member from public.company_memberships where company_id=p_company_id and user_id=p_user_id for update;
  if not found then raise exception 'Membership not found' using errcode='no_data_found'; end if;
  if member.role='admin' and member.active and (p_role<>'admin' or not p_active) then
    select count(*) into admin_count from public.company_memberships where company_id=p_company_id and role='admin' and active for update;
    if admin_count<=1 then raise exception 'The last active admin cannot be removed or demoted' using errcode='check_violation'; end if;
  end if;
  update public.company_memberships set role=p_role,active=p_active,updated_at=now() where company_id=p_company_id and user_id=p_user_id returning * into member;
  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(p_company_id,actor,'admin.member_changed','warning',p_request_id,jsonb_build_object('userId',p_user_id,'role',p_role,'active',p_active));
  return to_jsonb(member);
end;
$$;

create or replace function public.request_data_deletion(
  p_company_id uuid,p_scope text,p_subject_user_id uuid,p_receipt_id uuid,p_reason text,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); request_id uuid;
begin
  if not public.is_company_member(p_company_id) then raise exception 'Company membership required' using errcode='insufficient_privilege'; end if;
  if p_scope='company' and not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then raise exception 'Admin role required for company deletion' using errcode='insufficient_privilege'; end if;
  insert into public.data_deletion_requests(company_id,subject_user_id,scope,receipt_id,reason,requested_by)
  values(p_company_id,p_subject_user_id,p_scope,p_receipt_id,trim(p_reason),actor) returning id into request_id;
  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(p_company_id,actor,'privacy.deletion_requested','critical',p_request_id,jsonb_build_object('deletionRequestId',request_id,'scope',p_scope));
  return jsonb_build_object('requestId',request_id,'status','requested');
end;
$$;

create or replace function public.create_audit_export(
  p_company_id uuid,p_period_start timestamptz,p_period_end timestamptz,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); content jsonb; export_id uuid; checksum text;
begin
  if not public.has_company_role(p_company_id,array['admin','auditor']::public.company_role[]) then raise exception 'Admin or auditor role required' using errcode='insufficient_privilege'; end if;
  select jsonb_build_object('schemaVersion','audit-json-v1','companyId',p_company_id,'periodStart',p_period_start,'periodEnd',p_period_end,
    'auditEvents',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id) from public.audit_events e where e.company_id=p_company_id and e.created_at>=p_period_start and e.created_at<p_period_end),'[]'::jsonb),
    'securityEvents',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at,s.id) from public.security_events s where s.company_id=p_company_id and s.created_at>=p_period_start and s.created_at<p_period_end),'[]'::jsonb)) into content;
  checksum:=encode(digest(convert_to(content::text,'UTF8'),'sha256'),'hex');
  insert into public.audit_export_runs(company_id,period_start,period_end,status,content,checksum_sha256,created_by)
  values(p_company_id,p_period_start,p_period_end,'completed',content,checksum,actor) returning id into export_id;
  return jsonb_build_object('exportId',export_id,'checksumSha256',checksum,'content',content);
end;
$$;

alter table public.company_security_settings enable row level security;
alter table public.company_invitations enable row level security;
alter table public.support_access_grants enable row level security;
alter table public.data_deletion_requests enable row level security;
alter table public.security_events enable row level security;
alter table public.audit_export_runs enable row level security;
create policy security_settings_member_select on public.company_security_settings for select to authenticated using(public.is_company_member(company_id));
create policy invitations_admin_select on public.company_invitations for select to authenticated using(public.has_company_role(company_id,array['admin']::public.company_role[]));
create policy support_grants_admin_select on public.support_access_grants for select to authenticated using(public.has_company_role(company_id,array['admin']::public.company_role[]));
create policy deletion_requests_member_select on public.data_deletion_requests for select to authenticated using(requested_by=auth.uid() or public.has_company_role(company_id,array['admin','auditor']::public.company_role[]));
create policy security_events_privileged_select on public.security_events for select to authenticated using(public.has_company_role(company_id,array['admin','auditor']::public.company_role[]));
create policy audit_exports_privileged_select on public.audit_export_runs for select to authenticated using(public.has_company_role(company_id,array['admin','auditor']::public.company_role[]));

grant select on public.company_security_settings,public.company_invitations,public.support_access_grants,public.data_deletion_requests,public.security_events,public.audit_export_runs to authenticated;
grant all on public.company_security_settings,public.company_invitations,public.support_access_grants,public.data_deletion_requests,public.security_events,public.audit_export_runs to service_role;
grant execute on function public.update_company_security_settings(uuid,integer,jsonb,text),public.invite_company_member(uuid,text,public.company_role,integer,text),public.accept_company_invitation(text,text),public.change_company_member_role(uuid,uuid,public.company_role,boolean,text),public.request_data_deletion(uuid,text,uuid,uuid,text,text),public.create_audit_export(uuid,timestamptz,timestamptz,text) to authenticated;
revoke all on function public.update_company_security_settings(uuid,integer,jsonb,text),public.invite_company_member(uuid,text,public.company_role,integer,text),public.accept_company_invitation(text,text),public.change_company_member_role(uuid,uuid,public.company_role,boolean,text),public.request_data_deletion(uuid,text,uuid,uuid,text,text),public.create_audit_export(uuid,timestamptz,timestamptz,text) from public;

commit;
