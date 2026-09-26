terraform {
  required_version = ">= 1.6.0"
}

variable "project_name" {
  type    = string
  default = "event-driven-serverless-platform"
}

locals {
  event_flow = [
    "api-ingest",
    "queue-buffer",
    "function-processor",
    "object-storage",
    "audit-log",
    "dead-letter-queue"
  ]
}

output "serverless_event_flow" {
  value = local.event_flow
}

output "cost_model" {
  value = "pay-per-use, no idle compute"
}
