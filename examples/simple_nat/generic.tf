locals {
  name_prefix = random_string.random_id.result
  # Static AZ/private subnet count: passed to module.nat_gateway as private_subnet_count
  # to avoid for_each/count unknown-at-plan-time errors when switching NAT mode.
  az_count = length(["${var.aws_region}a", "${var.aws_region}b"])
}

# CREATE RANDOM STRING TO APPEND
resource "random_string" "random_id" {
  length  = 6 # Random prefix length
  special = false
  upper   = false
  lower   = false
}
