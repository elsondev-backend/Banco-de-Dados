-- =====================================================================
-- WelCar Locações - Banco de dados de uma locadora de veículos
-- 01_schema.sql : criação do banco, tabelas, chaves e índices
-- SGBD: MySQL 8.0+ (testado no 8.4)
-- =====================================================================

SET NAMES utf8mb4;

DROP DATABASE IF EXISTS welcar_locacoes;
CREATE DATABASE welcar_locacoes
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE welcar_locacoes;

-- ---------------------------------------------------------------------
-- Cadastros básicos
-- ---------------------------------------------------------------------

CREATE TABLE filial (
    id          SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome        VARCHAR(60)  NOT NULL,
    cidade      VARCHAR(60)  NOT NULL,
    uf          CHAR(2)      NOT NULL,
    telefone    VARCHAR(20)  NOT NULL,
    ativa       BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_filial_nome UNIQUE (nome)
) COMMENT = 'Lojas da locadora onde os veículos são retirados e devolvidos';

CREATE TABLE funcionario (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    filial_id   SMALLINT UNSIGNED NOT NULL,
    nome        VARCHAR(100) NOT NULL,
    cargo       ENUM('atendente', 'gerente', 'mecanico') NOT NULL,
    admitido_em DATE         NOT NULL,
    CONSTRAINT fk_funcionario_filial FOREIGN KEY (filial_id) REFERENCES filial (id)
) COMMENT = 'Funcionários das filiais (atendentes registram as locações)';

CREATE TABLE categoria (
    id            TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome          VARCHAR(30)   NOT NULL,
    descricao     VARCHAR(150)  NOT NULL,
    valor_diaria  DECIMAL(8,2)  NOT NULL,
    CONSTRAINT uq_categoria_nome UNIQUE (nome),
    CONSTRAINT ck_categoria_diaria CHECK (valor_diaria > 0)
) COMMENT = 'Grupos de veículos; a diária é definida pela categoria';

CREATE TABLE modelo (
    id            SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    categoria_id  TINYINT UNSIGNED NOT NULL,
    marca         VARCHAR(30)  NOT NULL,
    nome          VARCHAR(40)  NOT NULL,
    combustivel   ENUM('flex', 'gasolina', 'diesel', 'eletrico', 'hibrido') NOT NULL,
    cambio        ENUM('manual', 'automatico') NOT NULL,
    lugares       TINYINT UNSIGNED NOT NULL,
    CONSTRAINT uq_modelo UNIQUE (marca, nome),
    CONSTRAINT fk_modelo_categoria FOREIGN KEY (categoria_id) REFERENCES categoria (id),
    CONSTRAINT ck_modelo_lugares CHECK (lugares BETWEEN 2 AND 15)
) COMMENT = 'Modelos de carro que a locadora possui';

CREATE TABLE veiculo (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    modelo_id       SMALLINT UNSIGNED NOT NULL,
    filial_id       SMALLINT UNSIGNED NOT NULL COMMENT 'Filial onde o carro está agora',
    placa           CHAR(7)       NOT NULL COMMENT 'Padrão Mercosul, sem hífen (ex.: ABC1D23)',
    ano             SMALLINT UNSIGNED NOT NULL,
    cor             VARCHAR(20)   NOT NULL,
    km_atual        INT UNSIGNED  NOT NULL DEFAULT 0,
    status          ENUM('disponivel', 'alugado', 'manutencao', 'inativo') NOT NULL DEFAULT 'disponivel',
    adquirido_em    DATE          NOT NULL,
    valor_compra    DECIMAL(10,2) NOT NULL,
    CONSTRAINT uq_veiculo_placa UNIQUE (placa),
    CONSTRAINT fk_veiculo_modelo FOREIGN KEY (modelo_id) REFERENCES modelo (id),
    CONSTRAINT fk_veiculo_filial FOREIGN KEY (filial_id) REFERENCES filial (id),
    CONSTRAINT ck_veiculo_placa CHECK (REGEXP_LIKE(placa, '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$', 'c')),
    INDEX ix_veiculo_status_filial (status, filial_id)
) COMMENT = 'Frota: cada carro físico, identificado pela placa';

CREATE TABLE cliente (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    cpf             CHAR(11)     NOT NULL COMMENT 'Somente números',
    email           VARCHAR(120) NOT NULL,
    telefone        VARCHAR(20)  NOT NULL,
    data_nascimento DATE         NOT NULL,
    cnh_numero      CHAR(11)     NOT NULL,
    cnh_validade    DATE         NOT NULL,
    cidade          VARCHAR(60)  NOT NULL,
    uf              CHAR(2)      NOT NULL,
    cadastrado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_cliente_cpf   UNIQUE (cpf),
    CONSTRAINT uq_cliente_email UNIQUE (email),
    CONSTRAINT uq_cliente_cnh   UNIQUE (cnh_numero),
    CONSTRAINT ck_cliente_cpf CHECK (REGEXP_LIKE(cpf, '^[0-9]{11}$'))
) COMMENT = 'Pessoas que alugam veículos';

CREATE TABLE adicional (
    id            TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome          VARCHAR(40)  NOT NULL,
    valor_diaria  DECIMAL(8,2) NOT NULL,
    CONSTRAINT uq_adicional_nome UNIQUE (nome),
    CONSTRAINT ck_adicional_valor CHECK (valor_diaria >= 0)
) COMMENT = 'Itens opcionais cobrados por dia (GPS, cadeirinha, seguro...)';

-- ---------------------------------------------------------------------
-- Movimento
-- ---------------------------------------------------------------------

CREATE TABLE reserva (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cliente_id          INT UNSIGNED      NOT NULL,
    categoria_id        TINYINT UNSIGNED  NOT NULL COMMENT 'Reserva-se a categoria, não o carro',
    filial_id           SMALLINT UNSIGNED NOT NULL,
    retirada_prevista   DATETIME          NOT NULL,
    devolucao_prevista  DATETIME          NOT NULL,
    status              ENUM('pendente', 'confirmada', 'cancelada', 'convertida') NOT NULL DEFAULT 'pendente',
    criada_em           DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reserva_cliente   FOREIGN KEY (cliente_id)   REFERENCES cliente (id),
    CONSTRAINT fk_reserva_categoria FOREIGN KEY (categoria_id) REFERENCES categoria (id),
    CONSTRAINT fk_reserva_filial    FOREIGN KEY (filial_id)    REFERENCES filial (id),
    CONSTRAINT ck_reserva_periodo CHECK (devolucao_prevista > retirada_prevista),
    INDEX ix_reserva_retirada (retirada_prevista)
) COMMENT = 'Pedido antecipado de uma categoria para um período';

CREATE TABLE locacao (
    id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    reserva_id           INT UNSIGNED      NULL,
    cliente_id           INT UNSIGNED      NOT NULL,
    veiculo_id           INT UNSIGNED      NOT NULL,
    funcionario_id       INT UNSIGNED      NOT NULL COMMENT 'Quem entregou o carro',
    filial_retirada_id   SMALLINT UNSIGNED NOT NULL,
    filial_devolucao_id  SMALLINT UNSIGNED NULL,
    retirada_em          DATETIME          NOT NULL,
    devolucao_prevista   DATETIME          NOT NULL,
    devolvido_em         DATETIME          NULL,
    km_retirada          INT UNSIGNED      NOT NULL,
    km_devolucao         INT UNSIGNED      NULL,
    valor_diaria         DECIMAL(8,2)      NOT NULL COMMENT 'Diária congelada no momento da retirada',
    valor_total          DECIMAL(10,2)     NULL     COMMENT 'Calculado no encerramento',
    status               ENUM('aberta', 'encerrada', 'cancelada') NOT NULL DEFAULT 'aberta',
    CONSTRAINT uq_locacao_reserva UNIQUE (reserva_id),
    CONSTRAINT fk_locacao_reserva     FOREIGN KEY (reserva_id)          REFERENCES reserva (id),
    CONSTRAINT fk_locacao_cliente     FOREIGN KEY (cliente_id)          REFERENCES cliente (id),
    CONSTRAINT fk_locacao_veiculo     FOREIGN KEY (veiculo_id)          REFERENCES veiculo (id),
    CONSTRAINT fk_locacao_funcionario FOREIGN KEY (funcionario_id)      REFERENCES funcionario (id),
    CONSTRAINT fk_locacao_filial_ret  FOREIGN KEY (filial_retirada_id)  REFERENCES filial (id),
    CONSTRAINT fk_locacao_filial_dev  FOREIGN KEY (filial_devolucao_id) REFERENCES filial (id),
    CONSTRAINT ck_locacao_previsao CHECK (devolucao_prevista > retirada_em),
    CONSTRAINT ck_locacao_devolucao CHECK (devolvido_em IS NULL OR devolvido_em >= retirada_em),
    CONSTRAINT ck_locacao_km CHECK (km_devolucao IS NULL OR km_devolucao >= km_retirada),
    CONSTRAINT ck_locacao_encerrada CHECK (
        status <> 'encerrada'
        OR (devolvido_em IS NOT NULL AND km_devolucao IS NOT NULL AND valor_total IS NOT NULL)
    ),
    INDEX ix_locacao_retirada (retirada_em),
    INDEX ix_locacao_status (status, devolucao_prevista)
) COMMENT = 'Contrato de aluguel: um cliente, um carro, um período';

CREATE TABLE locacao_adicional (
    locacao_id    INT UNSIGNED     NOT NULL,
    adicional_id  TINYINT UNSIGNED NOT NULL,
    quantidade    TINYINT UNSIGNED NOT NULL DEFAULT 1,
    valor_diaria  DECIMAL(8,2)     NOT NULL COMMENT 'Valor congelado na contratação',
    PRIMARY KEY (locacao_id, adicional_id),
    CONSTRAINT fk_la_locacao   FOREIGN KEY (locacao_id)   REFERENCES locacao (id) ON DELETE CASCADE,
    CONSTRAINT fk_la_adicional FOREIGN KEY (adicional_id) REFERENCES adicional (id),
    CONSTRAINT ck_la_quantidade CHECK (quantidade BETWEEN 1 AND 5)
) COMMENT = 'Adicionais contratados em cada locação (N:N)';

CREATE TABLE pagamento (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    locacao_id  INT UNSIGNED  NOT NULL,
    valor       DECIMAL(10,2) NOT NULL,
    forma       ENUM('pix', 'credito', 'debito', 'dinheiro') NOT NULL,
    pago_em     DATETIME      NOT NULL,
    CONSTRAINT fk_pagamento_locacao FOREIGN KEY (locacao_id) REFERENCES locacao (id),
    CONSTRAINT ck_pagamento_valor CHECK (valor > 0),
    INDEX ix_pagamento_data (pago_em)
) COMMENT = 'Pagamentos recebidos; uma locação pode ser paga em mais de uma parte';

CREATE TABLE manutencao (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    veiculo_id  INT UNSIGNED  NOT NULL,
    tipo        ENUM('revisao', 'preventiva', 'corretiva', 'sinistro') NOT NULL,
    descricao   VARCHAR(200)  NOT NULL,
    inicio      DATE          NOT NULL,
    fim         DATE          NULL COMMENT 'NULL = carro ainda na oficina',
    custo       DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_manutencao_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculo (id),
    CONSTRAINT ck_manutencao_periodo CHECK (fim IS NULL OR fim >= inicio),
    CONSTRAINT ck_manutencao_custo CHECK (custo >= 0)
) COMMENT = 'Passagens dos veículos pela oficina';

-- Auditoria: preenchida por trigger sempre que o status de um veículo muda
CREATE TABLE log_status_veiculo (
    id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    veiculo_id       INT UNSIGNED NOT NULL,
    status_anterior  VARCHAR(20)  NOT NULL,
    status_novo      VARCHAR(20)  NOT NULL,
    alterado_em      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd       VARCHAR(100) NOT NULL,
    CONSTRAINT fk_log_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculo (id)
) COMMENT = 'Histórico de mudanças de status da frota (auditoria)';
