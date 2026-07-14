-- Phase 8 repair: make billing subscription lookup explicitly company scoped.
begin;

create or replace function public.apply_billing_event(
  p_provider text,
  p_provider_event_id text,
  p_event_type text,
  p_payload_hash text,
  p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  billing_event public.billing_events%rowtype;
  target_company_id uuid;
  selected_plan public.product_plans%rowtype;
  current_subscription public.company_subscriptions%rowtype;
  new_status public.subscription_status;
begin
  insert into public.billing_events(
    provider,provider_event_id,event_type,payload_hash,payload,signature_verified,status
  ) values (
    p_provider,p_provider_event_id,p_event_type,p_payload_hash,p_payload,true,'received'
  ) on conflict(provider,provider_event_id)
    do update set provider_event_id=excluded.provider_event_id
  returning * into billing_event;

  if billing_event.status='processed' then
    return jsonb_build_object('eventId',billing_event.id,'status','processed','duplicate',true);
  end if;

  target_company_id:=public.try_uuid(p_payload->>'companyId');
  if target_company_id is null then
    update public.billing_events set status='ignored',processed_at=now() where id=billing_event.id;
    return jsonb_build_object('eventId',billing_event.id,'status','ignored');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('subscription:'||target_company_id::text, 73));
  select * into selected_plan
  from public.product_plans
  where code=p_payload->>'planCode' and active
  order by version desc limit 1;
  if not found then raise exception 'Billing event plan not found' using errcode='no_data_found'; end if;

  new_status:=coalesce((p_payload->>'status')::public.subscription_status,'active');
  select * into current_subscription
  from public.company_subscriptions subscription
  where subscription.company_id=target_company_id
    and subscription.status in ('trialing','active','past_due')
  for update;
  if not found then raise exception 'Current company subscription not found' using errcode='no_data_found'; end if;

  update public.company_subscriptions
  set plan_id=selected_plan.id,
      status=new_status,
      provider=p_provider,
      provider_customer_ref=p_payload->>'customerRef',
      provider_subscription_ref=p_payload->>'subscriptionRef',
      current_period_start=coalesce((p_payload->>'periodStart')::timestamptz,now()),
      current_period_end=coalesce((p_payload->>'periodEnd')::timestamptz,now()+interval '1 month'),
      trial_ends_at=case when new_status='trialing' then trial_ends_at else null end,
      version=version+1
  where id=current_subscription.id;

  update public.billing_events set status='processed',processed_at=now() where id=billing_event.id;
  return jsonb_build_object('eventId',billing_event.id,'status','processed','duplicate',false,'companyId',target_company_id,'planCode',selected_plan.code);
exception when others then
  if billing_event.id is not null then
    update public.billing_events set status='failed',error_message=left(sqlerrm,2000),processed_at=now()
    where id=billing_event.id;
  end if;
  raise;
end;
$$;

grant execute on function public.apply_billing_event(text,text,text,text,jsonb) to service_role;
revoke all on function public.apply_billing_event(text,text,text,text,jsonb) from public;

commit;
