## [1.0.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v0.3.0...v1.0.0) (2025-07-29)


### ⚠ BREAKING CHANGES

* support AWS >= 6.0.0 and terraform >= 1.5.7 closes #9

### Features

* support AWS >= 6.0.0 and terraform >= 1.5.7 closes [#9](https://github.com/Longwave-innovation/terraform-aws-nat-instance/issues/9) ([5bc3717](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/5bc3717d08f809456f25ffe895184bfc794e3090))

## [0.3.0](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v0.2.2...v0.3.0) (2025-06-17)


### Features

* **ssh_keys:** now it can be decided whether to create ssh keys or not ([91cfd0e](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/91cfd0ef95c5948fce21a1858bf8afb5388176d2))


### Bug Fixes

* **action:** test to fix action error ([b861510](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/b86151003b20c447e6d6e6458be4c3d66d97c0d5))
* **ssh_keys:** parameter names for ssh keys now use instance names to be more linear ([d142746](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/d142746ce3cf797479600df257c47346128a2640))
* **terraform-docs:** configuration to make it recursive ([f1a6afa](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/f1a6afade8ea2dff95179dae9cab98db8b0e435c))

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

