import { Hono } from 'hono';
import { z } from 'zod';
import { EXPENSE_CLAIM_STATUSES, EXPENSE_REPORT_STATUSES } from '../domain/expense';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseExpenseRepository } from '../repositories/supabase-expense-repository';

const uuid = z.string().uuid();
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const createClaimSchema = z.object({
  receiptId: uuid,
  categoryId: uuid,
  projectId: uuid.nullable().optional(),
  costCentreId: uuid.nullable().optional(),
  businessPurpose: z.string().trim().min(3).max(1000),
  notes: z.string().trim().max(2000).nullable().optional(),
});

const updateClaimSchema = z.object({
  expectedVersion: z.number().int().positive(),
  changes: z.object({
    categoryId: uuid.optional(),
    projectId: uuid.nullable().optional(),
    costCentreId: uuid.nullable().optional(),
    businessPurpose: z.string().trim().min(3).max(1000).optional(),
    notes: z.string().trim().max(2000).nullable().optional(),
  }).refine((value) => Object.keys(value).length > 0, 'At least one claim field must change.'),
});

const createReportSchema = z.object({
  companyId: uuid,
  title: z.string().trim().min(1).max(160),
  periodStart: isoDate,
  periodEnd: isoDate,
});

const addItemSchema = z.object({
  claimId: uuid,
  expectedVersion: z.number().int().positive(),
});
const versionSchema = z.object({ expectedVersion: z.number().int().positive() });

async function jsonBody(request: Request): Promise<unknown> {
  const contentType = request.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().includes('application/json')) {
    throw new AppError('bad_request', 400, 'The request body must be JSON.');
  }
  try {
    return await request.json();
  } catch (error) {
    throw new AppError('bad_request', 400, 'The JSON request body is invalid.', undefined, {
      cause: error,
    });
  }
}

function requireUuid(value: string, label: string): string {
  if (!uuid.safeParse(value).success) {
    throw new AppError('bad_request', 400, `${label} is invalid.`);
  }
  return value;
}

function requireVersion(value: string | undefined): number {
  const parsed = z.coerce.number().int().positive().safeParse(value);
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'Expected version is invalid.');
  }
  return parsed.data;
}

export const expenseRoutes = new Hono<AppBindings>();

expenseRoutes.get('/dimensions', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  return context.json({ dimensions: await repository.listDimensions(companyId) });
});

expenseRoutes.post('/claims/from-receipt', async (context) => {
  const parsed = createClaimSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The expense claim is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const claim = await repository.createClaim({
    receiptId: parsed.data.receiptId,
    categoryId: parsed.data.categoryId,
    projectId: parsed.data.projectId ?? null,
    costCentreId: parsed.data.costCentreId ?? null,
    businessPurpose: parsed.data.businessPurpose,
    notes: parsed.data.notes ?? null,
    requestId: context.get('requestId'),
  });
  return context.json({ claim }, 201);
});

expenseRoutes.get('/claims', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const status = context.req.query('status');
  const parsedStatus = z.enum(EXPENSE_CLAIM_STATUSES).safeParse(status);
  if (status && !parsedStatus.success) {
    throw new AppError('bad_request', 400, 'Claim status is invalid.');
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  return context.json({
    claims: await repository.listClaims(
      companyId,
      parsedStatus.success ? parsedStatus.data : undefined,
    ),
  });
});

expenseRoutes.get('/claims/:claimId', async (context) => {
  const claimId = requireUuid(context.req.param('claimId'), 'Claim ID');
  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const claim = await repository.getClaim(claimId);
  if (!claim) throw new AppError('not_found', 404, 'Expense claim not found.');
  return context.json({ claim });
});

expenseRoutes.patch('/claims/:claimId', async (context) => {
  const claimId = requireUuid(context.req.param('claimId'), 'Claim ID');
  const parsed = updateClaimSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The claim update is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const claim = await repository.updateClaim({
    claimId,
    expectedVersion: parsed.data.expectedVersion,
    changes: parsed.data.changes,
    requestId: context.get('requestId'),
  });
  return context.json({ claim });
});

expenseRoutes.post('/reports', async (context) => {
  const parsed = createReportSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The expense report is invalid.', {
      issues: parsed.error.issues,
    });
  }
  if (parsed.data.periodEnd < parsed.data.periodStart) {
    throw new AppError('bad_request', 400, 'Report period end must not precede its start.');
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const report = await repository.createReport({
    companyId: parsed.data.companyId,
    title: parsed.data.title,
    periodStart: parsed.data.periodStart,
    periodEnd: parsed.data.periodEnd,
    requestId: context.get('requestId'),
  });
  return context.json({ report }, 201);
});

expenseRoutes.get('/reports', async (context) => {
  const companyId = requireUuid(context.req.query('companyId') ?? '', 'Company ID');
  const status = context.req.query('status');
  const parsedStatus = z.enum(EXPENSE_REPORT_STATUSES).safeParse(status);
  if (status && !parsedStatus.success) {
    throw new AppError('bad_request', 400, 'Report status is invalid.');
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  return context.json({
    reports: await repository.listReports(
      companyId,
      parsedStatus.success ? parsedStatus.data : undefined,
    ),
  });
});

expenseRoutes.get('/reports/:reportId', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const report = await repository.getReport(reportId);
  if (!report) throw new AppError('not_found', 404, 'Expense report not found.');
  return context.json({ report });
});

expenseRoutes.post('/reports/:reportId/items', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const parsed = addItemSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The report item is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const item = await repository.addClaim(
    reportId,
    parsed.data.claimId,
    parsed.data.expectedVersion,
    context.get('requestId'),
  );
  return context.json({ item }, 201);
});

expenseRoutes.delete('/reports/:reportId/items/:claimId', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const claimId = requireUuid(context.req.param('claimId'), 'Claim ID');
  const expectedVersion = requireVersion(context.req.query('expectedVersion'));
  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const result = await repository.removeClaim(
    reportId,
    claimId,
    expectedVersion,
    context.get('requestId'),
  );
  return context.json({ result });
});

expenseRoutes.post('/reports/:reportId/submit', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const parsed = versionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The submission request is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const result = await repository.submitReport(
    reportId,
    parsed.data.expectedVersion,
    context.get('requestId'),
  );
  return context.json({ result });
});

expenseRoutes.post('/reports/:reportId/withdraw', async (context) => {
  const reportId = requireUuid(context.req.param('reportId'), 'Report ID');
  const parsed = versionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The withdrawal request is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseExpenseRepository(context.env, context.get('accessToken'));
  const result = await repository.withdrawReport(
    reportId,
    parsed.data.expectedVersion,
    context.get('requestId'),
  );
  return context.json({ result });
});
