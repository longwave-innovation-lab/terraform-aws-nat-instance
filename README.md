# Modulo Terraform AWS NAT Gateway/Instance <!-- omit in toc -->

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Caratteristiche Principali del modulo](#caratteristiche-principali-del-modulo)
- [Architettura](#architettura)
  - [Configurazione](#configurazione)
  - [Gruppi di Sicurezza](#gruppi-di-sicurezza)
  - [Configurazione IAM](#configurazione-iam)
- [Dettagli dello Script User Data Default](#dettagli-dello-script-user-data-default)
  - [Aggiornamenti di Sistema e Pacchetti](#aggiornamenti-di-sistema-e-pacchetti)
  - [Configurazione di Rete](#configurazione-di-rete)
  - [Regole di Sicurezza](#regole-di-sicurezza)
  - [Configurazione del Monitoraggio](#configurazione-del-monitoraggio)
- [Note e Best Practices](#note-e-best-practices)
- [Troubleshooting](#troubleshooting)
- [Requirements](#requirements)
- [Providers](#providers)
- [Modules](#modules)
- [Resources](#resources)
- [Inputs](#inputs)
- [Outputs](#outputs)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

Questo modulo Terraform offre un modo flessibile per gestire la Nat Instance nel tuo Virtual Private Cloud di AWS. Nell'esempio riporto come usare sia i NAT Gateway (gestiti da AWS) che le NAT Instance (istanze EC2 che fungono da NAT). Puoi scegliere tra un singolo NAT Gateway per l'intero VPC, un NAT Gateway per Availability Zone oppure utilizzare le NAT Instance.

La scelta tra le soluzioni viene gestita dinamicamente attraverso la variabile vpc_natgw.

Se vpc_natgw = 0: Viene creata una o piu NAT Instance personalizzate.

Se vpc_natgw = 1: Viene creato un unico NAT Gateway per l'intero VPC.

Se vpc_natgw = 2: Viene creato un NAT Gateway per ogni zona di disponibilità (AZ).

## Caratteristiche Principali del modulo

- Opzioni di implementazione flessibili (single-AZ o multi-AZ)
- Configurazione automatica delle tabelle di routing
- Integrazione con CloudWatch per monitoraggio e logging
- Gestione completa dei gruppi di sicurezza
- Supporto per architetture ARM e x86
- Configurazione e logging automatici di iptables su Cloudwatch
- Attivazione profilo SSM su Nat Instance per utilizzarlo anche come bastion host o reverse port forwarding.
- Salvataggio chiave private SSH su servizio AWS Parametr Store e locale

## Architettura

### Configurazione

- Implementa istanze NAT con doppia interfaccia di rete:
  - eth0: Interfaccia pubblica nella subnet pubblica
  - eth1: Interfaccia privata nella subnet privata
- Configura il controllo source/destination disabilitato sull'interfaccia privata
- Associa IP elastici alle interfacce pubbliche
- OS Amazon Linux 2023

### Gruppi di Sicurezza

1. Interfaccia Pubblica (eth0):
   - Permette tutto il traffico in uscita
   - Limita il traffico in ingresso alle connessioni stabilite

2. Interfaccia Privata (eth1):
   - Permette tutto il traffico in ingresso dalle subnet private
   - Permette tutto il traffico in uscita

### Configurazione IAM

Crea un ruolo IAM con:

- Permessi per CloudWatch Agent
- Accesso a Systems Manager (SSM)

## Dettagli dello Script User Data Default

Lo script [default_userdata.sh](./ec2_conf/default_userdata.sh) esegue le seguenti configurazioni:

### Aggiornamenti di Sistema e Pacchetti

- Aggiorna i pacchetti di sistema
- Installa iptables-persistent
- Disabilita nftables

### Configurazione di Rete

1. Abilita l'IP forwarding
2. Configura il rilevamento automatico delle interfacce
3. Imposta il routing NAT:
   - Permette l'inoltro tra interfacce private e pubbliche
   - Implementa il masquerading per il traffico in uscita

### Regole di Sicurezza

Implementa regole iptables per:

- Inoltro del traffico dall'interfaccia privata a quella pubblica
- Blocco degli accessi non autorizzati dall'interfaccia pubblica
- Logging dei flussi di traffico

### Configurazione del Monitoraggio

1. Configurazione CloudWatch Agent:
   - Registra il traffico iptables
   - Raccoglie le metriche di sistema (CPU, memoria, disco) e le invia a Cloudwatch in una Custom Metric LW/EC2
2. Gestione dei Log:
   - Crea file di log dedicato per iptables
   - Configura la rotazione dei log (retention di 2 ore)
   - Imposta lo streaming dei log su CloudWatch (retention di 7gg)

## Note e Best Practices

1. Alta Disponibilità
   - Per ambienti di produzione, considerare l'attivazione di nat_instance_per_az o servizio nat gateway
   - Implementare monitoraggio e alerting appropriati

2. LOG Ipatbles
   - i log all'interno delle istanze NAT sono salvati in /var/log/iptables.log

3. Cloudwatch Configuration
   - la configurazione dell'agente cloudwatch è salvato in /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

## Troubleshooting

1. Ping da Nat instance usando interfaccia privata
  
   ```sh
   ping -I ens5 -c 4 8.8.8.8
   ```

2. Controllo tabella di routing
  
   ```sh
   ip route show
   ```

3. Controllare se l'IP forwarding è attivo

   ```sh
   sysctl net.ipv4.ip_forward
   ```

   Se il valore è 0, riattivalo con:

   ```sh
   echo 1 > /proc/sys/net/ipv4/ip_forward
   ```

   > **ATTENZIONE**: verificare che nel file di configurazione ci sia solo
   > <br>**net.ipv4.ip_forward=1**
   > <br>Se diverso (es. **net.ipv4.ip_forward=1**) potrebbe dare dei problemi.

4. Controllare le regole iptables attive

      iptables -L -v -n

5. Controllare le regole iptables attive per il NAT

   ```sh
   iptables -t nat -L -v -n
   ```

6. iptables reset contatori visibili con il comando iptables -L -v -n

   ```sh
   iptables -Z
   ```

7. Controllare il traffico in tempo reale con tcpdump
   <br>Per verificare se i pacchetti ICMP (ping) arrivano alla NAT instance:

   ```sh
   tcpdump -i $PRIVATE_INTERFACE icmp
   ```

   Per vedere se il traffico sta passando correttamente tra le interfacce:

   ```sh
   tcpdump -i $PUBLIC_INTERFACE icmp
   ```

   monitorare tutto il traffico su una specifica interfaccia

   ```sh
   tcpdump -i $PRIVATE_INTERFACE
   ```

8. Controllare i log di iptables

   ```sh
   tail -f /var/log/iptables.log`
   ```

9. Per vedere quali connessioni sono attualmente stabilite attraverso la NAT instance:

   ```sh
   netstat -nat
   ```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.67.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.67.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ec2_natgw"></a> [ec2\_natgw](#module\_ec2\_natgw) | terraform-aws-modules/ec2-instance/aws | 5.8.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.natgw_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.ec2-nat-ssm-cloudwatch-instance-profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ec2-nat-ssm-cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ec2-describe-network-policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch-nat-logs-policy2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm-nat-policy2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_key_pair.rsa_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_network_interface.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_network_interface.natgw_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_network_interface_sg_attachment.natgw_public_sg_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_sg_attachment) | resource |
| [aws_route.private_subs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.natgw_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.nat_instance_ssh_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [tls_private_key.pk_nat](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.immagine-arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Random name prefix for resources | `string` | n/a | yes |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | List of private route table IDs | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | `string` | n/a | yes |
| <a name="input_create_ssh_keys"></a> [create\_ssh\_keys](#input\_create\_ssh\_keys) | Create ssh keys for the NAT instance/s | `bool` | `false` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for NAT instances | `string` | `"t4g.nano"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Log retention in days | `string` | `7` | no |
| <a name="input_nat_instance_per_az"></a> [nat\_instance\_per\_az](#input\_nat\_instance\_per\_az) | Whether to create a NAT instance per AZ or a single NAT instance for all AZs | `bool` | `false` | no |
| <a name="input_user_data_script"></a> [user\_data\_script](#input\_user\_data\_script) | Path to the custom user data script. By default the Nat Instance/s use [this userdata](https://github.com/Longwave-innovation/terraform-aws-nat-instance/blob/main/ec2_conf/default_userdata.sh) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_instance_details"></a> [nat\_instance\_details](#output\_nat\_instance\_details) | Details of NAT instances including ID and Public IP |
| <a name="output_nat_instance_ids"></a> [nat\_instance\_ids](#output\_nat\_instance\_ids) | IDs of the NAT EC2 instances |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Public IPs of the NAT instances |
<!-- END_TF_DOCS -->