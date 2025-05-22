# CREO RANDOM SRING DA APPENDERE
resource "random_string" "random_id" {
  length  = 6 # Lunghezza del prefisso casuale
  special = false
  upper   = false
  lower   = false
}

#variable "prefix" {
#  default = "deploy-" # Prefisso personalizzabile
#}

locals {
  name_prefix = random_string.random_id.result
}