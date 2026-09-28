# Seções 5.1 a 5.7, 5.9 e 5.10

## 5.6 Tecnologias

| Camada | Tecnologia | Versão | Justificativa |
|---|---|---|---|
| Provedor e região | AWS — us-east-2 (Ohio) | - | Região com custo de instâncias EC2 e de NAT Gateway cerca de 30-40% menor que sa-east-1 (São Paulo). A carga prevista (1 usuário simultâneo, seção 5.1) não exige baixa latência garantida nem alta disponibilidade nesta entrega, então a latência adicional de ~150-180ms entre o Brasil e Ohio foi aceita conscientemente em troca do menor custo mensal. A região oferece todos os serviços exigidos pela Entrega 2 (VPC, sub-redes, NAT Gateway, Elastic IP, Security Groups, Systems Manager) com disponibilidade equivalente à de sa-east-1. |
| Sistema operacional | Amazon Linux 2023 (AMI ECS-Optimized) | 2023 | Imagem mantida pela AWS, já com Docker Engine e o agente do ECS pré-instalados e atualizados, dispensando provisionamento manual (cloud-init) no host que roda os containers. Inclui o SSM Agent nativamente, necessário para o acesso administrativo via Systems Manager sem bastion. |
| Orquestração de containers | Amazon ECS — launch type EC2 | - | As imagens de frontend e backend já existem prontas no Docker Hub; o ECS permite declarar task definitions que apontam direto para essas imagens, sem etapa de build na infraestrutura. O launch type EC2 foi escolhido no lugar do Fargate para manter controle sobre o dimensionamento e o custo da instância hospedeira, em vez do modelo de cobrança por vCPU/memória do Fargate. |
| Runtime / linguagem (backend) | Java 21 / Spring Boot | 21 / 3.3.x | Stack em que a aplicação do grupo já foi desenvolvida e containerizada; reaproveitar a imagem existente no Docker Hub evita reescrever a aplicação em outra linguagem só para a infraestrutura. |
| Runtime / linguagem (frontend) | React | build estático já publicado como imagem Docker | Mesma justificativa do backend: aplicação já existente e containerizada, servida como build estático atrás do Nginx. |
| Servidor web / proxy | Nginx | 1.26 | Único ponto de entrada público da arquitetura: encaminha `/` para o frontend e `/api` para o backend, ambos em sub-rede privada, e concentra o Elastic IP, evitando expor as instâncias de aplicação diretamente à internet. |
| Banco de dados | PostgreSQL | 16 | Banco relacional self-managed em EC2 (ver ADR-003), compatível com o driver JDBC já usado pelo backend Spring Boot. |
| Infraestrutura como código | Terraform | ~> 1.9 | Ferramenta padrão de mercado com provider oficial maduro para AWS; escolhida no lugar do OpenTofu por familiaridade do grupo. |
| Provider do Terraform | hashicorp/aws | ~> 5.0 | Provider oficial da HashiCorp, com suporte completo aos recursos exigidos (VPC, sub-redes, NAT Gateway, Security Groups, EC2, Elastic IP). |
| Instalação da aplicação | ECS task definitions (pull direto do Docker Hub) | - | Como as imagens de frontend e backend já estão publicadas no Docker Hub, a instalação não exige script de build nem Ansible: o ECS Agent apenas puxa a imagem e sobe o container conforme a task definition, o que também simplifica recriar o ambiente entre sessões de teste (seção 5.9). |

## 5.7 Dimensionamento das instâncias

O requisito não funcional definido pelo grupo (seção 5.1) é de **1 usuário simultâneo**, sem exigência de alta disponibilidade nesta entrega. Por isso o dimensionamento abaixo prioriza o menor custo mensal compatível com a carga, e não throughput ou concorrência.

Todas as instâncias usam a família **t3** (CPU baseada em créditos), adequada a uma carga majoritariamente ociosa com picos curtos por requisição — típica de 1 usuário simultâneo.

| Componente | Família | Tipo | vCPU | Memória | Disco (tipo e tamanho) | Sub-rede | Justificativa |
|---|---|---|---|---|---|---|---|
| Nginx (proxy público) | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 20 GiB | Pública (com Elastic IP) | TODO |
| Host ECS (frontend x2 + backend x2) | t3 (CPU baseada em créditos) | t3.medium | 2 | 4 GiB | gp3, 30 GiB | Privada | TODO |
| PostgreSQL | t3 (CPU baseada em créditos) | t3.micro | 2 | 1 GiB | gp3, 30 GiB | Privada | TODO |