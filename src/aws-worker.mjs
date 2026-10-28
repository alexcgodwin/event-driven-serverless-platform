// Idempotent audit model: deterministic S3 key, conditional DynamoDB record, no automatic DLQ replay.
// A write failure returns the SQS record as a retryable batch item failure.
import { createHash } from 'node:crypto';

export async function handleRecord(record, deps) {
  const payload = JSON.parse(record.body);
  if (!payload || typeof payload.id !== 'string' || !/^[A-Za-z0-9_-]{8,80}$/.test(payload.id)) throw new Error('Invalid event ID');
  if (typeof payload.action !== 'string' || !/^[a-z][a-z0-9_]{1,40}$/.test(payload.action)) throw new Error('Invalid action');
  const key = `events/${payload.id}.json`;
  const existing = await deps.exists(payload.id);
  if (existing) return { id: payload.id, duplicate: true };
  const audit = JSON.stringify({ id: payload.id, action: payload.action, status: 'processed', checksum: createHash('sha256').update(record.body).digest('hex') });
  await deps.writeAudit(key, audit);
  try { await deps.markProcessed(payload.id); }
  catch (error) {
    if (error.name === 'ConditionalCheckFailedException') return { id: payload.id, duplicate: true };
    throw error;
  }
  return { id: payload.id, duplicate: false };
}

export async function processBatch(event, deps) {
  const failures = [];
  for (const record of event.Records ?? []) {
    try { await handleRecord(record, deps); }
    catch (error) {
      console.error(JSON.stringify({ level: 'error', type: 'record_failed', message_id: record.messageId, class: error.name }));
      failures.push({ itemIdentifier: record.messageId });
    }
  }
  return { batchItemFailures: failures };
}

export async function handler(event, injected) {
  if (injected) return processBatch(event, injected);
  const { DynamoDBClient, GetItemCommand, PutItemCommand } = await import('@aws-sdk/client-dynamodb');
  const { S3Client, PutObjectCommand } = await import('@aws-sdk/client-s3');
  const dynamo = new DynamoDBClient({});
  const s3 = new S3Client({});
  const deps = {
    exists: async (id) => Boolean((await dynamo.send(new GetItemCommand({ TableName: process.env.IDEMPOTENCY_TABLE, Key: { event_id: { S: id } }, ConsistentRead: true }))).Item),
    writeAudit: async (key, body) => s3.send(new PutObjectCommand({ Bucket: process.env.AUDIT_BUCKET, Key: key, Body: body, ContentType: 'application/json', ServerSideEncryption: 'AES256' })),
    markProcessed: async (id) => dynamo.send(new PutItemCommand({ TableName: process.env.IDEMPOTENCY_TABLE, Item: { event_id: { S: id }, expires_at: { N: String(Math.floor(Date.now()/1000) + 30*86400) } }, ConditionExpression: 'attribute_not_exists(event_id)' }))
  };
  return processBatch(event, deps);
}
