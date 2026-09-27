# Event-Driven Serverless Platform

A serverless architecture project that models event ingestion, queue-based decoupling, function processing, audit output, and dead-letter handling.

## Problem

Synchronous systems are brittle when workloads spike or downstream services slow down. This project shows a low-cost event-driven pattern where work is accepted quickly, buffered safely, processed asynchronously, and tracked with operational evidence.

## Architecture

```mermaid
flowchart TD
    A[Event Source] --> B[Queue]
    B --> C[Function Processor]
    C --> D[Storage]
    C --> E[Audit Log]
    B --> F[Dead Letter Queue]
```

## What This Project Demonstrates

- Serverless and event-driven architecture design.
- Queue-based decoupling and retry thinking.
- Function handler implementation.
- Audit and dead-letter workflow awareness.
- Cost-controlled serverless model with reusable validation evidence.

## Repository Structure

| Path | Purpose |
| --- | --- |
| `terraform/` | Event-flow outputs and infrastructure model. |
| `src/` | Serverless handler code. |
| `docs/evidence/` | Validation summary and proof notes. |

## Validation

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

## Cost Control

This project uses a controlled validation model: event flow, handler logic, audit output and failure handling are maintained from code while cost exposure is kept under control.

## Engineering Talking Points

- Why queues protect systems under burst traffic.
- How dead-letter queues support reliability.
- How audit logs help debugging and compliance.
- Why serverless can be strong for low-volume event workflows.
