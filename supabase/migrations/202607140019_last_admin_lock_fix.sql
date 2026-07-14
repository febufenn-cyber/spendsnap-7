-- Production repair: serialize admin-role changes without FOR UPDATE on an aggregate.
begin;

create or replace function public.change_company_member_role(
  p_company_id uuid,
  p_user_id uuid,
  p_role public.company_role,
  p_active boolean,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  actor uuid:=auth.uid();
  member public.company_memberships%rowtype;
  admin_count integer;
begin
  if not public.has_company_role(p_company_id,array['admin']::public.company_role[]) then
    raise exception 'Admin role required' using errcode='insufficient_privilege';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('company-admin:'||p_company_id::text, 61));
  select * into member
  from public.company_memberships
  where company_id=p_company_id and user_id=p_user_id
  for update;
  if not found then raise exception 'Membership not found' using errcode='no_data_found'; end if;

  if member.role='admin' and member.active and (p_role<>'admin' or not p_active) then
    select count(*) into admin_count
    from public.company_memberships
    where company_id=p_company_id and role='admin' and active;
    if admin_count<=1 then
      raise exception 'The last active admin cannot be removed or demoted' using errcode='check_violation';
    end if;
  end if;

  update public.company_memberships
  set role=p_role,active=p_active,updated_at=now()
  where company_id=p_company_id and user_id=p_user_id
  returning * into member;

  insert into public.security_events(company_id,actor_user_id,event_type,severity,request_id,evidence)
  values(p_company_id,actor,'admin.member_changed','warning',p_request_id,
    jsonb_build_object('userId',p_user_id,'role',p_role,'active',p_active));
  return to_jsonb(member);
end;
$$;

commit;
