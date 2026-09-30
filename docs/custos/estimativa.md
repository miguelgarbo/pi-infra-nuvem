## 5.9 Estimativa de Custos

A estimativa de custos da arquitetura foi calculada utilizando a **AWS Pricing Calculator** para a região **US East (Ohio) / us-east-2**. O relatório exportado está disponível em `docs/custos/estimativa.md`.

### Detalhamento dos Custos (Operação Contínua - 730h/mês)

| Recurso / Componente | Qtd | Especificação | Custo Mensal Estimado |
| :--- | :---: | :--- | :---: |
| **Nginx** | 1 | Instância `t3.micro` + Volume EBS `gp3` (4 GB) | US$ 7,91 |
| **ECS Frontend** | 1 | Instância `t3.medium` + Volume EBS `gp3` (4 GB) | US$ 30,69 |
| **ECS Backend** | 1 | Instância `t3.medium` + Volume EBS `gp3` (4 GB) | US$ 30,69 |
| **PostgreSQL** | 1 | Instância `t3.micro` + Volume EBS `gp3` (8 GB) | US$ 8,23 |
| **VPC NAT Gateway** | 1 | 1 Gateway ativo na sub-rede pública | US$ 32,85 |
| **Custo Total Estimado** | -- | -- | **US$ 110,37 / mês** |

---

