## 5.9 Estimativa de Custos

A estimativa de custos da arquitetura foi calculada utilizando a **AWS Pricing Calculator** para a região **US East (Ohio) / us-east-2**. A exportação da estimativa (Cenário A) está disponível em `docs/custos/estimativa.pdf`.

### Detalhamento dos Custos (Operação Contínua - 730h/mês)

| Recurso / Componente | Qtd | Especificação | Custo Mensal Estimado |
| :--- | :---: | :--- | :---: |
| **Nginx** | 1 | Instância `t3.micro` + Volume EBS `gp3` (4 GB) | US$ 7,91 |
| **ECS Frontend** | 1 | Instância `t3.medium` + Volume EBS `gp3` (4 GB) | US$ 30,69 |
| **ECS Backend** | 1 | Instância `t3.medium` + Volume EBS `gp3` (4 GB) | US$ 30,69 |
| **PostgreSQL** | 1 | Instância `t3.micro` + Volume EBS `gp3` (8 GB) | US$ 8,23 |
| **VPC NAT Gateway** | 1 | 1 Gateway ativo na sub-rede pública | US$ 32,85 |
| **Custo Total Estimado** | -- | -- | **US$ 110,37 / mês** |

### Ajustes após a revisão do documento (Cenário A)

A revisão das seções 5.6 e 5.7 aumentou os volumes raiz para o mínimo aceito pelas AMIs (8 GiB na Amazon Linux 2023 e 30 GiB na ECS-Optimized) e identificou dois itens que não estavam na estimativa da calculadora. Preços unitários de `us-east-2`: EBS gp3 US$ 0,08/GB-mês, IPv4 público US$ 0,005/hora, dados processados pelo NAT Gateway US$ 0,045/GB.

| Ajuste | Cálculo | Custo mensal |
| :--- | :--- | :---: |
| Disco do Nginx: 4 → 8 GiB | +4 GB × US$ 0,08 | + US$ 0,32 |
| Discos dos hosts ECS: 4 → 30 GiB (2 hosts) | +52 GB × US$ 0,08 | + US$ 4,16 |
| IPv4 público (Elastic IP do Nginx) | 730 h × US$ 0,005 | + US$ 3,65 |
| Dados processados pelo NAT (estimativa de 10 GB/mês) | 10 GB × US$ 0,045 | + US$ 0,45 |
| **Cenário A ajustado** | US$ 110,37 + US$ 8,58 | **US$ 118,95 / mês** |

---

### Cenário B: período de trabalho da Entrega 2

O ambiente só ficará ligado durante as sessões de teste e na apresentação, e será destruído com `terraform destroy` ao fim de cada sessão (ver plano de controle de custos abaixo). Horas previstas:

| Atividade | Horas |
| :--- | :---: |
| 8 sessões de implantação e testes (outubro e novembro), 4 h cada | 32 h |
| Ensaio final e apresentação em 23/11 | 8 h |
| **Total previsto** | **40 h** |

| Item | Cálculo | Custo |
| :--- | :--- | :---: |
| 2 × `t3.medium` (hosts ECS) | 2 × 40 h × US$ 0,0416 | US$ 3,33 |
| 2 × `t3.micro` (Nginx e PostgreSQL) | 2 × 40 h × US$ 0,0104 | US$ 0,83 |
| NAT Gateway (hora) | 40 h × US$ 0,045 | US$ 1,80 |
| IPv4 público | 40 h × US$ 0,005 | US$ 0,20 |
| EBS gp3 (76 GB, só enquanto o ambiente existe) | 76 GB × US$ 0,08 × 40/730 | US$ 0,33 |
| Dados processados pelo NAT (pull de imagens a cada recriação, ~4 GB) | 4 GB × US$ 0,045 | US$ 0,18 |
| **Total do Cenário B** | | **≈ US$ 6,67** |

O Cenário B é o valor que o grupo efetivamente pagará, cerca de **5,6% do Cenário A**, e fica abaixo do alerta de orçamento de US$ 15,00 (seção 5.9.1). Se as sessões passarem de 40 h, cada hora adicional custa cerca de US$ 0,16.

---

### Análise dos Custos

* **Item Mais Caro:** O componente de maior custo na arquitetura é o **VPC NAT Gateway** (~US$ 32,85/mês), seguido pelas duas instâncias de aplicação **`t3.medium`** (~US$ 30,37/mês cada).
* **Proposta de Redução de Custo:** Para ambientes de desenvolvimento, o NAT Gateway gerenciado poderia ser substituído por uma instância EC2 rodando NAT (ex: `t3.micro`), reduzindo o custo fixo de rede de US$ 32,85 para US$ 7,59. No entanto, perde-se o gerenciamento automatizado, a largura de banda elástica e a alta disponibilidade nativa do serviço gerenciado da AWS.
* **Nível Gratuito (AWS Free Tier):** A conta AWS que conterá a infraestrutura está no plano gratuito (Free Tier), com US$ 100 em créditos. Os créditos foram considerados apenas como forma de pagamento: os valores dos cenários A e B foram calculados sem desconto de nível gratuito, para que o grupo saiba o custo real caso os créditos acabem.

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