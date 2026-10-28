output "iam_signed_ingest_url" {
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/events"
  description = "Use SigV4 signed POST requests; never expose unauthenticated."
}
output "event_queue_url" { value = aws_sqs_queue.events.url }
output "dead_letter_queue_arn" { value = aws_sqs_queue.dead_letter.arn }
output "audit_bucket_name" { value = aws_s3_bucket.audit.id }
