output "alb_dns_name" {
  description = "ALB DNS name for the application"
  value       = aws_lb.closetalk.dns_name
}

output "auth_service_url" {
  description = "Auth service URL (via CloudFront)"
  value       = "https://${aws_cloudfront_distribution.closetalk.domain_name}/auth"
}

output "ecr_auth_service_repo" {
  description = "ECR repository URL for auth-service"
  value       = aws_ecr_repository.auth_service.repository_url
}

output "ecr_message_service_repo" {
  description = "ECR repository URL for message-service"
  value       = aws_ecr_repository.message_service.repository_url
}

output "dynamodb_tables" {
  description = "DynamoDB table names"
  value = {
    messages  = aws_dynamodb_table.messages.name
    reactions = aws_dynamodb_table.reactions.name
    reads     = aws_dynamodb_table.reads.name
    bookmarks = aws_dynamodb_table.bookmarks.name
  }
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.closetalk.endpoint
}

output "elasticache_endpoint" {
  description = "ElastiCache Valkey endpoint"
  value       = aws_elasticache_replication_group.closetalk.primary_endpoint_address
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.closetalk.name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain (HTTPS)"
  value       = aws_cloudfront_distribution.closetalk.domain_name
}

output "app_url" {
  description = "Public HTTPS URL for the API"
  value       = "https://${aws_cloudfront_distribution.closetalk.domain_name}/"
}

output "s3_media_bucket_name" {
  description = "S3 media bucket name"
  value       = aws_s3_bucket.media.id
}

output "cloudfront_oac_id" {
  description = "CloudFront Origin Access Control ID for S3"
  value       = aws_cloudfront_origin_access_control.s3.id
}
