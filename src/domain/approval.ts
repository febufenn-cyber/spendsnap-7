export const APPROVAL_WORKFLOW_STATUSES = [
  'manager_review',
  'manager_changes_requested',
  'manager_approved',
  'finance_review',
  'finance_changes_requested',
  'finance_approved',
  'rejected',
  'superseded',
] as const;
export const APPROVAL_ACTIONS = ['approve', 'request_changes', 'reject', 'comment'] as const;
export const APPROVAL_STAGES = ['manager', 'finance'] as const;

export type ApprovalWorkflowStatus = (typeof APPROVAL_WORKFLOW_STATUSES)[number];
export type ApprovalAction = (typeof APPROVAL_ACTIONS)[number];
export type ApprovalStage = (typeof APPROVAL_STAGES)[number];

const terminal = new Set<ApprovalWorkflowStatus>(['finance_approved', 'rejected', 'superseded']);

export interface ApprovalTransitionInput {
  status: ApprovalWorkflowStatus;
  stage: ApprovalStage | null;
  action: ApprovalAction;
  actorId: string;
  employeeId: string;
  note: string | null;
}

export interface ApprovalTransitionResult {
  allowed: boolean;
  nextStatus: ApprovalWorkflowStatus;
  nextStage: ApprovalStage | null;
  issue: string | null;
}

export function evaluateApprovalTransition(input: ApprovalTransitionInput): ApprovalTransitionResult {
  if (input.actorId === input.employeeId) {
    return { allowed: false, nextStatus: input.status, nextStage: input.stage, issue: 'self_approval_forbidden' };
  }
  if (terminal.has(input.status) || input.stage == null) {
    return { allowed: false, nextStatus: input.status, nextStage: input.stage, issue: 'workflow_closed' };
  }
  if (input.action === 'comment') {
    return { allowed: true, nextStatus: input.status, nextStage: input.stage, issue: null };
  }
  if ((input.action === 'request_changes' || input.action === 'reject')
    && (input.note ?? '').trim().length < 3) {
    return { allowed: false, nextStatus: input.status, nextStage: input.stage, issue: 'reason_required' };
  }
  if (input.action === 'reject') {
    return { allowed: true, nextStatus: 'rejected', nextStage: null, issue: null };
  }
  if (input.action === 'request_changes') {
    return {
      allowed: true,
      nextStatus: input.stage === 'manager' ? 'manager_changes_requested' : 'finance_changes_requested',
      nextStage: null,
      issue: null,
    };
  }
  if (input.stage === 'manager') {
    return { allowed: true, nextStatus: 'finance_review', nextStage: 'finance', issue: null };
  }
  return { allowed: true, nextStatus: 'finance_approved', nextStage: null, issue: null };
}

export function delegationIsActive(startsAt: string, endsAt: string, at: string): boolean {
  const start = Date.parse(startsAt);
  const end = Date.parse(endsAt);
  const current = Date.parse(at);
  if (![start, end, current].every(Number.isFinite)) return false;
  return start <= current && current < end;
}
