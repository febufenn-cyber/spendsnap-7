import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { ExpenseClaimStatus, ExpenseReportStatus } from '../domain/expense';
import type { Env } from '../env';
import { AppError } from '../errors';
import type {
  CreateExpenseClaimInput,
  CreateExpenseReportInput,
  ExpenseRepository,
  UpdateExpenseClaimInput,
} from './expense-repository';

function userClient(env: Env, accessToken: string): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
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

const CLAIM_SELECT = [
  'id',
  'company_id',
  'employee_id',
  'receipt_id',
  'status',
  'merchant_name',
  'incurred_on',
  'currency',
  'amount',
  'business_purpose',
  'notes',
  'receipt_facts',
  'version',
  'created_at',
  'updated_at',
  'category:expense_categories(id,code,name,active)',
  'project:expense_projects(id,code,name,active)',
  'costCentre:expense_cost_centres(id,code,name,active)',
].join(',');

const REPORT_SELECT = [
  'id',
  'company_id',
  'employee_id',
  'status',
  'title',
  'period_start',
  'period_end',
  'version',
  'submitted_at',
  'withdrawn_at',
  'created_at',
  'updated_at',
].join(',');

export class SupabaseExpenseRepository implements ExpenseRepository {
  private readonly client: SupabaseClient;

  constructor(env: Env, accessToken: string) {
    this.client = userClient(env, accessToken);
  }

  async listDimensions(companyId: string): Promise<Record<string, unknown>> {
    const [categories, projects, costCentres] = await Promise.all([
      this.client
        .from('expense_categories')
        .select('id,code,name')
        .eq('company_id', companyId)
        .eq('active', true)
        .order('name'),
      this.client
        .from('expense_projects')
        .select('id,code,name')
        .eq('company_id', companyId)
        .eq('active', true)
        .order('name'),
      this.client
        .from('expense_cost_centres')
        .select('id,code,name')
        .eq('company_id', companyId)
        .eq('active', true)
        .order('name'),
    ]);

    for (const result of [categories, projects, costCentres]) {
      if (result.error) throw databaseError('Could not load expense dimensions.', result.error);
    }

    return {
      categories: categories.data ?? [],
      projects: projects.data ?? [],
      costCentres: costCentres.data ?? [],
    };
  }

  async createClaim(input: CreateExpenseClaimInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('create_expense_claim_from_receipt', {
      p_receipt_id: input.receiptId,
      p_category_id: input.categoryId,
      p_project_id: input.projectId,
      p_cost_centre_id: input.costCentreId,
      p_business_purpose: input.businessPurpose,
      p_notes: input.notes,
      p_request_id: input.requestId,
    });
    if (error) throw databaseError('Could not create the expense claim.', error);
    return data;
  }

  async updateClaim(input: UpdateExpenseClaimInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('update_expense_claim', {
      p_claim_id: input.claimId,
      p_expected_version: input.expectedVersion,
      p_patch: input.changes,
      p_request_id: input.requestId,
    });
    if (error) throw databaseError('Could not update the expense claim.', error);
    return data;
  }

  async getClaim(claimId: string): Promise<Record<string, unknown> | null> {
    const { data, error } = await this.client
      .from('expense_claims')
      .select(CLAIM_SELECT)
      .eq('id', claimId)
      .maybeSingle();
    if (error) throw databaseError('Could not load the expense claim.', error);
    return (data as Record<string, unknown> | null) ?? null;
  }

  async listClaims(companyId: string, status?: ExpenseClaimStatus): Promise<Record<string, unknown>[]> {
    const base = this.client
      .from('expense_claims')
      .select(CLAIM_SELECT)
      .eq('company_id', companyId);
    const { data, error } = status
      ? await base.eq('status', status).order('created_at', { ascending: false })
      : await base.order('created_at', { ascending: false });
    if (error) throw databaseError('Could not list expense claims.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async createReport(input: CreateExpenseReportInput): Promise<unknown> {
    const { data, error } = await this.client.rpc('create_expense_report', {
      p_company_id: input.companyId,
      p_title: input.title,
      p_period_start: input.periodStart,
      p_period_end: input.periodEnd,
      p_request_id: input.requestId,
    });
    if (error) throw databaseError('Could not create the expense report.', error);
    return data;
  }

  async getReport(reportId: string): Promise<Record<string, unknown> | null> {
    const { data: report, error: reportError } = await this.client
      .from('expense_reports')
      .select(REPORT_SELECT)
      .eq('id', reportId)
      .maybeSingle();
    if (reportError) throw databaseError('Could not load the expense report.', reportError);
    if (!report) return null;

    const [items, submissions] = await Promise.all([
      this.client
        .from('expense_report_items')
        .select(`position,added_at,claim:expense_claims(${CLAIM_SELECT})`)
        .eq('report_id', reportId)
        .order('position'),
      this.client
        .from('expense_report_submissions')
        .select('id,submission_number,snapshot,totals_by_currency,submitted_by,created_at')
        .eq('report_id', reportId)
        .order('submission_number', { ascending: false }),
    ]);
    if (items.error) throw databaseError('Could not load report items.', items.error);
    if (submissions.error) throw databaseError('Could not load report submissions.', submissions.error);

    return {
      ...(report as Record<string, unknown>),
      items: items.data ?? [],
      submissions: submissions.data ?? [],
    };
  }

  async listReports(companyId: string, status?: ExpenseReportStatus): Promise<Record<string, unknown>[]> {
    const base = this.client
      .from('expense_reports')
      .select(REPORT_SELECT)
      .eq('company_id', companyId);
    const { data, error } = status
      ? await base.eq('status', status).order('created_at', { ascending: false })
      : await base.order('created_at', { ascending: false });
    if (error) throw databaseError('Could not list expense reports.', error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async addClaim(reportId: string, claimId: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('add_claim_to_expense_report', {
      p_report_id: reportId,
      p_claim_id: claimId,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not add the claim to the report.', error);
    return data;
  }

  async removeClaim(reportId: string, claimId: string, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('remove_claim_from_expense_report', {
      p_report_id: reportId,
      p_claim_id: claimId,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not remove the claim from the report.', error);
    return data;
  }

  async submitReport(reportId: string, expectedVersion: number, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('submit_expense_report', {
      p_report_id: reportId,
      p_expected_version: expectedVersion,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not submit the expense report.', error);
    return data;
  }

  async withdrawReport(reportId: string, expectedVersion: number, requestId: string): Promise<unknown> {
    const { data, error } = await this.client.rpc('withdraw_expense_report', {
      p_report_id: reportId,
      p_expected_version: expectedVersion,
      p_request_id: requestId,
    });
    if (error) throw databaseError('Could not withdraw the expense report.', error);
    return data;
  }
}
