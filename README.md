# PI — Infraestrutura em Nuvem: Sistema de Aluguel de Carros

Projeto Integrador — Uniamérica Descomplica — Prof. Gildomiro Bairros

**Entrega 1:** Projeto de Arquitetura e Decisões de Infraestrutura (tag `entrega-1`)

## Integrantes e responsabilidades

| Integrante | Responsabilidade |
|---|---|
| Kristhian dos Santos Magalhães | Infraestrutura: tecnologias, versões e dimensionamento (seções 5.6 e 5.7) |
| Miguel Grigato Garbo | Arquitetura e Rede: diagrama, plano de endereçamento e tabelas de rota (seções 5.1, 5.2, 5.3 e 5.4) |
| João Pedro Rodrigues de Lima | Documentação e entrega: IA.md, organização do repositório e apresentação (seção 5.11) |
| Moroni de Melo | Custos: calculadora oficial e cenários de custo (seção 5.9) |
| João Felini | Segurança: security groups, ADRs e riscos (seções 5.5, 5.8 e 5.10) |

## Visão geral

Sistema web para gerenciamento de frota e reserva de aluguel de carros, com frontend em React, backend em Java/Spring Boot e banco PostgreSQL. A infraestrutura foi projetada para a **AWS, região us-east-2 (Ohio)**: uma VPC com uma sub-rede pública (proxy Nginx e NAT Gateway) e uma sub-rede privada (hosts Amazon ECS do frontend e do backend e instância do PostgreSQL).

## Estrutura do repositório

```
/
├── README.md                    # Identificação do grupo e visão geral
├── IA.md                        # Declaração de uso de IA
├── docs/
│   ├── arquitetura.md           # Seções 5.1 a 5.7, 5.9 e 5.10
│   ├── adr/                     # Registros de Decisão Arquitetural (5.8)
│   │   ├── 001-acesso-administrativo.md
│   │   ├── 002-saida-internet-subrede-privada.md
│   │   └── 003-localizacao-banco.md
│   ├── diagramas/
│   │   ├── arquitetura.drawio   # Fonte editável
│   │   └── arquitetura.png      # Imagem exportada
│   └── custos/
│       ├── estimativa.md        # Detalhamento da estimativa
│       └── estimativa.pdf       # Exportação da AWS Pricing Calculator
└── infra/                       # Vazio na entrega 1; usado na Entrega 2 (Terraform)
```

## Documentos

- [Documento de arquitetura](docs/arquitetura.md)
- [Registros de Decisão Arquitetural](docs/adr/)
- [Diagrama de arquitetura](docs/diagramas/arquitetura.png) ([fonte editável](docs/diagramas/arquitetura.drawio))
- [Estimativa de custos](docs/custos/estimativa.md) ([PDF da calculadora](docs/custos/estimativa.pdf))
- [Declaração de uso de IA](IA.md)
