-- =====================================================================
-- WelCar Locações - 04_views.sql
-- Views prontas para o dia a dia da loja e para relatórios
-- =====================================================================

SET NAMES utf8mb4;
USE welcar_locacoes;

-- Frota completa com os nomes já resolvidos (base para as outras consultas)
CREATE OR REPLACE VIEW vw_frota AS
SELECT
    v.id            AS veiculo_id,
    v.placa,
    CONCAT(m.marca, ' ', m.nome) AS modelo,
    c.nome          AS categoria,
    c.valor_diaria,
    v.ano,
    v.cor,
    v.km_atual,
    v.status,
    f.nome          AS filial,
    v.adquirido_em,
    v.valor_compra
FROM veiculo v
JOIN modelo    m ON m.id = v.modelo_id
JOIN categoria c ON c.id = m.categoria_id
JOIN filial    f ON f.id = v.filial_id;

-- Quantos carros de cada categoria estão livres em cada filial agora
CREATE OR REPLACE VIEW vw_disponibilidade AS
SELECT
    f.nome AS filial,
    c.nome AS categoria,
    c.valor_diaria,
    COUNT(v.id)                                 AS total_carros,
    COALESCE(SUM(v.status = 'disponivel'), 0)   AS disponiveis,
    COALESCE(SUM(v.status = 'alugado'), 0)      AS alugados,
    COALESCE(SUM(v.status = 'manutencao'), 0)   AS em_manutencao
FROM filial f
CROSS JOIN categoria c
LEFT JOIN modelo  m ON m.categoria_id = c.id
LEFT JOIN veiculo v ON v.modelo_id = m.id AND v.filial_id = f.id AND v.status <> 'inativo'
GROUP BY f.id, f.nome, c.id, c.nome, c.valor_diaria;

-- Locações em andamento, com destaque para as atrasadas
CREATE OR REPLACE VIEW vw_locacoes_abertas AS
SELECT
    l.id AS locacao_id,
    cl.nome AS cliente,
    cl.telefone,
    v.placa,
    CONCAT(m.marca, ' ', m.nome) AS modelo,
    f.nome AS filial_retirada,
    l.retirada_em,
    l.devolucao_prevista,
    CASE WHEN l.devolucao_prevista < NOW() THEN 'ATRASADA' ELSE 'no prazo' END AS situacao,
    GREATEST(TIMESTAMPDIFF(HOUR, l.devolucao_prevista, NOW()), 0) AS horas_atraso
FROM locacao l
JOIN cliente cl ON cl.id = l.cliente_id
JOIN veiculo v  ON v.id = l.veiculo_id
JOIN modelo  m  ON m.id = v.modelo_id
JOIN filial  f  ON f.id = l.filial_retirada_id
WHERE l.status = 'aberta';

-- Faturamento por mês e filial (pela data de devolução, quando a receita é reconhecida)
CREATE OR REPLACE VIEW vw_faturamento_mensal AS
SELECT
    DATE_FORMAT(l.devolvido_em, '%Y-%m') AS mes,
    f.nome                               AS filial,
    COUNT(*)                             AS locacoes,
    SUM(l.valor_total)                   AS receita,
    ROUND(AVG(l.valor_total), 2)         AS ticket_medio,
    SUM(fn_dias_cobrados(l.retirada_em, l.devolvido_em)) AS diarias_vendidas
FROM locacao l
JOIN filial f ON f.id = l.filial_retirada_id
WHERE l.status = 'encerrada'
GROUP BY mes, f.id, f.nome;

-- Quanto falta receber de cada locação encerrada
CREATE OR REPLACE VIEW vw_saldo_locacao AS
SELECT
    l.id AS locacao_id,
    cl.id AS cliente_id,
    cl.nome AS cliente,
    l.devolvido_em,
    l.valor_total,
    COALESCE(p.pago, 0)                 AS valor_pago,
    l.valor_total - COALESCE(p.pago, 0) AS saldo_devedor
FROM locacao l
JOIN cliente cl ON cl.id = l.cliente_id
LEFT JOIN (
    SELECT locacao_id, SUM(valor) AS pago
    FROM pagamento
    GROUP BY locacao_id
) p ON p.locacao_id = l.id
WHERE l.status = 'encerrada';

-- Resultado de cada carro: quanto rendeu x quanto custou de oficina
CREATE OR REPLACE VIEW vw_resultado_veiculo AS
SELECT
    fr.veiculo_id,
    fr.placa,
    fr.modelo,
    fr.categoria,
    fr.status,
    fr.valor_compra,
    COALESCE(r.receita, 0)   AS receita,
    COALESCE(mn.custo, 0)    AS custo_manutencao,
    COALESCE(r.receita, 0) - COALESCE(mn.custo, 0) AS resultado,
    ROUND((COALESCE(r.receita, 0) - COALESCE(mn.custo, 0)) / fr.valor_compra * 100, 1) AS retorno_pct
FROM vw_frota fr
LEFT JOIN (
    SELECT veiculo_id, SUM(valor_total) AS receita
    FROM locacao
    WHERE status = 'encerrada'
    GROUP BY veiculo_id
) r ON r.veiculo_id = fr.veiculo_id
LEFT JOIN (
    SELECT veiculo_id, SUM(custo) AS custo
    FROM manutencao
    GROUP BY veiculo_id
) mn ON mn.veiculo_id = fr.veiculo_id;
