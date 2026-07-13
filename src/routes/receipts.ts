import { Hono } from 'hono';
import { z } from 'zod';
import { RECEIPT_SOURCES, SUPPORTED_RECEIPT_MEDIA_TYPES } from '../domain/receipt';
import type { AppBindings } from '../env';
import { positiveInteger } from '../env';
import { AppError } from '../errors';
import { CloudflareExtractionQueuePublisher } from '../queue/publisher';
import { SupabaseReceiptRepository, SupabaseServiceReceiptRepository } from '../repositories/supabase-receipt-repository';
import { SupabaseReviewRepository } from '../repositories/supabase-review-repository';
import { SupabaseStorageGateway } from '../storage/supabase-storage';

const uploadIntentSchema = z.object({
  companyId: z.string().uuid(),
  originalFilename: z.string().trim().min(1).max(180),
  mediaType: z.enum(SUPPORTED_RECEIPT_MEDIA_TYPES),
  sizeBytes: z.number().int().positive(),
  source: z.enum(RECEIPT_SOURCES),
  capturedAt: z.string().datetime({ offset: true }).nullable().optional(),
});

const completionSchema = z.object({
  clientSha256: z.string().regex(/^[a-fA-F0-9]{64}$/),
});

const correctionRequestSchema = z.object({
  corrections: z.array(z.object({
    fieldName: z.string().regex(/^[a-z][a-z0-9_]{1,79}$/),
    previousFieldId: z.string().uuid(),
    correctedValue: z.unknown(),
    reason: z.string().trim().max(1000).nullable().optional(),
  })).min(1).max(25),
});

const resolutionRequestSchema = z.object({
  decisions: z.array(z.object({
    fieldName: z.string().regex(/^[a-z][a-z0-9_]{1,79}$/),
    source: z.enum(['prediction', 'correction']),
    sourceId: z.string().uuid(),
  })).max(50),
  finalize: z.boolean().default(false),
});

function safeFilename(filename: string): string {
  const normalized = filename.normalize('NFKC').replace(/[^A-Za-z0-9._-]+/g, '-');
  const withoutLeadingDots = normalized.replace(/^\.+/, '');
  return (withoutLeadingDots || 'receipt').slice(-120);
}

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

export const receiptRoutes = new Hono<AppBindings>();

receiptRoutes.post('/upload-intents', async (context) => {
  const parsed = uploadIntentSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The upload intent is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const maxBytes = positiveInteger(context.env.MAX_RECEIPT_BYTES, 7_500_000);
  if (parsed.data.sizeBytes > maxBytes) {
    throw new AppError('payload_too_large', 413, `Receipt images must not exceed ${maxBytes} bytes.`);
  }

  const user = context.get('user');
  const accessToken = context.get('accessToken');
  const receiptId = crypto.randomUUID();
  const filename = safeFilename(parsed.data.originalFilename);
  const storagePath = `${parsed.data.companyId}/${receiptId}/${filename}`;

  const receiptRepository = new SupabaseReceiptRepository(context.env, accessToken);
  const storage = new SupabaseStorageGateway(context.env);

  const receipt = await receiptRepository.create({
    id: receiptId,
    companyId: parsed.data.companyId,
    submittedBy: user.id,
    storagePath,
    originalFilename: parsed.data.originalFilename,
    mediaType: parsed.data.mediaType,
    declaredSizeBytes: parsed.data.sizeBytes,
    source: parsed.data.source,
    capturedAt: parsed.data.capturedAt ?? null,
  });

  const upload = await storage.createSignedUpload(storagePath);

  return context.json(
    {
      receipt,
      upload: {
        path: upload.path,
        signedUrl: upload.signedUrl,
        token: upload.token,
        expiresInSeconds: 7200,
      },
    },
    201,
  );
});

receiptRoutes.post('/:receiptId/complete', async (context) => {
  const receiptId = context.req.param('receiptId');
  if (!z.string().uuid().safeParse(receiptId).success) {
    throw new AppError('bad_request', 400, 'The receipt ID is invalid.');
  }

  const parsed = completionSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The receipt completion payload is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const userRepository = new SupabaseReceiptRepository(context.env, context.get('accessToken'));
  const serviceRepository = new SupabaseServiceReceiptRepository(context.env);
  const storage = new SupabaseStorageGateway(context.env);
  const queue = new CloudflareExtractionQueuePublisher(context.env);

  const receipt = await userRepository.getById(receiptId);
  if (!receipt) {
    throw new AppError('not_found', 404, 'Receipt not found.');
  }

  await storage.assertObjectExists(receipt.storagePath);
  const received = await serviceRepository.markReceived(receipt.id, {
    clientSha256: parsed.data.clientSha256.toLowerCase(),
  });

  await queue.publish({
    receiptId: received.id,
    companyId: received.companyId,
    requestedBy: context.get('user').id,
    requestId: context.get('requestId'),
    enqueuedAt: new Date().toISOString(),
  });

  // The queue consumer owns the received → queued → extracting transition.
  // Keeping the receipt in `received` here makes a failed publish safely retryable
  // and avoids racing a fast consumer that has already moved it to `extracting`.
  return context.json({
    receipt: received,
    queue: { status: 'published' },
  }, 202);
});

receiptRoutes.get('/:receiptId/review', async (context) => {
  const receiptId = context.req.param('receiptId');
  if (!z.string().uuid().safeParse(receiptId).success) {
    throw new AppError('bad_request', 400, 'The receipt ID is invalid.');
  }

  const repository = new SupabaseReviewRepository(context.env, context.get('accessToken'));
  const review = await repository.getReceiptReview(receiptId);
  if (!review) throw new AppError('not_found', 404, 'Receipt not found.');

  return context.json({ review });
});

receiptRoutes.post('/:receiptId/corrections', async (context) => {
  const receiptId = context.req.param('receiptId');
  if (!z.string().uuid().safeParse(receiptId).success) {
    throw new AppError('bad_request', 400, 'The receipt ID is invalid.');
  }

  const parsed = correctionRequestSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The correction request is invalid.', {
      issues: parsed.error.issues,
    });
  }

  const repository = new SupabaseReviewRepository(context.env, context.get('accessToken'));
  const corrections = await repository.submitCorrections(
    receiptId,
    context.get('user').id,
    parsed.data.corrections.map((correction) => ({
      fieldName: correction.fieldName,
      previousFieldId: correction.previousFieldId,
      correctedValue: correction.correctedValue,
      reason: correction.reason ?? null,
    })),
  );

  return context.json({ corrections }, 201);
});

receiptRoutes.post('/:receiptId/resolutions', async (context) => {
  const receiptId = context.req.param('receiptId');
  if (!z.string().uuid().safeParse(receiptId).success) {
    throw new AppError('bad_request', 400, 'The receipt ID is invalid.');
  }

  const parsed = resolutionRequestSchema.safeParse(await jsonBody(context.req.raw));
  if (!parsed.success) {
    throw new AppError('bad_request', 400, 'The field-resolution request is invalid.', {
      issues: parsed.error.issues,
    });
  }
  if (!parsed.data.finalize && parsed.data.decisions.length === 0) {
    throw new AppError('bad_request', 400, 'At least one resolution decision is required.');
  }

  const repository = new SupabaseReviewRepository(context.env, context.get('accessToken'));
  const result = await repository.resolveFields(
    receiptId,
    parsed.data.decisions,
    parsed.data.finalize,
    context.get('requestId'),
  );

  return context.json({ result });
});

receiptRoutes.get('/:receiptId', async (context) => {
  const receiptId = context.req.param('receiptId');
  if (!z.string().uuid().safeParse(receiptId).success) {
    throw new AppError('bad_request', 400, 'The receipt ID is invalid.');
  }

  const repository = new SupabaseReceiptRepository(context.env, context.get('accessToken'));
  const receipt = await repository.getById(receiptId);
  if (!receipt) {
    throw new AppError('not_found', 404, 'Receipt not found.');
  }

  return context.json({ receipt });
});
