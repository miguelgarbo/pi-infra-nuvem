# ADR-001: Estratégia de Acesso Administrativo às Instâncias

No contexto de uma aplicação na AWS com instâncias EC2 em sub-rede privada (frontend, backend e PostgreSQL),
diante da necessidade de que os administradores acessem as instâncias sem expor a porta 22 à internet,
decidimos usar o AWS Systems Manager Session Manager (SSM), serviço da própria AWS criado para acesso remoto, no lugar do bastion sugerido no material da disciplina,
e descartamos o bastion host com SSH restrito ao IP do grupo e a atribuição de IP público direto às instâncias privadas,
para eliminar a porta 22 de todos os security groups, controlar e auditar cada sessão por IAM e dispensar uma instância que existiria só para acesso,
aceitando que o acesso administrativo passa a depender do IAM, do SSM Agent e do NAT Gateway, de modo que a falha de qualquer um deixa as instâncias privadas sem acesso, e que a demonstração de SSH da Entrega 2 exigirá túnel via SSM com sshd ativo na instância.
