export async function handler(event) {
  const receivedAt = new Date().toISOString();
  const records = Array.isArray(event.records) ? event.records : [];

  const processed = records.map((record) => ({
    id: record.id,
    status: 'processed',
    receivedAt,
    checksum: String(JSON.stringify(record.payload || {})).length
  }));

  return {
    statusCode: 200,
    body: JSON.stringify({
      processedCount: processed.length,
      processed
    })
  };
}
