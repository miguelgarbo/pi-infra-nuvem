# Plano de Backup (Parte D)

Este documento cobre os itens B1 a B7 da Entrega 2. Ele tem duas políticas com papéis diferentes:

| Política | Papel | Onde aparece |
|---|---|---|
| **Conservadora (GFS)** | O que o grupo recomendaria para operar a aplicação de verdade | Só neste plano, com custo para 12 meses |
| **Mínima** | Exercitar o mecanismo de backup com custo próximo de zero | Configurada por Terraform em `infra/database.tf` e demonstrada na D6 |

> **Mudança em relação à Entrega 1.** O ADR-003 previa o PostgreSQL em uma EC2. Na implantação o banco passou para o **Amazon RDS for PostgreSQL** (ver `docs/errata.md`). Para banco gerenciado, a seção 6.3 do enunciado aceita o **backup automático do próprio serviço** com a retenção configurada por Terraform, e é esse o mecanismo usado. Por isso não há bucket de backup nem role de instância para gravar nele.

---

## B1. Inventário

| Ativo | Precisa de backup? | Justificativa |
|---|---|---|
| **Banco PostgreSQL (RDS)**: usuários, veículos, locações e auditoria | **Sim** | É o único ativo com dado que não pode ser recriado. O Terraform recria a instância, mas vazia. |
| Arquivos enviados por usuários | Não existe | A aplicação não tem upload de arquivos; todos os dados dos veículos ficam no banco. |
| Sessões de usuário | Não existe | A autenticação é por JWT, sem estado no servidor (RNF04). |
| **State do Terraform** (`terraform.tfstate`) | **Sim, com outra forma de proteção** | Fica só na máquina de quem rodou o `apply`. Se for perdido com o ambiente no ar, os recursos ficam órfãos e continuam sendo cobrados. Em produção, ele iria para um backend remoto em S3 com versionamento. No trabalho, o risco é aceito: o ambiente é efêmero, e quem executa o `apply` é responsável pelo `destroy`. |
| **Segredos** (`terraform.tfvars`: senha do banco, `HASH_TOKEN`) | **Sim, fora da nuvem** | Não estão no Git (`.gitignore`). Precisam ficar em um gerenciador de senhas do grupo. Se forem perdidos, o banco restaurado não abre com a senha nova e os JWT emitidos deixam de valer. |
| Código Terraform e documentação | Não | Já estão versionados no GitHub, que é a cópia de segurança. |
| Imagens de contêiner (ECR) | Não | São reproduzíveis a partir do código-fonte da aplicação e ficam no ECR, que não é destruído pelo `terraform destroy`. |
| Configuração do Nginx (EC2) | Não | É recriada pelo `user_data` em `infra/compute.tf`. |
| Tarefas do ECS, rede, security groups | Não | Reproduzíveis pelo código. |
| Logs no CloudWatch | Não | Retenção de 14 dias definida no código. Perder logs antigos é aceito no escopo do trabalho. |

## B2. RPO e RTO

A aplicação é o sistema de reservas de uma locadora de pequeno a médio porte (seção 5.1 e RNF01 da Entrega 1). Perder uma reserva confirmada significa um cliente que chega ao balcão sem carro, então perda de dado pesa mais do que algumas horas fora do ar.

| Meta | Valor | Justificativa |
|---|---|---|
| **RPO** | **15 minutos** | Uma reserva perdida gera prejuízo direto. O backup automático do RDS permite restauração a um ponto no tempo (PITR), com os logs de transação enviados a cada 5 minutos, então a meta é cumprida com folga dentro da janela de retenção. |
| **RTO** | **2 horas** | A restauração do RDS cria uma **nova instância** com novo endpoint. Somam-se o tempo de restauração (dezenas de minutos para poucos GB), a atualização do `DB_URL` do backend e o novo deploy das tarefas no ECS. Duas horas atendem uma locadora que pode registrar reservas no balcão por um período curto. |

**Importante: o Multi-AZ não é backup.** O `multi_az = true` mantém uma réplica síncrona em outra zona. Se alguém apagar uma tabela, a réplica apaga a mesma tabela no mesmo instante. O Multi-AZ protege contra falha de zona ou de hardware; contra exclusão, corrupção e ataque, só o backup protege.

## B3. Política conservadora (GFS)

| Geração | Mecanismo | Frequência | Promoção | Retenção | Armazenamento |
|---|---|---|---|---|---|
| **Son** (filho) | Backup automático do RDS (snapshot diário + logs de transação) | Diária, janela 03:00 às 03:30 (Brasília) | — | **7 dias**, com PITR em qualquer minuto do período | Armazenamento de backup do RDS em us-east-1 |
| **Father** (pai) | Snapshot pelo **AWS Backup**, regra semanal | Domingo, 05:00 (Brasília), depois do diário e da janela de manutenção | O backup de **domingo** vira o semanal | **5 semanas** | AWS Backup, warm, us-east-1 |
| **Grandfather** (avô) | Snapshot pelo **AWS Backup**, regra mensal | Dia 1 de cada mês, 05:00 (Brasília) | O backup do **dia 1** (fechamento do mês anterior) vira o mensal | **12 meses** | AWS Backup, warm, us-east-1, com **cópia para us-east-2** |

Por que esses valores:

- **7 dias de Son** cobrem erros descobertos durante a semana, como um cadastro de frota apagado por engano ou uma importação errada.
- **5 semanas de Father** garantem que sempre exista um ponto de um mês atrás, mesmo em meses com cinco domingos.
- **12 meses de Grandfather** atendem fechamento mensal e auditoria de locações (quem alugou qual carro em determinado mês).
- **Só o Grandfather vai para outra região.** É a cópia que protege contra perda da região inteira; os diários e semanais seriam caros de copiar e perdem valor rápido.

**Classe de armazenamento.** O AWS Backup só oferece armazenamento frio para EBS, EFS e DynamoDB; para RDS, todas as gerações ficam na camada warm. A alternativa para baratear o Grandfather seria um `pg_dump` mensal para S3 Glacier Deep Archive, mas exigiria uma rotina própria e tem duração mínima de cobrança de 180 dias e custo de recuperação. Como o volume é pequeno, o grupo preferiu a simplicidade do AWS Backup.

**Consistência.** O banco é gerenciado, então os backups do RDS são consistentes do ponto de vista do PostgreSQL: o snapshot combinado com os logs de transação restaura um estado válido. No Multi-AZ, o snapshot é tirado da réplica standby, sem pausar a instância principal.

Como a política GFS ficaria no código (apenas projetada, **não aplicada** para não gerar custo):

```hcl
resource "aws_backup_vault" "gfs" {
  name = "miguel-aluguel-gfs"
}

resource "aws_backup_plan" "gfs" {
  name = "miguel-aluguel-gfs"

  rule {
    rule_name         = "father-semanal"
    target_vault_name = aws_backup_vault.gfs.name
    schedule          = "cron(0 8 ? * SUN *)" # domingo 08:00 UTC
    lifecycle { delete_after = 35 }
  }

  rule {
    rule_name         = "grandfather-mensal"
    target_vault_name = aws_backup_vault.gfs.name
    schedule          = "cron(0 8 1 * ? *)"   # dia 1, 08:00 UTC
    lifecycle { delete_after = 365 }
    copy_action {
      destination_vault_arn = "<vault em us-east-2>"
      lifecycle { delete_after = 365 }
    }
  }
}
```

A geração Son continua sendo o `backup_retention_period = 7` do próprio RDS.

## B4. Armazenamento

| Requisito | Como é atendido |
|---|---|
| **Fora da instância** | Os backups do RDS e os snapshots do AWS Backup ficam no armazenamento gerenciado da AWS, separados do volume do banco. Apagar a instância não apaga os snapshots do AWS Backup. |
| **Outra zona ou região** | O armazenamento de backup é regional e replicado entre zonas. O Grandfather tem cópia em us-east-2. |
| **Criptografia (S6)** | A instância tem `storage_encrypted = true` declarado no código. Os backups automáticos e snapshots herdam a criptografia da instância (chave `aws/rds`). |
| **Acesso restrito (S5)** | Nenhuma instância ou tarefa precisa gravar backup: o próprio RDS faz isso. As tarefas do ECS não têm *task role*, então a aplicação não tem permissão de IAM para listar ou apagar snapshots. Só integrantes autenticados na conta AWS, com MFA (S8), podem gerenciar backups. |

**"Se um invasor obtiver acesso à aplicação, ele consegue apagar os backups?"**

- **Pela AWS, não.** A aplicação não tem credencial de IAM, então não consegue chamar a API do RDS para apagar backups.
- **Pelo banco, ele consegue apagar dados.** Com a senha do banco, um invasor pode executar `DROP TABLE`. O Multi-AZ replica o estrago, mas o PITR restaura o banco para alguns minutos antes do ataque.
- **Em produção**, o vault do AWS Backup teria **Vault Lock** em modo *compliance*, para que nem um administrador comprometido consiga apagar os snapshots antes do fim da retenção.

## B5. Responsabilidade compartilhada

| Ativo | O que a AWS garante | O que é responsabilidade do grupo |
|---|---|---|
| Banco RDS | Executar os backups na janela, guardar os logs para o PITR, durabilidade do armazenamento, criptografia com a chave KMS, failover do Multi-AZ | Definir a retenção, ativar a criptografia, proteger a senha do banco, decidir quando restaurar, apontar a aplicação para a instância restaurada |
| Snapshots do AWS Backup | Executar as regras, aplicar o ciclo de vida, copiar entre regiões | Definir as regras, a retenção e o vault; controlar quem acessa a conta |
| State do Terraform | Nada (está na máquina do integrante) | Guardar o arquivo e destruir o ambiente antes de perdê-lo |
| Segredos (`tfvars`) | Nada (não estão na AWS) | Guardar em gerenciador de senhas e trocar se vazarem |
| Código e documentação | Nada (estão no GitHub) | Manter o repositório e a tag `entrega-2` |

## B6. Política mínima configurada

| Requisito (seção 6.3) | Como foi atendido |
|---|---|
| **Mecanismo** | Backup automático do RDS (geração Son), conforme a seção 6.3 para banco gerenciado |
| **Configuração por código** | `infra/database.tf`: `backup_retention_period`, `backup_window`, `storage_encrypted`, `delete_automated_backups` e `copy_tags_to_snapshot` |
| **Retenção** | **1 dia** (`var.db_backup_retention_days`). A variável tem uma regra de `validation` que rejeita valores fora de 1 a 2 no `terraform plan`. O valor seria 2, o máximo da seção 6.3, mas a conta usada está no plano gratuito da AWS (Free plan), que recusa retenção acima de 1 dia: o primeiro `terraform apply` com 2 dias falhou com `FreeTierRestrictionError`. Com 1 dia, a política continua dentro do limite do enunciado. |
| **Criptografia** | `storage_encrypted = true`, declarado explicitamente. Os backups herdam a criptografia da instância. Comprovação: `StorageEncrypted: true` no `describe-db-instances` e `Encrypted: true` no snapshot automatizado. |
| **Existência de cópia** | O RDS cria o primeiro backup automático logo depois de criar a instância. Ele aparece em *RDS → Snapshots → Sistema* e no comando abaixo. |
| **Custo** | **US$ 0,00** no período do trabalho (ver B7). |

Comandos de comprovação (usados na D6):

```bash
# Retenção, janela e criptografia da instância
aws rds describe-db-instances --db-instance-identifier miguel-aluguel-db \
  --query 'DBInstances[0].{Retencao:BackupRetentionPeriod,Janela:PreferredBackupWindow,Criptografado:StorageEncrypted,UltimoPontoRestauravel:LatestRestorableTime}'

# Backup automático existente e criptografado
aws rds describe-db-snapshots --db-instance-identifier miguel-aluguel-db \
  --snapshot-type automated \
  --query 'DBSnapshots[].{Snapshot:DBSnapshotIdentifier,Criado:SnapshotCreateTime,Status:Status,Criptografado:Encrypted}' --output table
```

**Expiração assíncrona.** O RDS remove os backups automáticos que saem da janela de retenção por um processo interno, sem garantia de horário exato. O grupo conta que uma cópia pode continuar visível algumas horas depois de completar 1 dia. O `delete_automated_backups = true` garante que, no `terraform destroy`, os backups automáticos sejam apagados junto com a instância, sem deixar nada sendo cobrado.

Escolhas deliberadas para o ambiente acadêmico, que **seriam diferentes em produção**:

- `skip_final_snapshot = true` e `delete_automated_backups = true` fazem o `destroy` apagar o banco sem deixar cópia. Em produção, seria `skip_final_snapshot = false` (snapshot final) e `delete_automated_backups = false`.
- Mudar `storage_encrypted` em um banco existente obriga a recriá-lo. Como o grupo destrói o ambiente após cada teste, isso não causa perda de dados no trabalho.

### O que a política mínima não protege, comparada à GFS

| Situação | Política mínima (1 dia) | GFS |
|---|---|---|
| Erro descoberto depois de 2 dias (ex.: locações apagadas na sexta, percebido na segunda seguinte) | **Não recupera**, o ponto já expirou | Recupera pelo Son (até 7 dias) |
| Dado corrompido descoberto semanas depois | Não recupera | Recupera pelo Father (até 5 semanas) |
| Consulta ou auditoria de um mês antigo | Não recupera | Recupera pelo Grandfather (até 12 meses) |
| Perda da região us-east-1 | Não recupera, as cópias ficam na mesma região | Recupera pelo Grandfather copiado em us-east-2 |
| `terraform destroy` acidental | **Não recupera**, os backups são apagados junto | Os snapshots do AWS Backup sobrevivem à exclusão da instância |
| Invasor com acesso administrativo à conta | Pode apagar a instância e os backups | Com Vault Lock, os snapshots não podem ser apagados antes do prazo |

## B7. Custos

### Política mínima, no período do trabalho

| Item | Valor |
|---|---|
| Volume do banco | Poucos MB (dados de teste) |
| Cópias retidas | No máximo 1 a 2 (1 dia de retenção) |
| Franquia gratuita | Backups do RDS não são cobrados até 100% do armazenamento provisionado (`allocated_storage = 20` GB) |
| Período cobrado | Só enquanto o ambiente está no ar; o `destroy` apaga os backups (`delete_automated_backups = true`) |
| **Custo estimado** | **US$ 0,00** |

### Política conservadora GFS, 12 meses

A tabela completa, com premissas, preços e o cálculo mês a mês, está em [`custos/backup-gfs-12meses.md`](custos/backup-gfs-12meses.md).

| Resumo | Valor |
|---|---|
| Custo no mês 1 | US$ 0,61 |
| Custo no mês 12 | US$ 23,90 |
| **Total no primeiro ano** | **US$ 127,11** |

O custo cresce mês a mês porque o Grandfather acumula uma cópia por mês até chegar a 12, e porque o banco cresce. A estimativa é um **teto**: considera que cada cópia ocupa o banco inteiro, mas os snapshots do RDS são incrementais.

**Qual parâmetro mais influencia o custo anual?**

| Redução testada | Economia no ano |
|---|---:|
| Sem cópia do Grandfather em us-east-2 | US$ 43,13 |
| Grandfather com 6 meses em vez de 12 | US$ 26,60 |
| Son com 3 dias em vez de 7 | US$ 21,28 |
| Father com 2 semanas em vez de 5 | US$ 16,06 |

Entre os parâmetros de retenção, o que mais pesa é a **retenção do Grandfather**: é a única geração que cresce o ano inteiro, e cada cópia mensal é a maior, porque o banco está maior. A **cópia em outra região** pesa ainda mais, porque duplica o armazenamento do Grandfather e soma a transferência.

O que se perderia ao reduzir:

- **Grandfather de 12 para 6 meses:** deixa de ser possível consultar ou restaurar o estado de mais de 6 meses atrás, o que atrapalha auditoria anual e fechamento contábil.
- **Sem cópia em us-east-2:** uma falha regional da AWS deixaria a locadora sem nenhum backup utilizável. É o cenário mais raro, mas o único em que todas as outras cópias somem juntas.

A recomendação do grupo é **manter os 12 meses e a cópia regional**: cerca de US$ 10,60 por mês na média do ano, um valor baixo diante do custo de perder o histórico de locações.

> Preços de us-east-1 usados: armazenamento de backup e snapshot do RDS a US$ 0,095/GB-mês (mesmo valor no AWS Backup), transferência entre regiões a US$ 0,02/GB e restauração a partir da camada warm sem custo. Conferir na AWS Pricing Calculator e anexar a exportação em `docs/custos/`.
