-- Spendsnap Phase 5: GST readiness, accounting mappings, period locks, deterministic Tally CSV.
begin;

create type public.gst_readiness_status as enum ('complete','review_required','not_applicable');
create type public.export_batch_status as enum ('processing','completed','failed','reconciled','voided');

create table public.accounting_ledgers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check(code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,49}$'),
  name text not null check(char_length(trim(name)) between 1 and 160),
  active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id,code)
);

create table public.category_ledger_mappings (
  company_id uuid not null references public.companies(id) on delete cascade,
  category_id uuid not null references public.expense_categories(id) on delete restrict,
  ledger_id uuid not null references public.accounting_ledgers(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(company_id,category_id)
);

create table public.vendor_mappings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  normalized_merchant text not null check(char_length(trim(normalized_merchant)) between 1 and 200),
  accounting_vendor_name text not null check(char_length(trim(accounting_vendor_name)) between 1 and 200),
  gstin text,
  active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id,normalized_merchant)
);

create table public.accounting_export_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  voucher_type text not null default 'Payment' check(char_length(trim(voucher_type)) between 1 and 80),
  fallback_ledger_id uuid not null references public.accounting_ledgers(id) on delete restrict,
  schema_version text not null default 'tally-csv-v1',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.accounting_period_locks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  reason text not null check(char_length(trim(reason)) between 3 and 1000),
  locked_by uuid not null references auth.users(id) on delete restrict,
  locked_at timestamptz not null default now(),
  unlocked_by uuid references auth.users(id) on delete restrict,
  unlocked_at timestamptz,
  constraint accounting_period_lock_range check(period_end>=period_start),
  constraint accounting_period_unlock_check check((unlocked_by is null and unlocked_at is null) or (unlocked_by is not null and unlocked_at is not null))
);
create index accounting_period_locks_active_idx on public.accounting_period_locks(company_id,period_start,period_end) where unlocked_at is null;

create table public.gst_readiness_evaluations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  workflow_id uuid not null references public.approval_workflows(id) on delete restrict,
  submission_id uuid not null references public.expense_report_submissions(id) on delete restrict,
  status public.gst_readiness_status not null,
  summary jsonb not null,
  evaluated_by uuid not null references auth.users(id) on delete restrict,
  request_id text,
  created_at timestamptz not null default now()
);
create index gst_readiness_workflow_created_idx on public.gst_readiness_evaluations(workflow_id,created_at desc);

create table public.accounting_export_batches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  workflow_id uuid not null references public.approval_workflows(id) on delete restrict,
  submission_id uuid not null references public.expense_report_submissions(id) on delete restrict,
  export_type text not null default 'tally_csv' check(export_type='tally_csv'),
  schema_version text not null,
  status public.export_batch_status not null,
  idempotency_key text not null check(char_length(idempotency_key) between 8 and 160),
  content_type text not null default 'text/csv; charset=utf-8',
  filename text not null,
  content text,
  checksum_sha256 text check(checksum_sha256 is null or checksum_sha256 ~ '^[a-f0-9]{64}$'),
  item_count integer not null default 0 check(item_count>=0),
  totals_by_currency jsonb not null default '{}'::jsonb,
  mapping_snapshot jsonb not null default '{}'::jsonb,
  gst_snapshot jsonb not null default '{}'::jsonb,
  error_details jsonb,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  reconciliation_note text,
  reconciled_by uuid references auth.users(id) on delete restrict,
  reconciled_at timestamptz,
  unique(company_id,idempotency_key)
);
create index accounting_export_batches_company_created_idx on public.accounting_export_batches(company_id,created_at desc);
create index accounting_export_batches_workflow_idx on public.accounting_export_batches(workflow_id,created_at desc);

create table public.accounting_export_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.accounting_export_batches(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  position integer not null check(position>0),
  claim_id uuid not null references public.expense_claims(id) on delete restrict,
  receipt_id uuid not null references public.receipts(id) on delete restrict,
  row_snapshot jsonb not null,
  row_text text not null,
  created_at timestamptz not null default now(),
  unique(batch_id,position)
);

alter table public.audit_events
  add column accounting_export_batch_id uuid references public.accounting_export_batches(id) on delete restrict,
  add column gst_evaluation_id uuid references public.gst_readiness_evaluations(id) on delete restrict;

create trigger accounting_ledgers_updated before update on public.accounting_ledgers for each row execute function public.set_updated_at();
create trigger category_ledger_mappings_updated before update on public.category_ledger_mappings for each row execute function public.set_updated_at();
create trigger vendor_mappings_updated before update on public.vendor_mappings for each row execute function public.set_updated_at();
create trigger accounting_export_settings_updated before update on public.accounting_export_settings for each row execute function public.set_updated_at();

create or replace function public.normalize_merchant(value text)
returns text language sql immutable as $$ select lower(regexp_replace(trim(coalesce(value,'')),'\s+',' ','g')); $$;

create or replace function public.csv_safe_text(value text)
returns text language plpgsql immutable as $$
declare safe text:=coalesce(value,'');
begin
  if left(safe,1) in ('=','+','-','@') then safe:=''''||safe; end if;
  return '"'||replace(safe,'"','""')||'"';
end;
$$;

create or replace function public.gst_readiness_for_facts(facts jsonb)
returns jsonb language plpgsql immutable as $$
declare issues jsonb:='[]'::jsonb; gstin text:=nullif(trim(facts->>'gstin'),''); cgst numeric:=coalesce(nullif(facts->>'cgst','')::numeric,0); sgst numeric:=coalesce(nullif(facts->>'sgst','')::numeric,0); igst numeric:=coalesce(nullif(facts->>'igst','')::numeric,0); status public.gst_readiness_status;
begin
  if gstin is null and facts->>'taxable_value' is null and cgst=0 and sgst=0 and igst=0 then
    return jsonb_build_object('status','not_applicable','issues','[]'::jsonb,'label','No GST fields detected; review only if a tax invoice was expected.');
  end if;
  if gstin is null then issues:=issues||jsonb_build_array('gstin_missing');
  elsif gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then issues:=issues||jsonb_build_array('gstin_format_questionable'); end if;
  if nullif(trim(facts->>'invoice_number'),'') is null then issues:=issues||jsonb_build_array('invoice_number_missing'); end if;
  if nullif(trim(facts->>'invoice_date'),'') is null then issues:=issues||jsonb_build_array('invoice_date_missing'); end if;
  if nullif(trim(facts->>'taxable_value'),'') is null then issues:=issues||jsonb_build_array('taxable_value_missing'); end if;
  if igst>0 and (cgst>0 or sgst>0) then issues:=issues||jsonb_build_array('igst_and_cgst_sgst_both_present'); end if;
  if (cgst>0 and sgst=0) or (sgst>0 and cgst=0) then issues:=issues||jsonb_build_array('cgst_sgst_pair_incomplete'); end if;
  status:=case when jsonb_array_length(issues)=0 then 'complete' else 'review_required' end;
  return jsonb_build_object('status',status,'issues',issues,'label',case when status='complete' then 'GST fields appear complete; tax eligibility still requires professional review.' else 'GST completeness requires tax review.' end);
exception when invalid_text_representation then
  return jsonb_build_object('status','review_required','issues',jsonb_build_array('tax_amount_format_invalid'),'label','GST completeness requires tax review.');
end;
$$;

create or replace function public.validate_accounting_mapping_scope()
returns trigger language plpgsql security invoker set search_path=public as $$
declare ref_company uuid;
begin
  if tg_table_name='category_ledger_mappings' then
    select company_id into ref_company from public.expense_categories where id=new.category_id;
    if ref_company is distinct from new.company_id then raise exception 'Category mapping scope mismatch' using errcode='check_violation'; end if;
    select company_id into ref_company from public.accounting_ledgers where id=new.ledger_id;
  elsif tg_table_name='accounting_export_settings' then
    select company_id into ref_company from public.accounting_ledgers where id=new.fallback_ledger_id;
  else return new; end if;
  if ref_company is distinct from new.company_id then raise exception 'Ledger mapping scope mismatch' using errcode='check_violation'; end if;
  return new;
end;
$$;
create trigger category_ledger_mappings_validate before insert or update on public.category_ledger_mappings for each row execute function public.validate_accounting_mapping_scope();
create trigger accounting_export_settings_validate before insert or update on public.accounting_export_settings for each row execute function public.validate_accounting_mapping_scope();

create or replace function public.seed_accounting_defaults()
returns trigger language plpgsql security definer set search_path=public as $$
declare ledger_id uuid;
begin
  insert into public.accounting_ledgers(company_id,code,name,created_by) values(new.id,'unmapped','Unmapped Expenses',new.created_by) returning id into ledger_id;
  insert into public.accounting_export_settings(company_id,fallback_ledger_id,created_by) values(new.id,ledger_id,new.created_by);
  return new;
end;
$$;
create trigger companies_seed_accounting_defaults after insert on public.companies for each row execute function public.seed_accounting_defaults();

insert into public.accounting_ledgers(company_id,code,name,created_by)
select c.id,'unmapped','Unmapped Expenses',c.created_by from public.companies c on conflict(company_id,code) do nothing;
insert into public.accounting_export_settings(company_id,fallback_ledger_id,created_by)
select c.id,l.id,c.created_by from public.companies c join public.accounting_ledgers l on l.company_id=c.id and l.code='unmapped'
on conflict(company_id) do nothing;

create or replace function public.evaluate_gst_readiness(
  p_workflow_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); workflow public.approval_workflows%rowtype; submission public.expense_report_submissions%rowtype; item jsonb; result jsonb; rows jsonb:='[]'::jsonb; complete_count integer:=0; review_count integer:=0; na_count integer:=0; overall public.gst_readiness_status; evaluation_id uuid;
begin
  select * into workflow from public.approval_workflows where id=p_workflow_id;
  if not found then raise exception 'Approval workflow not found' using errcode='no_data_found'; end if;
  if not public.has_company_role(workflow.company_id,array['finance','admin','auditor']::public.company_role[]) then raise exception 'Finance role required' using errcode='insufficient_privilege'; end if;
  select * into submission from public.expense_report_submissions where id=workflow.submission_id;
  for item in select value from jsonb_array_elements(submission.snapshot->'items') loop
    result:=public.gst_readiness_for_facts(item->'receiptFacts');
    rows:=rows||jsonb_build_array(jsonb_build_object('claimId',item->>'claimId','receiptId',item->>'receiptId','merchantName',item->>'merchantName','readiness',result));
    if result->>'status'='complete' then complete_count:=complete_count+1; elsif result->>'status'='review_required' then review_count:=review_count+1; else na_count:=na_count+1; end if;
  end loop;
  overall:=case when review_count>0 then 'review_required' when complete_count>0 then 'complete' else 'not_applicable' end;
  insert into public.gst_readiness_evaluations(company_id,workflow_id,submission_id,status,summary,evaluated_by,request_id)
  values(workflow.company_id,workflow.id,submission.id,overall,jsonb_build_object('status',overall,'complete',complete_count,'reviewRequired',review_count,'notApplicable',na_count,'items',rows),actor,p_request_id)
  returning id into evaluation_id;
  return jsonb_build_object('evaluationId',evaluation_id,'status',overall,'complete',complete_count,'reviewRequired',review_count,'notApplicable',na_count,'items',rows);
end;
$$;

create or replace function public.create_tally_csv_export(
  p_workflow_id uuid,p_idempotency_key text,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); workflow public.approval_workflows%rowtype; report public.expense_reports%rowtype; submission public.expense_report_submissions%rowtype; settings public.accounting_export_settings%rowtype; existing public.accounting_export_batches%rowtype; batch_id uuid:=gen_random_uuid(); item jsonb; position integer:=0; facts jsonb; readiness jsonb; gst_rows jsonb:='[]'::jsonb; row_snapshot jsonb; row_text text; body text:=''; header text; ledger_name text; vendor_name text; mapping_rows jsonb:='[]'::jsonb; checksum text; total_items integer:=0; filename text;
begin
  if actor is null then raise exception 'Authentication required' using errcode='insufficient_privilege'; end if;
  select * into workflow from public.approval_workflows where id=p_workflow_id for update;
  if not found then raise exception 'Approval workflow not found' using errcode='no_data_found'; end if;
  if workflow.status<>'finance_approved' then raise exception 'Finance approval is required before export' using errcode='check_violation'; end if;
  if not public.has_company_role(workflow.company_id,array['finance','admin']::public.company_role[]) then raise exception 'Finance role required' using errcode='insufficient_privilege'; end if;
  select * into existing from public.accounting_export_batches where company_id=workflow.company_id and idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('batchId',existing.id,'status',existing.status,'filename',existing.filename,'checksumSha256',existing.checksum_sha256,'itemCount',existing.item_count); end if;
  select * into report from public.expense_reports where id=workflow.report_id for update;
  if exists(select 1 from public.accounting_period_locks l where l.company_id=workflow.company_id and l.unlocked_at is null and daterange(l.period_start,l.period_end,'[]') && daterange(report.period_start,report.period_end,'[]')) then
    raise exception 'The report period is locked for accounting export' using errcode='check_violation';
  end if;
  select * into submission from public.expense_report_submissions where id=workflow.submission_id for update;
  select * into settings from public.accounting_export_settings where company_id=workflow.company_id for update;
  if not found then raise exception 'Accounting export settings are missing' using errcode='check_violation'; end if;
  filename:='spendsnap-'||report.id||'-submission-'||submission.submission_number||'.csv';
  header:='Voucher Date,Voucher Type,Ledger,Vendor,Reference,Amount,Currency,Cost Centre,Project,Narration,GSTIN,Taxable Value,CGST,SGST,IGST,GST Readiness';
  body:=header||chr(13)||chr(10);
  for item in select value from jsonb_array_elements(submission.snapshot->'items') order by (value->>'position')::integer loop
    position:=position+1; facts:=item->'receiptFacts'; readiness:=public.gst_readiness_for_facts(facts);
    select coalesce(ledger.name,fallback.name) into ledger_name
      from public.accounting_export_settings s join public.accounting_ledgers fallback on fallback.id=s.fallback_ledger_id
      left join public.category_ledger_mappings mapping on mapping.company_id=s.company_id and mapping.category_id=public.try_uuid(item->'category'->>'id')
      left join public.accounting_ledgers ledger on ledger.id=mapping.ledger_id
      where s.company_id=workflow.company_id;
    select coalesce(v.accounting_vendor_name,nullif(item->>'merchantName',''),'Unknown Vendor') into vendor_name
      from (select 1) seed left join public.vendor_mappings v on v.company_id=workflow.company_id and v.active and v.normalized_merchant=public.normalize_merchant(item->>'merchantName');
    row_snapshot:=jsonb_build_object('position',position,'claimId',item->>'claimId','receiptId',item->>'receiptId','voucherDate',item->>'incurredOn','voucherType',settings.voucher_type,'ledger',ledger_name,'vendor',vendor_name,'reference',facts->>'invoice_number','amount',item->>'amount','currency',item->>'currency','costCentre',item->'costCentre'->>'code','project',item->'project'->>'code','narration',item->>'businessPurpose','gstin',facts->>'gstin','taxableValue',facts->>'taxable_value','cgst',facts->>'cgst','sgst',facts->>'sgst','igst',facts->>'igst','gstReadiness',readiness);
    row_text:=array_to_string(array[
      public.csv_safe_text(item->>'incurredOn'),public.csv_safe_text(settings.voucher_type),public.csv_safe_text(ledger_name),public.csv_safe_text(vendor_name),public.csv_safe_text(facts->>'invoice_number'),public.csv_safe_text(item->>'amount'),public.csv_safe_text(item->>'currency'),public.csv_safe_text(item->'costCentre'->>'code'),public.csv_safe_text(item->'project'->>'code'),public.csv_safe_text(item->>'businessPurpose'),public.csv_safe_text(facts->>'gstin'),public.csv_safe_text(facts->>'taxable_value'),public.csv_safe_text(facts->>'cgst'),public.csv_safe_text(facts->>'sgst'),public.csv_safe_text(facts->>'igst'),public.csv_safe_text(readiness->>'status')],',');
    body:=body||row_text||chr(13)||chr(10); total_items:=total_items+1;
    gst_rows:=gst_rows||jsonb_build_array(jsonb_build_object('claimId',item->>'claimId','readiness',readiness));
    mapping_rows:=mapping_rows||jsonb_build_array(jsonb_build_object('claimId',item->>'claimId','ledger',ledger_name,'vendor',vendor_name));
    insert into public.accounting_export_items(id,batch_id,company_id,position,claim_id,receipt_id,row_snapshot,row_text)
    values(gen_random_uuid(),batch_id,workflow.company_id,position,(item->>'claimId')::uuid,(item->>'receiptId')::uuid,row_snapshot,row_text);
  end loop;
  checksum:=encode(digest(convert_to(body,'UTF8'),'sha256'),'hex');
  insert into public.accounting_export_batches(id,company_id,workflow_id,submission_id,schema_version,status,idempotency_key,filename,content,checksum_sha256,item_count,totals_by_currency,mapping_snapshot,gst_snapshot,created_by,completed_at)
  values(batch_id,workflow.company_id,workflow.id,submission.id,settings.schema_version,'completed',p_idempotency_key,filename,body,checksum,total_items,submission.totals_by_currency,jsonb_build_object('voucherType',settings.voucher_type,'rows',mapping_rows),jsonb_build_object('items',gst_rows),actor,now());
  insert into public.audit_events(company_id,actor_user_id,expense_report_id,approval_workflow_id,accounting_export_batch_id,event_type,request_id,payload)
  values(workflow.company_id,actor,workflow.report_id,workflow.id,batch_id,'accounting.export_completed',p_request_id,jsonb_build_object('filename',filename,'checksumSha256',checksum,'itemCount',total_items));
  return jsonb_build_object('batchId',batch_id,'status','completed','filename',filename,'checksumSha256',checksum,'itemCount',total_items);
end;
$$;

create or replace function public.reconcile_accounting_export(p_batch_id uuid,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare actor uuid:=auth.uid(); batch public.accounting_export_batches%rowtype;
begin
  select * into batch from public.accounting_export_batches where id=p_batch_id for update;
  if not found then raise exception 'Export batch not found' using errcode='no_data_found'; end if;
  if not public.has_company_role(batch.company_id,array['finance','admin']::public.company_role[]) then raise exception 'Finance role required' using errcode='insufficient_privilege'; end if;
  if batch.status<>'completed' then raise exception 'Only completed exports may be reconciled' using errcode='check_violation'; end if;
  update public.accounting_export_batches set status='reconciled',reconciliation_note=nullif(trim(p_note),''),reconciled_by=actor,reconciled_at=now() where id=batch.id;
  return jsonb_build_object('batchId',batch.id,'status','reconciled');
end;
$$;

create or replace function public.protect_export_evidence()
returns trigger language plpgsql security invoker as $$
begin
  if tg_op='DELETE' then raise exception 'Accounting export evidence cannot be deleted' using errcode='check_violation'; end if;
  if tg_table_name='accounting_export_items' then raise exception 'Accounting export items are immutable' using errcode='check_violation'; end if;
  if old.status='completed' and new.status='reconciled' and new.content is not distinct from old.content and new.checksum_sha256 is not distinct from old.checksum_sha256 and new.mapping_snapshot is not distinct from old.mapping_snapshot and new.gst_snapshot is not distinct from old.gst_snapshot then return new; end if;
  raise exception 'Completed accounting export evidence is immutable' using errcode='check_violation';
end;
$$;
create trigger export_batches_protect before update or delete on public.accounting_export_batches for each row when(old.status in ('completed','reconciled')) execute function public.protect_export_evidence();
create trigger export_items_protect before update or delete on public.accounting_export_items for each row execute function public.protect_export_evidence();

alter table public.accounting_ledgers enable row level security;
alter table public.category_ledger_mappings enable row level security;
alter table public.vendor_mappings enable row level security;
alter table public.accounting_export_settings enable row level security;
alter table public.accounting_period_locks enable row level security;
alter table public.gst_readiness_evaluations enable row level security;
alter table public.accounting_export_batches enable row level security;
alter table public.accounting_export_items enable row level security;

create policy ledgers_member_select on public.accounting_ledgers for select to authenticated using(public.is_company_member(company_id));
create policy category_mappings_member_select on public.category_ledger_mappings for select to authenticated using(public.is_company_member(company_id));
create policy vendor_mappings_member_select on public.vendor_mappings for select to authenticated using(public.is_company_member(company_id));
create policy export_settings_member_select on public.accounting_export_settings for select to authenticated using(public.is_company_member(company_id));
create policy period_locks_member_select on public.accounting_period_locks for select to authenticated using(public.is_company_member(company_id));
create policy gst_evaluations_member_select on public.gst_readiness_evaluations for select to authenticated using(public.is_company_member(company_id));
create policy export_batches_finance_select on public.accounting_export_batches for select to authenticated using(public.has_company_role(company_id,array['finance','admin','auditor']::public.company_role[]));
create policy export_items_finance_select on public.accounting_export_items for select to authenticated using(public.has_company_role(company_id,array['finance','admin','auditor']::public.company_role[]));

grant select on public.accounting_ledgers,public.category_ledger_mappings,public.vendor_mappings,public.accounting_export_settings,public.accounting_period_locks,public.gst_readiness_evaluations,public.accounting_export_batches,public.accounting_export_items to authenticated;
grant all on public.accounting_ledgers,public.category_ledger_mappings,public.vendor_mappings,public.accounting_export_settings,public.accounting_period_locks,public.gst_readiness_evaluations,public.accounting_export_batches,public.accounting_export_items to service_role;
grant execute on function public.evaluate_gst_readiness(uuid,text) to authenticated;
grant execute on function public.create_tally_csv_export(uuid,text,text) to authenticated;
grant execute on function public.reconcile_accounting_export(uuid,text,text) to authenticated;
revoke all on function public.evaluate_gst_readiness(uuid,text),public.create_tally_csv_export(uuid,text,text),public.reconcile_accounting_export(uuid,text,text) from public;

commit;
