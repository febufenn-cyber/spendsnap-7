import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';
import type {
  CreatePolicyRuleInput,
  PolicyRepository,
  ResolvePolicyExceptionInput,
} from './policy-repository';

function userClient(env: Env, accessToken: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

function databaseError(message: string, error: { code?: string; message?: string } | null): AppError {
  if (error?.code === '42501') return new AppError('forbidden', 403, error.message || message);
  if (error?.code === 'P0002') return new AppError('not_found', 404, error.message || message);
  if (error?.code === '22P02') return new AppError('bad_request', 400, error.message || message);
  if (['23505', '23514', 'P0001', '40001'].includes(error?.code ?? '')) {
    return new AppError('conflict', 409, error?.message || message);
  }
  return new AppError('database_error', 502, message, undefined, { cause: error });
}

const RULE_SELECT = [
  'id', 'company_id', 'code', 'name', 'description', 'rule_type', 'severity', 'config',
  'version', 'active', 'effective_from', 'effective_to', 'supersedes_rule_id',
  'created_by', 'created_at', 'updated_at',
].join(',');

export class SupabasePolicyRepository implements PolicyRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env, accessToken: string) {
    this.client = userClient(env, accessToken);
  }

  async listRules(companyId: string, active?: boolean): Promise<Record<string, unknown>[]> {
    const query = this.client.from('expense_policy_rules').select(RULE_SELECT).eq('company_id', companyId);
    const { data, error } = active === undefined
      ? await query.order('code').order('version', { ascending: false })
      : await query.eq('active', active).order('code').order('version', { ascending: false });
    if (error) throw databaseError('Could not list policy rules.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async createRule(input: CreatePolicyRuleInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('create_expense_policy_rule', {
      p_company_id: input.companyId,
      p_code: input.code,
      p_name: input.name,
      p_description: input.description,
      p_rule_type: input.ruleType,
      p_severity: input.severity,
      p_config: input.config,
      p_effective_from: input.effectiveFrom,
      p_supersedes_rule_id: input.supersedesRuleId,
      p_request_id: input.requestId,
    });
    if (error) throw databaseError('Could not create the policy rule.', error);
    return data;
  }

  async deactivateRule(ruleId: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('deactivate_expense_policy_rule', {
      p_rule_id: ruleId,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not deactivate the policy rule.', error);
    return data;
  }

  async evaluateReport(reportId: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('evaluate_expense_report_policy', {
      p_report_id: reportId,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not evaluate the report policy.', error);
    return data;
  }

  async getReportPolicy(reportId: string): Promise<Record<string, unknown> | null> {
    const { data: runs, error: runError } = await this.client
      .from('policy_evaluation_runs')
      .select('id,company_id,report_id,report_version,evaluated_on,rules_snapshot,policy_set_hash,outcome,counts,request_id,created_at,completed_at')
      .eq('report_id', reportId)
      .order('created_at', { ascending: false });
    if (runError) throw databaseError('Could not load policy evaluations.', runError);
    if (!runs?.length) return null;

    const runIds = runs.map((run) => run.id as string);
    const [results, exceptions] = await Promise.all([
      this.client
        .from('policy_evaluation_results')
        .select('id,run_id,claim_id,rule_id,rule_code,rule_version,severity,outcome,explanation,evidence,created_at')
        .in('run_id', runIds)
        .order('created_at'),
      this.client
        .from('policy_exception_requests')
        .select('id,report_id,claim_id,rule_id,evaluation_result_id,employee_id,report_version_at_request,claim_version_at_request,status,reason,reviewed_by,review_note,reviewed_at,created_at,updated_at')
        .eq('report_id', reportId)
        .order('created_at', { ascending: false }),
    ]);
    if (results.error) throw databaseError('Could not load policy results.', results.error);
    if (exceptions.error) throw databaseError('Could not load policy exceptions.', exceptions.error);
    return { runs, results: results.data ?? [], exceptions: exceptions.data ?? [] };
  }

  async requestException(evaluationResultId: string, reason: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('request_policy_exception', {
      p_evaluation_result_id: evaluationResultId,
      p_reason: reason,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not request the policy exception.', error);
    return data;
  }

  async resolveException(input: ResolvePolicyExceptionInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('resolve_policy_exception', {
      p_exception_id: input.exceptionId,
      p_status: input.status,
      p_review_note: input.reviewNote,
      p_request_id: input.requestId,
    });
    if (error) throw databaseError('Could not resolve the policy exception.', error);
    return data;
  }
}
