-- Phase 5 repair: allow export rows and their immutable parent batch to be assembled atomically.
begin;

alter table public.accounting_export_items
  drop constraint accounting_export_items_batch_id_fkey;

alter table public.accounting_export_items
  add constraint accounting_export_items_batch_id_fkey
  foreign key (batch_id)
  references public.accounting_export_batches(id)
  on delete restrict
  deferrable initially deferred;

commit;
