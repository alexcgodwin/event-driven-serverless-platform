data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
locals { prefix = "${var.project}-${var.environment}" }

resource "aws_sqs_queue" "dead_letter" {
  name                      = "${local.prefix}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "events" {
  name                       = "${local.prefix}-events"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dead_letter.arn, maxReceiveCount = 4 })
}
resource "aws_dynamodb_table" "idempotency" {
  name         = "${local.prefix}-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"
  attribute {
    name = "event_id"
    type = "S"
  }
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
  server_side_encryption { enabled = true }
  point_in_time_recovery { enabled = false }
}
resource "aws_s3_bucket" "audit" {
  bucket_prefix = "${local.prefix}-audit-"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    id     = "expire-audit-records"
    status = "Enabled"
    filter {}
    expiration { days = var.data_retention_days }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
  depends_on = [aws_s3_bucket_versioning.audit]
}
resource "aws_s3_bucket_policy" "tls" {
  bucket = aws_s3_bucket.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.audit]
}

data "archive_file" "worker" {
  type        = "zip"
  source_file = "${path.module}/../../src/aws-worker.mjs"
  output_path = "${path.module}/worker.zip"
}
data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/../../src/aws-ingest.mjs"
  output_path = "${path.module}/ingest.zip"
}
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${local.prefix}-worker"
  retention_in_days = 14
}
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${local.prefix}-ingest"
  retention_in_days = 14
}
resource "aws_lambda_function" "worker" {
  function_name                  = "${local.prefix}-worker"
  role                           = aws_iam_role.worker.arn
  filename                       = data.archive_file.worker.output_path
  source_code_hash               = data.archive_file.worker.output_base64sha256
  runtime                        = "nodejs22.x"
  handler                        = "aws-worker.handler"
  timeout                        = 30
  memory_size                    = 256
  reserved_concurrent_executions = 3
  environment { variables = {
    AUDIT_BUCKET      = aws_s3_bucket.audit.id
    IDEMPOTENCY_TABLE = aws_dynamodb_table.idempotency.name
  } }
  depends_on = [aws_cloudwatch_log_group.worker]
}
resource "aws_lambda_function" "ingest" {
  function_name                  = "${local.prefix}-ingest"
  role                           = aws_iam_role.ingest.arn
  filename                       = data.archive_file.ingest.output_path
  source_code_hash               = data.archive_file.ingest.output_base64sha256
  runtime                        = "nodejs22.x"
  handler                        = "aws-ingest.handler"
  timeout                        = 10
  memory_size                    = 128
  reserved_concurrent_executions = 3
  environment { variables = { QUEUE_URL = aws_sqs_queue.events.url } }
  depends_on = [aws_cloudwatch_log_group.ingest]
}
resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn        = aws_sqs_queue.events.arn
  function_name           = aws_lambda_function.worker.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config { maximum_concurrency = 2 }
}
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.prefix}-ingest"
  protocol_type = "HTTP"
  description   = "AWS_IAM authorized event ingress; SigV4 required"
}
resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "events" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /events"
  target             = "integrations/${aws_apigatewayv2_integration.ingest.id}"
  authorization_type = "AWS_IAM"
}
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}
resource "aws_lambda_permission" "apigateway" {
  statement_id  = "AllowAuthorizedApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/POST/events"
}
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.prefix}-dlq-visible-messages"
  alarm_description   = "Manual DLQ investigation required; never auto-replay."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter.name }
  alarm_actions       = var.alert_topic_arn == "" ? [] : [var.alert_topic_arn]
}
resource "aws_cloudwatch_metric_alarm" "queue_age" {
  alarm_name          = "${local.prefix}-queue-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.events.name }
  alarm_actions       = var.alert_topic_arn == "" ? [] : [var.alert_topic_arn]
}
