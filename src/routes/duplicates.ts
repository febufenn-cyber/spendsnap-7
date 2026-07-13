import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '../env';
import { AppError } from '../errors';
import { SupabaseReviewRepository } from '../repositories/supabase-review-repository';

const duplicateResolutionSchema = z.object({
  resolution: z.enum(['confirmed_duplicate', 'not_duplicate', 'allowed_exception']),
  note: z.string().trim().max(1000).nullable().optional(),
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

export const duplicateRoutes = new Hono<AppBindings>();

duplicateRoutes.post('/:candidateId/resolve', async (context) => {
  const candidateId = context.req.param('candidateId');
  if (!z.string().uuid().safeParse(candidateId).success) {
    throw new AppError('bad_request', 400, 'The duplicate candidate ID is invalid.');
  }

  const parsed = duplicateResolutionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The duplicate resolution is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseReviewRepository(context.env, context.get('accessToken'));
  const result = await repository.resolveDuplicate(
    candidateId,
    parsed.data.resolution,
    parsed.data.note ?? null,
    context.get('requestId'),
  );

  return context.json({ result });
});
