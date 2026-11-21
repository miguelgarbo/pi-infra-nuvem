# Segurança (Parte B)

Este documento cobre os controles S1 a S8, o tratamento dos achados das ferramentas de análise (seção 4.3 do enunciado) e a análise de ameaças (seção 4.4).

Arquitetura analisada: o Terraform em `infra/`, na região `us-east-1`. O único ponto de entrada público é uma EC2 com Nginx. Frontend e backend rodam no ECS Fargate em duas sub-redes privadas, o banco é um RDS PostgreSQL Multi-AZ e o acesso administrativo é feito pelo SSM Session Manager.

---

## 1. Controles obrigatórios (S1 a S8)

| # | Controle | Como foi aplicado | Onde | Evidência |
|---|---|---|---|---|
| **S1** | Endurecimento do SSH | Não existe porta 22 aberta em nenhum security group. O acesso administrativo é feito só pelo SSM Session Manager (ADR-001), autenticado pelo IAM. Mesmo assim, o `sshd` é endurecido no boot pelo `user_data`, com o arquivo `/etc/ssh/sshd_config.d/01-hardening.conf` contendo `PasswordAuthentication no`, `KbdInteractiveAuthentication no` e `PermitRootLogin no`. O prefixo `01-` garante que essas linhas são lidas primeiro (no `sshd`, vale o primeiro valor encontrado). Para conferir pelo SSM: `sudo sshd -T \| grep -Ei "passwordauth\|permitroot"`. | `infra/compute.tf` (`user_data`), `infra/security.tf`, `infra/iam.tf` | D3 |
| **S2** | Saída restrita | Não existe regra "todo o tráfego" de saída. Cada grupo libera só as portas necessárias: Nginx → frontend (80) e backend (8080) por referência de SG, e 443/80 para SSM e `apt`. Frontend e backend saem só em 443 (ECR, CloudWatch e SSM, via NAT). O backend acessa o banco em 5432 só por referência de SG. O RDS **não tem nenhuma regra de saída**. | `infra/security.tf` | `trivy-depois.txt` |
| **S3** | HTTPS | No boot, o `user_data` gera um **certificado autoassinado** (RSA 2048, 30 dias) com o IP público da instância no CN e no `subjectAltName`. O IP é lido do metadata com IMDSv2. O Nginx atende na porta **443 com TLS 1.2/1.3**, e a porta 80 só devolve `301` para `https://`. O output `url_app` e as variáveis `FRONT_URL` e `VITE_API_URL` usam `https://`. Para conferir: `curl -vk https://<IP>` mostra o handshake TLS, e `curl -I http://<IP>` mostra o `301`. | `infra/compute.tf` (`user_data`), `infra/outputs.tf` | D2 |
| **S4** | Gestão de segredos | `DB_PASSWORD` e `HASH_TOKEN` são variáveis com `sensitive = true`, fornecidas pelo `terraform.tfvars` (fora do Git) ou por `TF_VAR_*`. O Terraform grava os valores no **SSM Parameter Store como `SecureString`**. A task definition do backend usa o bloco `secrets` com o ARN do parâmetro, então a senha **não aparece** na task definition nem no console do ECS. | `infra/secrets.tf`, `infra/compute.tf`, `infra/variables.tf` | D5 |
| **S5** | Menor privilégio para as instâncias | Nenhuma chave de acesso fica gravada em instância ou container. **EC2 Nginx:** role `role-ssm-nginx-pi`, só com `AmazonSSMManagedInstanceCore`, e **IMDSv2 obrigatório** (`http_tokens = "required"`, `hop_limit = 1`), que impede o roubo das credenciais temporárias por SSRF. **Tasks ECS:** sem `task_role_arn`, então a aplicação **não tem nenhuma permissão na AWS**. A role de execução (usada pelo agente do Fargate) puxa imagens, envia logs e lê **apenas os dois parâmetros** `/miguel-aluguel/db/password` e `/miguel-aluguel/app/hash-token` (`ssm:GetParameters` com o ARN exato). **Backup:** o mecanismo é o backup automático do RDS (ver `backup.md`), então não há bucket nem permissão de backup em instância. | `infra/iam.tf`, `infra/compute.tf` | D5 |
| **S6** | Criptografia em repouso | **RDS:** `storage_encrypted = true` (chave `aws/rds`), e os backups automáticos e snapshots herdam essa criptografia. **EC2:** `root_block_device { encrypted = true }` (chave `aws/ebs`). **Segredos:** `SecureString` com a chave `aws/ssm`. **Fargate:** o armazenamento efêmero das tasks é criptografado pela AWS por padrão com AES-256 (ver achados aceitos). | `infra/database.tf`, `infra/compute.tf`, `infra/secrets.tf` | `console-criptografia.png` |
| **S7** | Análise automatizada | **Trivy 0.76.2** (`trivy config infra/`) antes e depois das correções, e **Gitleaks 8.30.1** (`gitleaks git .`) em todo o histórico (53 commits, última execução em 21/11/2026). | — | `docs/evidencias/seguranca/` |
| **S8** | MFA na conta | MFA virtual (aplicativo autenticador) habilitado em 17/11/2026 no usuário IAM usado pelo integrante, exigido no login do console. A captura foi feita em IAM → Usuário → Credenciais de segurança, com o ID da conta mascarado. | — | `docs/evidencias/seguranca/mfa.png` |

### Como reproduzir as análises (S7)

```bash
# Análise da IaC
trivy config infra/

# Segredos em todo o histórico do Git (Gitleaks 8.19 ou mais novo; versões antigas usam "gitleaks detect --source .")
gitleaks git --redact -v .
```

| Arquivo | Conteúdo |
|---|---|
| `docs/evidencias/seguranca/trivy-antes.txt` | Trivy no código antes das correções desta parte: 15 achados (3 HIGH, 4 CRITICAL) |
| `docs/evidencias/seguranca/trivy-depois.txt` | Trivy depois das correções: 12 achados (0 HIGH, 4 CRITICAL aceitos) |
| `docs/evidencias/seguranca/gitleaks.txt` / `.json` | Gitleaks no histórico completo, com o segredo **redigido** no relatório |

---

## 2. Tratamento dos achados

Todos os achados estão listados, inclusive os de severidade média e baixa. "Aceito" significa que o risco foi avaliado e o motivo está registrado; nenhum achado foi silenciado na ferramenta.

### 2.1 Trivy (IaC)

| Achado | ID | Severidade | Recurso | Decisão | Justificativa |
|---|---|---|---|---|---|
| Disco raiz da EC2 sem criptografia | AWS-0131 | **Alta** | `aws_instance.ec2-nginx-pi` | **Corrigido** | Bloco `root_block_device` com `encrypted = true` (S6). |
| EC2 aceita IMDSv1 (metadata sem token) | AWS-0028 | **Alta** | `aws_instance.ec2-nginx-pi` | **Corrigido** | `metadata_options` com `http_tokens = "required"` e `hop_limit = 1` (S5). O Nginx é um proxy exposto à internet, e um SSRF poderia ler as credenciais da role pelo IMDSv1. |
| Sub-rede pública atribui IP público automaticamente | AWS-0164 | **Alta** | `aws_subnet.subnet-pub-1` | **Corrigido** | `map_public_ip_on_launch = false`. Só recebem IP público os recursos que pedem explicitamente: a EC2 do Nginx (`associate_public_ip_address`) e o NAT (Elastic IP). Um recurso criado por engano nessa sub-rede não fica exposto. |
| Saída irrestrita (`0.0.0.0/0`) na porta 443 | AWS-0104 | **Crítica** | `app_https_out`, `front_https`, `back_https` | **Aceito** | O SSM Agent, o pull de imagens do ECR e o envio de logs ao CloudWatch usam endpoints públicos da AWS com IPs variáveis, que não podem ser listados em um SG. A saída já é limitada à porta 443 (S2) e, nas sub-redes privadas, passa pelo NAT. A correção seria usar **VPC endpoints** (ssm, ssmmessages, ec2messages, ecr.api, ecr.dkr, logs e S3) e remover a saída para a internet. Cada interface endpoint custa cerca de US$ 0,01/h por zona: 6 endpoints × 2 zonas ≈ **US$ 88/mês**, mais que o resto da infraestrutura. Risco residual: exfiltração por HTTPS a partir de um container comprometido (ameaça A5). |
| Saída irrestrita (`0.0.0.0/0`) na porta 80 | AWS-0104 | **Crítica** | `app_http_out` | **Aceito** | Os espelhos `apt` do Ubuntu na AWS usam HTTP. Os pacotes são assinados com GPG, então um atacante no caminho não consegue injetar um pacote modificado. A regra vale só para a EC2 do Nginx. |
| Retenção de backup muito baixa | AWS-0077 | Média | `aws_db_instance.postgres_rds` | **Aceito** | É a **política mínima** exigida pela seção 6.3 (máximo de 2 dias). A conta no plano gratuito recusa mais de 1 dia. A política recomendada para produção (GFS, 7 dias de Son) está em `backup.md`. |
| RDS sem autenticação IAM | AWS-0176 | Média | `aws_db_instance.postgres_rds` | **Aceito** | O backend (Spring Boot) conecta com usuário e senha. A senha está no SSM (S4) e o banco só aceita conexões do SG do backend. A autenticação IAM exigiria mudar o código da aplicação para gerar tokens. |
| RDS sem proteção contra exclusão | AWS-0177 | Média | `aws_db_instance.postgres_rds` | **Aceito** | O ambiente precisa ser destruído com `terraform destroy` em até 24 h após a apresentação (seção 11), e `deletion_protection = true` bloquearia o destroy. Em produção, seria ativado. |
| VPC sem Flow Logs | AWS-0178 | Média | `aws_vpc.vpc_miguel_aluguel` | **Aceito** | Os logs de fluxo exigem log group, role e custo de ingestão no CloudWatch por um ambiente que fica no ar poucas horas. Risco residual: sem registro de rede para investigar um incidente (ameaças A3 e A5). |
| Log groups sem chave KMS própria | AWS-0017 | Baixa | `backend_logs`, `frontend_logs` | **Aceito** | O CloudWatch Logs já criptografa os dados em repouso com chave da AWS. A chave KMS própria (US$ 1/mês por chave) só acrescentaria controle de quem pode descriptografar. |
| Cluster ECS sem Container Insights | AWS-0034 | Baixa | `aws_ecs_cluster.pi_cluster` | **Aceito** | É monitoramento, não controle de segurança, e cobra métricas personalizadas. |
| RDS sem Performance Insights | AWS-0133 | Baixa | `aws_db_instance.postgres_rds` | **Aceito** | É monitoramento de desempenho, não controle de segurança. |
| Armazenamento efêmero do Fargate com chave da AWS | — | Informativo | `aws_ecs_cluster.pi_cluster` | **Aceito** | Não foi apontado pela ferramenta, mas está registrado por causa do S6. O Fargate criptografa o armazenamento efêmero com AES-256 por padrão, e não existe parâmetro para "ativar" isso no código. Só dá para trocar por uma chave KMS própria (US$ 1/mês), que não traz ganho para o escopo. |

### 2.2 Gitleaks (segredos no histórico)

| Achado | Regra | Severidade | Local | Decisão | Justificativa |
|---|---|---|---|---|---|
| Senha do banco escrita no código | `hashicorp-tf-password` | **Crítica** | `infra/terraform/rds.tf`, linha 10, commit `0f10cb5` (13/11/2026) | **Corrigido (incidente)** | Era um rascunho do Terraform com a senha do RDS escrita direto no código. Nos commits seguintes ela passou para a variável `DB_PASSWORD` (`b46f9d0`), mas **continua no histórico** do repositório, que é público. Tratamento: (1) a senha exposta foi **descartada**, e o `terraform.tfvars` usa uma senha nova e diferente **[CONFIRMAR com quem faz o apply]**; (2) a senha agora fica no SSM Parameter Store (S4); (3) o ocorrido está registrado em `docs/errata.md`. O histórico não foi reescrito porque isso não remove cópias já clonadas: a medida eficaz é a troca da senha. |

---

## 3. Análise de ameaças

Ameaças específicas desta arquitetura, não genéricas. A coluna "Controle aplicado" cita os controles S1 a S8 e os requisitos R do enunciado.

| # | Ameaça | Ativo afetado | Controle aplicado | Risco residual |
|---|---|---|---|---|
| **A1** | **SSRF pelo Nginx ou pelo backend para roubar credenciais da role.** O atacante faz o servidor requisitar `http://169.254.169.254/latest/meta-data/iam/security-credentials/` e obtém as credenciais temporárias da role da EC2. | EC2 Nginx e role `role-ssm-nginx-pi` | IMDSv2 obrigatório com `hop_limit = 1` (S5): sem o token obtido por `PUT`, o metadata não responde. A role tem apenas `AmazonSSMManagedInstanceCore`, sem acesso a RDS, ECS ou outros recursos. As tasks não têm task role. | Mesmo com credenciais roubadas, o atacante conseguiria só registrar a instância no SSM, sem acesso a dados. |
| **A2** | **Vazamento da senha do banco ou do segredo do JWT.** A senha aparece no Git, na task definition (visível para qualquer um com `ecs:DescribeTaskDefinition`) ou na saída do `terraform plan`. Com o `HASH_TOKEN`, dá para forjar um JWT de administrador. | Senha do RDS e `HASH_TOKEN` | S4: os valores ficam em `SecureString` no SSM, são passados pelo bloco `secrets` e as variáveis têm `sensitive = true`. `.gitignore` para `*.tfvars` e `*.tfstate`. Gitleaks no histórico (S7). A senha que vazou no commit `0f10cb5` foi trocada. | O `terraform.tfstate` guarda os valores em texto puro, então quem tiver o state tem os segredos. O state fica num backend S3 (`infra/backend.tf`) com `encrypt = true` e lock nativo, fora do Git e fora das máquinas dos integrantes. Ainda assim, qualquer integrante com acesso ao bucket consegue ler os segredos. O bucket foi criado fora do Terraform, que é uma exceção permitida pela seção 3. |
| **A3** | **Movimento lateral a partir da EC2 do Nginx comprometida**, por exemplo por uma vulnerabilidade no Nginx. O atacante tenta acessar o PostgreSQL diretamente. | RDS PostgreSQL | SGs encadeados (R7, S2): o banco aceita 5432 **só** do SG `back-pi`; o Nginx só tem saída para o frontend (80) e o backend (8080). O RDS fica em sub-rede privada, com `publicly_accessible = false`. | O atacante ainda consegue chamar a API do backend como qualquer cliente. A proteção passa a ser a autenticação JWT da aplicação. Sem Flow Logs (achado aceito), a tentativa não fica registrada. |
| **A4** | **Credenciais de um integrante do grupo roubadas** (phishing ou notebook comprometido). Com o console ou a CLI, o atacante cria máquinas para minerar criptomoeda ou apaga o RDS. | Conta AWS, RDS e faturamento | S8: MFA na conta. Não há portas administrativas abertas: o acesso às instâncias exige IAM + SSM. Alerta de orçamento configurado antes do primeiro apply. | Chaves de acesso de longa duração da CLI nos notebooks não exigem MFA. Mitigação recomendada: perfis com `aws sso login` ou exigir MFA por condição na política. |
| **A5** | **Exfiltração de dados a partir de um container comprometido** (por exemplo, uma dependência maliciosa no backend), enviando a base de clientes para um servidor externo. | Dados de clientes e locações | S2: saída só em 443 pelo NAT, com IP de origem fixo e conhecido. O backend não tem permissões na AWS (sem task role). | A saída 443 aceita qualquer destino (AWS-0104 aceito), e não há Flow Logs para detectar o envio. Correção completa: VPC endpoints com saída bloqueada (custo em 2.1). |
| **A6** | **Invasor apagando os backups junto com o banco** (pergunta típica da defesa). | RDS e backups automáticos | A aplicação não tem permissão para chamar a API do RDS: sem task role, e a role do Nginx não tem permissão de RDS. Apagar o banco ou os backups exige uma credencial IAM de integrante, protegida por MFA (S8). | Quem tiver a credencial de um integrante pode apagar tudo, porque `delete_automated_backups = true` e não há `deletion_protection` (aceitos para permitir o destroy). Na política GFS (`backup.md`), as cópias semanais e mensais ficariam em um AWS Backup Vault, que pode receber Vault Lock. |
| **A7** | **Interceptação de credenciais de login** (senha do locatário ou JWT) em uma rede Wi-Fi pública, se a aplicação for acessada por HTTP. | Contas de usuários da aplicação | S3: TLS 1.2/1.3 no Nginx, com a porta 80 respondendo só `301` para HTTPS. A API é servida na mesma origem (`/api`), então não há chamada em HTTP puro. Senhas dos usuários com BCrypt no banco (RNF05). | Com certificado autoassinado, o navegador mostra um alerta, e o usuário que aceitar o alerta fica exposto a um ataque man-in-the-middle. Não há limitação de tentativas de login (sem WAF). |
| **A8** | **Acesso a uma cópia do disco ou a um snapshot** compartilhado por engano ou copiado de outra conta. | Volume EBS do Nginx, armazenamento e snapshots do RDS | S6: EBS, RDS e snapshots criptografados com KMS. Um snapshot criptografado com a chave gerenciada pela AWS **não pode ser compartilhado** com outra conta. | Baixo. |

---

## 4. Demonstração D5 (roteiro)

1. **Segredos fora do código (S4).** Rodar um `grep` nos arquivos `.tf`. Só aparecem referências a variáveis:
   ```bash
   git grep -nE "DB_PASSWORD|HASH_TOKEN" -- infra/
   ```
   Na task definition, aparece só o ARN do parâmetro, e não a senha:
   ```bash
   aws ecs describe-task-definition --task-definition miguel-aluguel-backend \
     --query "taskDefinition.containerDefinitions[0].secrets"
   ```
   No SSM, o valor fica criptografado. Sem `--with-decryption`, o comando não mostra a senha:
   ```bash
   aws ssm get-parameter --name /miguel-aluguel/db/password --query "Parameter.[Type,Value]"
   ```
2. **Um achado corrigido.** Mostrar o AWS-0131 (disco sem criptografia) em `trivy-antes.txt`, o bloco `root_block_device` em `compute.tf` e a ausência do achado ao rodar `trivy config infra/` ao vivo.
3. **Um achado aceito.** Mostrar o AWS-0104 (saída 443 para `0.0.0.0/0`) e explicar: a saída já é limitada à porta 443, e os VPC endpoints custariam cerca de US$ 88/mês.
4. Se houver tempo, mostrar o Gitleaks: o achado do commit `0f10cb5` e como foi tratado (senha trocada, SSM, errata).
