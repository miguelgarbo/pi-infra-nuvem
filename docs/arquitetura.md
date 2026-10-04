# Descrição da Aplicação e Arquitetura

## 5.1 Descrição da aplicação

A aplicação é um sistema web para gerenciamento e reserva de aluguel de carros. Ela resolve a burocracia do controle manual de frotas e a falta de transparência no cálculo de valores, automatizando a gestão de veículos para a empresa e permitindo que os clientes calculem custos em tempo real, façam reservas online e acompanhem seu histórico de locações.

### Perfis de Usuários
O sistema possue dois tipos de usuários com permissões distintas:

* **Administrador:** Responsável pela manutenção e alimentação do banco de dados. Possui privilégios de acesso para gerenciar a maioria das rotas administrativas do sistema.
* **Locatário:** Cliente final que utiliza o sistema para visualizar o catálogo de veículos disponíveis, simular o valor final do aluguel de acordo com o período selecionado, efetivar a reserva e consultar seu histórico de locações.

### Funcionalidades Principais
* **Gestão de Frota (Admin):** Cadastro, atualização e controle de status dos veículos disponíveis.
* **Controle de Acesso:** Autenticação e autorização diferenciando as rotas de administrador e locatário.
* **Simulação e Cálculo de Aluguel:** Ferramenta que calcula o valor total da reserva com base nas diárias/período escolhido pelo locatário.
* **Aluguel de Carros:** Fluxo para o locatário confirmar o aluguel do veículo selecionado.
* **Histórico de Locações:** Painel no qual o locatário acompanha suas reservas passadas e ativas.

### Componentes Técnicos
A aplicação adota uma arquitetura em camadas desacoplada (cliente-servidor via API RESTful):

* **Frontend:** Desenvolvido em **React** com o empacotador **Vite**, responsável por renderizar uma interface dinâmica, leve e responsiva no navegador do usuário (*Single Page Application*).
* **Backend:** Desenvolvido em **Java** com **Spring Boot**, responsável pelas regras de negócio, rotas REST e segurança. Utiliza **Spring Security** em conjunto com **JWT** (JSON Web Tokens) para autenticação stateless e controle de autorização baseado em perfis (RBAC).
* **Banco de Dados:** **PostgreSQL**, banco relacional responsável pela persistência durável dos dados da aplicação (usuários, veículos, alugueis e auditoria de ações).

---

### Requisitos Não-Funcionais Assumidos

* **RNF01 – Usuários Simultâneos:** O sistema vai dimensionado para suportar até **50 usuários simultâneos** em regime normal de operação (cenário compatível com uma empresa local de aluguel de carros de pequeno a médio porte).

* **RNF02 – Disponibilidade Esperada:** O sistema almeja um nível de disponibilidade estimado em **99,0%** em ambiente de execução regular. **Análise de Alta Disponibilidade (HA)**: A arquitetura proposta adota redundância na camada de aplicação, prevendo a execução de 2 instâncias (tasks) para o frontend e 2 instâncias (tasks) para o backend gerenciadas via Amazon ECS, com um servidor NGINX atuando como reverse proxy e distribuidor de tráfego na subnet pública.

* **RNF03 – Tempo de Resposta:** As consultas ao catálogo de veículos e o cálculo do valor da locação devem retornar respostas para o *frontend* em um tempo máximo de **2 segundos** para requisições sob carga normal.

* **RNF04 – Autenticação e Autorização:** A autenticação do sistema deve ser realizada via tokens JWT transmitidos no cabeçalho das requisições HTTP, garantindo que apenas usuários com a role de Admin acessem as rotas protegidas.

* **RNF05 – Criptografia de Credenciais:** As senhas dos usuários devem ser armazenadas no PostgreSQL de forma segura usando algoritmo de *hash* (como BCrypt), nunca em texto plano.

* **RNF06 – Interface Responsiva:** O *frontend* deve se adaptar adequadamente a telas de computadores e dispositivos móveis.



## 5.3 Tabela de Plano de Enderaçamento IP

| Recurso | Nome | CIDR | Faixa de IP | Zona | Tipo | Finalidade |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **VPC - Rede Virtual Privada** | `vpc-pi-infra` | `10.50.0.0/24` | `10.50.0.0 -> 10.50.0.255` | `us-east-2` | - | Rede Privada do Projeto |
| **Sub-rede da VPC** | `pb-subnet` | `10.50.0.0/28` | `10.50.0.0 -> 10.50.0.15` | `us-east-2a` | Pública | Proxy Reverso e Load Balancer |
| **Sub-rede da VPC** | `pv-subnet` | `10.50.0.16/28` | `10.50.0.16 -> 10.50.0.31` | `us-east-2a` | Privada | Frontend, Backend, Banco de dados |


## 5.4 Tabelas de Roteamento

As tabelas de roteamento definem as regras de encaminhamento do tráfego IP dentro da VPC `vpc-pi-infra`

### 1. Tabela de Rotas da Sub-rede Pública (`pb-subnet-rt`)
permite que instâncias como o proxy NGINX tenham conectividade bidirecional direta com a internet.

| Destino | Alvo (*Target*) | Descrição / Finalidade |
| :--- | :--- | :--- |
| `10.50.0.0/24` | `local` | Roteamento interno entre todos os recursos pertencentes à VPC |
| `0.0.0.0/0` | `Internet Gateway` | Encaminha todo o tráfego destinado à internet pública através do Internet Gateway |

---

### 2. Tabela de Rotas da Sub-rede Privada (`pv-subnet-rt`)
Esta tabela está associada à sub-rede privada `10.50.0.16/28` (`pv-subnet`), onde residem os serviços de *Frontend*, *Backend* e o banco de dados PostgreSQL.

| Destino | Alvo (*Target*) | Descrição / Finalidade |
| :--- | :--- | :--- |
| `10.50.0.0/24` | `local` | Roteamento interno entre os componentes privados e públicos da VPC. |
| `0.0.0.0/0` | `NAT Gateway` | Permite que as instâncias privadas iniciem conexões de saída para a internet através do NAT Gateway. |

---

### Impacto da Ausência da Rota para o NAT Gateway

Se a rota padrão (`0.0.0.0/0`) apontando para o NAT Gateway for removida da sub-rede privada, os recursos nela localizados perderão completamente o acesso de saída para a internet, deixando-os impossibilitados de baixar qualquer coisa da internet. Isso causará os seguintes impactos:

1. **Falha ao baixar imagens de contêiner no ECR:** Os nós do Amazon ECS na sub-rede privada não conseguirão realizar o *pull* das imagens Docker registradas nos repositórios.

2. **Impossibilidade de atualização de pacotes e SO:** A instância EC2 do PostgreSQL e os nós do ECS ficarão impossibilitados de efetuar atualizações de segurança do sistema operacional.

3. **Perda de gerenciamento remoto via AWS Systems Manager (SSM):** A gestão remota realizada pelo AWS Systems Manager em direção às instâncias privadas será interrompida, pois o agente do SSM precisa de conexão de saída para comunicar com os *endpoints* da AWS.

## 5.5 Matriz de regras de segurança

O acesso administrativo é feito exclusivamente pelo **AWS Systems Manager (Session Manager)**. O agente SSM, instalado nas instâncias, abre uma conexão de saída (HTTPS/443) até os endpoints da AWS, então nenhum grupo de segurança possui regra de entrada para SSH (porta 22). O SSH nunca é liberado para `0.0.0.0/0`.

| Grupo de segurança | Direção | Protocolo | Porta | Origem/Destino | Justificativa |
|---|---|---|---|---|---|
| sg-nginx | Entrada | TCP | 443 | `0.0.0.0/0` | Fluxo 1: usuários acessam a aplicação via HTTPS. É o único ponto de entrada pública da arquitetura. |
| sg-nginx | Saída | TCP | 80 | sg-frontend | Encaminha as rotas `/*` ao frontend. |
| sg-nginx | Saída | TCP | 8080 | sg-backend | Encaminha as rotas `/api` ao backend. |
| sg-nginx | Saída | TCP | 443 | `0.0.0.0/0` | O SSM Agent e as atualizações do SO acessam endpoints da AWS pelo Internet Gateway (a instância tem IP público). |
| sg-frontend | Entrada | TCP | 80 | sg-nginx | Somente o proxy acessa o frontend. |
| sg-frontend | Saída | TCP | 443 | `0.0.0.0/0` (via NAT Gateway) | Pull da imagem no ECR, SSM Agent e envio de logs. |
| sg-backend | Entrada | TCP | 8080 | sg-nginx | Somente o proxy chama a API. O frontend não acessa o backend diretamente. |
| sg-backend | Saída | TCP | 5432 | sg-database | Conexão com o PostgreSQL. |
| sg-backend | Saída | TCP | 443 | `0.0.0.0/0` (via NAT Gateway) | Pull da imagem no ECR, SSM Agent e envio de logs. |
| sg-database | Entrada | TCP | 5432 | sg-backend | O banco aceita conexões apenas do backend. |
| sg-database | Saída | TCP | 443 | `0.0.0.0/0` (via NAT Gateway) | Exclusivo para o SSM Agent e atualizações do SO. |

## 5.6 Tecnologias

| Camada | Tecnologia | Versão | Justificativa |
|---|---|---|---|
| Provedor e região | AWS — us-east-2 (Ohio) | - | Região escolhida por apresentar o menor custo de infraestrutura da AWS. O valor de recursos como instâncias EC2 e NAT Gateway em Ohio (us-east-2) garante a menor tarifação mensal possível, otimizando o orçamento do projeto acadêmico. Como o ambiente destina-se a uma entrega/demonstração acadêmica e a carga prevista é reduzida (50 usuários simultâneos), o acréscimo de latência entre o Brasil e os EUA foi aceito conscientemente como um trade-off viável, priorizando a economia de custos acima da resposta em milissegundos sem comprometer o funcionamento da aplicação |
| Sistema operacional | Amazon Linux 2023 (AMI ECS-Optimized) | 2023 | Imagem mantida pela AWS, já com Docker Engine e o agente do ECS pré-instalados e atualizados, dispensando provisionamento manual (cloud-init) no host que roda os containers. Inclui o SSM Agent nativamente, necessário para o acesso administrativo via Systems Manager sem bastion. |
| Orquestração de containers | Amazon ECS — launch type EC2 | - | O ECS permite declarar task definitions que apontam direto para as imagens de frontend e backend, sem etapa de build na infraestrutura. O launch type EC2 foi escolhido no lugar do Fargate para manter controle sobre o dimensionamento e o custo da instância hospedeira, em vez do modelo de cobrança por vCPU/memória do Fargate. Frontend e backend rodam em hosts ECS separados, isolando o consumo de recursos de cada camada. |
| Registro de imagens | Amazon ECR (Elastic Container Registry) | - | Repositório privado gerenciado pela AWS para as imagens de frontend e backend. Mantém o pull de imagens dentro da rede da AWS (sem depender de um registro externo nem passar pelo NAT/internet) e integra-se nativamente com as permissões IAM das instâncias ECS. |
| Runtime / backend | Java / Spring Boot | 24 | API de regras de negócio, containerizada e isolada em sub-rede privada. O reuso da imagem pré-compilada no Amazon ECR evitou a reescrita do código, garantindo a integração com o PostgreSQL e acelerando o deploy|
| Runtime / frontend | React | 19.2.8 | Aplicação SPA em React compilada como build estático (HTML/JS/CSS) e servida diretamente pelo Nginx. Essa abordagem elimina a necessidade de um servidor Node.js em produção, economizando memória e CPU da instância EC2. Como a imagem Docker já estava pronta no ECR, seu reuso otimizou o tempo de deploy |
| Servidor web / proxy | Nginx | 1.26 | Único ponto de entrada público da arquitetura: encaminha `/` para o frontend e `/api` para o backend, ambos em sub-rede privada, e concentra o Elastic IP, evitando expor as instâncias de aplicação diretamente à internet. |
| Banco de dados | PostgreSQL | 16 | Banco relacional self-managed em EC2 (ver ADR-003), compatível com o driver JDBC já usado pelo backend Spring Boot. |
| Infraestrutura como código | Terraform | ~> 1.9 | Ferramenta padrão de mercado com provider oficial maduro para AWS; escolhida no lugar do OpenTofu por familiaridade do grupo. |
| Provider do Terraform | hashicorp/aws | ~> 5.0 | Provider oficial da HashiCorp, com suporte completo aos recursos exigidos (VPC, sub-redes, NAT Gateway, Security Groups, EC2, Elastic IP). |
| Instalação da aplicação | ECS task definitions (pull direto do Amazon ECR) | - | Como as imagens de frontend e backend já estão publicadas no ECR, a instalação não exige script de build nem Ansible: o ECS Agent apenas puxa a imagem do registro privado e sobe o container conforme a task definition, o que também simplifica recriar o ambiente entre sessões de teste |

## 5.7 Dimensionamento das instâncias

O requisito não funcional desta entrega é suportar 50 usuários simultâneos sem exigência estrita de alta disponibilidade, priorizando o menor custo mensal.

Para isso, todas as instâncias usam a família t3 (CPU baseada em créditos). Essa arquitetura é ideal para o projeto: as instâncias acumulam créditos computacionais durante a ociosidade e os utilizam para entregar picos de CPU (burstable performance) nos momentos de tráfego. Isso garante fluidez e estabilidade para os 50 usuários com um custo muito inferior ao de instâncias de capacidade fixa.

| Componente | Família | Tipo | vCPU | Memória | Disco (tipo e tamanho) | Sub-rede | Justificativa |
|---|---|---|---|---|---|---|---|
| Nginx (proxy público) | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 4 GiB | Pública (com Elastic IP) | Atua exclusivamente como proxy reverso. A instância garante a memória (1 GiB) necessária para gerenciar conexões concorrentes e buffers do Nginx com estabilidade para a carga de 50 usuários, aproveitando os picos de CPU (burstable) quando há aumento súbito de tráfego. |
| Host ECS — Frontend (2 tasks) | t3 (CPU baseada em créditos) | t3.medium | 2 | 4 GiB | gp3, 4 GiB | Privada | Hospeda as duas réplicas do frontend, mantendo esta camada isolada do processamento de negócio. A capacidade de 4 GiB fornece um ambiente com ampla folga de memória para o sistema operacional, ECS Agent e a execução dos containers, prevenindo qualquer concorrência de recursos. |
| Host ECS — Backend (2 tasks) | t3 (CPU baseada em créditos) | t3.medium | 2 | 4 GiB | gp3, 4 GiB | Privada | Dedicada às duas réplicas da API em Spring Boot. Por ser baseada em Java, cada container exige uma reserva de memória considerável. Os 4 GiB garantem a operação segura de ambos os containers simultaneamente, sem risco de queda por falta de memória, deixando margem para o SO. |
| PostgreSQL | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 8 GiB | Privada | Configuração ideal para o volume de dados do escopo acadêmico. A memória atende eficientemente ao cache e aos shared buffers do banco para a carga estimada, enquanto o disco gp3 de 8 GiB oferece espaço abundante e seguro para o armazenamento, mantendo o ambiente otimizado e com baixo custo mensal. |

## 5.10 Riscos e limitações

| # | Ponto de falha ou limitação | Impacto | Mitigação possível (Entrega 2) |
|---|---|---|---|
| 1 | **Zona de disponibilidade única.** Todos os recursos (Nginx, hosts ECS, banco e NAT) estão em `us-east-2a`. | Uma falha na zona (energia, rede, datacenter) derruba toda a aplicação. Também não há redundância regional: usuários distantes de `us-east-2` têm maior latência. | Distribuir hosts ECS e banco em uma segunda AZ. Multi-região reduziria a latência e aumentaria a resiliência, mas é a opção mais cara e não será adotada. |
| 2 | **Banco PostgreSQL em container numa EC2 `t3.micro`.** Não é serviço gerenciado nem serverless. | Se a instância ou o container falhar, o banco fica indisponível até a recuperação manual. Não há failover, backup automático nem escala. Os dados dependem do disco da instância e podem ser perdidos ao destruir e recriar o ambiente (seção 5.9). | Migrar para Amazon RDS (Multi-AZ), Aurora Serverless ou outra solução serverless da AWS. |
| 3 | **Redundância apenas em nível de container.** Frontend e backend têm 2 tasks, mas cada serviço roda em um único host EC2 (`10.50.0.20` e `10.50.0.21`). | A falha do host derruba o serviço inteiro, apesar das duas tasks. | Distribuir os hosts ECS em mais de uma AZ, com as tasks espalhadas entre eles. |

A arquitetura **não oferece alta disponibilidade** atualmente. A tabela acima identifica os principais pontos únicos de falha e limitações do sistema, e esta lista será o ponto de partida da proposta de alta disponibilidade da próxima entrega.

Caso alguma das mitigações propostas não possa ser aplicada (por custo, complexidade ou outro motivo), a decisão e sua justificativa serão documentadas na Entrega 2.
