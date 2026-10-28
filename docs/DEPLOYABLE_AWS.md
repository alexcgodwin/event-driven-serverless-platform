# AWS serverless deployment contract

This optional `terraform/aws` stack provisions actual AWS resources only when an authorized operator runs `terraform apply`. The existing output-only `terraform/` root remains for design comparison.

## Components

API Gateway HTTP API (`POST /events`, **AWS_IAM**, SigV4) invokes a small ingress Lambda, which validates a bounded event and publishes it to encrypted SQS. A separate Lambda consumes the queue with partial-batch failure reporting. Every accepted event is audited under a deterministic, private S3 object key and recorded in a DynamoDB idempotency ledger. SQS routes exhausted retries to an encrypted dead-letter queue. CloudWatch alarms track DLQ depth and queue age.

## Security controls

- No anonymous HTTP ingress. IAM policies granting `execute-api:Invoke` must be approved separately.
- Separate ingest and worker roles; no wildcard administrative privileges or access keys committed to Git.
- S3 bucket blocks public access, enforces TLS, retains versions, and does not force-destroy on Terraform destroy.
- Lambda concurrency limits, API throttling, and bounded queue retries. No automatic DLQ replay.
- Data is an example audit workload and must not contain personal, regulated, or secret material.

## Validation

`node --test tests/*.test.js tests/*.test.mjs` and `terraform -chdir=terraform/aws init -backend=false` then `terraform -chdir=terraform/aws validate`.

## Deployment (costs apply)

Choose an authorized AWS account. Configure remote state with encryption and locking, role trust, budgets, service quotas and incident contacts. Copy `terraform/aws/terraform.tfvars.example` to an untracked `.tfvars` file, review `terraform plan` with Security and Platform owners, then apply only after approval. Capture verified AWS resource IDs, plan evidence, SQS replay test, and teardown separately. No live AWS deployment or measured latency is claimed in this repository.

## Failure exercise

Use synthetically malformed SQS payloads in a dedicated sandbox. Confirm DLQ redrive at the configured maximum receive count, alarm state, and operator review before redrive. After processing, inspect DynamoDB, S3 audit object, and Lambda log correlation IDs. Rolling back a function version does not replay or delete previously accepted queue messages.
