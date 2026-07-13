import type { ExpenseClaimStatus, ExpenseReportStatus } from '../domain/expense';

export interface CreateExpenseClaimInput {
  receiptId: string;
  categoryId: string;
  projectId: string | null;
  costCentreId: string | null;
  businessPurpose: string;
  notes: string | null;
  requestId: string;
}

export interface UpdateExpenseClaimInput {
  claimId: string;
  expectedVersion: number;
  changes: Record<string, unknown>;
  requestId: string;
}

export interface CreateExpenseReportInput {
  companyId: string;
  title: string;
  periodStart: string;
  periodEnd: string;
  requestId: string;
}

export interface ExpenseRepository {
  listDimensions(companyId: string): Promise<Record<string, unknown>>;
  createClaim(input: CreateExpenseClaimInput): Promise<unknown>;
  updateClaim(input: UpdateExpenseClaimInput): Promise<unknown>;
  getClaim(claimId: string): Promise<Record<string, unknown> | null>;
  listClaims(companyId: string, status?: ExpenseClaimStatus): Promise<Record<string, unknown>[]>;
  createReport(input: CreateExpenseReportInput): Promise<unknown>;
  getReport(reportId: string): Promise<Record<string, unknown> | null>;
  listReports(companyId: string, status?: ExpenseReportStatus): Promise<Record<string, unknown>[]>;
  addClaim(reportId: string, claimId: string, expectedVersion: number, requestId: string): Promise<unknown>;
  removeClaim(reportId: string, claimId: string, expectedVersion: number, requestId: string): Promise<unknown>;
  submitReport(reportId: string, expectedVersion: number, requestId: string): Promise<unknown>;
  withdrawReport(reportId: string, expectedVersion: number, requestId: string): Promise<unknown>;
}
