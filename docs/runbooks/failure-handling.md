# Failure Handling Runbook

## Goal

Keep asynchronous workloads recoverable when processing fails.

## Steps

1. Confirm whether the source event reached the queue.
2. Review retry attempts and function error output.
3. Inspect the dead-letter queue for failed payloads.
4. Confirm whether audit output was created.
5. Reprocess after the cause is corrected.
6. Record the incident note and evidence.

## Production Notes

A production version would add alarms for dead-letter depth, retry exhaustion, function errors, processing latency and audit-write failures.