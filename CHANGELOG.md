## [1.0.2](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.0.1...v1.0.2) (2025-09-23)


### Bug Fixes

* change default cloudwatch log to false ([47b4e92](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/47b4e9297659f396aa045bfa164466955e209871))
* change network config of ec2 nat gw ([ed4eacf](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/ed4eacf0e74a9f81ec1c89169af71d8cf7eacc65))
* change network config of ec2 nat gw ([88464e1](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/88464e16d9df0bf2e6ecce6b83d443887d0670ac))
* change network config of ec2 nat gw ([84f600e](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/84f600ef6af21ad13f8f1900e01a9680170cc753))
* disable lifecycle ami ([9db04d6](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/9db04d6c0e8d08a9580782ac6dd02ccf93b87cae))
* disable module ec2 and set resource terraform for each component ([613c37f](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/613c37fd17a17f9b10d57d1ff33f423a2c9726a7))
* format text and delete comment ([addd845](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/addd845279919432e490cfe81c48d41bdd4400e7))
* select ami amazon linux 2023 standard ([a1c3bc1](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/a1c3bc19842a357c418c257d894adfc4c99911ed))
* upgrade default root volume at 30GB ([256c01b](https://github.com/Longwave-innovation/terraform-aws-nat-instance/commit/256c01b8fe8603d49eb298722697f2d7e4eaa725))

## [1.0.1](https://github.com/Longwave-innovation/terraform-aws-nat-instance/compare/v1.0.0...v1.0.1) (2025-09-16)

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

