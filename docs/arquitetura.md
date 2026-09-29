Seções Contidas no Documento Atualmente:
5.1, 5.3, 5.4, 5.6, 5.7, 5.9 e 5.10

Faltam:
5.5 e 5.7

# 5 Descrição da Aplicação e Arquitetura

## 5.1 Descrição e Problema Resolvido pela Aplicação

A aplicação é um sistema web para gerenciamento e reserva de aluguel de carros. Ela resolve a burocracia do controle manual de frotas e a falta de transparência no cálculo de valores, automatizando a gestão de veículos para a empresa e permitindo que os clientes calculem custos em tempo real, façam reservas online e acompanhem seu histórico de locações.

## Perfis de Usuários
O sistema possue dois tipos de usuários com permissões distintas:

* **Administrador:** Responsável pela manutenção e alimentação do banco de dados. Possui privilégios de acesso para gerenciar a maioria das rotas administrativas do sistema.
* **Locatário:** Cliente final que utiliza o sistema para visualizar o catálogo de veículos disponíveis, simular o valor final do aluguel de acordo com o período selecionado, efetivar a reserva e consultar seu histórico de locações.

## Funcionalidades Principais
* **Gestão de Frota (Admin):** Cadastro, atualização e controle de status dos veículos disponíveis.
* **Controle de Acesso:** Autenticação e autorização diferenciando as rotas de administrador e locatário.
* **Simulação e Cálculo de Aluguel:** Ferramenta que calcula o valor total da reserva com base nas diárias/período escolhido pelo locatário.
* **Aluguel de Carros:** Fluxo para o locatário confirmar o aluguel do veículo selecionado.
* **Histórico de Locações:** Painel no qual o locatário acompanha suas reservas passadas e ativas.

## Componentes Técnicos
A aplicação adota uma arquitetura em camadas desacoplada (cliente-servidor via API RESTful):

* **Frontend:** Desenvolvido em **React** com o empacotador **Vite**, responsável por renderizar uma interface dinâmica, leve e responsiva no navegador do usuário (*Single Page Application*).
* **Backend:** Desenvolvido em **Java** com **Spring Boot**, responsável pelas regras de negócio, rotas REST e segurança. Utiliza **Spring Security** em conjunto com **JWT** (JSON Web Tokens) para autenticação stateless e controle de autorização baseado em perfis (RBAC).
* **Banco de Dados:** **PostgreSQL**, banco relacional responsável pela persistência durável dos dados da aplicação (usuários, veículos, alugueis e auditoria de ações).

---

## Requisitos Não-Funcionais Assumidos

* **RNF01 – Usuários Simultâneos:** O sistema foi dimensionado para suportar até **50 usuários simultâneos** em regime normal de operação (cenário compatível com uma empresa local de aluguel de carros de pequeno a médio porte).

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
| `0.0.0.0/0` | `Internet Gateway` (`igw-...`) | Encaminha todo o tráfego destinado à internet pública através do Internet Gateway |

---

### 2. Tabela de Rotas da Sub-rede Privada (`pv-subnet-rt`)
Esta tabela está associada à sub-rede privada `10.50.0.16/28` (`pv-subnet`), onde residem os serviços de *Frontend*, *Backend* e o banco de dados PostgreSQL.

| Destino | Alvo (*Target*) | Descrição / Finalidade |
| :--- | :--- | :--- |
| `10.50.0.0/24` | `local` | Roteamento interno entre os componentes privados e públicos da VPC. |
| `0.0.0.0/0` | `NAT Gateway` (`nat-...`) | Permite que as instâncias privadas iniciem conexões de saída para a internet através do NAT Gateway. |

---

### Impacto da Ausência da Rota para o NAT Gateway

Se a rota padrão (`0.0.0.0/0`) apontando para o NAT Gateway for removida da sub-rede privada, os recursos nela localizados perderão completamente o acesso de saída para a internet, deixando-os impossibilitados de baixar qualquer coisa da internet. Isso causará os seguintes impactos:

1. **Falha ao baixar imagens de contêiner no ECR:** Os nós do Amazon ECS na sub-rede privada não conseguirão realizar o *pull* das imagens Docker registradas nos repositórios.

2. **Impossibilidade de atualização de pacotes e SO:** A instância EC2 do PostgreSQL e os nós do ECS ficarão impossibilitados de efetuar atualizações de segurança do sistema operacional.

3. **Perda de gerenciamento remoto via AWS Systems Manager (SSM):** A gestão remota realizada pelo AWS Systems Manager em direção às instâncias privadas será interrompida, pois o agente do SSM precisa de conexão de saída para comunicar com os *endpoints* da AWS.


## 5.6 Tecnologias

| Camada | Tecnologia | Versão | Justificativa |
|---|---|---|---|
| Provedor e região | AWS — us-east-2 (Ohio) | - | Região com custo de instâncias EC2 e de NAT Gateway cerca de 30-40% menor que sa-east-1 (São Paulo). A carga prevista (1 usuário simultâneo, seção 5.1) não exige baixa latência garantida nem alta disponibilidade nesta entrega, então a latência adicional de ~150-180ms entre o Brasil e Ohio foi aceita conscientemente em troca do menor custo mensal. A região oferece todos os serviços exigidos pela Entrega 2 (VPC, sub-redes, NAT Gateway, Elastic IP, Security Groups, Systems Manager) com disponibilidade equivalente à de sa-east-1. |
| Sistema operacional | Amazon Linux 2023 (AMI ECS-Optimized) | 2023 | Imagem mantida pela AWS, já com Docker Engine e o agente do ECS pré-instalados e atualizados, dispensando provisionamento manual (cloud-init) no host que roda os containers. Inclui o SSM Agent nativamente, necessário para o acesso administrativo via Systems Manager sem bastion. |
| Orquestração de containers | Amazon ECS — launch type EC2 | - | O ECS permite declarar task definitions que apontam direto para as imagens de frontend e backend, sem etapa de build na infraestrutura. O launch type EC2 foi escolhido no lugar do Fargate para manter controle sobre o dimensionamento e o custo da instância hospedeira, em vez do modelo de cobrança por vCPU/memória do Fargate. Frontend e backend rodam em hosts ECS separados (ver seção 5.7), isolando o consumo de recursos de cada camada. |
| Registro de imagens | Amazon ECR (Elastic Container Registry) | - | Repositório privado gerenciado pela AWS para as imagens de frontend e backend, no lugar do Docker Hub. Mantém o pull de imagens dentro da rede da AWS (sem depender de um registro externo nem passar pelo NAT/internet) e integra-se nativamente com as permissões IAM das instâncias ECS. |
| Runtime / linguagem (backend) | Java 21 / Spring Boot | 21 / 3.3.x | Stack em que a aplicação do grupo já foi desenvolvida e containerizada; reaproveitar a imagem existente (publicada no ECR) evita reescrever a aplicação em outra linguagem só para a infraestrutura. |
| Runtime / linguagem (frontend) | React | build estático já publicado como imagem Docker | Mesma justificativa do backend: aplicação já existente e containerizada, servida como build estático atrás do Nginx. |
| Servidor web / proxy | Nginx | 1.26 | Único ponto de entrada público da arquitetura: encaminha `/` para o frontend e `/api` para o backend, ambos em sub-rede privada, e concentra o Elastic IP, evitando expor as instâncias de aplicação diretamente à internet. |
| Banco de dados | PostgreSQL | 16 | Banco relacional self-managed em EC2 (ver ADR-003), compatível com o driver JDBC já usado pelo backend Spring Boot. |
| Infraestrutura como código | Terraform | ~> 1.9 | Ferramenta padrão de mercado com provider oficial maduro para AWS; escolhida no lugar do OpenTofu por familiaridade do grupo. |
| Provider do Terraform | hashicorp/aws | ~> 5.0 | Provider oficial da HashiCorp, com suporte completo aos recursos exigidos (VPC, sub-redes, NAT Gateway, Security Groups, EC2, Elastic IP). |
| Instalação da aplicação | ECS task definitions (pull direto do Amazon ECR) | - | Como as imagens de frontend e backend já estão publicadas no ECR, a instalação não exige script de build nem Ansible: o ECS Agent apenas puxa a imagem do registro privado e sobe o container conforme a task definition, o que também simplifica recriar o ambiente entre sessões de teste (seção 5.9). |

## 5.7 Dimensionamento das instâncias

O requisito não funcional definido pelo grupo (seção 5.1) é de **1 usuário simultâneo**, sem exigência de alta disponibilidade nesta entrega. Por isso o dimensionamento abaixo prioriza o menor custo mensal compatível com a carga, e não throughput ou concorrência.

Todas as instâncias usam a família **t3** (CPU baseada em créditos), adequada a uma carga majoritariamente ociosa com picos curtos por requisição — típica de 1 usuário simultâneo.

| Componente | Família | Tipo | vCPU | Memória | Disco (tipo e tamanho) | Sub-rede | Justificativa |
|---|---|---|---|---|---|---|---|
| Nginx (proxy público) | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 4 GiB | Pública (com Elastic IP) | Função de proxy reverso puro, sem lógica de aplicação: para 1 usuário simultâneo o consumo de CPU é esporádico. O t3.nano foi descartado por oferecer apenas 512 MiB de memória, insuficiente para sustentar conexões keep-alive e buffers de proxy com folga. Quando os créditos de CPU se esgotam, a instância não é interrompida — apenas tem seu desempenho reduzido ao baseline garantido do t3.micro (~10% de 1 vCPU), o que é aceitável porque a carga prevista dificilmente sustenta uso de CPU acima do baseline por tempo suficiente para esgotar o saldo de créditos. |
| Host ECS — Frontend (2 tasks) | t3 (CPU baseada em créditos) | t3.medium | 2 | 4 GiB | gp3, 4 GiB | Privada | VM dedicada às 2 réplicas do frontend (build estático), isolada da VM de backend para que picos de CPU/memória de uma camada não afetem a outra. O consumo do frontend estático é leve, mas o grupo optou por t3.medium (4 GiB) para manter folga confortável de memória, incluindo overhead do ECS Agent e do sistema operacional. Sob esgotamento de créditos de CPU, a instância cai para o desempenho baseline do t3.medium (~20% de 1 vCPU), impacto baixo dado o perfil leve do frontend estático. |
| Host ECS — Backend (2 tasks) | t3 (CPU baseada em créditos) | t3.medium | 2 | 4 GiB | gp3, 4 GiB | Privada | VM dedicada às 2 réplicas do backend Spring Boot; cada instância da JVM reserva tipicamente 512 MiB–1 GiB de heap, totalizando ~1-2 GiB para os dois containers, com folga no t3.medium para o overhead do ECS Agent e do sistema operacional. O t3.small (2 GiB) foi descartado por deixar a instância sujeita a OOM kill de containers em picos simultâneos das réplicas de backend. Sob esgotamento de créditos de CPU, o host cai para o desempenho baseline do t3.medium (~20% de 1 vCPU), podendo aumentar a latência de resposta, mas sem derrubar os containers — risco aceitável dado o único usuário simultâneo previsto. |
| PostgreSQL | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 8 GiB | Privada | Atende a 1 usuário simultâneo com volume de dados pequeno (cadastro e listagem de registros); 1 GiB é suficiente para o shared_buffers e cache do PostgreSQL 16 nesse volume. O t3.small foi descartado por dobrar o custo mensal sem ganho perceptível para essa carga. Se os créditos de CPU se esgotarem, as consultas passam a rodar no desempenho baseline do t3.micro, aumentando a latência de consultas mais pesadas, mas sem indisponibilidade (risco também listado na seção 5.10). O disco (8 GiB) foi dimensionado com folga em relação ao volume de dados esperado para acomodar o crescimento do banco sem exigir redimensionamento manual durante a Entrega 2. |