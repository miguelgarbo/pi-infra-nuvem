# Infraestrutura AWS – Miguel Aluguel

Documentação da infraestrutura do projeto **Miguel Aluguel** na AWS: uma aplicação com frontend e backend em contêineres (ECS Fargate), banco de dados relacional com alta disponibilidade (RDS Multi-AZ) e um ponto de entrada via NGINX em uma instância EC2.

![Diagrama da infraestrutura](docs/diagramas/diagrama_infra_pi_4.drawio.png)

---

## Sumário

- [Visão geral](#visão-geral)
- [Tecnologias e serviços](#tecnologias-e-serviços)
- [Rede](#rede)
- [Componentes](#componentes)
- [Security Groups](#security-groups)
- [Fluxo de tráfego](#fluxo-de-tráfego)
- [Acesso administrativo](#acesso-administrativo)
- [Alta disponibilidade](#alta-disponibilidade)
- [Deploy das imagens](#deploy-das-imagens)
- [Limitações e pontos de melhoria](#limitações-e-pontos-de-melhoria)

---

## Visão geral

| Item | Valor |
|---|---|
| Provedor | AWS |
| Região | `us-east-1` (US East / N. Virginia) |
| VPC | `vpc_miguel_aluguel` – `10.20.0.0/20` |
| Zonas de disponibilidade | `us-east-1a` e `us-east-1b` |
| Computação das aplicações | ECS com Fargate (frontend e backend) |
| Ponto de entrada | EC2 `t3.micro` com NGINX (proxy reverso) |
| Banco de dados | Amazon RDS (Primary + Standby, replicação síncrona) |
| Service discovery | AWS Cloud Map (`miguel-aluguel.internal`) |
| Registro de imagens | Amazon ECR (frontend e backend) |
| Acesso administrativo | AWS Systems Manager |

A arquitetura segue o modelo de **sub-rede pública mínima + sub-redes privadas para a aplicação e o banco**: somente o NGINX fica exposto à internet; frontend, backend e banco ficam em sub-redes privadas, sem IP público.

---

## Tecnologias e serviços

- **Amazon VPC** – isolamento de rede
- **Internet Gateway** – entrada/saída de tráfego da internet para a sub-rede pública
- **NAT Gateway** – saída das sub-redes privadas para a internet (ex.: pull de imagens do ECR)
- **Amazon EC2 (t3.micro)** – hospeda o NGINX
- **NGINX** – proxy reverso / ponto de entrada HTTPS
- **Amazon ECS + AWS Fargate** – execução dos contêineres de frontend e backend sem gerenciar servidores
- **Amazon ECR** – repositórios das imagens `frontend` e `backend`
- **Amazon RDS** – banco de dados com instância Primary e Standby
- **AWS Cloud Map** – descoberta de serviços via DNS interno
- **AWS Systems Manager** – acesso administrativo à instância EC2

---

## Rede

### VPC

- **Nome:** `vpc_miguel_aluguel`
- **CIDR:** `10.20.0.0/20`

### Sub-redes

| Sub-rede | Tipo | CIDR | AZ | Recursos |
|---|---|---|---|---|
| Public subnet | Pública | `10.20.0.0/24` | `us-east-1a` | EC2 (NGINX), NAT Gateway |
| Private subnet 1 | Privada | `10.20.1.0/24` | `us-east-1a` | Frontend #1, Backend #1, RDS Primary |
| Private subnet 2 | Privada | `10.20.2.0/24` | `us-east-1b` | Frontend #2, Backend #2, RDS Standby |

### Gateways

- **Internet Gateway:** anexado à VPC; recebe o tráfego HTTPS (porta 443) dos usuários e o encaminha à sub-rede pública.
- **NAT Gateway:** localizado na sub-rede pública (`us-east-1a`); permite que as tarefas Fargate das sub-redes privadas acessem a internet e o ECR sem ficarem expostas.

---

## Componentes

### EC2 – NGINX (`t3.micro`)

- Localizado na **sub-rede pública** (`10.20.0.0/24`).
- Security Group: `app_access`.
- Atua como **proxy reverso**, recebendo as requisições HTTPS dos usuários e encaminhando para os serviços internos usando os nomes registrados no Cloud Map:
  - `frontend.miguel-aluguel.internal:80`
  - `backend.miguel-aluguel.internal:8080`

### ECS Fargate – Frontend

- 2 tarefas (uma por AZ): **Frontend #1** (`us-east-1a`) e **Frontend #2** (`us-east-1b`).
- Security Group: `front-pi`.
- Porta: `80`.
- Imagem obtida do repositório ECR `frontend`.

### ECS Fargate – Backend

- 2 tarefas (uma por AZ): **Backend #1** (`us-east-1a`) e **Backend #2** (`us-east-1b`).
- Security Group: `back-pi`.
- Porta: `8080`.
- Imagem obtida do repositório ECR `backend`.
- Comunica-se com o banco de dados RDS.

### Amazon RDS

- **Primary DB** na sub-rede privada de `us-east-1a`.
- **Standby DB** na sub-rede privada de `us-east-1b`.
- Security Group: `rds-pi`.
- **Replicação síncrona** entre Primary e Standby (RDS Multi-AZ), com failover automático.
- Engine / versão / classe da instância: _preencher (ex.: PostgreSQL 16, db.t3.micro)_.

### AWS Cloud Map

- Namespace privado: `miguel-aluguel.internal`.
- Serviços registrados:

| Serviço | Endereço |
|---|---|
| Backend | `backend.miguel-aluguel.internal:8080` |
| Frontend | `frontend.miguel-aluguel.internal:80` |

### Amazon ECR

| Repositório | Descrição |
|---|---|
| `frontend` | Imagem do frontend |
| `backend` | Imagem do backend |

---

## Security Groups

| Security Group | Associado a | Finalidade |
|---|---|---|
| `app_access` | EC2 NGINX | Aceita HTTPS (443) vindo da internet |
| `front-pi` | Tarefas Fargate do frontend | Aceita tráfego do NGINX na porta 80 |
| `back-pi` | Tarefas Fargate do backend | Aceita tráfego do NGINX/frontend na porta 8080 |
| `rds-pi` | RDS Primary e Standby | Aceita conexões do `back-pi` na porta do banco |

> As regras abaixo foram inferidas a partir do diagrama. Ajuste conforme a configuração real.

| SG | Direção | Origem / Destino | Porta |
|---|---|---|---|
| `app_access` | Inbound | `0.0.0.0/0` | 443 |
| `front-pi` | Inbound | `app_access` | 80 |
| `back-pi` | Inbound | `app_access` | 8080 |
| `rds-pi` | Inbound | `back-pi` | 5432 |

---

## Fluxo de tráfego

1. O **usuário** acessa a aplicação via **HTTPS (443)**.
2. A requisição passa pelo **Internet Gateway** e chega ao **NGINX** na sub-rede pública.
3. O NGINX consulta o **Cloud Map** para resolver `frontend.miguel-aluguel.internal` e `backend.miguel-aluguel.internal`.
4. O tráfego é encaminhado para as tarefas **Fargate** (frontend na porta 80, backend na porta 8080) nas sub-redes privadas, distribuído entre as duas AZs.
5. O **backend** acessa o **RDS Primary**.
6. O RDS replica de forma **síncrona** para o **Standby** em outra AZ.
7. As tarefas Fargate saem para a internet / ECR através do **NAT Gateway** para baixar as imagens dos contêineres.

---

## Acesso administrativo

O administrador acessa a infraestrutura pelo **AWS Systems Manager** (Session Manager), sem necessidade de expor SSH (porta 22) nem de manter chaves `.pem`:

```
Admin → AWS Systems Manager → EC2 (NGINX)
```

Requisitos:

- A instância EC2 deve ter um **IAM Instance Profile** com a política `AmazonSSMManagedInstanceCore`.
- O SSM Agent precisa estar ativo na instância.

---

## Alta disponibilidade

| Camada | Estratégia |
|---|---|
| Frontend | 2 tarefas em AZs diferentes |
| Backend | 2 tarefas em AZs diferentes |
| Banco de dados | RDS Multi-AZ com Standby e replicação síncrona |
| Entrada (NGINX) | Instância única em `us-east-1a` |
| Saída (NAT Gateway) | Único em `us-east-1a` |

---



---

## Limitações e pontos de melhoria

- **Ponto único de falha na entrada:** o NGINX roda em uma única EC2 em uma única AZ. Se a instância ou a AZ falhar, a aplicação fica inacessível, mesmo com Fargate e RDS redundantes. Uma alternativa é usar um **Application Load Balancer** em duas sub-redes públicas, ou um Auto Scaling Group para o NGINX.
- **NAT Gateway único:** se `us-east-1a` falhar, as tarefas de `us-east-1b` perdem a saída para a internet/ECR. Considere um NAT Gateway por AZ ou **VPC Endpoints** (ECR, S3, CloudWatch Logs) para reduzir custo e dependência do NAT.
- **Sem sub-rede pública em `us-east-1b`:** necessária caso se adote ALB ou NAT redundante.
- **HTTPS:** garantir certificado válido (ex.: ACM + ALB, ou Let's Encrypt no NGINX).
- **Observabilidade:** configurar logs das tasks no CloudWatch Logs e alarmes (CPU, memória, saúde do RDS).
- **Backups do RDS:** confirmar retenção de backups automáticos e snapshots.

---
