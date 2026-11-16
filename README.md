# PI — Infraestrutura em Nuvem: Sistema de Aluguel de Carros

Projeto Integrador — Uniamérica Descomplica — Prof. Gildomiro Bairros

| Entrega | Conteúdo | Tag |
|---|---|---|
| **Entrega 1** | Projeto de Arquitetura e Decisões de Infraestrutura | `entrega-1` |
| **Entrega 2** | Infraestrutura como Código (Terraform), segurança, backup e alta disponibilidade | `entrega-2` |

## Visão geral

Sistema web para gerenciamento de frota e reserva de aluguel de carros, com frontend em React, backend em Java/Spring Boot e banco PostgreSQL, hospedado na **AWS**.

- **Entrega 1:** a infraestrutura foi projetada para a região `us-east-2` (Ohio): uma VPC com uma sub-rede pública (proxy Nginx e NAT Gateway) e uma sub-rede privada (hosts Amazon ECS do frontend e do backend e instância do PostgreSQL).
- **Entrega 2:** a arquitetura foi implementada com **Terraform**. Um `terraform apply` provisiona a VPC, o proxy Nginx, os serviços no ECS Fargate, o banco no RDS e o acesso administrativo. O detalhamento está em [`infra/terraform/README.md`](infra/terraform/README.md).

## Integrantes e responsabilidades

### Entrega 1

| Integrante | Responsabilidade |
|---|---|
| Kristhian dos Santos Magalhães | Infraestrutura: tecnologias, versões e dimensionamento (seções 5.6 e 5.7) |
| Miguel Grigato Garbo | Arquitetura e Rede: diagrama, plano de endereçamento e tabelas de rota (seções 5.1, 5.2, 5.3 e 5.4) |
| João Pedro Rodrigues de Lima | Documentação e entrega: IA.md, organização do repositório e apresentação (seção 5.11) |
| Moroni de Melo | Custos: calculadora oficial e cenários de custo (seção 5.9) |
| João Felini | Segurança: security groups, ADRs e riscos (seções 5.5, 5.8 e 5.10) |

### Entrega 2

O trabalho foi dividido em cinco áreas, e cada integrante conduz pelo menos uma demonstração.

| Pessoa | Responsável | Área | Entregáveis | Demonstrações |
|---|---|---|---|---|
| 1 | Miguel Grigato Garbo | **Infraestrutura base (Parte A)** | Código Terraform (rede, security groups, instâncias, outputs); requisitos R1 a R11 e S2 (egress restrito); alerta de orçamento antes do primeiro `apply`; encerramento com tag `entrega-2`, `git archive` e `terraform destroy` com evidência | D1 (plan sem alterações e outputs) e D4 (NAT e isolamento) |
| 2 | João Pedro Felini | **Aplicação e hardening do SO** | R12 (instalação da aplicação); S1 (SSH sem senha e sem root), S3 (HTTPS com redirecionamento) e S4 (gestão de segredos); README completo | D2 (aplicação via HTTPS) e D3 (acesso administrativo e recusa de senha) |
| 3 | João Pedro Rodrigues de Lima | **Segurança** | S5 (identidade de instância, em conjunto com a Pessoa 4), S6 (criptografia dos discos), S7 (Trivy/Checkov e Gitleaks) e S8 (MFA com evidência); `docs/seguranca.md` com os achados e pelo menos 5 ameaças concretas; evidências em `docs/evidencias/` | D5 (um achado corrigido, um aceito e segredos fora do código) |
| 4 | Kristhian dos Santos Magalhães | **Backup (Parte D)** | Política mínima (bucket com criptografia explícita, ciclo de vida de no máximo 2 dias, role da instância restrita ao bucket e pelo menos uma cópia gerada); `docs/backup.md` (B1 a B6, política GFS, RPO/RTO e limites da política mínima); B7 com a tabela de custo de 12 meses | D6 (política mínima e custo anual da GFS) |
| 5 | Moroni de Melo | **Alta disponibilidade e fechamento (Parte C)** | `arquitetura-ha.drawio/png` (H1 a H7); `docs/altadisponibilidade.md` com o custo comparado ao cenário A; 2 novos ADRs (HA e backup); `docs/errata.md`; issues do professor respondidas; `IA.md`; vídeo de contingência; custo real comparado ao cenário B | D7 (alta disponibilidade e análise de custo) |

### Organização da equipe

- **Dependências:** a Pessoa 1 entrega rede, security groups e instâncias logo no início, porque as Pessoas 2, 3 e 4 dependem disso. As Pessoas 3 e 4 combinam entre si a role da instância (S5).
- **Errata:** como a Pessoa 5 mantém o `docs/errata.md`, todos avisam qualquer divergência entre o projeto e o que foi implantado.


## Infraestrutura implementada (Terraform)

| Camada | Implementação |
|---|---|
| Rede | VPC `10.20.0.0/20` em `us-east-1`, com sub-rede pública `10.20.0.0/24` e sub-redes privadas `10.20.1.0/24` e `10.20.2.0/24` em duas zonas de disponibilidade, Internet Gateway e NAT Gateway |
| Entrada | EC2 `t3.micro` com Nginx como proxy reverso e único ponto de entrada público |
| Aplicação | Frontend e backend (Spring Boot) no **ECS Fargate**, com 2 réplicas cada, uma por zona |
| Banco de dados | **RDS PostgreSQL Multi-AZ** com replicação síncrona |
| DNS interno | **AWS Cloud Map** (`miguel-aluguel.internal`) |
| Segurança de rede | Security Groups encadeados por referência: cada camada só aceita tráfego da camada anterior |
| Acesso administrativo | **AWS Systems Manager (Session Manager)**, sem chave `.pem` e sem porta 22 aberta |
| Imagens | Amazon ECR (frontend e backend) |

### Como executar

```bash
cd infra/terraform
cp terraform.tfvars.ex terraform.tfvars   # preencher os valores
terraform init
terraform plan
terraform apply
```

Para conectar na instância do Nginx pelo SSM:

```bash
$(terraform output -raw ssm_command)
```

> **Aviso de custos:** NAT Gateway, RDS Multi-AZ, instâncias EC2 e tarefas Fargate são cobrados por hora. Ao terminar os testes ou a demonstração, rode `terraform destroy` para remover todos os recursos.

### Alterações em relação à Entrega 1

Os pontos abaixo diferem do que foi projetado na Entrega 1 e devem constar no `docs/errata.md`, vinculados aos ADRs correspondentes.

| Item | Entrega 1 | Implementado |
|---|---|---|
| Região | `us-east-2` (Ohio) | `us-east-1` (N. Virginia) |
| Zonas de disponibilidade | Uma sub-rede privada | Duas sub-redes privadas, em duas zonas |
| Frontend e backend | Hosts Amazon ECS | ECS Fargate (sem gerenciar hosts) |
| Banco de dados | Instância do PostgreSQL | RDS PostgreSQL Multi-AZ |
| Acesso administrativo | Conforme o ADR 001 | AWS Systems Manager (sem SSH) |

## Estrutura do repositório

```
/
├── README.md                    # Identificação do grupo e visão geral
├── IA.md                        # Declaração de uso de IA
├── docs/
│   ├── arquitetura.md           # Seções 5.1 a 5.7, 5.9 e 5.10
│   ├── seguranca.md             # Achados de segurança e ameaças (Entrega 2)
│   ├── backup.md                # Plano de backup, GFS, RPO/RTO (Entrega 2)
│   ├── altadisponibilidade.md   # Arquitetura de alta disponibilidade e custo (Entrega 2)
│   ├── errata.md                # Divergências entre o projeto e o implantado (Entrega 2)
│   ├── adr/                     # Registros de Decisão Arquitetural
│   │   ├── 001-acesso-administrativo.md
│   │   ├── 002-saida-internet-subrede-privada.md
│   │   └── 003-localizacao-banco.md
│   ├── diagramas/
│   │   ├── arquitetura.drawio   # Fonte editável
│   │   ├── arquitetura.png      # Imagem exportada
│   │   ├── arquitetura-ha.drawio
│   │   └── arquitetura-ha.png
│   ├── custos/
│   │   ├── estimativa.md        # Detalhamento da estimativa
│   │   └── estimativa.pdf       # Exportação da AWS Pricing Calculator
│   └── evidencias/              # Relatórios de análise, MFA e capturas de backup
└── infra/
    └── terraform/
        ├── README.md            # Documentação detalhada da infraestrutura
        ├── provider.tf          # Provider AWS
        ├── variables.tf         # Variáveis da infraestrutura e da aplicação
        ├── terraform.tfvars.ex  # Template para criar o terraform.tfvars
        ├── network.tf           # VPC, sub-redes, IGW, NAT Gateway e rotas
        ├── security.tf          # Security Groups e regras
        ├── iam.tf               # Role, política e instance profile do SSM
        ├── compute.tf           # EC2 Nginx, cluster ECS, task definitions e services
        ├── database.tf          # DB subnet group e RDS Multi-AZ
        ├── cloudmap.tf          # Namespace e serviços de DNS interno
        └── outputs.tf           # Outputs com IPs e comando de acesso SSM
```

## Documentos

- [Documento de arquitetura](docs/arquitetura.md)
- [Registros de Decisão Arquitetural](docs/adr/)
- [Diagrama de arquitetura](docs/diagramas/arquitetura.png) ([fonte editável](docs/diagramas/arquitetura.drawio))
- [Estimativa de custos](docs/custos/estimativa.md) ([PDF da calculadora](docs/custos/estimativa.pdf))
- [Infraestrutura como código (Terraform)](infra/terraform/README.md)
- [Declaração de uso de IA](IA.md)
