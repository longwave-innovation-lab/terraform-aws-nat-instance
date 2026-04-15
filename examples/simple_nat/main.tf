
############################
# 1. VPC
############################

module "vpc" {
  source                = "terraform-aws-modules/vpc/aws"
  version               = "6.6.0"                                 # Check latest available version
  name                  = "VPC-${random_string.random_id.result}" # must not start with a number!!!!
  cidr                  = "192.168.0.0/19"
  azs                   = ["${var.aws_region}a", "${var.aws_region}b"] # Replace with your availability zones
  private_subnets       = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnet_names  = ["${random_string.random_id.result} Private Subnet 1a", "${random_string.random_id.result} Private Subnet 2b"]
  public_subnets        = ["192.168.10.0/24", "192.168.11.0/24"]
  public_subnet_names   = ["${random_string.random_id.result} Public Subnet 1a", "${random_string.random_id.result} Public Subnet 2b"]
  database_subnets      = ["192.168.20.0/24", "192.168.21.0/24"]
  database_subnet_names = ["${random_string.random_id.result} Database Subnet 1a", "${random_string.random_id.result} Database Subnet 2b"]

  create_database_subnet_group = true
  enable_dns_support           = true
  enable_dns_hostnames         = true
  create_igw                   = true
  ## If vpc_natgw_service_type is set to "MANAGED", then enable_nat_gateway
  # will be set to true. If vpc_natgw_distribution is set to "SINGLE", then
  # single_nat_gateway will be set to true. If vpc_natgw_distribution is set
  # to "MULTI-AZ", then one_nat_gateway_per_az will be set to true.
  # enable_nat_gateway     = var.vpc_natgw == 0 ? false : true
  # single_nat_gateway     = var.vpc_natgw == 2 ? false : var.vpc_natgw == 1 ? true : false
  # one_nat_gateway_per_az = var.vpc_natgw == 2 ? true : false

  enable_nat_gateway     = var.vpc_natgw_service_type == "MANAGED" ? true : false
  single_nat_gateway     = var.vpc_natgw_distribution == "SINGLE" ? true : false
  one_nat_gateway_per_az = var.vpc_natgw_distribution == "MULTI-AZ" ? true : false
}

module "nat_gateway" {
  count                   = var.vpc_natgw_service_type == "NAT_INSTANCE" ? 1 : 0
  source                  = "../../"
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = module.vpc.public_subnets
  private_subnet_ids      = module.vpc.private_subnets
  private_route_table_ids = module.vpc.private_route_table_ids
  name_prefix             = local.name_prefix
  nat_instance_per_az     = var.vpc_natgw_distribution == "MULTI-AZ" ? true : false
  instance_type           = var.instance_type
  # Static value required when enable_internet_check = true and an apply also modifies
  # module.vpc in the same plan (e.g. MANAGED→NAT_INSTANCE switch).
  # Must match the number of private subnets defined in the vpc module.
  private_subnet_count = local.az_count
  # if ami_id is null set latest
  #ami_id                  = var.ami_id

  # Internet Connectivity Check (Lambda-based monitoring)
  # enable_internet_check       = true
  # internet_check_alert_emails = ["change_me@email.com"] # Required when enable_internet_check is true
  # internet_check_schedule_expression = "rate(5 minutes)"
  # internet_check_log_retention_days  = 7
  # internet_check_evaluation_periods  = 2
  # internet_check_period              = 300
  # internet_check_threshold           = 1
}
