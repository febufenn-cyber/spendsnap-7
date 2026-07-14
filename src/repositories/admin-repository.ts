export interface AdminRepository {
  getOverview(companyId: string): Promise<Record<string, unknown>>;
  updateSecuritySettings(companyId: string, expectedVersion: number, patch: Record<string, unknown>, requestId: string): Promise<unknown>;
  invite(companyId: string, email: string, role: string, expiresHours: number, requestId: string): Promise<unknown>;
  acceptInvitation(token: string, requestId: string): Promise<unknown>;
  changeMember(companyId: string, userId: string, role: string, active: boolean, requestId: string): Promise<unknown>;
  requestDeletion(companyId: string, scope: string, subjectUserId: string | null, receiptId: string | null, reason: string, requestId: string): Promise<unknown>;
  createAuditExport(companyId: string, periodStart: string, periodEnd: string, requestId: string): Promise<unknown>;
}
