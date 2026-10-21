"""
Testes automatizados das regras de negócio que ficam dentro do banco
(procedures, funções e triggers).

Pré-requisito: banco criado e rodando (docker compose up -d).
Uso:  python -m unittest discover -s testes -v

Atenção: os testes criam um cliente de teste e abrem/encerram locações
reais no banco. Para voltar ao estado original: docker compose down -v
e depois docker compose up -d.
"""

import os
import unittest
import uuid
from decimal import Decimal

import mysql.connector
from mysql.connector import errors


def conectar():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", "welcar123"),
        database="welcar_locacoes",
        autocommit=True,
    )


class TestRegrasDoBanco(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.con = conectar()
        cls.cur = cls.con.cursor(dictionary=True)
        cls.cur_proc = cls.con.cursor()   # callproc devolve os parâmetros OUT numa tupla
        # Cliente novo, maior de idade e com CNH válida, só para os testes
        sufixo = uuid.uuid4().hex[:8]
        cls.cur.execute(
            """INSERT INTO cliente (nome, cpf, email, telefone, data_nascimento, cnh_numero,
                                    cnh_validade, cidade, uf)
               VALUES ('Cliente de Teste', %s, %s, '(71) 90000-0000', '1990-05-10', %s,
                       CURDATE() + INTERVAL 5 YEAR, 'Salvador', 'BA')""",
            (str(int(sufixo, 16))[:11].rjust(11, "1"), f"teste.{sufixo}@email.com",
             str(int(sufixo, 16) + 1)[:11].rjust(11, "2")),
        )
        cls.cliente_id = cls.cur.lastrowid

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    # -- utilidades ---------------------------------------------------------

    def um(self, sql, params=()):
        self.cur.execute(sql, params)
        linha = self.cur.fetchone()
        self.cur.fetchall()
        return linha

    def carro_disponivel(self):
        return self.um(
            """SELECT v.id, v.filial_id, v.km_atual,
                      (SELECT id FROM funcionario
                        WHERE filial_id = v.filial_id AND cargo = 'atendente' LIMIT 1) AS atendente
                 FROM veiculo v WHERE v.status = 'disponivel' ORDER BY v.id LIMIT 1""")

    def abrir(self, cliente_id, veiculo_id, funcionario_id, dias=3, reserva_id=None):
        resultado = self.cur_proc.callproc(
            "sp_abrir_locacao", (cliente_id, veiculo_id, funcionario_id, dias, reserva_id, 0))
        return resultado[5]

    def encerrar(self, locacao_id, km, filial_id):
        resultado = self.cur_proc.callproc("sp_encerrar_locacao", (locacao_id, km, filial_id, 0))
        return Decimal(resultado[3])

    def assertErroDoBanco(self, trecho_mensagem, funcao, *args):
        with self.assertRaises(errors.DatabaseError) as ctx:
            funcao(*args)
        self.assertIn(trecho_mensagem, ctx.exception.msg)

    # -- testes -------------------------------------------------------------

    def test_dias_cobrados_respeita_tolerancia_de_uma_hora(self):
        casos = [
            ("2026-01-01 10:00", "2026-01-01 12:00", 1),   # poucas horas = 1 diária
            ("2026-01-01 10:00", "2026-01-02 10:59", 1),   # dentro da tolerância
            ("2026-01-01 10:00", "2026-01-02 11:01", 2),   # passou da tolerância
            ("2026-01-01 10:00", "2026-01-08 10:00", 7),
        ]
        for inicio, fim, esperado in casos:
            with self.subTest(inicio=inicio, fim=fim):
                linha = self.um("SELECT fn_dias_cobrados(%s, %s) AS dias", (inicio, fim))
                self.assertEqual(linha["dias"], esperado)

    def test_valores_do_historico_batem_com_a_funcao(self):
        linha = self.um(
            """SELECT COUNT(*) AS divergentes FROM locacao
                WHERE status = 'encerrada'
                  AND valor_total <> fn_valor_locacao(id, devolvido_em, filial_devolucao_id)""")
        self.assertEqual(linha["divergentes"], 0)

    def test_fluxo_completo_abrir_e_encerrar(self):
        carro = self.carro_disponivel()
        locacao_id = self.abrir(self.cliente_id, carro["id"], carro["atendente"], 2)
        self.cur_proc.callproc("sp_adicionar_adicional", (locacao_id, 1, 1))   # GPS

        self.assertEqual(self.um("SELECT status FROM veiculo WHERE id = %s", (carro["id"],))["status"],
                         "alugado")

        total = self.encerrar(locacao_id, carro["km_atual"] + 120, carro["filial_id"])
        # devolveu na hora: 1 diária de carro + 1 de GPS
        diaria = self.um("SELECT valor_diaria FROM locacao WHERE id = %s", (locacao_id,))["valor_diaria"]
        self.assertEqual(total, diaria + Decimal("15.00"))

        veiculo = self.um("SELECT status, km_atual FROM veiculo WHERE id = %s", (carro["id"],))
        self.assertEqual(veiculo["status"], "disponivel")
        self.assertEqual(veiculo["km_atual"], carro["km_atual"] + 120)

        log = self.um("""SELECT COUNT(*) AS n FROM log_status_veiculo
                          WHERE veiculo_id = %s AND alterado_em >= NOW() - INTERVAL 1 MINUTE""",
                      (carro["id"],))
        self.assertGreaterEqual(log["n"], 2)   # disponivel->alugado e alugado->disponivel

    def test_devolucao_em_outra_filial_cobra_taxa(self):
        carro = self.carro_disponivel()
        outra = 1 if carro["filial_id"] != 1 else 2
        locacao_id = self.abrir(self.cliente_id, carro["id"], carro["atendente"], 1)
        total = self.encerrar(locacao_id, carro["km_atual"] + 50, outra)
        diaria = self.um("SELECT valor_diaria FROM locacao WHERE id = %s", (locacao_id,))["valor_diaria"]
        self.assertEqual(total, diaria + Decimal("150.00"))

    def test_nao_aluga_carro_ja_alugado(self):
        alugado = self.um(
            """SELECT v.id, (SELECT id FROM funcionario WHERE filial_id = v.filial_id
                               AND cargo = 'atendente' LIMIT 1) AS atendente
                 FROM veiculo v WHERE v.status = 'alugado' LIMIT 1""")
        self.assertErroDoBanco("não está disponível", self.abrir,
                               self.cliente_id, alugado["id"], alugado["atendente"])

    def test_nao_aluga_para_cnh_vencida(self):
        cliente = self.um("SELECT id FROM cliente WHERE cnh_validade < CURDATE() LIMIT 1")
        carro = self.carro_disponivel()
        self.assertErroDoBanco("CNH vencida", self.abrir, cliente["id"], carro["id"], carro["atendente"])

    def test_funcionario_de_outra_filial_nao_registra(self):
        carro = self.carro_disponivel()
        de_fora = self.um("SELECT id FROM funcionario WHERE filial_id <> %s AND cargo = 'atendente' LIMIT 1",
                          (carro["filial_id"],))
        self.assertErroDoBanco("não pode registrar", self.abrir, self.cliente_id, carro["id"], de_fora["id"])

    def test_erro_no_meio_desfaz_tudo(self):
        # reserva de outro cliente: a procedure falha e nada pode ter sido gravado
        reserva = self.um("SELECT id FROM reserva WHERE status = 'confirmada' AND cliente_id <> %s LIMIT 1",
                          (self.cliente_id,))
        carro = self.carro_disponivel()
        antes = self.um("SELECT COUNT(*) AS n FROM locacao")["n"]
        self.assertErroDoBanco("não pertence", self.abrir, self.cliente_id, carro["id"],
                               carro["atendente"], 2, reserva["id"])
        self.assertEqual(self.um("SELECT COUNT(*) AS n FROM locacao")["n"], antes)
        self.assertEqual(self.um("SELECT status FROM veiculo WHERE id = %s", (carro["id"],))["status"],
                         "disponivel")

    def test_km_nao_pode_diminuir(self):
        carro = self.carro_disponivel()
        self.assertErroDoBanco("não pode diminuir", self.cur.execute,
                               "UPDATE veiculo SET km_atual = km_atual - 1 WHERE id = %s", (carro["id"],))

    def test_manutencao_muda_status_do_carro(self):
        carro = self.carro_disponivel()
        self.cur.execute("""INSERT INTO manutencao (veiculo_id, tipo, descricao, inicio, custo)
                            VALUES (%s, 'corretiva', 'Teste automatizado', CURDATE(), 100)""",
                         (carro["id"],))
        manutencao_id = self.cur.lastrowid
        self.assertEqual(self.um("SELECT status FROM veiculo WHERE id = %s", (carro["id"],))["status"],
                         "manutencao")
        self.cur.execute("UPDATE manutencao SET fim = CURDATE() WHERE id = %s", (manutencao_id,))
        self.assertEqual(self.um("SELECT status FROM veiculo WHERE id = %s", (carro["id"],))["status"],
                         "disponivel")

    def test_pagamento_acima_do_devido_e_recusado(self):
        locacao = self.um("""SELECT locacao_id, saldo_devedor FROM vw_saldo_locacao
                              WHERE saldo_devedor = 0 LIMIT 1""")
        self.assertErroDoBanco("maior que o saldo", self.cur.execute,
                               "INSERT INTO pagamento (locacao_id, valor, forma, pago_em) VALUES (%s, 10, 'pix', NOW())",
                               (locacao["locacao_id"],))


if __name__ == "__main__":
    unittest.main(verbosity=2)
