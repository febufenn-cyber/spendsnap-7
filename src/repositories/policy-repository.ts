import type {
  PolicyExceptionStatus,
  PolicyRuleType,
  PolicySeverity,
} from '../domain/policy';

export interface CreatePolicyRuleInput {
  companyId: string;
  code: string;
  name: string;
  description: string | null;
  ruleType: PolicyRuleType;
  severity: PolicySeverity;
  config: Record<string, unknown>;
  effectiveFrom: string | null;
  supersedesRuleId: string | null;
  requestId: string;
}

export interface ResolvePolicyExceptionInput {
  exceptionId: string;
  status: Extract<PolicyExceptionStatus, 'approved' | 'rejected'>;
  reviewNote: string | null;
  requestId: string;
}

export interface PolicyRepository {
  listRules(companyId: string, active?: boolean): Promise<Record<string, unknown>[]>;
  createRule(input: CreatePolicyRuleInput): Promise<unknown>;
  deactivateRule(ruleId: string, requestId: string): Promise<unknown>;
  evaluateReport(reportId: string, requestId: string): Promise<unknown>;
  getReportPolicy(reportId: string): Promise<Record<string, unknown> | null>;
  requestException(evaluationResultId: string, reason: string, requestId: string): Promise<unknown>;
  resolveException(input: ResolvePolicyExceptionInput): Promise<unknown>;
}
