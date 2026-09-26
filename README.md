# Event-Driven Serverless Platform

A serverless architecture project for event ingestion, processing, audit trails, alerts and operational visibility using queues, functions, object storage and infrastructure as code.

## What this proves

- Event-driven architecture
- Serverless workload design
- Queue-based decoupling and retry handling
- Observability and dead-letter handling
- Low-cost cloud architecture

## Architecture

Events enter through an API or object upload, move through a queue, trigger processing, write output to durable storage, and publish audit/alert events.

## Cost rule

Serverless validation is designed for near-zero cost, with no long-running compute.
