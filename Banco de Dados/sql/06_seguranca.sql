-- =====================================================================
-- WelCar Locações - 06_seguranca.sql
-- Perfis de acesso (roles) seguindo o princípio do menor privilégio.
-- As senhas abaixo são só de exemplo: troque antes de usar de verdade.
-- =====================================================================

USE welcar_locacoes;

DROP ROLE IF EXISTS 'welcar_atendente', 'welcar_analista', 'welcar_gerente';
CREATE ROLE 'welcar_atendente', 'welcar_analista', 'welcar_gerente';

-- Atendente: consulta cadastros e opera locações SÓ pelas procedures
-- (não consegue dar UPDATE direto em locação nem mexer em valores)
GRANT SELECT ON welcar_locacoes.cliente      TO 'welcar_atendente';
GRANT INSERT, UPDATE ON welcar_locacoes.cliente TO 'welcar_atendente';
GRANT SELECT ON welcar_locacoes.vw_frota            TO 'welcar_atendente';
GRANT SELECT ON welcar_locacoes.vw_disponibilidade  TO 'welcar_atendente';
GRANT SELECT ON welcar_locacoes.vw_locacoes_abertas TO 'welcar_atendente';
GRANT SELECT, INSERT ON welcar_locacoes.reserva     TO 'welcar_atendente';
GRANT INSERT ON welcar_locacoes.pagamento           TO 'welcar_atendente';
GRANT EXECUTE ON PROCEDURE welcar_locacoes.sp_abrir_locacao       TO 'welcar_atendente';
GRANT EXECUTE ON PROCEDURE welcar_locacoes.sp_adicionar_adicional TO 'welcar_atendente';
GRANT EXECUTE ON PROCEDURE welcar_locacoes.sp_encerrar_locacao    TO 'welcar_atendente';

-- Analista de dados: somente leitura, sem ver CPF/CNH (usa as views)
GRANT SELECT ON welcar_locacoes.vw_faturamento_mensal TO 'welcar_analista';
GRANT SELECT ON welcar_locacoes.vw_resultado_veiculo  TO 'welcar_analista';
GRANT SELECT ON welcar_locacoes.vw_disponibilidade    TO 'welcar_analista';
GRANT SELECT ON welcar_locacoes.vw_frota              TO 'welcar_analista';
GRANT EXECUTE ON PROCEDURE welcar_locacoes.sp_faturamento_periodo TO 'welcar_analista';

-- Gerente: tudo do atendente + leitura completa e cadastro da frota
GRANT 'welcar_atendente', 'welcar_analista' TO 'welcar_gerente';
GRANT SELECT ON welcar_locacoes.* TO 'welcar_gerente';
GRANT INSERT, UPDATE ON welcar_locacoes.veiculo    TO 'welcar_gerente';
GRANT INSERT, UPDATE ON welcar_locacoes.manutencao TO 'welcar_gerente';

-- Usuários de exemplo
DROP USER IF EXISTS 'atendente_pituba'@'%', 'analista_bi'@'%';
CREATE USER 'atendente_pituba'@'%' IDENTIFIED BY 'Troque#Esta#Senha1' DEFAULT ROLE 'welcar_atendente';
CREATE USER 'analista_bi'@'%'      IDENTIFIED BY 'Troque#Esta#Senha2' DEFAULT ROLE 'welcar_analista';
