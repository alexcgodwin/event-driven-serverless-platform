// API Gateway HTTP API with AWS_IAM authorization. AWS SDK v3 is available in Lambda Node.js 22 runtime.
import { createHash } from 'node:crypto';

export function parseRequest(event) {
  let payload;
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body ?? '', 'base64').toString('utf8') : event.body;
    if (typeof raw !== 'string' || Buffer.byteLength(raw) > 32768) throw new Error('Invalid payload size');
    payload = JSON.parse(raw);
  } catch { throw new Error('Invalid JSON payload'); }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Object expected');
  if (typeof payload.id !== 'string' || !/^[A-Za-z0-9_-]{8,80}$/.test(payload.id)) throw new Error('Invalid event id');
  if (typeof payload.action !== 'string' || !/^[a-z][a-z0-9_]{1,40}$/.test(payload.action)) throw new Error('Invalid action');
  return { id: payload.id, action: payload.action, correlationId: createHash('sha256').update(payload.id).digest('hex').slice(0, 24) };
}

export async function handler(event, deps = {}) {
  let message;
  try { message = parseRequest(event); }
  catch { return { statusCode: 400, body: JSON.stringify({ error: 'Invalid event' }) }; }
  const send = deps.send ?? (async (queue) => {
    const { SQSClient, SendMessageCommand } = await import('@aws-sdk/client-sqs');
    const client = new SQSClient({});
    await client.send(new SendMessageCommand({ QueueUrl: process.env.QUEUE_URL, MessageBody: JSON.stringify(queue) }));
  });
  try { await send(message); }
  catch (error) {
    console.error(JSON.stringify({ level: 'error', type: 'queue_publish_failed', event_id: message.id }));
    return { statusCode: 503, body: JSON.stringify({ error: 'Event temporarily unavailable' }) };
  }
  return { statusCode: 202, body: JSON.stringify({ accepted: true, correlationId: message.correlationId }) };
}
