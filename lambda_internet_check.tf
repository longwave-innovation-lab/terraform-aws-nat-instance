# ============================================================================
# Lambda Internet Connectivity Check
# ============================================================================
# This module creates Lambda functions to verify internet connectivity
# from private subnets through NAT instances.

# Retrieve private subnets
locals {
  subnet_map = var.enable_internet_check ? { for idx, subnet_id in var.private_subnet_ids : tostring(idx) => subnet_id } : {}
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
  count       = var.enable_internet_check ? 1 : 0
  name_prefix = "${var.name_prefix}-lambda-internet-check-role-"

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

# Lambda Function for each private subnet
resource "aws_lambda_function" "internet_check" {
  depends_on = [aws_instance.nat_instance]
  for_each   = local.subnet_map

  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${var.name_prefix}-internet-check-${each.value}"
  role             = aws_iam_role.lambda_role[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  timeout          = 10
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      SubnetId   = each.value
      VPC_ID     = var.vpc_id
      CHECK_URLS = jsonencode(var.internet_check_urls)
    }
  }

  vpc_config {
    subnet_ids         = [each.value]
    security_group_ids = [aws_security_group.lambda_sg[0].id]
  }

  tags = {
    Name = "${var.name_prefix}-internet-check-${each.value}"
  }
}

# CloudWatch Log Group for Lambda functions
resource "aws_cloudwatch_log_group" "internet_check_log_group" {
  for_each          = local.subnet_map
  name              = "/aws/lambda/${aws_lambda_function.internet_check[each.key].function_name}"
  retention_in_days = var.internet_check_log_retention_days

  tags = {
    Name = "${var.name_prefix}-internet-check-logs-${each.value}"
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

# Target for each Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  for_each = aws_lambda_function.internet_check

  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "Lambda${each.key}"
  arn       = each.value.arn
}

# Permission for EventBridge to invoke Lambda functions
resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = aws_lambda_function.internet_check

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule[0].arn
}

# CloudWatch Metric Alarm for each subnet
resource "aws_cloudwatch_metric_alarm" "internet_check" {
  for_each = local.subnet_map

  alarm_name          = "${var.name_prefix}-internet-check-alarm-${each.value}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.internet_check_evaluation_periods
  metric_name         = "InternetConnectivityStatus"
  namespace           = "Lambda/InternetConnectivity"
  period              = var.internet_check_period
  statistic           = "SampleCount"
  threshold           = var.internet_check_threshold
  alarm_description   = "Internet connectivity check failed in subnet ${each.value}"
  alarm_actions       = var.enable_internet_check ? [aws_sns_topic.lambda_alerts[0].arn] : []
  ok_actions          = var.enable_internet_check ? [aws_sns_topic.lambda_alerts[0].arn] : []
  treat_missing_data  = "breaching"

  dimensions = {
    VpcId    = var.vpc_id
    SubnetId = each.value
  }

  tags = {
    Name = "${var.name_prefix}-internet-check-alarm-${each.value}"
  }
}
