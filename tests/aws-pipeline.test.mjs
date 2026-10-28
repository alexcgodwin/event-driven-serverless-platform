import test from 'node:test';
import assert from 'node:assert/strict';
import { handler as ingest, parseRequest } from '../src/aws-ingest.mjs';
import { handler as worker } from '../src/aws-worker.mjs';

test('ingress requires bounded event identifiers and returns 202 on queue accept', async () => {
  const sent = [];
  const response = await ingest({ body: JSON.stringify({ id: 'event_123456', action: 'publish' }) }, { send: async x => sent.push(x) });
  assert.equal(response.statusCode, 202);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].id, 'event_123456');
});
test('rejects malformed and oversized payloads before queue invocation', async () => {
  let calls = 0;
  const send = async () => { calls++; };
  const invalid = [ { body: '{' }, { body: JSON.stringify({ id: 'x', action: 'a' }) }, { body: 'x'.repeat(32769) } ];
  for (const x of invalid) assert.equal((await ingest(x, { send })).statusCode, 400);
  assert.equal(calls, 0);
});
test('queue outage is retryable to authorized clients', async () => {
  assert.equal((await ingest({ body: JSON.stringify({ id: 'event_123456', action: 'publish' }) }, { send: async () => { throw new Error('offline'); } })).statusCode, 503);
});
test('worker records durable audit before marking id and treats duplicate as no-op', async () => {
  const seen = new Set(); const order = [];
  const deps = { exists: async id => seen.has(id), writeAudit: async (key) => order.push(key), markProcessed: async id => { seen.add(id); order.push('state:'+id); } };
  const record = { messageId: 'sqs_01', body: JSON.stringify({ id: 'event_123456', action: 'publish' }) };
  assert.deepEqual(await worker({ Records: [record] }, deps), { batchItemFailures: [] });
  assert.deepEqual(await worker({ Records: [record] }, deps), { batchItemFailures: [] });
  assert.deepEqual(order, ['events/event_123456.json', 'state:event_123456']);
});
test('worker identifies only failed items for SQS partial batch retry', async () => {
  const deps = { exists: async () => false, writeAudit: async () => { throw new Error('unavailable'); }, markProcessed: async () => {} };
  const result = await worker({ Records: [{ messageId: 'broken', body: JSON.stringify({ id: 'event_123456', action: 'publish' }) }] }, deps);
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: 'broken' }] });
});
