
output "nat_instance_ids" {
  description = "IDs of the NAT EC2 instances"
  value       = aws_instance.nat_instance[*].id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT instances"
  value       = aws_eip.nat_eip[*].public_ip
}

output "nat_instance_details" {
  description = "Details of NAT instances including ID and Public IP"
  value = [
    for i in range(length(aws_instance.nat_instance)) : {
      instance_id = aws_instance.nat_instance[i].id
      public_ip   = aws_eip.nat_eip[i].public_ip
    }
  ]
}

# ============================================================================
# Lambda Internet Connectivity Check Outputs
# ============================================================================

output "internet_check_enabled" {
  description = "Whether internet connectivity check is enabled"
  value       = var.enable_internet_check
}

output "internet_check_lambda_functions" {
  description = "Map of Lambda function names for internet connectivity checks"
  value       = var.enable_internet_check ? { for k, v in aws_lambda_function.internet_check : k => v.function_name } : {}
}

output "internet_check_sns_topic_arn" {
  description = "ARN of the SNS topic for internet connectivity alerts"
  value       = var.enable_internet_check ? aws_sns_topic.lambda_alerts[0].arn : null
}

output "internet_check_alarm_names" {
  description = "Map of CloudWatch alarm names for internet connectivity checks"
  value       = var.enable_internet_check ? { for k, v in aws_cloudwatch_metric_alarm.internet_check : k => v.alarm_name } : {}
}
