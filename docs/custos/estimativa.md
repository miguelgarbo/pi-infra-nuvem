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

### Análise dos Custos

* **Item Mais Caro:** O componente de maior custo na arquitetura é o **VPC NAT Gateway** (~US$ 32,85/mês), seguido pelas duas instâncias de aplicação **`t3.medium`** (~US$ 30,37/mês cada).
* **Proposta de Redução de Custo:** Para ambientes de desenvolvimento, o NAT Gateway gerenciado poderia ser substituído por uma instância EC2 rodando NAT (ex: `t3.micro`), reduzindo o custo fixo de rede de US$ 32,85 para US$ 7,59. No entanto, perde-se o gerenciamento automatizado, a largura de banda elástica e a alta disponibilidade nativa do serviço gerenciado da AWS.
* **Nível Gratuito (AWS Free Tier):** A conta AWS que cntem a Infraestrutura esta logada em uma conta Free Tier. Possibilitando 100 Dolares em creditos.

---

