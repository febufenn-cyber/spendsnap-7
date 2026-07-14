import type { ApprovalAction, ApprovalStage } from '../domain/approval';

export interface ApprovalDecisionInput {
  workflowId: string;
  expectedVersion: number;
  action: ApprovalAction;
  note: string | null;
  claimId: string | null;
  idempotencyKey: string;
  requestId: string;
}

export interface ApprovalRepository {
  listAssignments(stage?: ApprovalStage): Promise<Record<string, unknown>[]>;
  getWorkflow(workflowId: string): Promise<Record<string, unknown> | null>;
  decide(input: ApprovalDecisionInput): Promise<unknown>;
  startRevision(workflowId: string, expectedVersion: number, requestId: string): Promise<unknown>;
  listNotifications(companyId: string): Promise<Record<string, unknown>[]>;
}
