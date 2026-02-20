# Modulo Terraform AWS NAT Gateway/Instance <!-- omit in toc -->

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Caratteristiche Principali del modulo](#caratteristiche-principali-del-modulo)
- [Architettura](#architettura)
  - [Configurazione](#configurazione)
  - [Gruppi di Sicurezza](#gruppi-di-sicurezza)
  - [Configurazione IAM](#configurazione-iam)
- [Dettagli dello Script User Data Default](#dettagli-dello-script-user-data-default)
  - [Fasi di Inizializzazione](#fasi-di-inizializzazione)
    - [1. Test di Connettività e Validazione](#1-test-di-connettività-e-validazione)
    - [2. Aggiornamento Sistema e Installazione Pacchetti](#2-aggiornamento-sistema-e-installazione-pacchetti)
    - [3. Configurazione IP Forwarding](#3-configurazione-ip-forwarding)
    - [4. Identificazione Interfacce di Rete](#4-identificazione-interfacce-di-rete)
    - [5. Configurazione Routing VPC](#5-configurazione-routing-vpc)
    - [6. Configurazione nftables per Funzionalità NAT](#6-configurazione-nftables-per-funzionalità-nat)
    - [7. Configurazione Logging (se enable\_cloudwatch\_logs = true)](#7-configurazione-logging-se-enable_cloudwatch_logs--true)
    - [8. Configurazione CloudWatch Agent](#8-configurazione-cloudwatch-agent)
  - [Variabili Template](#variabili-template)
  - [File e Servizi Creati](#file-e-servizi-creati)
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

Lo script [userdata.tpl](./ec2_conf/userdata.tpl) è un template Terraform che utilizza la funzione `templatefile` per configurare dinamicamente le istanze NAT. Il template riceve due variabili:

- `enable_cloudwatch_logs`: Abilita/disabilita il logging su CloudWatch
- `log_group_name`: Nome del log group CloudWatch (se abilitato)

### Fasi di Inizializzazione

#### 1. Test di Connettività e Validazione

Prima di procedere con l'installazione, lo script esegue test di connettività per garantire che l'istanza possa raggiungere Internet:

- **Test connettività IP**: Verifica la raggiungibilità di 8.8.8.8 e 1.1.1.1 (minimo 3 risposte su 10 ping)
- **Test risoluzione DNS**: Verifica la risoluzione di google.com e cloudflare.com
- **Retry automatico**: Ogni test viene ripetuto fino a 2 volte con attesa di 60 secondi tra i tentativi
- **Logging dettagliato**: Tutti i test vengono registrati in `/var/log/user-data.log`

Se i test falliscono, lo script termina con errore per evitare configurazioni incomplete.

#### 2. Aggiornamento Sistema e Installazione Pacchetti

Lo script installa i seguenti pacchetti con retry automatico in caso di fallimento:

**Pacchetti Core:**
- `traceroute`, `tcpdump`: Strumenti di diagnostica di rete
- `amazon-cloudwatch-agent`: Agent per metriche e log CloudWatch
- `logrotate`, `rsyslog`: Gestione e rotazione dei log
- `nftables`: Framework per il firewall (sostituisce iptables)

**Pacchetti Aggiuntivi:**
- `amazon-ssm-agent`: Abilita l'accesso tramite AWS Systems Manager Session Manager

Ogni installazione viene tentata fino a 2 volte con attesa di 30 secondi tra i tentativi.

#### 3. Configurazione IP Forwarding

Abilita permanentemente l'IP forwarding necessario per la funzionalità NAT:

```bash
net.ipv4.ip_forward=1
```

Il parametro viene salvato in `/etc/sysctl.d/99-ip-forward.conf` per persistere ai riavvii.

#### 4. Identificazione Interfacce di Rete

Lo script identifica automaticamente le interfacce di rete (escludendo loopback e Docker):

- **PUBLIC_INTERFACE** (eth0/ens5): Prima interfaccia, connessa alla subnet pubblica
- **PRIVATE_INTERFACE** (eth1/ens6): Seconda interfaccia, connessa alla subnet privata

#### 5. Configurazione Routing VPC

Recupera i metadati AWS per configurare il routing corretto:

1. Ottiene il VPC ID dall'Instance Metadata Service (IMDSv2)
2. Recupera il CIDR block del VPC tramite AWS CLI
3. Aggiunge una route statica per il traffico VPC attraverso l'interfaccia privata
4. Crea un servizio systemd (`custom-routes.service`) per rendere persistente la route

#### 6. Configurazione nftables per Funzionalità NAT

Lo script configura **nftables** (non iptables) con le seguenti regole:

**Chain INPUT:**
- Accetta tutto il traffico su loopback
- Accetta tutto il traffico dall'interfaccia privata
- Accetta solo traffico ESTABLISHED/RELATED dall'interfaccia pubblica
- Accetta ICMP echo-request/reply dall'interfaccia privata
- Logga e blocca tutto il resto (se logging abilitato)

**Chain FORWARD:**
- Permette il forward da interfaccia privata a pubblica
- Permette il forward da pubblica a privata solo per connessioni ESTABLISHED/RELATED
- Logga il traffico privato→pubblico (se logging abilitato)
- Blocca tutto il resto

**Chain OUTPUT:**
- Permette tutto il traffico in uscita sull'interfaccia pubblica

**Chain POSTROUTING (NAT):**
- Applica masquerading su tutto il traffico in uscita dall'interfaccia pubblica

Le regole vengono salvate in:
- `/etc/nftables/nat-instance.nft`: Configurazione principale
- `/etc/sysconfig/nftables.conf`: Copia per persistenza

Un servizio systemd dedicato (`nftables-nat.service`) garantisce il caricamento automatico delle regole all'avvio.

#### 7. Configurazione Logging (se enable_cloudwatch_logs = true)

Quando il logging è abilitato, lo script configura:

**File di Log Locale:**
- Crea `/var/log/iptables.log` per i log nftables
- Configura rsyslog per filtrare i messaggi con prefisso "NFTables-"
- Imposta logrotate per rotazione oraria (mantiene solo 1 ora di log, max 10MB)

**Prefissi Log nftables:**
- `NFTables-PRIV-to-PUB:` - Traffico dalla subnet privata alla pubblica
- `NFTables-Dropped-PRIVATE-IN:` - Traffico bloccato in ingresso su interfaccia privata
- `NFTables-Dropped-FORWARD:` - Traffico bloccato in forward

#### 8. Configurazione CloudWatch Agent

Lo script configura sempre il CloudWatch Agent con le seguenti metriche custom:

**Namespace:** `EC2/NATinstance`

**Metriche Raccolte (intervallo 60 secondi):**
- `disk_used_percent`: Percentuale di utilizzo disco (root filesystem)
- `memory_used_percent`: Percentuale di utilizzo memoria RAM
- `swap_used_percent`: Percentuale di utilizzo swap

**Dimensioni Aggiunte:**
- `InstanceId`: ID dell'istanza EC2
- `InstanceType`: Tipo di istanza (es. t4g.nano)

**Configurazione Log (solo se enable_cloudwatch_logs = true):**
- Stream dei log da `/var/log/iptables.log` al log group specificato
- Log stream nominato con l'Instance ID
- Timezone: UTC

Il file di configurazione viene salvato in:
`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`

### Variabili Template

Il template supporta le seguenti variabili Terraform:

| Variabile | Tipo | Descrizione |
|-----------|------|-------------|
| `enable_cloudwatch_logs` | bool | Abilita il logging nftables su CloudWatch |
| `log_group_name` | string | Nome del CloudWatch Log Group (usato solo se logging abilitato) |

### File e Servizi Creati

**File di Configurazione:**
- `/etc/sysctl.d/99-ip-forward.conf` - IP forwarding persistente
- `/etc/nftables/nat-instance.nft` - Regole nftables
- `/etc/sysconfig/nftables.conf` - Copia delle regole per persistenza
- `/etc/rsyslog.d/10-nftables.conf` - Configurazione rsyslog per nftables
- `/etc/logrotate.d/nat-traffic` - Rotazione log nftables
- `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` - Configurazione CloudWatch Agent

**Servizi Systemd:**
- `custom-routes.service` - Mantiene le route statiche VPC
- `nftables-nat.service` - Carica le regole nftables all'avvio
- `amazon-ssm-agent.service` - Agent SSM per accesso remoto
- `amazon-cloudwatch-agent.service` - Agent CloudWatch per metriche e log

**File di Log:**
- `/var/log/user-data.log` - Log di esecuzione dello script userdata
- `/var/log/iptables.log` - Log del traffico nftables (se abilitato)

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | n/a |

## Modules

No modules.

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
| [aws_instance.nat_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_key_pair.rsa_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_network_interface.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_network_interface_attachment.nat_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_attachment) | resource |
| [aws_route.private_subs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.natgw_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.natgw_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.nat_instance_ssh_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [tls_private_key.pk_nat](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.latest_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Random name prefix for resources | `string` | n/a | yes |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | List of private route table IDs | `list(string)` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of public subnet IDs | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | `string` | n/a | yes |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID for NAT instances. If null, uses latest Amazon Linux 2023. To find AMI: aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-kernel-*-arm64' 'Name=virtualization-type,Values=hvm' --query 'Images[*].[ImageId,Name,CreationDate]' --output table --region <your-region> | `string` | `null` | no |
| <a name="input_create_ssh_keys"></a> [create\_ssh\_keys](#input\_create\_ssh\_keys) | Create ssh keys for the NAT instance/s | `bool` | `false` | no |
| <a name="input_credits_mode"></a> [credits\_mode](#input\_credits\_mode) | Credits mode for NAT instances. Can be `standard` or `unlimited` | `string` | `"unlimited"` | no |
| <a name="input_disk_configuration"></a> [disk\_configuration](#input\_disk\_configuration) | Disk configuration for NAT instances | <pre>object({<br/>    delete_on_termination = optional(bool),<br/>    encrypted             = optional(bool),<br/>    iops                  = optional(number),<br/>    kms_key_id            = optional(string),<br/>    tags                  = optional(map(string)),<br/>    throughput            = optional(number),<br/>    size                  = optional(number),<br/>    type                  = optional(string)<br/>  })</pre> | <pre>{<br/>  "delete_on_termination": true,<br/>  "encrypted": true,<br/>  "size": 30,<br/>  "type": "gp3"<br/>}</pre> | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Enable CloudWatch logging for NAT instances | `bool` | `false` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for NAT instances | `string` | `"t4g.nano"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Log retention in days | `string` | `7` | no |
| <a name="input_nat_instance_per_az"></a> [nat\_instance\_per\_az](#input\_nat\_instance\_per\_az) | Whether to create a NAT instance per AZ or a single NAT instance for all AZs | `bool` | `false` | no |
| <a name="input_user_data_script"></a> [user\_data\_script](#input\_user\_data\_script) | Path to the custom user data script. By default use /ec2\_conf/default\_userdata.sh | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_instance_details"></a> [nat\_instance\_details](#output\_nat\_instance\_details) | Details of NAT instances including ID and Public IP |
| <a name="output_nat_instance_ids"></a> [nat\_instance\_ids](#output\_nat\_instance\_ids) | IDs of the NAT EC2 instances |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Public IPs of the NAT instances |
<!-- END_TF_DOCS -->