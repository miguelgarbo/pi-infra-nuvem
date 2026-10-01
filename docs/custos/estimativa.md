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

### Plano de Controle de Custos

Para a gestão financeira do projeto, o grupo adotará as seguintes estratégias:

1. **Automação via Infraestrutura como Código (IaC):** Todo o ambiente de rede e computação é provisionado utilizando **Terraform**.
2. **Destruição do Ambiente:** A execução do comando `terraform destroy` será feita sempre que o ambiente não estiver sob uso ativo para interromper a cobrança por hora de computação e NAT Gateway.
3. **Trade-off Custo vs. Esforço:** O grupo aceita o esforço adicional de re-executar os scripts de provisionamento e carga inicial da aplicação a cada nova sessão de uso, garantindo em troca que o custo acumulado fique muito abaixo do valor mensal contínuo.
4. **Alerta de Orçamento (AWS Budgets):** Foi configurado um alerta no AWS Budgets para notificar o grupo via e-mail caso os gastos acumulados ultrapassem o limite de **US$ 15,00**.
5. **Tagging de Recursos:** Todos os recursos criados via Terraform recebem tags padronizadas (ex: `Project: PI-Uniamerica`, `Environment: Test`, `ManagedBy: Terraform`) para facilitar o rastreamento no painel de faturamento da AWS.

## 5.9.1. Controle Prático de Custos e Alertas (AWS Budgets)

Para garantir a previsibilidade financeira e evitar cobranças inesperadas durante os testes da infraestrutura, foi implementado um mecanismo de controle ativo no serviço **AWS Budgets**.

### Configuração do Orçamento:
- **Nome do Orçamento:** `Alerta-PI-15USD`
- **Tipo de Orçamento:** Orçamento de custos (*Cost Budget*)
- **Período:** Mensal (*Monthly*)
- **Limite Máximo Estipulado:** US$ 15,00 / mês
- **Escopo:** Todos os serviços da conta AWS (visão global do projeto)

### Regra de Disparo (Alert Threshold):
- **Gatilho de Alerta:** 80% do valor orçado (**US$ 12,00**).
- **Métrica:** Custos reais acumulados (*Actual Costs*).
- **Ação Automática:** Notificação via e-mail para a equipe técnica assim que o acumulado atingir US$ 12,00, servindo como sinalizador imediato para a destruição temporária do ambiente via IaC (`terraform destroy`).