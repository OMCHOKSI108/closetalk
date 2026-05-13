terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ─── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "closetalk" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.app_name}-${var.environment}"
  }
}

resource "aws_internet_gateway" "closetalk" {
  vpc_id = aws_vpc.closetalk.id
}

locals {
  azs = ["ap-south-1a", "ap-south-1b"]
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.closetalk.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.app_name}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.closetalk.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.app_name}-private-${count.index}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "closetalk" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.closetalk.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.closetalk.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.closetalk.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.closetalk.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── Security Groups ──────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-${var.environment}"
  description = "ALB security group"
  vpc_id      = aws_vpc.closetalk.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.app_name}-ecs-${var.environment}"
  description = "ECS tasks security group"
  vpc_id      = aws_vpc.closetalk.id

  ingress {
    from_port       = 8081
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-rds-${var.environment}"
  description = "RDS security group"
  vpc_id      = aws_vpc.closetalk.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

resource "aws_security_group" "elasticache" {
  name        = "${var.app_name}-elasticache-${var.environment}"
  description = "ElastiCache security group"
  vpc_id      = aws_vpc.closetalk.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

# ─── ECR Repositories ─────────────────────────────────────────────────────────

resource "aws_ecr_repository" "auth_service" {
  name         = "${var.app_name}/auth-service"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "message_service" {
  name         = "${var.app_name}/message-service"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ─── DynamoDB Tables ──────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "messages" {
  name           = "${var.app_name}-messages"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "chat_id"
  range_key      = "sort_key"

  attribute {
    name = "chat_id"
    type = "S"
  }
  attribute {
    name = "sort_key"
    type = "S"
  }
  attribute {
    name = "message_id"
    type = "S"
  }

  global_secondary_index {
    name            = "message_id-index"
    hash_key        = "message_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.app_name}-messages" }
}

resource "aws_dynamodb_table" "reactions" {
  name           = "${var.app_name}-message-reactions"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "message_id"
  range_key      = "user_emoji"

  attribute {
    name = "message_id"
    type = "S"
  }
  attribute {
    name = "user_emoji"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.app_name}-message-reactions" }
}

resource "aws_dynamodb_table" "reads" {
  name           = "${var.app_name}-message-reads"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "message_id"
  range_key      = "user_id"

  attribute {
    name = "message_id"
    type = "S"
  }
  attribute {
    name = "user_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.app_name}-message-reads" }
}

resource "aws_dynamodb_table" "bookmarks" {
  name           = "${var.app_name}-bookmarks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"
  range_key      = "sort_key"

  attribute {
    name = "user_id"
    type = "S"
  }
  attribute {
    name = "sort_key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.app_name}-bookmarks" }
}

# ─── RDS PostgreSQL ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "closetalk" {
  name       = "${var.app_name}-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "closetalk" {
  identifier             = "${var.app_name}-${var.environment}"
  engine                 = "postgres"
  engine_version         = "17.4"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name  = var.app_name
  username = var.app_name
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.closetalk.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot     = true

  auto_minor_version_upgrade = true

  tags = { Name = "${var.app_name}-postgres" }
}

# ─── ElastiCache Valkey ───────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "closetalk" {
  name       = "${var.app_name}-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "closetalk" {
  replication_group_id = "${var.app_name}-${var.environment}"
  description          = "CloseTalk Valkey cache"
  engine               = "valkey"
  engine_version       = "8.1"
  node_type            = "cache.t4g.micro"
  num_cache_clusters   = 1
  parameter_group_name = "default.valkey8"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.closetalk.name
  security_group_ids = [aws_security_group.elasticache.id]

  tags = { Name = "${var.app_name}-valkey" }
}

# ─── S3 Media Bucket ───────────────────────────────────────────────────────────

resource "aws_s3_bucket" "media" {
  bucket        = var.s3_media_bucket_name
  force_destroy = true

  tags = { Name = "${var.app_name}-media" }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.app_name}-s3-oac-${var.environment}"
  description                       = "OAC for ${var.app_name} S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "s3_media_cloudfront" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.closetalk.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "media_cloudfront" {
  bucket = aws_s3_bucket.media.id
  policy = data.aws_iam_policy_document.s3_media_cloudfront.json
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

resource "aws_lb" "closetalk" {
  name               = "${var.app_name}-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = { Name = "${var.app_name}-alb" }
}

resource "aws_lb_target_group" "auth_service" {
  name        = "${var.app_name}-auth-${var.environment}"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.closetalk.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = 8081
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${var.app_name}-auth-tg" }
}

resource "aws_lb_target_group" "message_service" {
  name        = "${var.app_name}-msg-${var.environment}"
  port        = 8082
  protocol    = "HTTP"
  vpc_id      = aws_vpc.closetalk.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = 8082
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${var.app_name}-msg-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.closetalk.arn
  port              = 80
  protocol          = "HTTP"

  # Default catch-all routes to auth-service so new auth-service endpoints
  # don't require an ALB rule update. Message-service paths still take priority
  # via their explicit listener rules below.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service.arn
  }
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_execution" {
  name = "${var.app_name}-ecs-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_extra" {
  name = "${var.app_name}-ecs-execution-extra-${var.environment}"
  role = aws_iam_role.ecs_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = [
          aws_ecr_repository.auth_service.arn,
          aws_ecr_repository.message_service.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.app_name}-ecs-task-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_dynamodb" {
  name = "${var.app_name}-ecs-task-dynamodb-${var.environment}"
  role = aws_iam_role.ecs_task.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.messages.arn,
        "${aws_dynamodb_table.messages.arn}/index/*",
        aws_dynamodb_table.reactions.arn,
        aws_dynamodb_table.reads.arn,
        aws_dynamodb_table.bookmarks.arn,
      ]
    },{
      Effect = "Allow"
      Action = [
        "ses:SendEmail",
        "ses:SendRawEmail",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_s3_media" {
  name = "${var.app_name}-ecs-task-s3-media-${var.environment}"
  role = aws_iam_role.ecs_task.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
      ]
      Resource = "${aws_s3_bucket.media.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_infrastructure" {
  name = "${var.app_name}-ecs-task-infrastructure-${var.environment}"
  role = aws_iam_role.ecs_task.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:DescribeServices",
        "ecs:UpdateService",
        "rds:DescribeDBInstances",
        "rds:StopDBInstance",
        "rds:StartDBInstance",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
      ]
      Resource = "*"
    }]
  })
}

# ─── ECS ───────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "closetalk" {
  name = "${var.app_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "closetalk" {
  cluster_name = aws_ecs_cluster.closetalk.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "auth_service" {
  name              = "/ecs/${var.app_name}/auth-service"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "message_service" {
  name              = "/ecs/${var.app_name}/message-service"
  retention_in_days = 30
}

# ─── Task Definitions ─────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "auth_service" {
  family                   = "${var.app_name}-auth-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "auth-service"
    image = "${aws_ecr_repository.auth_service.repository_url}:latest"
    portMappings = [{
      containerPort = 8081
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT",              value = "8081" },
      { name = "DATABASE_URL",      value = "postgres://${var.app_name}:${var.db_password}@${aws_db_instance.closetalk.endpoint}/${var.app_name}?sslmode=require" },
      { name = "VALKEY_ADDR",       value = "${aws_elasticache_replication_group.closetalk.primary_endpoint_address}:6379" },
      { name = "VALKEY_PASSWORD",   value = "" },
      { name = "JWT_SECRET",        value = var.jwt_secret },
      { name = "SES_FROM_EMAIL",    value = "noreply@closetalk.app" },
      { name = "AWS_REGION",        value = var.aws_region },
      { name = "S3_BUCKET",         value = aws_s3_bucket.media.id },
      { name = "S3_PUBLIC_URL",     value = "https://${aws_cloudfront_distribution.closetalk.domain_name}" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.auth_service.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8081/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
}

resource "aws_ecs_task_definition" "message_service" {
  family                   = "${var.app_name}-message-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "message-service"
    image = "${aws_ecr_repository.message_service.repository_url}:latest"
    portMappings = [{
      containerPort = 8082
      protocol      = "tcp"
    }]

    environment = [
      { name = "MESSAGE_SERVICE_PORT", value = "8082" },
      { name = "VALKEY_ADDR",          value = "${aws_elasticache_replication_group.closetalk.primary_endpoint_address}:6379" },
      { name = "JWT_SECRET",           value = var.jwt_secret },
      { name = "AWS_REGION",           value = var.aws_region },
      { name = "S3_BUCKET",            value = aws_s3_bucket.media.id },
      { name = "S3_PUBLIC_URL",        value = "https://${aws_cloudfront_distribution.closetalk.domain_name}" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.message_service.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8082/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
}

# ─── ECS Services ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "auth_service" {
  name            = "auth-service"
  cluster         = aws_ecs_cluster.closetalk.id
  task_definition = aws_ecs_task_definition.auth_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth_service.arn
    container_name   = "auth-service"
    container_port   = 8081
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "message_service" {
  name            = "message-service"
  cluster         = aws_ecs_cluster.closetalk.id
  task_definition = aws_ecs_task_definition.message_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.message_service.arn
    container_name   = "message-service"
    container_port   = 8082
  }

  depends_on = [aws_lb_listener.http]
}

# ─── ALB Listener Rules ───────────────────────────────────────────────────────

resource "aws_lb_listener_rule" "auth_service" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service.arn
  }

  # ALB caps each path-pattern condition at 5 values; auth-service uses two rules.
  condition {
    path_pattern {
      values = ["/", "/auth/*", "/devices/*", "/groups/*", "/health"]
    }
  }
}

resource "aws_lb_listener_rule" "auth_service_extra" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service.arn
  }

  condition {
    path_pattern {
      values = ["/users/*", "/devices"]
    }
  }
}

resource "aws_lb_listener_rule" "message_service" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.message_service.arn
  }

  condition {
    path_pattern {
      values = ["/messages/*", "/bookmarks/*", "/sync/*", "/ws"]
    }
  }
}

resource "aws_lb_listener_rule" "message_service_exact" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.message_service.arn
  }

  condition {
    path_pattern {
      values = ["/messages", "/bookmarks"]
    }
  }
}

# ─── CloudFront ─────────────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "closetalk" {
  origin {
    domain_name = aws_lb.closetalk.dns_name
    origin_id   = "closetalk-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.media.bucket_domain_name
    origin_id                = "closetalk-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"  # use only North America/Europe/Asia edges

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "closetalk-alb"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Idempotency-Key", "Origin", "Host"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern     = "/media/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "closetalk-s3"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
