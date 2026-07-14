import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';
import type { FinanceRepository } from './finance-repository';

function clientFor(env: Env, token: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
function dbError(message: string, error: { code?: string; message?: string } | null): AppError {
  if (error?.code === '42501') return new AppError('forbidden', 403, error.message || message);
  if (error?.code === 'P0002') return new AppError('not_found', 404, error.message || message);
  if (['23505', '23514', 'P0001', '40001'].includes(error?.code ?? '')) return new AppError('conflict', 409, error?.message || message);
  return new AppError('database_error', 502, message, undefined, { cause: error });
}

export class SupabaseFinanceRepository implements FinanceRepository {
  private readonly client: SupabaseClient;
  constructor(env: Env, token: string) { this.client = clientFor(env, token); }

  async listWorkflows(companyId: string, status?: string): Promise<Record<string, unknown>[]> {
    let query = this.client.from('approval_workflows')
      .select('id,company_id,report_id,submission_id,submission_number,employee_id,status,version,current_stage,manager_approved_at,finance_approved_at,created_at')
      .eq('company_id', companyId);
    if (status) query = query.eq('status', status);
    const { data, error } = await query.order('created_at', { ascending: false });
    if (error) throw dbError('Could not list finance workflows.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async getWorkspace(companyId: string): Promise<Record<string, unknown>> {
    const [ledgers, mappings, vendors, settings, locks] = await Promise.all([
      this.client.from('accounting_ledgers').select('*').eq('company_id', companyId).order('name'),
      this.client.from('category_ledger_mappings').select('*,category:expense_categories(id,code,name),ledger:accounting_ledgers(id,code,name)').eq('company_id', companyId),
      this.client.from('vendor_mappings').select('*').eq('company_id', companyId).order('normalized_merchant'),
      this.client.from('accounting_export_settings').select('*,fallback:accounting_ledgers(id,code,name)').eq('company_id', companyId).maybeSingle(),
      this.client.from('accounting_period_locks').select('*').eq('company_id', companyId).order('period_start', { ascending: false }),
    ]);
    for (const result of [ledgers, mappings, vendors, settings, locks]) if (result.error) throw dbError('Could not load finance workspace.', result.error);
    return { ledgers: ledgers.data ?? [], mappings: mappings.data ?? [], vendors: vendors.data ?? [], settings: settings.data, periodLocks: locks.data ?? [] };
  }

  async evaluateGst(workflowId: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('evaluate_gst_readiness', { p_workflow_id: workflowId, p_request_id: requestId });
    if (error) throw dbError('Could not evaluate GST readiness.', error); return data;
  }
  async createExport(workflowId: string, idempotencyKey: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('create_tally_csv_export', { p_workflow_id: workflowId, p_idempotency_key: idempotencyKey, p_request_id: requestId });
    if (error) throw dbError('Could not create Tally CSV export.', error); return data;
  }
  async listExports(companyId: string): Promise<Record<string, unknown>[]> {
    const { data, error } = await this.client.from('accounting_export_batches')
      .select('id,workflow_id,submission_id,export_type,schema_version,status,filename,checksum_sha256,item_count,totals_by_currency,created_at,completed_at,reconciliation_note,reconciled_at')
      .eq('company_id', companyId).order('created_at', { ascending: false });
    if (error) throw dbError('Could not list exports.', error); return (data ?? []) as Record<string, unknown>[];
  }
  async getExport(batchId: string): Promise<Record<string, unknown> | null> {
    const { data, error } = await this.client.from('accounting_export_batches')
      .select('id,company_id,workflow_id,submission_id,export_type,schema_version,status,content_type,filename,content,checksum_sha256,item_count,totals_by_currency,mapping_snapshot,gst_snapshot,created_at,completed_at,reconciliation_note,reconciled_at,items:accounting_export_items(position,claim_id,receipt_id,row_snapshot,row_text)')
      .eq('id', batchId).maybeSingle();
    if (error) throw dbError('Could not load export.', error); return (data as Record<string, unknown> | null) ?? null;
  }
  async reconcileExport(batchId: string, note: string | null, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('reconcile_accounting_export', { p_batch_id: batchId, p_note: note, p_request_id: requestId });
    if (error) throw dbError('Could not reconcile export.', error); return data;
  }
}
