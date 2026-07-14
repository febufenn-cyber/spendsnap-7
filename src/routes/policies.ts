import { Hono } from 'hono';
import { z } from 'zod';
import {
  POLICY_EXCEPTION_STATUSES,
  POLICY_RULE_TYPES,
  POLICY_SEVERITIES,
  validatePolicyRuleConfig,
} from '../domain/policy';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabasePolicyRepository } from '../repositories/supabase-policy-repository';

const uuid = z.string().uuid();
const ruleSchema = z.object({
  companyId: uuid,
  code: z.string().trim().regex(/^[a-z][a-z0-9_.-]{1,59}$/),
  name: z.string().trim().min(1).max(140),
  description: z.string().trim().max(1000).nullable().optional(),
  ruleType: z.enum(POLICY_RULE_TYPES),
  severity: z.enum(POLICY_SEVERITIES),
  config: z.record(z.string(), z.unknown()),
  effectiveFrom: z.string().datetime({ offset: true }).nullable().optional(),
  supersedesRuleId: uuid.nullable().optional(),
});
const exceptionSchema = z.object({ reason: z.string().trim().min(10).max(2000) });
const resolutionSchema = z.object({
  status: z.enum(POLICY_EXCEPTION_STATUSES).refine(
    (value): value is 'approved' | 'rejected' => value === 'approved' || value === 'rejected',
    'Only approved or rejected are valid review decisions.',
  ),
  reviewNote: z.string().trim().max(2000).nullable().optional(),
});

async function jsonBody(request: Request): Promise<unknown> {
  if (!(request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) {
    throw new AppError('bad_request', 400, 'The request body must be JSON.');
  }
  try {
    return await request.json();
  } catch (error) {
    throw new AppError('bad_request', 400, 'The JSON request body is invalid.', undefined, { cause: error });
  }
}

function requireUuid(value: string, label: string): string {
  if (!uuid.safeParse(value).success) throw new AppError('bad_request', 400, `${label} is invalid.`);
  return value;
}

export const policyRoutes = new Hono<AppBindings>();

policyRoutes.get('/rules', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const activeValue = context.req.query('active');
  if (activeValue !== undefined && activeValue !== 'true' && activeValue !== 'false') {
    throw new AppError('bad_request', 400, 'active must be true or false.');
  }
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  return context.json({
    rules: await repository.listRules(
      companyId,
      activeValue === undefined ? undefined : activeValue === 'true',
    ),
  });
});

policyRoutes.post('/rules', async (context) => {
  const parsed = ruleSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The policy rule is invalid.', { issues: parsed.error.issues });
  }
  const configIssues = validatePolicyRuleConfig(parsed.data.ruleType, parsed.data.config);
  if (configIssues.length > 0) {
    throw new AppError('bad_request', 400, 'The policy rule configuration is invalid.', {
      issues: configIssues,
    });
  }
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  const rule = await repository.createRule({
    companyId: parsed.data.companyId,
    code: parsed.data.code,
    name: parsed.data.name,
    description: parsed.data.description ?? null,
    ruleType: parsed.data.ruleType,
    severity: parsed.data.severity,
    config: parsed.data.config,
    effectiveFrom: parsed.data.effectiveFrom ?? null,
    supersedesRuleId: parsed.data.supersedesRuleId ?? null,
    requestId: context.get('requestId'),
  });
  return context.json({ rule }, 201);
});

policyRoutes.post('/rules/:ruleId/deactivate', async (context) => {
  const ruleId = requireUuid(context.req.param('ruleId'), 'Policy rule ID');
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  return context.json({
    rule: await repository.deactivateRule(ruleId, context.get('requestId')),
  });
});

policyRoutes.post('/reports/:reportId/evaluate', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  return context.json({
    evaluation: await repository.evaluateReport(reportId, context.get('requestId')),
  });
});

policyRoutes.get('/reports/:reportId', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  return context.json({ policy: await repository.getReportPolicy(reportId) });
});

policyRoutes.post('/results/:resultId/exceptions', async (context) => {
  const resultId = requireUuid(context.req.param('resultId'), 'Policy result ID');
  const parsed = exceptionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The exception request is invalid.', {
      issues: parsed.error.issues,
    });
  }
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  const exception = await repository.requestException(
    resultId,
    parsed.data.reason,
    context.get('requestId'),
  );
  return context.json({ exception }, 201);
});

policyRoutes.post('/exceptions/:exceptionId/resolve', async (context) => {
  const exceptionId = requireUuid(context.req.param('exceptionId'), 'Policy exception ID');
  const parsed = resolutionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The exception resolution is invalid.', {
      issues: parsed.error.issues,
    });
  }
  const repository = new SupabasePolicyRepository(context.env, context.get('accessToken'));
  return context.json({
    exception: await repository.resolveException({
      exceptionId,
      status: parsed.data.status,
      reviewNote: parsed.data.reviewNote ?? null,
      requestId: context.get('requestId'),
    }),
  });
});
