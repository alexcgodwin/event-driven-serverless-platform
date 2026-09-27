import test from "node:test";
import assert from "node:assert/strict";
import { handler } from "../src/handler.js";

test("processes an event batch and returns an auditable count", async () => {
  const result = await handler({
    records: [{ id: "evt-001", payload: { action: "provision" } }]
  });
  const body = JSON.parse(result.body);
  assert.equal(result.statusCode, 200);
  assert.equal(body.processedCount, 1);
  assert.equal(body.processed[0].id, "evt-001");
  assert.equal(body.processed[0].status, "processed");
});

test("handles an empty event batch safely", async () => {
  const result = await handler({ records: [] });
  const body = JSON.parse(result.body);
  assert.equal(result.statusCode, 200);
  assert.equal(body.processedCount, 0);
});
