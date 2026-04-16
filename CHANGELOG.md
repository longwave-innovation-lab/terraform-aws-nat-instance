## [1.2.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.1.1...v1.2.0) (2026-04-16)


### Features

* **main:** force NAT instance recreation on nat_instance_count change ([16f0394](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/16f03940b392aeb7b7bbabcc7a01aa5f60fa5937))
* **userdata:** reboot at end of user data script ([305d9e5](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/305d9e5cfc963869eb342b735846f0effee6e9c2))


### Bug Fixes

* **alarm:** include subnet ID in CloudWatch alarm name for SNS notifications ([32b1ca8](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/32b1ca828951921ee3b890719a1756269f4ab37f))
* **lambda:** add private_subnet_count to resolve for_each unknown at plan-time ([357f0b5](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/357f0b580075a795c057779747db3b5499d4cc95))
* **lambda:** IAM role name_prefix too long + CloudWatch alarm for_each robustness ([3c831b8](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/3c831b80d37d2691bc69ce07b386207ac073ce28))
* **lambda:** make private_subnet_count required + remove ternary from subnet_indices ([9fbec88](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/9fbec88d4e71de7fb4c4425d4a437effb162d5e9))
* **lambda:** use static subnet_indices map + translate all comments to English ([724a639](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/724a639f36a11b9b4eccbb2ba85e5b98d8d0a149))
* **main:** separate EIP association to fix SINGLE→MULTI-AZ lifecycle ([0f67abd](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/0f67abd6d5022762b67234fe23b6d74345f520bb))
* **userdata:** IMDSv2 for VPC CIDR + NM dispatcher for persistent route ([1351521](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/1351521af64d8e9728cf2e5597f7c79bd7d4fe75))
* **userdata:** reduce script size to stay well under 16KB EC2 limit ([47f7fe7](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/47f7fe7cd4b027eea4cfebbb2d1e6589cd3f472b))
* **userdata:** systemd vpc-route service with retry loop for persistent VPC CIDR route ([2ce2a0a](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/2ce2a0acfbd9e4e553de76b96b2ce727619f58da))
* **userdata:** use NetworkManager for persistent VPC CIDR route on private ENI ([73f6e30](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/73f6e30b310d4f4143526a75e87463155c9bbc05))
* **userdata:** wait for DHCP on private interface before routing setup ([64c7f70](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/64c7f70d71ca06f7443da1cc8f9ce057d48cfa51))

## [1.1.1](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.1.0...v1.1.1) (2026-03-16)

## [1.1.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.0.5...v1.1.0) (2026-03-14)


### Features

* improved nft table script add lambdacheck ([7815d1c](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/7815d1c5e131067ebd77f55d181d0213ea234982))


### Bug Fixes

* translate readme.md to English ([b821d55](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/b821d55c3ff9162e1c0b8264e0b32142ce31bbe3))

## [1.0.5](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.0.4...v1.0.5) (2026-02-20)

## [1.0.4](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.0.3...v1.0.4) (2026-02-20)


### Bug Fixes

* swicth userdata with nftables and internet connettivity check closes [#13](https://github.com/Longwave-innovation/terraform-aws-nat-instance/issues/13) ([db93b93](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/db93b93293263af0f44b2501fcbc0805e2a976ea))

