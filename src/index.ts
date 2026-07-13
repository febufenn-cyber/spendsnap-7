import { createApp } from './app';
import type { Env } from './env';
import type { ExtractionJob } from './queue/contracts';

const app = createApp();

export default {
  fetch: app.fetch,
  async queue(batch: MessageBatch<ExtractionJob>, _env: Env): Promise<void> {
    // The extraction consumer is implemented in the next Phase 1 slice.
    // Retrying here prevents a deployed intake API from silently discarding jobs.
    for (const message of batch.messages) {
      message.retry({ delaySeconds: 60 });
    }
  },
};
