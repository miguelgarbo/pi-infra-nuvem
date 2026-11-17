# ADR-005: Estratégia de Backup do Banco de Dados

**Status:** aceita

No contexto do sistema de reservas de uma locadora, cujo único dado não reproduzível pelo Terraform é o PostgreSQL no Amazon RDS Multi-AZ, com RPO de 15 minutos e RTO de 2 horas,
diante da necessidade de recuperar o banco após exclusão acidental, corrupção ou ataque, sem que o ambiente acadêmico gere custo contínuo,
decidimos adotar como política de produção um GFS com o backup automático do RDS como geração Son (diária, 7 dias, com PITR), e snapshots do AWS Backup como Father (domingo, 5 semanas) e Grandfather (dia 1 do mês, 12 meses, com cópia para us-east-2), e configurar no trabalho apenas a geração Son com retenção de 2 dias e criptografia declarada no Terraform,
e descartamos o `pg_dump` agendado para um bucket S3 e os snapshots de disco de VM, que só fariam sentido com o banco em EC2 (ADR-003, substituída),
para usar o mecanismo nativo do serviço gerenciado, que é consistente, criptografado e não exige rotina, role nem credencial dentro das instâncias, com custo estimado de US$ 127 no primeiro ano para a GFS e próximo de zero para a política mínima,
aceitando que a classe fria não está disponível para RDS no AWS Backup, então todas as gerações ficam em armazenamento warm, que a restauração cria uma nova instância e exige atualizar o endpoint do backend, e que no trabalho o `terraform destroy` apaga o banco e seus backups automáticos (`skip_final_snapshot` e `delete_automated_backups`), de modo que um erro descoberto depois de 2 dias, ou depois do destroy, não pode ser desfeito.
