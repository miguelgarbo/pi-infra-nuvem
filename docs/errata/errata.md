# Errata simplificada: o que o enunciado realmente pede

Projeto Integrador, Entrega 2 (Uniamérica Descomplica)

O enunciado pede bem menos do que o rascunho inicial do `errata.md` continha. Este documento resume o que é necessário e o que pode ficar de fora.

## O que a seção 8 pede da errata

Só isto: **toda divergência entre o que foi projetado na Entrega 1 e o que foi implantado, com o motivo.** Se a mudança alterou uma decisão, cite o número do ADR afetado. O ADR original recebe o status "substituída" e um novo ADR é criado. Não há formato obrigatório, e uma tabela simples basta.

## Versão simples (o suficiente)

| # | O que mudou | Entrega 1 | Implantado | Motivo | ADR |
|---|---|---|---|---|---|
| 1 | Computação | ECS em EC2 | ECS Fargate | Simplificar a operação | — |
| 2 | Banco de dados | PostgreSQL em EC2 | RDS PostgreSQL | Serviço gerenciado, menos operação | ADR-003 (substituída) |
| 3 | Região e rede | us-east-2, `10.50.0.0/24` | us-east-1, `10.20.0.0/20` | [motivo] | — |
| 4 | Zonas | 1 AZ | 2 AZs nas sub-redes privadas | Exigência do RDS e das tasks | — |
| 5 | Serviços novos | — | Cloud Map, SSM Parameter Store, CloudWatch Logs | Descoberta de serviço, segredos e logs no Fargate | — |

Com isso o exigido está cumprido. As outras linhas do rascunho anterior (nomes dos security groups, estado do Terraform) são detalhes opcionais.

## O que não faz parte da errata

A seção de **pendências** no fim do rascunho não é da errata. São problemas que o grupo precisa resolver, principalmente:

1. **Multi-AZ já implantado**, enquanto o enunciado diz que a alta disponibilidade só deve ser projetada.
2. **SSH na demonstração D3**, que não combina bem com Fargate.

Eles podem custar nota e vale levá-los ao grupo, mas não precisam estar no arquivo da errata, a não ser que mudem o que foi implantado.

## Sugestão

Use a tabela simples acima e complete apenas o motivo da mudança de região e de CIDR. Se quiser, o `errata.md` pode ser reescrito de forma enxuta, com 5 a 6 linhas, pronto para colar no repositório.
