export interface FinanceRepository {
  listWorkflows(companyId: string, status?: string): Promise<Record<string, unknown>[]>;
  getWorkspace(companyId: string): Promise<Record<string, unknown>>;
  evaluateGst(workflowId: string, requestId: string): Promise<unknown>;
  createExport(workflowId: string, idempotencyKey: string, requestId: string): Promise<unknown>;
  listExports(companyId: string): Promise<Record<string, unknown>[]>;
  getExport(batchId: string): Promise<Record<string, unknown> | null>;
  reconcileExport(batchId: string, note: string | null, requestId: string): Promise<unknown>;
}
