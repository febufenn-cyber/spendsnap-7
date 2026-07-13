import type { ReceiptStatus } from './receipt';

const TRANSITIONS: Record<ReceiptStatus, readonly ReceiptStatus[]> = {
  upload_pending: ['received', 'rejected', 'archived'],
  received: ['queued', 'rejected', 'archived'],
  queued: ['extracting', 'failed', 'rejected', 'archived'],
  extracting: ['extracted', 'needs_review', 'failed'],
  extracted: ['needs_review', 'verified', 'failed', 'archived'],
  needs_review: ['verified', 'rejected', 'archived'],
  verified: ['archived'],
  failed: ['queued', 'rejected', 'archived'],
  rejected: ['archived'],
  archived: [],
};

export function canTransition(from: ReceiptStatus, to: ReceiptStatus): boolean {
  return from === to || TRANSITIONS[from].includes(to);
}

export function allowedTransitions(from: ReceiptStatus): readonly ReceiptStatus[] {
  return TRANSITIONS[from];
}
