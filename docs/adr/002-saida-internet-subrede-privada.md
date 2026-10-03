# ADR-002: Saída Para a Internet da Sub-Rede Privada
No contexto de uma aplicação na AWS com frontend, backend e PostgreSQL em sub-rede privada (`10.50.0.16/28`) que precisam acessar o ECR, o SSM e os repositórios de atualização do SO,
diante da necessidade de saída para a internet sem expor essas instâncias a conexões iniciadas de fora,
decidimos usar um NAT Gateway gerenciado na sub-rede pública (`us-east-2a`), com a rota `0.0.0.0/0` da sub-rede privada apontando para ele,
e descartamos o NAT em instância (EC2 com NAT configurado manualmente) e a ausência de saída para a internet,
para obter uma saída gerenciada pela AWS, sem manutenção de SO nem configuração de roteamento em instância, e manter o pull de imagens do ECR e o acesso administrativo via SSM (ADR-001) funcionando,
aceitando que o NAT Gateway é cobrado por hora (cerca de US$ 32/mês) mais o volume de dados processado, sendo provavelmente o item mais caro da arquitetura mesmo com carga baixa, e que, por existir em uma única AZ, sua falha interrompe os pulls de imagem e o acesso via SSM.
