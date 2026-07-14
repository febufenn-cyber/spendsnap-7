-- Phase 8 repair: billing events are callable only by the server service role.
begin;
grant execute on function public.apply_billing_event(text,text,text,text,jsonb) to service_role;
commit;
