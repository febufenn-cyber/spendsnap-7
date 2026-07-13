# Receipt evaluation data

This directory contains schemas and manifests only. Do not commit real customer receipts or identifiable financial records.

## Recommended storage

Store source images in a private, access-controlled bucket outside Git. Assign each document an opaque `receipt_id` and keep the identity mapping in a separately restricted system.

## Gold dataset

A gold record should be verified by a human reviewer and stored as one JSON object per line:

```json
{"receiptId":"opaque-id","fields":{"merchant_name":"Example Hotel","invoice_date":"2026-07-13","currency":"INR","subtotal":"1000.00","cgst":"90.00","sgst":"90.00","total":"1180.00"}}
```

The actual extraction file uses the same shape. Run:

```bash
npm run evaluate -- research/gold.jsonl research/actual.jsonl research/report.json
```

Optional release gates:

```bash
MIN_CRITICAL_ACCURACY=0.98 MIN_OVERALL_COVERAGE=0.95 \
  npm run evaluate -- research/gold.jsonl research/actual.jsonl
```

Never use the evaluation dataset to claim tax eligibility or fraud detection performance unless those labels were designed and independently reviewed for that purpose.
