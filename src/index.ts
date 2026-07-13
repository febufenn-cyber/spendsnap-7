import { createApp } from './app';
import type { Env } from './env';
import { isAppError } from './errors';
import { ReceiptExtractionProcessor } from './extraction/processor';
import type { ExtractionJob } from './queue/contracts';

const app = createApp();

export default {
  fetch: app.fetch,
  async queue(batch: MessageBatch<ExtractionJob>, env: Env): Promise<void> {
    const processor = new ReceiptExtractionProcessor(env);

    for (const message of batch.messages) {
      try {
        const outcome = await processor.process(message.body);
        console.log(JSON.stringify({
          level: 'info',
          event: 'receipt_extraction_message_completed',
          messageId: message.id,
          receiptId: outcome.receiptId,
          runId: outcome.runId ?? null,
          outcome: outcome.status,
          reason: outcome.reason ?? null,
        }));
        message.ack();
      } catch (error) {
        const retryable = !isAppError(error) || error.status >= 500;
        console.error(JSON.stringify({
          level: 'error',
          event: 'receipt_extraction_message_failed',
          messageId: message.id,
          receiptId: message.body.receiptId,
          retryable,
          code: isAppError(error) ? error.code : 'internal_error',
        }));

        if (retryable) {
          message.retry({ delaySeconds: 60 });
        } else {
          message.ack();
        }
      }
    }
  },
};
