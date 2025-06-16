## [0.2.2](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v0.2.1...v0.2.2) (2025-06-16)


### Bug Fixes

* added IAM permission for NAT instance to perform DescribeVpcs AND added static route to enable return traffic for VPC CIDR block ([93f6157](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/93f615782eabcada386f8855444b08b229ab43a4))

## [0.2.1](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v0.2.0...v0.2.1) (2025-05-23)


### Bug Fixes

* added descriptions for private and public ENI ([806a757](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/806a757b609a3ec3ddabf7700a98c0dd54b95a0b))
* added variable for log retention days ([333db97](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/333db973d645b8f1ae680015bdca6752258f59d1))
* changed ternary operator in example ([185a1a3](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/185a1a3aa69e3c75717da274c94a1ffff80b8cbb))

## [0.2.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v0.1.0...v0.2.0) (2025-05-23)


### Features

* now the nat has a default userdata script with the option to overwrite it ([c689a68](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/c689a68a8f4d43d07f0703f36e408888f1e58802))

## [0.1.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/915f9c8ce6b7e2ec8577a0138ca11c6aa4149f8e...v0.1.0) (2025-05-22)


### Features

* first release as a terraform module ([915f9c8](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/915f9c8ce6b7e2ec8577a0138ca11c6aa4149f8e))

