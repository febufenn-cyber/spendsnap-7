import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { ApprovalStage } from '../domain/approval';
import type { Env } from '../env';
import { AppError } from '../errors';
import type { ApprovalDecisionInput, ApprovalRepository } from './approval-repository';

function clientFor(env: Env, token: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

function dbError(message: string, error: { code?: string; message?: string } | null): AppError {
  if (error?.code === '42501') return new AppError('forbidden', 403, error.message || message);
  if (error?.code === 'P0002') return new AppError('not_found', 404, error.message || message);
  if (['23505', '23514', 'P0001', '40001'].includes(error?.code ?? '')) {
    return new AppError('conflict', 409, error?.message || message);
  }
  return new AppError('database_error', 502, message, undefined, { cause: error });
}

export class SupabaseApprovalRepository implements ApprovalRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env, token: string) {
    this.client = clientFor(env, token);
  }

  async listAssignments(stage?: ApprovalStage): Promise<Record<string, unknown>[]> {
    let query = this.client
      .from('approval_assignments')
      .select('id,workflow_id,company_id,stage,assigned_to,delegated_from,status,due_at,created_at,workflow:approval_workflows(id,report_id,submission_id,submission_number,employee_id,status,version,current_stage,created_at)')
      .eq('status', 'pending');
    if (stage) query = query.eq('stage', stage);
    const { data, error } = await query.order('created_at');
    if (error) throw dbError('Could not list approval assignments.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async getWorkflow(workflowId: string): Promise<Record<string, unknown> | null> {
    const { data: workflow, error } = await this.client
      .from('approval_workflows')
      .select('id,company_id,report_id,submission_id,submission_number,employee_id,status,version,current_stage,manager_approved_at,finance_approved_at,closed_at,created_at,updated_at')
      .eq('id', workflowId)
      .maybeSingle();
    if (error) throw dbError('Could not load approval workflow.', error);
    if (!workflow) return null;
    const [assignments, decisions, report] = await Promise.all([
      this.client.from('approval_assignments').select('*').eq('workflow_id', workflowId).order('created_at'),
      this.client.from('approval_decisions').select('*').eq('workflow_id', workflowId).order('created_at'),
      this.client.from('expense_reports').select('id,title,period_start,period_end,status,version,employee_id,expense_report_submissions(id,submission_number,snapshot,totals_by_currency,created_at)').eq('id', workflow.report_id).maybeSingle(),
    ]);
    for (const result of [assignments, decisions, report]) {
      if (result.error) throw dbError('Could not load complete approval evidence.', result.error);
    }
    return { ...workflow, assignments: assignments.data ?? [], decisions: decisions.data ?? [], report: report.data } as Record<string, unknown>;
  }

  async decide(input: ApprovalDecisionInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('decide_approval_workflow', {
      p_workflow_id: input.workflowId,
      p_expected_version: input.expectedVersion,
      p_action: input.action,
      p_note: input.note,
      p_claim_id: input.claimId,
      p_idempotency_key: input.idempotencyKey,
      p_request_id: input.requestId,
    });
    if (error) throw dbError('Could not record the approval decision.', error);
    return data;
  }

  async startRevision(workflowId: string, expectedVersion: number, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('start_report_revision', {
      p_workflow_id: workflowId,
      p_expected_version: expectedVersion,
      p_request_id: requestId,
    });
    if (error) throw dbError('Could not start a report revision.', error);
    return data;
  }

  async listNotifications(companyId: string): Promise<Record<string, unknown>[]> {
    const { data, error } = await this.client
      .from('notification_outbox')
      .select('id,event_key,event_type,recipient_user_id,channel,payload,status,attempt_count,available_at,delivered_at,last_error,created_at')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false });
    if (error) throw dbError('Could not list notification outbox records.', error);
    return (data ?? []) as Record<string, unknown>[];
  }
}
