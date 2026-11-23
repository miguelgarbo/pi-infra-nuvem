# Errata (Entrega 2)

Este documento registra cada divergência entre o projeto da Entrega 1 e o que foi implantado, com o motivo. Quando a divergência muda uma decisão, o ADR afetado é citado pelo número.

> Documento mantido pela Pessoa 5. Os itens abaixo foram levantados a partir do README e da Parte B (segurança). Os ADRs novos que substituem decisões da Entrega 1 são criados na Parte C.

## 1. Divergências de arquitetura

| # | Item | Projeto (Entrega 1) | Implantado (Entrega 2) | Motivo | ADR afetado |
|---|---|---|---|---|---|
| E1 | Região | `us-east-2` (Ohio) | `us-east-1` (N. Virginia) | **[CONFIRMAR motivo com o Miguel]** | ADR-002 (cita `us-east-2a`) |
| E2 | Plano de endereçamento | VPC `10.50.0.0/24`, sub-redes `/28` | VPC `10.20.0.0/20`, sub-rede pública `10.20.0.0/24` e privadas `10.20.1.0/24` e `10.20.2.0/24` | Passou a ter duas sub-redes privadas em zonas diferentes (E3). **[CONFIRMAR com o Miguel o motivo da troca da faixa `10.50` para `10.20`]** | ADR-002 (cita `10.50.0.16/28`) |
| E3 | Zonas de disponibilidade | Uma sub-rede privada em uma zona | Duas sub-redes privadas, em `us-east-1a` e `us-east-1b` | O RDS exige um DB subnet group com duas zonas, e as tasks foram distribuídas entre elas. | — |
| E4 | Frontend e backend | ECS com hosts EC2 | ECS Fargate | Elimina a gestão dos hosts (patches, SSM Agent) e o ponto único de falha do host (risco 3 da seção 5.10). | — |
| E5 | Banco de dados | PostgreSQL em EC2 `t3.micro` | Amazon RDS for PostgreSQL Multi-AZ | Backup automático, criptografia e failover gerenciados (risco 2 da seção 5.10). | **ADR-003 substituída** |

## 2. Incidente de segurança

| # | Data | O que ocorreu | Detecção | Tratamento |
|---|---|---|---|---|
| I1 | 13/11/2026 | A senha do usuário do RDS foi escrita direto no código em `infra/terraform/rds.tf`, linha 10, no commit `0f10cb5`, um rascunho do Terraform. No commit seguinte (`b46f9d0`) ela passou para a variável `DB_PASSWORD`, mas continua no histórico do repositório público. | Gitleaks (regra `hashicorp-tf-password`), na análise de segredos do S7. Relatório em `docs/evidencias/seguranca/gitleaks.txt`. | (1) **Revogação:** a senha exposta foi descartada, e o ambiente usa uma senha diferente, fornecida pelo `terraform.tfvars` **[CONFIRMAR com quem faz o apply]**. (2) A senha passou a ser guardada no SSM Parameter Store como `SecureString` (S4). (3) O histórico não foi reescrito, porque cópias já clonadas continuariam com o valor. Detalhes em `docs/seguranca.md`, seção 2.2. |

## 3. Correções feitas durante a implantação

| # | Item | O que foi corrigido |
|---|---|---|
| C1 | `infra/.terraform.lock.hcl` | O commit `6bf03b3` versionou o arquivo com marcadores de conflito de merge (`<<<<<<<`, `=======`, `>>>>>>>`), o que fazia o `terraform init` falhar. Os marcadores foram removidos, e os hashes conferidos com `terraform providers lock` para Windows, Linux e macOS. |
| C2 | Sub-rede pública | A sub-rede pública passou a ter `map_public_ip_on_launch = false` (achado AWS-0164 do Trivy). Só a EC2 do Nginx e o NAT recebem IP público, e de forma explícita. |
