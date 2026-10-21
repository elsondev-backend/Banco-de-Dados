# Dicionário de dados - welcar_locacoes

Gerado automaticamente por `python/dicionario_dados.py` a partir do banco.

## filial

Lojas da locadora onde os veículos são retirados e devolvidos

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `smallint unsigned` | não | PK |  |  |  |
| nome | `varchar(60)` | não | UK |  |  |  |
| cidade | `varchar(60)` | não |  |  |  |  |
| uf | `char(2)` | não |  |  |  |  |
| telefone | `varchar(20)` | não |  |  |  |  |
| ativa | `tinyint(1)` | não |  | 1 |  |  |

## funcionario

Funcionários das filiais (atendentes registram as locações)

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| filial_id | `smallint unsigned` | não | FK |  | filial.id |  |
| nome | `varchar(100)` | não |  |  |  |  |
| cargo | `enum('atendente','gerente','mecanico')` | não |  |  |  |  |
| admitido_em | `date` | não |  |  |  |  |

## categoria

Grupos de veículos; a diária é definida pela categoria

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `tinyint unsigned` | não | PK |  |  |  |
| nome | `varchar(30)` | não | UK |  |  |  |
| descricao | `varchar(150)` | não |  |  |  |  |
| valor_diaria | `decimal(8,2)` | não |  |  |  |  |

## modelo

Modelos de carro que a locadora possui

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `smallint unsigned` | não | PK |  |  |  |
| categoria_id | `tinyint unsigned` | não | FK |  | categoria.id |  |
| marca | `varchar(30)` | não | índice |  |  |  |
| nome | `varchar(40)` | não |  |  |  |  |
| combustivel | `enum('flex','gasolina','diesel','eletrico','hibrido')` | não |  |  |  |  |
| cambio | `enum('manual','automatico')` | não |  |  |  |  |
| lugares | `tinyint unsigned` | não |  |  |  |  |

## veiculo

Frota: cada carro físico, identificado pela placa

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| modelo_id | `smallint unsigned` | não | FK |  | modelo.id |  |
| filial_id | `smallint unsigned` | não | FK |  | filial.id | Filial onde o carro está agora |
| placa | `char(7)` | não | UK |  |  | Padrão Mercosul, sem hífen (ex.: ABC1D23) |
| ano | `smallint unsigned` | não |  |  |  |  |
| cor | `varchar(20)` | não |  |  |  |  |
| km_atual | `int unsigned` | não |  | 0 |  |  |
| status | `enum('disponivel','alugado','manutencao','inativo')` | não | índice | disponivel |  |  |
| adquirido_em | `date` | não |  |  |  |  |
| valor_compra | `decimal(10,2)` | não |  |  |  |  |

## cliente

Pessoas que alugam veículos

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| nome | `varchar(100)` | não |  |  |  |  |
| cpf | `char(11)` | não | UK |  |  | Somente números |
| email | `varchar(120)` | não | UK |  |  |  |
| telefone | `varchar(20)` | não |  |  |  |  |
| data_nascimento | `date` | não |  |  |  |  |
| cnh_numero | `char(11)` | não | UK |  |  |  |
| cnh_validade | `date` | não |  |  |  |  |
| cidade | `varchar(60)` | não |  |  |  |  |
| uf | `char(2)` | não |  |  |  |  |
| cadastrado_em | `datetime` | não |  | CURRENT_TIMESTAMP |  |  |

## adicional

Itens opcionais cobrados por dia (GPS, cadeirinha, seguro...)

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `tinyint unsigned` | não | PK |  |  |  |
| nome | `varchar(40)` | não | UK |  |  |  |
| valor_diaria | `decimal(8,2)` | não |  |  |  |  |

## reserva

Pedido antecipado de uma categoria para um período

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| cliente_id | `int unsigned` | não | FK |  | cliente.id |  |
| categoria_id | `tinyint unsigned` | não | FK |  | categoria.id | Reserva-se a categoria, não o carro |
| filial_id | `smallint unsigned` | não | FK |  | filial.id |  |
| retirada_prevista | `datetime` | não | índice |  |  |  |
| devolucao_prevista | `datetime` | não |  |  |  |  |
| status | `enum('pendente','confirmada','cancelada','convertida')` | não |  | pendente |  |  |
| criada_em | `datetime` | não |  | CURRENT_TIMESTAMP |  |  |

## locacao

Contrato de aluguel: um cliente, um carro, um período

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| reserva_id | `int unsigned` | sim | UK |  | reserva.id |  |
| cliente_id | `int unsigned` | não | FK |  | cliente.id |  |
| veiculo_id | `int unsigned` | não | FK |  | veiculo.id |  |
| funcionario_id | `int unsigned` | não | FK |  | funcionario.id | Quem entregou o carro |
| filial_retirada_id | `smallint unsigned` | não | FK |  | filial.id |  |
| filial_devolucao_id | `smallint unsigned` | sim | FK |  | filial.id |  |
| retirada_em | `datetime` | não | índice |  |  |  |
| devolucao_prevista | `datetime` | não |  |  |  |  |
| devolvido_em | `datetime` | sim |  |  |  |  |
| km_retirada | `int unsigned` | não |  |  |  |  |
| km_devolucao | `int unsigned` | sim |  |  |  |  |
| valor_diaria | `decimal(8,2)` | não |  |  |  | Diária congelada no momento da retirada |
| valor_total | `decimal(10,2)` | sim |  |  |  | Calculado no encerramento |
| status | `enum('aberta','encerrada','cancelada')` | não | índice | aberta |  |  |

## locacao_adicional

Adicionais contratados em cada locação (N:N)

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| locacao_id | `int unsigned` | não | PK |  | locacao.id |  |
| adicional_id | `tinyint unsigned` | não | PK |  | adicional.id |  |
| quantidade | `tinyint unsigned` | não |  | 1 |  |  |
| valor_diaria | `decimal(8,2)` | não |  |  |  | Valor congelado na contratação |

## pagamento

Pagamentos recebidos; uma locação pode ser paga em mais de uma parte

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| locacao_id | `int unsigned` | não | FK |  | locacao.id |  |
| valor | `decimal(10,2)` | não |  |  |  |  |
| forma | `enum('pix','credito','debito','dinheiro')` | não |  |  |  |  |
| pago_em | `datetime` | não | índice |  |  |  |

## manutencao

Passagens dos veículos pela oficina

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `int unsigned` | não | PK |  |  |  |
| veiculo_id | `int unsigned` | não | FK |  | veiculo.id |  |
| tipo | `enum('revisao','preventiva','corretiva','sinistro')` | não |  |  |  |  |
| descricao | `varchar(200)` | não |  |  |  |  |
| inicio | `date` | não |  |  |  |  |
| fim | `date` | sim |  |  |  | NULL = carro ainda na oficina |
| custo | `decimal(10,2)` | não |  | 0.00 |  |  |

## log_status_veiculo

Histórico de mudanças de status da frota (auditoria)

| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |
|---|---|---|---|---|---|---|
| id | `bigint unsigned` | não | PK |  |  |  |
| veiculo_id | `int unsigned` | não | FK |  | veiculo.id |  |
| status_anterior | `varchar(20)` | não |  |  |  |  |
| status_novo | `varchar(20)` | não |  |  |  |  |
| alterado_em | `datetime` | não |  | CURRENT_TIMESTAMP |  |  |
| usuario_bd | `varchar(100)` | não |  |  |  |  |
