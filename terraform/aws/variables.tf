variable "aws_region" { type = string }
variable "project" {
  type    = string
  default = "eds-platform"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,17}$", var.project))
    error_message = "Use 3-18 lowercase alphanumeric or hyphen characters."
  }
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Choose dev, stage or prod."
  }
}
variable "alert_topic_arn" {
  type        = string
  default     = ""
  description = "Optional pre-existing SNS topic; alarms remain queryable without a subscription."
}
variable "data_retention_days" {
  type    = number
  default = 30
  validation {
    condition     = var.data_retention_days >= 1 && var.data_retention_days <= 365
    error_message = "Retention must be 1 to 365 days."
  }
}
