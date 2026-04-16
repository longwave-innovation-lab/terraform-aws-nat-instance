# out vpc
output "vpc_id" {
  description = "Id VPC"
  value       = module.vpc.vpc_id
}

output "nat_instances" {
  description = "Details of NAT instances"
  value       = try(module.nat_gateway[0].nat_instance_details, null)
}
