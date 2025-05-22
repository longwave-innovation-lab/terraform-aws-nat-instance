
output "nat_instance_ids" {
  description = "IDs of the NAT EC2 instances"
  value       = module.ec2_natgw[*].id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT instances"
  value       = aws_eip.nat_eip[*].public_ip
}

output "nat_instance_details" {
  description = "Details of NAT instances including ID and Public IP"
  value = [
    for i in range(length(module.ec2_natgw)) : {
      instance_id = module.ec2_natgw[i].id
      public_ip   = aws_eip.nat_eip[i].public_ip
    }
  ]
}