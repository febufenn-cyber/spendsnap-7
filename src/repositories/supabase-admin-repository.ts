import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../env';
import { AppError } from '../errors';
import type { AdminRepository } from './admin-repository';

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

export class SupabaseAdminRepository implements AdminRepository {
  private readonly client: SupabaseClient;
  constructor(env: Env, token: string) { this.client = clientFor(env, token); }
  async getOverview(companyId: string): Promise<Record<string, unknown>> {
    const [settings, members, invitations, grants, deletions, events, auditExports] = await Promise.all([
      this.client.from('company_security_settings').select('*').eq('company_id', companyId).maybeSingle(),
      this.client.from('company_memberships').select('company_id,user_id,role,active,created_at,updated_at').eq('company_id', companyId).order('created_at'),
      this.client.from('company_invitations').select('id,email,role,status,expires_at,invited_by,accepted_by,accepted_at,created_at').eq('company_id', companyId).order('created_at', { ascending: false }),
      this.client.from('support_access_grants').select('*').eq('company_id', companyId).order('created_at', { ascending: false }),
      this.client.from('data_deletion_requests').select('*').eq('company_id', companyId).order('requested_at', { ascending: false }),
      this.client.from('security_events').select('*').eq('company_id', companyId).order('created_at', { ascending: false }).limit(100),
      this.client.from('audit_export_runs').select('id,period_start,period_end,status,checksum_sha256,created_by,created_at').eq('company_id', companyId).order('created_at', { ascending: false }),
    ]);
    for (const result of [settings, members, invitations, grants, deletions, events, auditExports]) if (result.error) throw dbError('Could not load administration workspace.', result.error);
    return { settings: settings.data, members: members.data ?? [], invitations: invitations.data ?? [], supportGrants: grants.data ?? [], deletionRequests: deletions.data ?? [], securityEvents: events.data ?? [], auditExports: auditExports.data ?? [] };
  }
  private async rpc(name: string, args: Record<string, unknown>, message: string): Promise<unknown> {
    const { data, error } = await this.client.rpc(name, args); if (error) throw dbError(message, error); return data;
  }
  updateSecuritySettings(companyId: string, expectedVersion: number, patch: Record<string, unknown>, requestId: string) { return this.rpc('update_company_security_settings', { p_company_id: companyId, p_expected_version: expectedVersion, p_patch: patch, p_request_id: requestId }, 'Could not update security settings.'); }
  invite(companyId: string, email: string, role: string, expiresHours: number, requestId: string) { return this.rpc('invite_company_member', { p_company_id: companyId, p_email: email, p_role: role, p_expires_hours: expiresHours, p_request_id: requestId }, 'Could not create invitation.'); }
  acceptInvitation(token: string, requestId: string) { return this.rpc('accept_company_invitation', { p_token: token, p_request_id: requestId }, 'Could not accept invitation.'); }
  changeMember(companyId: string, userId: string, role: string, active: boolean, requestId: string) { return this.rpc('change_company_member_role', { p_company_id: companyId, p_user_id: userId, p_role: role, p_active: active, p_request_id: requestId }, 'Could not change membership.'); }
  requestDeletion(companyId: string, scope: string, subjectUserId: string | null, receiptId: string | null, reason: string, requestId: string) { return this.rpc('request_data_deletion', { p_company_id: companyId, p_scope: scope, p_subject_user_id: subjectUserId, p_receipt_id: receiptId, p_reason: reason, p_request_id: requestId }, 'Could not request data deletion.'); }
  createAuditExport(companyId: string, periodStart: string, periodEnd: string, requestId: string) { return this.rpc('create_audit_export', { p_company_id: companyId, p_period_start: periodStart, p_period_end: periodEnd, p_request_id: requestId }, 'Could not create audit export.'); }
}
