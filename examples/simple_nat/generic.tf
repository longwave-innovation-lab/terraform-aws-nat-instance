locals {
  name_prefix = random_string.random_id.result
}

# CREATE RANDOM STRING TO APPEND
resource "random_string" "random_id" {
  length  = 6 # Random prefix length
  special = false
  upper   = false
  lower   = false
}
