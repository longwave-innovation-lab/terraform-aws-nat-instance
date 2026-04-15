locals {
  name_prefix = random_string.random_id.result
  # Numero statico di AZ/subnet private: usato da module.nat_gateway come
  # private_subnet_count per evitare errori for_each/count al cambio di NAT mode.
  az_count = length(["${var.aws_region}a", "${var.aws_region}b"])
}

# CREATE RANDOM STRING TO APPEND
resource "random_string" "random_id" {
  length  = 6 # Random prefix length
  special = false
  upper   = false
  lower   = false
}
