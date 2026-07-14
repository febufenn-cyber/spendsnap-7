-- Phase 7 repair: allow only the controlled proposal status transition used by confirmation RPC.
begin;

drop trigger agent_proposals_no_update_delete on public.agent_proposals;

create or replace function public.protect_agent_proposal()
returns trigger language plpgsql security invoker as $$
begin
  if tg_op='DELETE' then raise exception 'Agent proposals cannot be deleted' using errcode='check_violation'; end if;
  if old.status='proposed' and new.status in ('accepted','rejected','expired')
     and new.id=old.id and new.run_id=old.run_id and new.company_id=old.company_id
     and new.proposal_type=old.proposal_type and new.title=old.title and new.rationale=old.rationale
     and new.proposed_payload=old.proposed_payload and new.evidence=old.evidence
     and new.confidence=old.confidence and new.risk_level=old.risk_level
     and new.requires_confirmation=old.requires_confirmation and new.expires_at=old.expires_at
     and new.created_at=old.created_at then return new;
  end if;
  raise exception 'Agent proposal content is immutable' using errcode='check_violation';
end;
$$;

create trigger agent_proposals_protect before update or delete on public.agent_proposals
for each row execute function public.protect_agent_proposal();

commit;
