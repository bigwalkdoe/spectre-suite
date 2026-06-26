# Enhanced Terraform configuration for system maintenance
# Add network segmentation, VPC flow logs, and security enhancements

# VPC Flow Logs for audit
resource "aws_flow_log" "main" {
  count = var.deployment_target == "aws" ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main[0].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-flow-log"
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.deployment_target == "aws" ? 1 : 0

  name              = "/aws/vpc-flow-logs/${local.project_name}"
  retention_in_days = 90

  tags = local.common_tags
}

resource "aws_iam_role" "flow_log" {
  count = var.deployment_target == "aws" ? 1 : 0

  name = "${local.project_name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.deployment_target == "aws" ? 1 : 0

  name = "${local.project_name}-flow-log-policy"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Enhanced security group with network segmentation
resource "aws_security_group" "internal" {
  count = var.deployment_target == "aws" ? 1 : 0

  name_prefix = "${local.project_name}-internal-"
  vpc_id      = aws_vpc.main[0].id

  # Allow internal traffic within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main[0].cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-internal-sg"
  })
}

# Backup vault for off-site backups
resource "aws_backup_vault" "main" {
  count = var.deployment_target == "aws" ? 1 : 0

  name        = "${local.project_name}-backup-vault"
  kms_key_arn = aws_kms_key.backup[0].arn

  tags = local.common_tags
}

resource "aws_kms_key" "backup" {
  count = var.deployment_target == "aws" ? 1 : 0

  description             = "Backup encryption key for ${local.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_backup_plan" "main" {
  count = var.deployment_target == "aws" ? 1 : 0

  name = "${local.project_name}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 2 * * ? *)"
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 30
    }

    recovery_point_tags = {
      Environment = var.environment
      Project     = local.project_name
    }
  }

  tags = local.common_tags
}

# S3 bucket for backup storage
resource "aws_s3_bucket" "backups" {
  count = var.deployment_target == "aws" ? 1 : 0

  bucket = "${local.project_name}-backups-${var.environment}"
  force_destroy = var.environment == "dev" ? true : false

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "backups" {
  count = var.deployment_target == "aws" ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  count = var.deployment_target == "aws" ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backup[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count = var.deployment_target == "aws" ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    expiration {
      days = 90
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}

# WAF for DDoS protection
resource "aws_wafv2_web_acl" "main" {
  count = var.deployment_target == "aws" ? 1 : 0

  name        = "${local.project_name}-waf"
  description = "WAF for system-maintenance services"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "RateLimitRule"
      sampled_requests_enabled  = true
    }
  }

  rule {
    name     = "block-bad-bots"
    priority = 2

    action {
      block {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "BlockBadBots"
      sampled_requests_enabled  = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "${local.project_name}-waf"
    sampled_requests_enabled  = true
  }

  tags = local.common_tags
}

# Associate WAF with load balancer (if exists)
resource "aws_wafv2_web_acl_association" "main" {
  count = var.deployment_target == "aws" ? (length(aws_lb.main) > 0 ? 1 : 0) : 0

  resource_arn = aws_lb.main[0].arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}

# Application Load Balancer for services
resource "aws_lb" "main" {
  count = var.deployment_target == "aws" ? 1 : 0

  name               = "${local.project-name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main[0].id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.environment == "production"

  tags = local.common_tags
}

resource "aws_lb_target_group" "grafana" {
  count = var.deployment_target == "aws" ? 1 : 0

  name     = "${local.project-name}-grafana-tg"
  port     = 3002
  protocol = "HTTP"
  vpc_id   = aws_vpc.main[0].id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "grafana" {
  count = var.deployment_target == "aws" ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for ALB"
  type        = string
  default     = ""
}

# Outputs
output "backup_bucket_name" {
  value = var.deployment_target == "aws" ? aws_s3_bucket.backups[0].id : ""
  description = "S3 bucket for off-site backups"
}

output "waf_acl_id" {
  value = var.deployment_target == "aws" ? aws_wafv2_web_acl.main[0].id : ""
  description = "WAF ACL ID"
}

output "alb_dns_name" {
  value = var.deployment_target == "aws" ? aws_lb.main[0].dns_name : ""
  description = "ALB DNS name"
}
