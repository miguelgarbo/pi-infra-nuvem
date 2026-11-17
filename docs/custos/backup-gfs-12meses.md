# Custo anual da política conservadora GFS (B7)


## Premissas

| Premissa | Valor | Justificativa |
|---|---|---|
| Volume do banco no mês 1 | 2,0 GB | Locadora de pequeno a médio porte (RNF01: 50 usuários simultâneos); tabelas de usuários, veículos, locações e auditoria |
| Crescimento mensal | 0,5 GB | Novas locações e registros de auditoria; a auditoria é a tabela que mais cresce |
| Tamanho de cada cópia | Volume inteiro do banco no mês | Premissa conservadora (teto). Snapshots do RDS são incrementais, então o valor real tende a ser menor |
| Cópias retidas | Son 7 + Father 5 + Grandfather até 12 | Conta o pico de cópias de cada mês |
| Franquia gratuita de backup | 20 GB | Backups e snapshots do RDS não são cobrados até 100% do armazenamento provisionado da região |
| Cópia em outra região | Só o Grandfather, para us-east-2 | Protege contra perda da região inteira; diários e semanais ficam só em us-east-1 |

## Preços unitários (us-east-1)

| Item | Preço | Observação |
|---|---|---|
| Armazenamento de backup/snapshot RDS | US$ 0.095/GB-mês | Mesmo valor para snapshots criados pelo AWS Backup |
| Armazenamento do snapshot copiado em us-east-2 | US$ 0.095/GB-mês | Cobrado na região de destino |
| Transferência entre regiões | US$ 0.02/GB | Cobrada a cada cópia mensal |
| Restauração a partir do armazenamento warm | Sem custo | Não entra na tabela (não há teste de restauração) |
| Requisições de API do AWS Backup | Desprezível | Poucas execuções por mês |
| Classe fria (cold storage) | Não disponível | O AWS Backup só oferece cold storage para EBS, EFS e DynamoDB, não para RDS |

## Tabela de 12 meses

| Mês | Volume de dados | Cópias retidas (S + F + G) | Volume em backup us-east-1 | Cobrado após franquia | Cópia em us-east-2 | Custo mensal |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2,0 GB | 7 + 4 + 1 = 12 | 24,0 GB | 4,0 GB | 2,0 GB | US$ 0,61 |
| 2 | 2,5 GB | 7 + 5 + 2 = 14 | 35,0 GB | 15,0 GB | 5,0 GB | US$ 1,95 |
| 3 | 3,0 GB | 7 + 5 + 3 = 15 | 45,0 GB | 25,0 GB | 9,0 GB | US$ 3,29 |
| 4 | 3,5 GB | 7 + 5 + 4 = 16 | 56,0 GB | 36,0 GB | 14,0 GB | US$ 4,82 |
| 5 | 4,0 GB | 7 + 5 + 5 = 17 | 68,0 GB | 48,0 GB | 20,0 GB | US$ 6,54 |
| 6 | 4,5 GB | 7 + 5 + 6 = 18 | 81,0 GB | 61,0 GB | 27,0 GB | US$ 8,45 |
| 7 | 5,0 GB | 7 + 5 + 7 = 19 | 95,0 GB | 75,0 GB | 35,0 GB | US$ 10,55 |
| 8 | 5,5 GB | 7 + 5 + 8 = 20 | 110,0 GB | 90,0 GB | 44,0 GB | US$ 12,84 |
| 9 | 6,0 GB | 7 + 5 + 9 = 21 | 126,0 GB | 106,0 GB | 54,0 GB | US$ 15,32 |
| 10 | 6,5 GB | 7 + 5 + 10 = 22 | 143,0 GB | 123,0 GB | 65,0 GB | US$ 17,99 |
| 11 | 7,0 GB | 7 + 5 + 11 = 23 | 161,0 GB | 141,0 GB | 77,0 GB | US$ 20,85 |
| 12 | 7,5 GB | 7 + 5 + 12 = 24 | 180,0 GB | 160,0 GB | 90,0 GB | US$ 23,90 |
| **Total no ano** | | | | | | **US$ 127,11** |

## Qual parâmetro mais pesa no custo anual

| Cenário | Custo anual | Economia |
|---|---:|---:|
| Política proposta (7 diários, 5 semanais, 12 mensais, cópia em us-east-2) | US$ 127,11 | US$ 0,00 |
| Son com 3 dias em vez de 7 | US$ 105,83 | US$ 21,28 |
| Father com 2 semanas em vez de 5 | US$ 111,05 | US$ 16,06 |
| Grandfather com 6 meses em vez de 12 | US$ 100,51 | US$ 26,60 |
| Sem cópia do Grandfather em outra região | US$ 83,98 | US$ 43,13 |
