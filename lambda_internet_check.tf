# ============================================================================
# Lambda Internet Connectivity Check
# ============================================================================
# This module creates Lambda functions to verify internet connectivity
# from private subnets through NAT instances.

locals {
  # _subnet_count: static integer from private_subnet_count.
  # When enable_internet_check = false, defaults to 0 (no resources created, no unknown needed).
  # When enable_internet_check = true, private_subnet_count MUST be passed explicitly
  # (enforced by precondition on aws_sns_topic.lambda_alerts) because private_subnet_ids
  # may be unknown at plan-time when module.vpc is being modified in the same apply.
  _subnet_count = var.enable_internet_check ? coalesce(var.private_subnet_count, 0) : 0

  # subnet_indices: fully static map { "0" = 0, "1" = 1, ... } derived from _subnet_count.
  # No ternary conditional: range(0) = {} when disabled, range(N) = {0..N-1} when enabled.
  # Keys and values are pure integers, always known at plan-time.
  # Actual subnet IDs are referenced only inside resource attributes (where unknown is fine).
  subnet_indices = { for i in range(local._subnet_count) : tostring(i) => i }
}

# SNS Topic for alarms
resource "aws_sns_topic" "lambda_alerts" {
  count = var.enable_internet_check ? 1 : 0
  name  = "${var.name_prefix}-internet-check-alerts"

  tags = {
    Name = "${var.name_prefix}-internet-check-alerts"
  }

  lifecycle {
    precondition {
      condition     = length(var.internet_check_alert_emails) > 0
      error_message = "You must set 'internet_check_alert_emails' with at least one address when 'enable_internet_check' is true."
    }
    precondition {
      condition     = var.private_subnet_count != null
      error_message = "You must set 'private_subnet_count' to the number of private subnets (e.g. 1, 2, or 3) when 'enable_internet_check' is true. This must be a static integer — not derived from module outputs — to allow Terraform to plan Lambda resources even when the VPC module is being modified in the same apply."
    }
  }
}

resource "aws_sns_topic_subscription" "lambda_alerts_email" {
  for_each = var.enable_internet_check ? toset(var.internet_check_alert_emails) : []

  topic_arn = aws_sns_topic.lambda_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  count = var.enable_internet_check ? 1 : 0
  name  = "${var.name_prefix}-lambda-inet-chk-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-lambda-internet-check-role"
  }
}

# Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  count       = var.enable_internet_check ? 1 : 0
  name_prefix = "${var.name_prefix}-lambda-internet-check-policy-"
  role        = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  count       = var.enable_internet_check ? 1 : 0
  name_prefix = "${var.name_prefix}-lambda-internet-check-sg-"
  description = "Security group for internet check lambda"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.name_prefix}-lambda-internet-check-sg"
  }
}

# ZIP file for Lambda code
data "archive_file" "lambda_zip" {
  count       = var.enable_internet_check ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# Lambda Function for each private subnet.
# for_each uses subnet_indices { "0"=0, "1"=1 } — fully static keys and values.
# The actual subnet ID is referenced as an attribute (var.private_subnet_ids[each.value])
# where unknown values are acceptable; it never appears as a map key.
resource "aws_lambda_function" "internet_check" {
  depends_on = [aws_instance.nat_instance]
  for_each   = local.subnet_indices

  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${var.name_prefix}-internet-check-${each.key}"
  role             = aws_iam_role.lambda_role[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  timeout          = 10
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      SubnetId   = var.private_subnet_ids[each.value]
      VPC_ID     = var.vpc_id
      CHECK_URLS = jsonencode(var.internet_check_urls)
    }
  }

  vpc_config {
    subnet_ids         = [var.private_subnet_ids[each.value]]
    security_group_ids = [aws_security_group.lambda_sg[0].id]
  }

  tags = {
    Name = "${var.name_prefix}-internet-check-${each.key}"
  }
}

# CloudWatch Log Group for Lambda functions.
# Name derived from prefix + index (known at plan-time), not from the Lambda object's function_name.
resource "aws_cloudwatch_log_group" "internet_check_log_group" {
  for_each          = local.subnet_indices
  name              = "/aws/lambda/${var.name_prefix}-internet-check-${each.key}"
  retention_in_days = var.internet_check_log_retention_days

  tags = {
    Name = "${var.name_prefix}-internet-check-logs-${each.key}"
  }
}

# CloudWatch Event Rule (scheduling)
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count               = var.enable_internet_check ? 1 : 0
  name                = "${var.name_prefix}-internet-check-schedule"
  description         = "Trigger lambda internet check every ${var.internet_check_schedule_minutes} minutes"
  schedule_expression = var.internet_check_schedule_expression

  tags = {
    Name = "${var.name_prefix}-internet-check-schedule"
  }
}

# Target for each Lambda.
# Uses subnet_indices (static) instead of aws_lambda_function.internet_check
# to avoid depending on a resource object that may itself be unknown at first apply.
resource "aws_cloudwatch_event_target" "lambda_target" {
  for_each = local.subnet_indices

  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "Lambda${each.key}"
  arn       = aws_lambda_function.internet_check[each.key].arn
}

# Permission for EventBridge to invoke Lambda functions
resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = local.subnet_indices

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.internet_check[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule[0].arn
}

# CloudWatch Metric Alarm for each subnet.
# count uses _subnet_count (static integer from private_subnet_count) — always known at plan-time.
# alarm_name and tags use var.private_subnet_ids[count.index] which is an attribute value
# (not a for_each/count key), so it may be unknown at plan-time without causing errors.
resource "aws_cloudwatch_metric_alarm" "internet_check" {
  count = local._subnet_count

  alarm_name          = "${var.name_prefix}-no-internet-${var.private_subnet_ids[count.index]}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.internet_check_evaluation_periods
  metric_name         = "InternetConnectivityStatus"
  namespace           = "Lambda/InternetConnectivity"
  period              = var.internet_check_period
  statistic           = "SampleCount"
  threshold           = var.internet_check_threshold
  alarm_description   = "Internet connectivity check failed in subnet ${var.private_subnet_ids[count.index]}"
  alarm_actions       = [aws_sns_topic.lambda_alerts[0].arn]
  ok_actions          = [aws_sns_topic.lambda_alerts[0].arn]
  treat_missing_data  = "breaching"

  dimensions = {
    VpcId    = var.vpc_id
    SubnetId = var.private_subnet_ids[count.index]
  }

  tags = {
    Name = "${var.name_prefix}-no-internet-${var.private_subnet_ids[count.index]}"
  }
}
