import { readFile } from 'node:fs/promises';
import process from 'node:process';
import { evaluateCorpus } from '../dist/evaluation/metrics.js';

function usage() {
  console.error('Usage: npm run evaluate -- <expected.jsonl> <actual.jsonl> [report.json]');
}

async function readJsonLines(path) {
  const text = await readFile(path, 'utf8');
  const records = [];
  const ids = new Set();

  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (!line.trim()) continue;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      throw new Error(`${path}:${index + 1} is not valid JSON`, { cause: error });
    }
    if (!parsed || typeof parsed.receiptId !== 'string' || !parsed.fields || typeof parsed.fields !== 'object') {
      throw new Error(`${path}:${index + 1} must contain receiptId and fields`);
    }
    if (ids.has(parsed.receiptId)) throw new Error(`${path} contains duplicate receiptId ${parsed.receiptId}`);
    ids.add(parsed.receiptId);
    records.push({ receiptId: parsed.receiptId, fields: parsed.fields });
  }
  return records;
}

const [, , expectedPath, actualPath, reportPath] = process.argv;
if (!expectedPath || !actualPath) {
  usage();
  process.exitCode = 1;
} else {
  const [expected, actual] = await Promise.all([
    readJsonLines(expectedPath),
    readJsonLines(actualPath),
  ]);
  const report = {
    generatedAt: new Date().toISOString(),
    expectedPath,
    actualPath,
    ...evaluateCorpus(expected, actual),
  };
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (reportPath) {
    const { writeFile } = await import('node:fs/promises');
    await writeFile(reportPath, output, 'utf8');
  }
  process.stdout.write(output);

  const minimumCriticalAccuracy = Number(process.env.MIN_CRITICAL_ACCURACY ?? '0');
  const minimumOverallCoverage = Number(process.env.MIN_OVERALL_COVERAGE ?? '0');
  if (
    report.critical.exactAccuracy < minimumCriticalAccuracy
    || report.overall.coverage < minimumOverallCoverage
  ) {
    process.exitCode = 2;
  }
}
