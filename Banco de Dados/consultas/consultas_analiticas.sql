-- =====================================================================
-- WelCar Locações - Consultas analíticas
-- Perguntas de negócio respondidas com SQL, da mais simples à mais avançada.
-- Rode depois de criar o banco (scripts da pasta sql/).
-- =====================================================================

USE welcar_locacoes;

-- ---------------------------------------------------------------------
-- 1. Quais carros estão livres agora no aeroporto, do mais barato ao mais caro?
--    (JOIN + filtro + ordenação)
-- ---------------------------------------------------------------------
SELECT placa, modelo, categoria, valor_diaria, km_atual
FROM vw_frota
WHERE filial = 'Salvador - Aeroporto'
  AND status = 'disponivel'
ORDER BY valor_diaria, km_atual;

-- ---------------------------------------------------------------------
-- 2. Receita e quantidade de locações por categoria em 2025
--    (GROUP BY + funções de agregação)
-- ---------------------------------------------------------------------
SELECT
    c.nome                        AS categoria,
    COUNT(*)                      AS locacoes,
    SUM(l.valor_total)            AS receita,
    ROUND(AVG(l.valor_total), 2)  AS ticket_medio,
    ROUND(AVG(fn_dias_cobrados(l.retirada_em, l.devolvido_em)), 1) AS media_diarias
FROM locacao l
JOIN veiculo v   ON v.id = l.veiculo_id
JOIN modelo m    ON m.id = v.modelo_id
JOIN categoria c ON c.id = m.categoria_id
WHERE l.status = 'encerrada'
  AND l.devolvido_em >= '2025-01-01' AND l.devolvido_em < '2026-01-01'
GROUP BY c.id, c.nome
ORDER BY receita DESC;

-- ---------------------------------------------------------------------
-- 3. Clientes que alugaram 30 vezes ou mais (clientes fiéis)
--    (GROUP BY + HAVING)
-- ---------------------------------------------------------------------
SELECT
    cl.nome,
    cl.cidade,
    COUNT(*)            AS locacoes,
    SUM(l.valor_total)  AS total_gasto,
    MAX(l.retirada_em)  AS ultima_locacao
FROM cliente cl
JOIN locacao l ON l.cliente_id = cl.id
WHERE l.status = 'encerrada'
GROUP BY cl.id, cl.nome, cl.cidade
HAVING COUNT(*) >= 30
ORDER BY locacoes DESC;

-- ---------------------------------------------------------------------
-- 4. Clientes cadastrados que nunca alugaram (para campanha de marketing)
--    (anti-join com NOT EXISTS)
-- ---------------------------------------------------------------------
SELECT cl.nome, cl.email, cl.cadastrado_em
FROM cliente cl
WHERE NOT EXISTS (SELECT 1 FROM locacao l WHERE l.cliente_id = cl.id)
ORDER BY cl.cadastrado_em;

-- ---------------------------------------------------------------------
-- 5. Clientes com CNH vencida ou vencendo nos próximos 60 dias
--    (funções de data)
-- ---------------------------------------------------------------------
SELECT
    nome,
    telefone,
    cnh_validade,
    DATEDIFF(cnh_validade, CURDATE()) AS dias_para_vencer,
    IF(cnh_validade < CURDATE(), 'VENCIDA', 'vence em breve') AS situacao
FROM cliente
WHERE cnh_validade < CURDATE() + INTERVAL 60 DAY
ORDER BY cnh_validade;

-- ---------------------------------------------------------------------
-- 6. Inadimplência: locações encerradas com saldo a receber
--    (view + agregação)
-- ---------------------------------------------------------------------
SELECT cliente, COUNT(*) AS locacoes_em_aberto, SUM(saldo_devedor) AS total_devido
FROM vw_saldo_locacao
WHERE saldo_devedor > 0
GROUP BY cliente_id, cliente
ORDER BY total_devido DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 7. Faturamento mês a mês da empresa com crescimento em relação
--    ao mês anterior e ao mesmo mês do ano anterior
--    (CTE + window function LAG)
-- ---------------------------------------------------------------------
WITH mensal AS (
    SELECT mes, SUM(receita) AS receita
    FROM vw_faturamento_mensal
    GROUP BY mes
)
SELECT
    mes,
    receita,
    ROUND((receita / LAG(receita, 1)  OVER (ORDER BY mes) - 1) * 100, 1) AS variacao_mes_pct,
    ROUND((receita / LAG(receita, 12) OVER (ORDER BY mes) - 1) * 100, 1) AS variacao_ano_pct,
    SUM(receita) OVER (PARTITION BY LEFT(mes, 4) ORDER BY mes)        AS acumulado_no_ano
FROM mensal
ORDER BY mes;

-- ---------------------------------------------------------------------
-- 8. Categoria campeã de cada filial
--    (CTE + ROW_NUMBER por partição)
-- ---------------------------------------------------------------------
WITH ranking AS (
    SELECT
        f.nome AS filial,
        c.nome AS categoria,
        COUNT(*) AS locacoes,
        ROW_NUMBER() OVER (PARTITION BY f.id ORDER BY COUNT(*) DESC) AS posicao
    FROM locacao l
    JOIN filial f    ON f.id = l.filial_retirada_id
    JOIN veiculo v   ON v.id = l.veiculo_id
    JOIN modelo m    ON m.id = v.modelo_id
    JOIN categoria c ON c.id = m.categoria_id
    GROUP BY f.id, f.nome, c.id, c.nome
)
SELECT filial, categoria, locacoes
FROM ranking
WHERE posicao = 1
ORDER BY locacoes DESC;

-- ---------------------------------------------------------------------
-- 9. Curva ABC de clientes: quem são os clientes que somam 50% da receita?
--    (window function com soma acumulada + percentual)
-- ---------------------------------------------------------------------
WITH por_cliente AS (
    SELECT cliente_id, SUM(valor_total) AS receita
    FROM locacao
    WHERE status = 'encerrada'
    GROUP BY cliente_id
),
acumulado AS (
    SELECT
        cliente_id,
        receita,
        SUM(receita) OVER (ORDER BY receita DESC, cliente_id) / SUM(receita) OVER () * 100 AS pct_acumulado
    FROM por_cliente
)
SELECT
    CASE
        WHEN pct_acumulado <= 50 THEN 'A (50% da receita)'
        WHEN pct_acumulado <= 80 THEN 'B (próximos 30%)'
        ELSE 'C (últimos 20%)'
    END AS classe,
    COUNT(*)      AS clientes,
    SUM(receita)  AS receita
FROM acumulado
GROUP BY classe
ORDER BY classe;

-- ---------------------------------------------------------------------
-- 10. Taxa de ocupação da frota por mês: % das diárias possíveis que
--     foram de fato alugadas
--     (CTE recursiva para gerar o calendário + junção por intervalo)
-- ---------------------------------------------------------------------
WITH RECURSIVE meses AS (
    SELECT DATE('2025-01-01') AS inicio
    UNION ALL
    SELECT inicio + INTERVAL 1 MONTH FROM meses WHERE inicio < '2026-09-01'
),
capacidade AS (
    -- dias que cada carro existia na frota dentro do mês
    SELECT m.inicio,
           SUM(DATEDIFF(LEAST(m.inicio + INTERVAL 1 MONTH, CURDATE()),
                        GREATEST(m.inicio, v.adquirido_em))) AS dias_carro
    FROM meses m
    JOIN veiculo v ON v.adquirido_em < m.inicio + INTERVAL 1 MONTH
    GROUP BY m.inicio
),
uso AS (
    -- horas alugadas dentro do mês (corta as locações que atravessam a virada)
    SELECT m.inicio,
           SUM(TIMESTAMPDIFF(MINUTE,
                   GREATEST(l.retirada_em, m.inicio),
                   LEAST(COALESCE(l.devolvido_em, NOW()), m.inicio + INTERVAL 1 MONTH))) / 1440 AS dias_alugados
    FROM meses m
    JOIN locacao l
      ON l.retirada_em < m.inicio + INTERVAL 1 MONTH
     AND COALESCE(l.devolvido_em, NOW()) > m.inicio
    GROUP BY m.inicio
)
SELECT
    DATE_FORMAT(c.inicio, '%Y-%m') AS mes,
    c.dias_carro,
    ROUND(u.dias_alugados)         AS dias_alugados,
    ROUND(u.dias_alugados / c.dias_carro * 100, 1) AS ocupacao_pct
FROM capacidade c
JOIN uso u ON u.inicio = c.inicio
ORDER BY c.inicio;

-- ---------------------------------------------------------------------
-- 11. Carros que deram mais e menos retorno (top 5 e bottom 5)
--     (view + UNION ALL de dois rankings)
-- ---------------------------------------------------------------------
(SELECT 'Melhores' AS grupo, placa, modelo, receita, custo_manutencao, retorno_pct
   FROM vw_resultado_veiculo ORDER BY retorno_pct DESC LIMIT 5)
UNION ALL
(SELECT 'Piores', placa, modelo, receita, custo_manutencao, retorno_pct
   FROM vw_resultado_veiculo WHERE status <> 'inativo' ORDER BY retorno_pct LIMIT 5);

-- ---------------------------------------------------------------------
-- 12. Quanto tempo o carro fica parado entre uma locação e outra?
--     (LAG para comparar cada locação com a anterior do mesmo carro)
-- ---------------------------------------------------------------------
WITH intervalos AS (
    SELECT
        l.veiculo_id,
        TIMESTAMPDIFF(HOUR,
            LAG(l.devolvido_em) OVER (PARTITION BY l.veiculo_id ORDER BY l.retirada_em),
            l.retirada_em) AS horas_parado
    FROM locacao l
)
SELECT
    c.nome AS categoria,
    ROUND(AVG(i.horas_parado) / 24, 1) AS media_dias_parado,
    MAX(i.horas_parado) DIV 24         AS maior_intervalo_dias
FROM intervalos i
JOIN veiculo v   ON v.id = i.veiculo_id
JOIN modelo m    ON m.id = v.modelo_id
JOIN categoria c ON c.id = m.categoria_id
WHERE i.horas_parado IS NOT NULL
GROUP BY c.id, c.nome
ORDER BY media_dias_parado;

-- ---------------------------------------------------------------------
-- 13. Pontualidade na devolução por filial
--     (CASE dentro de agregação)
-- ---------------------------------------------------------------------
SELECT
    f.nome AS filial,
    COUNT(*) AS devolucoes,
    ROUND(AVG(l.devolvido_em <= l.devolucao_prevista + INTERVAL 1 HOUR) * 100, 1) AS no_prazo_pct,
    ROUND(AVG(l.devolvido_em >  l.devolucao_prevista + INTERVAL 1 HOUR) * 100, 1) AS atrasadas_pct,
    ROUND(AVG(l.filial_devolucao_id <> l.filial_retirada_id) * 100, 1)        AS outra_filial_pct
FROM locacao l
JOIN filial f ON f.id = l.filial_retirada_id
WHERE l.status = 'encerrada'
GROUP BY f.id, f.nome
ORDER BY no_prazo_pct DESC;

-- ---------------------------------------------------------------------
-- 14. Taxa de conversão de reservas e antecedência média
--     (agregação condicional)
-- ---------------------------------------------------------------------
SELECT
    DATE_FORMAT(r.retirada_prevista, '%Y') AS ano,
    COUNT(*)                                AS reservas,
    SUM(r.status = 'convertida')            AS convertidas,
    SUM(r.status = 'cancelada')             AS canceladas,
    ROUND(AVG(r.status = 'convertida') * 100, 1) AS conversao_pct,
    ROUND(AVG(DATEDIFF(r.retirada_prevista, r.criada_em)), 1) AS antecedencia_media_dias
FROM reserva r
WHERE r.retirada_prevista < NOW()
GROUP BY ano;

-- ---------------------------------------------------------------------
-- 15. Adicionais mais vendidos e quanto cada um trouxe de receita
--     (N:N + cálculo por diárias)
-- ---------------------------------------------------------------------
SELECT
    a.nome AS adicional,
    COUNT(*) AS locacoes,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM locacao) * 100, 1) AS presenca_pct,
    SUM(la.quantidade * la.valor_diaria * fn_dias_cobrados(l.retirada_em, l.devolvido_em)) AS receita_estimada
FROM locacao_adicional la
JOIN adicional a ON a.id = la.adicional_id
JOIN locacao l   ON l.id = la.locacao_id
WHERE l.status = 'encerrada'
GROUP BY a.id, a.nome
ORDER BY receita_estimada DESC;

-- ---------------------------------------------------------------------
-- 16. Formas de pagamento: participação por ano
--     (pivot com SUM(CASE ...))
-- ---------------------------------------------------------------------
SELECT
    YEAR(pago_em) AS ano,
    ROUND(SUM(CASE WHEN forma = 'pix'      THEN valor END) / SUM(valor) * 100, 1) AS pix_pct,
    ROUND(SUM(CASE WHEN forma = 'credito'  THEN valor END) / SUM(valor) * 100, 1) AS credito_pct,
    ROUND(SUM(CASE WHEN forma = 'debito'   THEN valor END) / SUM(valor) * 100, 1) AS debito_pct,
    ROUND(SUM(CASE WHEN forma = 'dinheiro' THEN valor END) / SUM(valor) * 100, 1) AS dinheiro_pct,
    SUM(valor) AS total_recebido
FROM pagamento
GROUP BY ano
ORDER BY ano;

-- ---------------------------------------------------------------------
-- 17. Carros que já passaram da próxima revisão de 10.000 km
--     (subconsulta correlacionada)
-- ---------------------------------------------------------------------
SELECT
    fr.placa,
    fr.modelo,
    fr.km_atual,
    (SELECT MAX(mn.inicio) FROM manutencao mn
      WHERE mn.veiculo_id = fr.veiculo_id AND mn.tipo = 'revisao') AS ultima_revisao,
    fr.km_atual DIV 10000 * 10000 AS revisao_devida_km
FROM vw_frota fr
WHERE fr.status <> 'inativo'
  AND (SELECT COUNT(*) FROM manutencao mn
        WHERE mn.veiculo_id = fr.veiculo_id AND mn.tipo = 'revisao') < fr.km_atual DIV 10000
ORDER BY fr.km_atual DESC;
