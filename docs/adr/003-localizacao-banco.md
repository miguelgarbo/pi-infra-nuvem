# ADR-003: Localização do Banco de Dados

No contexto de uma aplicação de aluguel de carros cujo backend Spring Boot persiste usuários, veículos e locações em um banco relacional, com carga estimada baixa e orçamento pago pelo próprio grupo,
diante da necessidade de definir se o PostgreSQL ficará em uma instância própria na sub-rede privada ou em um serviço gerenciado,
decidimos executar o PostgreSQL 16 em uma EC2 `t3.micro` na sub-rede privada (`10.50.0.22`), acessível apenas pelo `sg-backend` na porta 5432,
e descartamos o Amazon RDS for PostgreSQL e o Aurora Serverless,
para manter o menor custo mensal, ter controle total da instalação e da configuração do banco,
aceitando que o grupo assume patches, backups, monitoramento e recuperação do banco, que não há failover automático, e que os dados podem ser perdidos se a instância ou o volume EBS forem destruídos ao recriar o ambiente sem um `pg_dump` ou snapshot prévio.
