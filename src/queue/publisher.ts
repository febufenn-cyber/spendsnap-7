import type { Env } from '../env';
import { AppError } from '../errors';
import type { ExtractionJob } from './contracts';

export interface ExtractionQueuePublisher {
  publish(job: ExtractionJob): Promise<void>;
}

export class CloudflareExtractionQueuePublisher implements ExtractionQueuePublisher {
  constructor(private readonly env: Env) {}

  async publish(job: ExtractionJob): Promise<void> {
    try {
      await this.env.EXTRACTION_QUEUE.send(job, {
        contentType: 'json',
      });
    } catch (error) {
      throw new AppError('queue_error', 502, 'Could not queue receipt extraction.', undefined, {
        cause: error,
      });
    }
  }
}
