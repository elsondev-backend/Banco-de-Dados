-- =====================================================================
-- WelCar Locações - 05_triggers.sql
-- Regras que o banco garante sozinho, venha a alteração de onde vier.
-- Criadas depois da carga de dados para não interferir no histórico.
-- =====================================================================

SET NAMES utf8mb4;
USE welcar_locacoes;

DROP TRIGGER IF EXISTS trg_veiculo_bu;
DROP TRIGGER IF EXISTS trg_veiculo_au;
DROP TRIGGER IF EXISTS trg_locacao_bi;
DROP TRIGGER IF EXISTS trg_manutencao_bi;
DROP TRIGGER IF EXISTS trg_manutencao_ai;
DROP TRIGGER IF EXISTS trg_manutencao_au;
DROP TRIGGER IF EXISTS trg_pagamento_bi;

DELIMITER $$

-- Hodômetro nunca volta para trás
CREATE TRIGGER trg_veiculo_bu
BEFORE UPDATE ON veiculo
FOR EACH ROW
BEGIN
    IF NEW.km_atual < OLD.km_atual THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A quilometragem do veículo não pode diminuir.';
    END IF;
END$$

-- Auditoria: toda mudança de status do carro fica registrada
CREATE TRIGGER trg_veiculo_au
AFTER UPDATE ON veiculo
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        INSERT INTO log_status_veiculo (veiculo_id, status_anterior, status_novo, usuario_bd)
        VALUES (NEW.id, OLD.status, NEW.status, CURRENT_USER());
    END IF;
END$$

-- Um carro não pode ter duas locações abertas ao mesmo tempo
CREATE TRIGGER trg_locacao_bi
BEFORE INSERT ON locacao
FOR EACH ROW
BEGIN
    IF NEW.status = 'aberta' AND EXISTS (
        SELECT 1 FROM locacao WHERE veiculo_id = NEW.veiculo_id AND status = 'aberta'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este veículo já tem uma locação aberta.';
    END IF;
END$$

-- Carro alugado não entra na oficina
CREATE TRIGGER trg_manutencao_bi
BEFORE INSERT ON manutencao
FOR EACH ROW
BEGIN
    IF NEW.fim IS NULL AND EXISTS (
        SELECT 1 FROM veiculo WHERE id = NEW.veiculo_id AND status = 'alugado'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Veículo está alugado; encerre a locação antes da manutenção.';
    END IF;
END$$

-- Abriu manutenção -> carro fica indisponível
CREATE TRIGGER trg_manutencao_ai
AFTER INSERT ON manutencao
FOR EACH ROW
BEGIN
    IF NEW.fim IS NULL THEN
        UPDATE veiculo SET status = 'manutencao' WHERE id = NEW.veiculo_id;
    END IF;
END$$

-- Fechou a manutenção (preencheu a data de fim) -> carro volta a ficar disponível
CREATE TRIGGER trg_manutencao_au
AFTER UPDATE ON manutencao
FOR EACH ROW
BEGIN
    IF OLD.fim IS NULL AND NEW.fim IS NOT NULL THEN
        UPDATE veiculo
           SET status = 'disponivel'
         WHERE id = NEW.veiculo_id
           AND status = 'manutencao';
    END IF;
END$$

-- Não aceita pagamento em locação cancelada nem acima do valor devido
CREATE TRIGGER trg_pagamento_bi
BEFORE INSERT ON pagamento
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_total  DECIMAL(10,2);
    DECLARE v_pago   DECIMAL(10,2);

    SELECT status, valor_total INTO v_status, v_total
      FROM locacao WHERE id = NEW.locacao_id;

    IF v_status = 'cancelada' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Locação cancelada não recebe pagamento.';
    END IF;

    IF v_status = 'encerrada' THEN
        SELECT COALESCE(SUM(valor), 0) INTO v_pago
          FROM pagamento WHERE locacao_id = NEW.locacao_id;

        IF v_pago + NEW.valor > v_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento maior que o saldo devedor da locação.';
        END IF;
    END IF;
END$$

DELIMITER ;
