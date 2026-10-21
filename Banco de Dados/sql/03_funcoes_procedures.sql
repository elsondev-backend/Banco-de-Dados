-- =====================================================================
-- WelCar Locações - 03_funcoes_procedures.sql
-- Regras de negócio dentro do banco: cálculo de valores, abertura e
-- encerramento de locações com validação e transação.
-- =====================================================================

SET NAMES utf8mb4;
USE welcar_locacoes;

DROP FUNCTION  IF EXISTS fn_dias_cobrados;
DROP FUNCTION  IF EXISTS fn_valor_locacao;
DROP PROCEDURE IF EXISTS sp_abrir_locacao;
DROP PROCEDURE IF EXISTS sp_adicionar_adicional;
DROP PROCEDURE IF EXISTS sp_encerrar_locacao;
DROP PROCEDURE IF EXISTS sp_faturamento_periodo;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Diárias cobradas entre dois momentos.
-- Regra: cada diária tem 24h, há 1 hora de tolerância e o mínimo é 1.
-- Ex.: retirou 10:00 e devolveu no dia seguinte 10:50 -> 1 diária;
--      devolveu 11:30 -> 2 diárias.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_dias_cobrados(p_inicio DATETIME, p_fim DATETIME)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    RETURN GREATEST(1, CEIL((TIMESTAMPDIFF(MINUTE, p_inicio, p_fim) - 60) / 1440));
END$$

-- ---------------------------------------------------------------------
-- Valor final de uma locação, dado o momento e a filial de devolução.
--   * diárias até a data prevista: (diária do carro + adicionais)
--   * diárias além do previsto: diária do carro com 20% de acréscimo + adicionais
--   * devolver em outra filial: taxa fixa de R$ 150,00
-- Devolução antecipada cobra só as diárias usadas.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_valor_locacao(
    p_locacao_id        INT UNSIGNED,
    p_devolvido_em      DATETIME,
    p_filial_devolucao  SMALLINT UNSIGNED
)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_retirada     DATETIME;
    DECLARE v_prevista     DATETIME;
    DECLARE v_diaria       DECIMAL(8,2);
    DECLARE v_filial_ret   SMALLINT UNSIGNED;
    DECLARE v_adicionais   DECIMAL(8,2);
    DECLARE v_dias_prev    INT;
    DECLARE v_dias_real    INT;
    DECLARE v_total        DECIMAL(10,2);

    SELECT retirada_em, devolucao_prevista, valor_diaria, filial_retirada_id
      INTO v_retirada, v_prevista, v_diaria, v_filial_ret
      FROM locacao
     WHERE id = p_locacao_id;

    SELECT COALESCE(SUM(quantidade * valor_diaria), 0)
      INTO v_adicionais
      FROM locacao_adicional
     WHERE locacao_id = p_locacao_id;

    SET v_dias_prev = fn_dias_cobrados(v_retirada, v_prevista);
    SET v_dias_real = fn_dias_cobrados(v_retirada, p_devolvido_em);

    SET v_total = LEAST(v_dias_real, v_dias_prev) * (v_diaria + v_adicionais)
                + GREATEST(v_dias_real - v_dias_prev, 0) * (ROUND(v_diaria * 1.20, 2) + v_adicionais)
                + IF(p_filial_devolucao <> v_filial_ret, 150.00, 0);

    RETURN v_total;
END$$

-- ---------------------------------------------------------------------
-- Abre uma locação (entrega do carro ao cliente).
-- Valida cliente, CNH, idade, carro, atendente e reserva, tudo numa
-- transação: ou grava tudo, ou não grava nada.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_abrir_locacao(
    IN  p_cliente_id      INT UNSIGNED,
    IN  p_veiculo_id      INT UNSIGNED,
    IN  p_funcionario_id  INT UNSIGNED,
    IN  p_dias            INT,
    IN  p_reserva_id      INT UNSIGNED,      -- pode ser NULL (cliente de balcão)
    OUT p_locacao_id      INT UNSIGNED
)
BEGIN
    DECLARE v_nascimento   DATE;
    DECLARE v_cnh_validade DATE;
    DECLARE v_status       VARCHAR(20);
    DECLARE v_filial       SMALLINT UNSIGNED;
    DECLARE v_km           INT UNSIGNED;
    DECLARE v_categoria    TINYINT UNSIGNED;
    DECLARE v_diaria       DECIMAL(8,2);
    DECLARE v_prevista     DATETIME;
    DECLARE v_func_filial  SMALLINT UNSIGNED;
    DECLARE v_func_cargo   VARCHAR(20);
    DECLARE v_res_cliente  INT UNSIGNED;
    DECLARE v_res_cat      TINYINT UNSIGNED;
    DECLARE v_res_status   VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_dias IS NULL OR p_dias NOT BETWEEN 1 AND 90 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantidade de dias deve estar entre 1 e 90.';
    END IF;

    SET v_prevista = NOW() + INTERVAL p_dias DAY;

    START TRANSACTION;

    -- Cliente
    SELECT data_nascimento, cnh_validade
      INTO v_nascimento, v_cnh_validade
      FROM cliente
     WHERE id = p_cliente_id;

    IF v_nascimento IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente não encontrado.';
    END IF;
    IF TIMESTAMPDIFF(YEAR, v_nascimento, CURDATE()) < 21 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente precisa ter pelo menos 21 anos.';
    END IF;
    IF v_cnh_validade < DATE(v_prevista) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CNH vencida ou vence antes da devolução.';
    END IF;

    -- Veículo (FOR UPDATE trava a linha: dois atendentes não alugam o mesmo carro)
    SELECT v.status, v.filial_id, v.km_atual, m.categoria_id, c.valor_diaria
      INTO v_status, v_filial, v_km, v_categoria, v_diaria
      FROM veiculo v
      JOIN modelo m    ON m.id = v.modelo_id
      JOIN categoria c ON c.id = m.categoria_id
     WHERE v.id = p_veiculo_id
       FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veículo não encontrado.';
    END IF;
    IF v_status <> 'disponivel' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veículo não está disponível.';
    END IF;

    -- Funcionário precisa ser da filial onde o carro está
    SELECT filial_id, cargo INTO v_func_filial, v_func_cargo
      FROM funcionario WHERE id = p_funcionario_id;

    IF v_func_filial IS NULL OR v_func_filial <> v_filial OR v_func_cargo = 'mecanico' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Funcionário não pode registrar locação nesta filial.';
    END IF;

    -- Reserva (opcional)
    IF p_reserva_id IS NOT NULL THEN
        SELECT cliente_id, categoria_id, status
          INTO v_res_cliente, v_res_cat, v_res_status
          FROM reserva WHERE id = p_reserva_id
           FOR UPDATE;

        IF v_res_cliente IS NULL OR v_res_cliente <> p_cliente_id THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva não pertence a este cliente.';
        END IF;
        IF v_res_status NOT IN ('pendente', 'confirmada') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva já foi usada ou cancelada.';
        END IF;
        IF v_res_cat <> v_categoria THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veículo não é da categoria reservada.';
        END IF;

        UPDATE reserva SET status = 'convertida' WHERE id = p_reserva_id;
    END IF;

    INSERT INTO locacao (reserva_id, cliente_id, veiculo_id, funcionario_id, filial_retirada_id,
                         retirada_em, devolucao_prevista, km_retirada, valor_diaria, status)
    VALUES (p_reserva_id, p_cliente_id, p_veiculo_id, p_funcionario_id, v_filial,
            NOW(), v_prevista, v_km, v_diaria, 'aberta');

    SET p_locacao_id = LAST_INSERT_ID();

    UPDATE veiculo SET status = 'alugado' WHERE id = p_veiculo_id;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- Inclui um adicional (GPS, cadeirinha...) numa locação aberta
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_adicionar_adicional(
    IN p_locacao_id   INT UNSIGNED,
    IN p_adicional_id TINYINT UNSIGNED,
    IN p_quantidade   TINYINT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM locacao WHERE id = p_locacao_id AND status = 'aberta') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível incluir adicionais em locação aberta.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM adicional WHERE id = p_adicional_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Adicional não encontrado.';
    END IF;

    -- se o adicional já estava na locação, só atualiza a quantidade
    INSERT INTO locacao_adicional (locacao_id, adicional_id, quantidade, valor_diaria)
    SELECT p_locacao_id, id, p_quantidade, valor_diaria
      FROM adicional
     WHERE id = p_adicional_id
    ON DUPLICATE KEY UPDATE quantidade = p_quantidade;
END$$

-- ---------------------------------------------------------------------
-- Encerra uma locação (cliente devolveu o carro): calcula o valor,
-- atualiza quilometragem, filial e status do carro.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_encerrar_locacao(
    IN  p_locacao_id        INT UNSIGNED,
    IN  p_km_devolucao      INT UNSIGNED,
    IN  p_filial_devolucao  SMALLINT UNSIGNED,
    OUT p_valor_total       DECIMAL(10,2)
)
BEGIN
    DECLARE v_status     VARCHAR(20);
    DECLARE v_veiculo    INT UNSIGNED;
    DECLARE v_km_ret     INT UNSIGNED;
    DECLARE v_agora      DATETIME DEFAULT NOW();

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status, veiculo_id, km_retirada
      INTO v_status, v_veiculo, v_km_ret
      FROM locacao
     WHERE id = p_locacao_id
       FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Locação não encontrada.';
    END IF;
    IF v_status <> 'aberta' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Locação não está aberta.';
    END IF;
    IF p_km_devolucao < v_km_ret THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quilometragem de devolução menor que a de retirada.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM filial WHERE id = p_filial_devolucao AND ativa) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Filial de devolução inválida.';
    END IF;

    SET p_valor_total = fn_valor_locacao(p_locacao_id, v_agora, p_filial_devolucao);

    UPDATE locacao
       SET devolvido_em        = v_agora,
           km_devolucao        = p_km_devolucao,
           filial_devolucao_id = p_filial_devolucao,
           valor_total         = p_valor_total,
           status              = 'encerrada'
     WHERE id = p_locacao_id;

    UPDATE veiculo
       SET km_atual  = p_km_devolucao,
           filial_id = p_filial_devolucao,
           status    = 'disponivel'
     WHERE id = v_veiculo;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- Relatório: faturamento por filial num período qualquer
-- Ex.: CALL sp_faturamento_periodo('2026-01-01', '2026-03-31');
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_faturamento_periodo(IN p_inicio DATE, IN p_fim DATE)
BEGIN
    SELECT
        f.nome                         AS filial,
        COUNT(l.id)                    AS locacoes,
        COALESCE(SUM(l.valor_total), 0) AS receita,
        ROUND(AVG(l.valor_total), 2)   AS ticket_medio
    FROM filial f
    LEFT JOIN locacao l
           ON l.filial_retirada_id = f.id
          AND l.status = 'encerrada'
          AND l.devolvido_em >= p_inicio
          AND l.devolvido_em <  p_fim + INTERVAL 1 DAY
    GROUP BY f.id, f.nome
    ORDER BY receita DESC;
END$$

DELIMITER ;
