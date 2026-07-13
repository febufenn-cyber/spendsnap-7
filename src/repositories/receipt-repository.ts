import type { CreateReceiptInput, ReceiptRecord } from '../domain/receipt';

export interface CompleteReceiptInput {
  clientSha256: string;
}

export interface ReceiptRepository {
  create(input: CreateReceiptInput): Promise<ReceiptRecord>;
  getById(receiptId: string): Promise<ReceiptRecord | null>;
}

export interface ServiceReceiptRepository {
  markReceived(receiptId: string, input: CompleteReceiptInput): Promise<ReceiptRecord>;
  markQueued(receiptId: string): Promise<ReceiptRecord>;
}
