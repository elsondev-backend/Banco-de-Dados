"""
Gera o arquivo sql/02_dados.sql com dados fictícios, mas coerentes, para o
banco welcar_locacoes.

A ideia é simular a operação real da locadora dia a dia: cada carro alterna
entre ficar parado, ser alugado e ir para a oficina, sem nunca ter duas
locações ao mesmo tempo, com a quilometragem sempre subindo e com os valores
calculados pela mesma regra da função fn_valor_locacao do banco.

Uso:  python gerador/gerar_dados.py              (simula até 20/10/2026 18:00)
      python gerador/gerar_dados.py 2027-03-15   (simula até a data informada)
Usa só a biblioteca padrão; a semente fixa faz o resultado ser sempre igual.
"""

import random
import sys
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from math import ceil
from pathlib import Path

SEMENTE = 2026
AGORA = (datetime.fromisoformat(sys.argv[1]).replace(hour=18) if len(sys.argv) > 1
         else datetime(2026, 10, 20, 18, 0))   # "hoje" na simulação
INICIO_OPERACAO = date(2025, 1, 2)
TAXA_RETORNO_OUTRA_FILIAL = Decimal("150.00")
ACRESCIMO_ATRASO = Decimal("1.20")
SAIDA = Path(__file__).resolve().parent.parent / "sql" / "02_dados.sql"

rnd = random.Random(SEMENTE)

# ---------------------------------------------------------------------------
# Cadastros fixos
# ---------------------------------------------------------------------------

FILIAIS = [
    ("Salvador - Aeroporto", "Salvador", "BA", "(71) 3204-1000"),
    ("Salvador - Pituba", "Salvador", "BA", "(71) 3204-2000"),
    ("Salvador - Comércio", "Salvador", "BA", "(71) 3204-3000"),
    ("Lauro de Freitas", "Lauro de Freitas", "BA", "(71) 3369-4000"),
    ("Feira de Santana", "Feira de Santana", "BA", "(75) 3221-5000"),
]
# peso de movimento de cada filial (o aeroporto aluga mais)
PESO_FILIAL = [0.32, 0.22, 0.14, 0.17, 0.15]

CATEGORIAS = [
    ("Econômico", "Carros de entrada, ideais para a cidade", "119.90"),
    ("Compacto", "Hatches com ar, direção e multimídia", "149.90"),
    ("Sedã", "Porta-malas grande para viagens em família", "189.90"),
    ("SUV", "Mais espaço e altura, bom para estrada", "249.90"),
    ("Executivo", "Conforto e câmbio automático", "389.90"),
    ("Utilitário", "Picapes e furgões para carga", "219.90"),
]

# (categoria, marca, nome, combustível, câmbio, lugares, preço de compra)
MODELOS = [
    (1, "Fiat", "Mobi", "flex", "manual", 5, 72000),
    (1, "Renault", "Kwid", "flex", "manual", 5, 70000),
    (2, "Hyundai", "HB20", "flex", "manual", 5, 88000),
    (2, "Chevrolet", "Onix", "flex", "manual", 5, 90000),
    (2, "Volkswagen", "Polo", "flex", "manual", 5, 92000),
    (2, "Fiat", "Argo", "flex", "manual", 5, 86000),
    (3, "Chevrolet", "Onix Plus", "flex", "automatico", 5, 110000),
    (3, "Volkswagen", "Virtus", "flex", "automatico", 5, 118000),
    (3, "Hyundai", "HB20S", "flex", "automatico", 5, 108000),
    (4, "Hyundai", "Creta", "flex", "automatico", 5, 150000),
    (4, "Volkswagen", "T-Cross", "flex", "automatico", 5, 148000),
    (4, "Jeep", "Renegade", "flex", "automatico", 5, 140000),
    (4, "Fiat", "Pulse", "flex", "automatico", 5, 120000),
    (5, "Toyota", "Corolla", "hibrido", "automatico", 5, 190000),
    (5, "Jeep", "Compass", "diesel", "automatico", 5, 220000),
    (5, "BYD", "Song Plus", "hibrido", "automatico", 5, 230000),
    (6, "Fiat", "Strada", "flex", "manual", 2, 105000),
    (6, "Fiat", "Toro", "diesel", "automatico", 5, 170000),
]
# quantos carros de cada categoria a frota tem
FROTA_POR_CATEGORIA = {1: 10, 2: 14, 3: 8, 4: 10, 5: 5, 6: 5}
# procura relativa por categoria
PESO_CATEGORIA = {1: 1.2, 2: 1.0, 3: 0.8, 4: 0.9, 5: 0.6, 6: 0.5}

ADICIONAIS = [
    ("GPS", "15.00"),
    ("Cadeirinha infantil", "20.00"),
    ("Condutor adicional", "25.00"),
    ("Proteção total", "45.00"),
    ("Wi-Fi 4G", "12.00"),
]
PESO_ADICIONAL = {1: 15, 2: 14, 3: 22, 4: 38, 5: 11}

CORES = ["Branco", "Prata", "Preto", "Cinza", "Vermelho", "Azul"]

PRIMEIROS_NOMES = """Ana Bruno Carla Daniel Eduarda Felipe Gabriela Henrique Isabela João Juliana
Lucas Larissa Marcos Mariana Nathan Patrícia Pedro Rafaela Rodrigo Sabrina Tiago Vanessa Vinícius
Yasmin Alice Arthur Beatriz Caio Camila Diego Elaine Fábio Fernanda Gustavo Helena Igor Jéssica
Leonardo Letícia Matheus Natália Otávio Paula Renato Sara Thiago Úrsula Victor Wesley Aline André
Bianca Cláudio Débora Emerson Flávia Gilberto Ingrid Jorge Karina Luana Márcio Nívea Priscila
Ricardo Simone Tatiane Ulisses Valéria William Antônio Cristiane Edson Joana Raimundo Sônia""".split()

SOBRENOMES = """Silva Santos Oliveira Souza Lima Pereira Costa Ferreira Rodrigues Almeida
Nascimento Carvalho Araújo Ribeiro Gomes Barbosa Rocha Dias Teixeira Moreira Cardoso Mendes
Nunes Freitas Lopes Pinto Ramos Cruz Batista Moura Reis Campos Andrade Sena Bonfim Conceição
Evangelista Menezes Brito Matos Machado Vieira""".split()

CIDADES_CLIENTES = [
    ("Salvador", "BA", 45), ("Lauro de Freitas", "BA", 8), ("Feira de Santana", "BA", 10),
    ("Camaçari", "BA", 5), ("São Paulo", "SP", 9), ("Rio de Janeiro", "RJ", 6),
    ("Belo Horizonte", "MG", 4), ("Recife", "PE", 4), ("Brasília", "DF", 4),
    ("Aracaju", "SE", 3), ("Curitiba", "PR", 2),
]

DESCRICOES_CORRETIVA = [
    "Troca de pastilhas de freio", "Troca de bateria", "Reparo no ar-condicionado",
    "Troca de pneus", "Alinhamento e balanceamento", "Reparo na suspensão",
    "Troca de embreagem", "Reparo elétrico", "Funilaria de para-choque",
]

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------


def dinheiro(valor):
    return Decimal(valor).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def dias_cobrados(inicio, fim):
    """Mesma regra de fn_dias_cobrados: diárias de 24h, 1h de tolerância, mínimo 1."""
    minutos = (fim - inicio).total_seconds() / 60
    return max(1, ceil((minutos - 60) / 1440))


def valor_locacao(diaria, adicionais_dia, retirada, prevista, devolvido, outra_filial):
    """Mesma regra de fn_valor_locacao (ver 03_funcoes_procedures.sql)."""
    d_prev = dias_cobrados(retirada, prevista)
    d_real = dias_cobrados(retirada, devolvido)
    normais = min(d_real, d_prev)
    extras = max(d_real - d_prev, 0)
    total = normais * (diaria + adicionais_dia)
    total += extras * (dinheiro(diaria * ACRESCIMO_ATRASO) + adicionais_dia)
    if outra_filial:
        total += TAXA_RETORNO_OUTRA_FILIAL
    return dinheiro(total)


def gerar_cpf():
    base = [rnd.randint(0, 9) for _ in range(9)]
    for tamanho in (9, 10):
        soma = sum(d * p for d, p in zip(base, range(tamanho + 1, 1, -1)))
        resto = (soma * 10) % 11
        base.append(0 if resto == 10 else resto)
    return "".join(map(str, base))


def gerar_placa(usadas):
    letras = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    while True:
        placa = (
            "".join(rnd.choice(letras) for _ in range(3))
            + str(rnd.randint(0, 9))
            + rnd.choice(letras)
            + f"{rnd.randint(0, 99):02d}"
        )
        if placa not in usadas:
            usadas.add(placa)
            return placa


def sem_acento(texto):
    trocas = str.maketrans("áàâãéêíóôõúüçÁÉÍÓÚÂÊÔÃÕÇ", "aaaaeeiooouucAEIOUAEOAOC")
    return texto.translate(trocas)


def sql(valor):
    if valor is None:
        return "NULL"
    if isinstance(valor, bool):
        return "TRUE" if valor else "FALSE"
    if isinstance(valor, (int, Decimal)):
        return str(valor)
    if isinstance(valor, datetime):
        return f"'{valor:%Y-%m-%d %H:%M:%S}'"
    if isinstance(valor, date):
        return f"'{valor:%Y-%m-%d}'"
    return "'" + str(valor).replace("'", "''") + "'"


def fator_sazonal(dia):
    """Procura maior no verão/carnaval, julho e fim de ano."""
    return {1: 1.45, 2: 1.5, 3: 1.0, 4: 0.85, 5: 0.8, 6: 0.95,
            7: 1.3, 8: 0.85, 9: 0.85, 10: 0.95, 11: 1.0, 12: 1.45}[dia.month]


def hora_comercial(dia):
    return datetime(dia.year, dia.month, dia.day, rnd.randint(7, 19), rnd.choice((0, 15, 30, 45)))


# ---------------------------------------------------------------------------
# Geração
# ---------------------------------------------------------------------------

def gerar():
    tabelas = {nome: [] for nome in (
        "filial", "funcionario", "categoria", "modelo", "veiculo", "cliente", "adicional",
        "reserva", "locacao", "locacao_adicional", "pagamento", "manutencao")}

    for f in FILIAIS:
        tabelas["filial"].append(f)
    for c in CATEGORIAS:
        tabelas["categoria"].append(c)
    for m in MODELOS:
        tabelas["modelo"].append(m[:6])
    for a in ADICIONAIS:
        tabelas["adicional"].append(a)
    adicional_valor = {i + 1: Decimal(v) for i, (_, v) in enumerate(ADICIONAIS)}
    diaria_categoria = {i + 1: Decimal(c[2]) for i, c in enumerate(CATEGORIAS)}

    # Funcionários: 1 gerente, 2 atendentes e 1 mecânico por filial
    atendentes = {}
    for filial_id in range(1, len(FILIAIS) + 1):
        for cargo in ("gerente", "atendente", "atendente", "mecanico"):
            nome = f"{rnd.choice(PRIMEIROS_NOMES)} {rnd.choice(SOBRENOMES)}"
            admitido = INICIO_OPERACAO - timedelta(days=rnd.randint(0, 900))
            tabelas["funcionario"].append((filial_id, nome, cargo, admitido))
            if cargo == "atendente":
                atendentes.setdefault(filial_id, []).append(len(tabelas["funcionario"]))

    # Clientes
    clientes = []
    usados = {"cpf": set(), "email": set(), "cnh": set()}
    cidades = [c[:2] for c in CIDADES_CLIENTES]
    pesos_cidades = [c[2] for c in CIDADES_CLIENTES]
    for i in range(420):
        nome = f"{rnd.choice(PRIMEIROS_NOMES)} {rnd.choice(SOBRENOMES)} {rnd.choice(SOBRENOMES)}"
        cpf = gerar_cpf()
        while cpf in usados["cpf"]:
            cpf = gerar_cpf()
        usados["cpf"].add(cpf)
        base_email = sem_acento(nome.lower()).replace(" ", ".")
        email = f"{base_email}@email.com"
        n = 2
        while email in usados["email"]:
            email = f"{base_email}{n}@email.com"
            n += 1
        usados["email"].add(email)
        cnh = str(rnd.randint(10**10, 10**11 - 1))
        while cnh in usados["cnh"]:
            cnh = str(rnd.randint(10**10, 10**11 - 1))
        usados["cnh"].add(cnh)
        nascimento = date(rnd.randint(1958, 2004), rnd.randint(1, 12), rnd.randint(1, 28))
        cadastro = hora_comercial(INICIO_OPERACAO + timedelta(days=rnd.randint(-60, 620)))
        # ~4% com CNH que venceu em 2026 (para testar a validação da procedure)
        if rnd.random() < 0.04:
            validade = date(2026, rnd.randint(1, 9), rnd.randint(1, 28))
        else:
            validade = date(rnd.randint(2027, 2035), rnd.randint(1, 12), rnd.randint(1, 28))
        cidade, uf = rnd.choices(cidades, pesos_cidades)[0]
        ddd = {"BA": "71", "SP": "11", "RJ": "21", "MG": "31", "PE": "81", "DF": "61",
               "SE": "79", "PR": "41"}[uf]
        telefone = f"({ddd}) 9{rnd.randint(8000, 9999)}-{rnd.randint(0, 9999):04d}"
        # alguns clientes alugam muito mais que outros (distribuição de Pareto)
        peso = min(rnd.paretovariate(2.0), 8.0)
        clientes.append({
            "id": i + 1, "nascimento": nascimento, "cadastro": cadastro,
            "validade": validade, "peso": peso,
        })
        tabelas["cliente"].append((nome, cpf, email, telefone, nascimento, cnh, validade,
                                   cidade, uf, cadastro))

    def sortear_cliente(quando):
        candidatos = [c for c in clientes
                      if c["cadastro"] <= quando
                      and c["validade"] > quando.date()
                      and (quando.date() - c["nascimento"]).days >= 21 * 365]
        return rnd.choices(candidatos, [c["peso"] for c in candidatos])[0]["id"]

    # Frota
    placas = set()
    veiculos = []
    modelos_por_categoria = {}
    for idx, m in enumerate(MODELOS, start=1):
        modelos_por_categoria.setdefault(m[0], []).append((idx, m))
    for categoria_id, qtd in FROTA_POR_CATEGORIA.items():
        for _ in range(qtd):
            modelo_id, m = rnd.choice(modelos_por_categoria[categoria_id])
            filial_id = rnd.choices(range(1, 6), PESO_FILIAL)[0]
            adquirido = INICIO_OPERACAO + timedelta(days=rnd.choice((0, 0, 0, 30, 90, 180, 300, 420)))
            ano = adquirido.year if adquirido.month < 7 else adquirido.year + 1
            valor = dinheiro(m[6] * rnd.uniform(0.9, 1.0))
            veiculos.append({
                "id": len(veiculos) + 1, "modelo_id": modelo_id, "categoria_id": categoria_id,
                "filial_id": filial_id, "placa": gerar_placa(placas), "ano": ano,
                "cor": rnd.choice(CORES), "km": rnd.randint(0, 40), "adquirido": adquirido,
                "valor": valor, "status": "disponivel", "proxima_revisao": 10000,
            })
    rnd.shuffle(veiculos)
    for novo_id, v in enumerate(veiculos, start=1):
        v["id"] = novo_id

    # Simulação de cada carro ao longo do tempo
    locacoes = []
    manutencoes = []
    for v in veiculos:
        momento = datetime.combine(v["adquirido"], datetime.min.time()) + timedelta(hours=9)
        # um carro antigo foi vendido em setembro/2026 (fica inativo)
        fim_vida = AGORA if v["id"] != 7 else datetime(2026, 9, 15, 10, 0)
        while True:
            # tempo parado no pátio até a próxima locação
            fator = fator_sazonal(momento) * PESO_CATEGORIA[v["categoria_id"]]
            momento += timedelta(hours=rnd.expovariate(fator / 40.0))
            retirada = hora_comercial(momento.date())
            if retirada < momento:
                retirada += timedelta(days=1)
            if retirada >= fim_vida:
                break

            # revisão a cada 10.000 km
            if v["km"] >= v["proxima_revisao"]:
                inicio = retirada.date()
                fim = inicio + timedelta(days=rnd.randint(1, 2))
                manutencoes.append((v["id"], "revisao", f"Revisão de {v['proxima_revisao']:,} km".replace(",", "."),
                                    inicio, fim if fim <= AGORA.date() else None,
                                    dinheiro(rnd.uniform(380, 950))))
                v["proxima_revisao"] += 10000
                if fim > AGORA.date():
                    v["status"] = "manutencao"
                    break
                momento = datetime.combine(fim, datetime.min.time()) + timedelta(hours=8)
                continue

            duracao_prevista = rnd.choices(
                [1, 2, 3, 4, 5, 7, 10, 15, 30], [14, 18, 16, 12, 12, 13, 7, 6, 2])[0]
            prevista = retirada + timedelta(days=duracao_prevista)
            sorteio = rnd.random()
            if sorteio < 0.10:      # devolveu antes
                devolvido = retirada + timedelta(hours=rnd.uniform(3, duracao_prevista * 24 - 2))
            elif sorteio < 0.22:    # devolveu atrasado
                devolvido = prevista + timedelta(hours=rnd.uniform(0.5, 52))
            else:                   # no horário (dentro da tolerância)
                devolvido = prevista + timedelta(minutes=rnd.randint(-120, 50))
            devolvido = devolvido.replace(second=0, microsecond=0)
            if devolvido <= retirada:
                devolvido = retirada + timedelta(hours=2)

            filial_ret = v["filial_id"]
            filial_dev = filial_ret if rnd.random() > 0.08 else rnd.choice(
                [f for f in range(1, 6) if f != filial_ret])
            aberta = devolvido > AGORA
            km_rodados = int((devolvido - retirada).total_seconds() / 86400 * rnd.uniform(60, 220)) + rnd.randint(5, 40)

            adicionais = []
            if rnd.random() < 0.4:
                quantos = rnd.choices([1, 2, 3], [6, 3, 1])[0]
                # sorteio ponderado sem repetição: proteção total é o mais pedido
                escolhidos = sorted(PESO_ADICIONAL, key=lambda a: rnd.random() ** (1 / PESO_ADICIONAL[a]),
                                    reverse=True)[:quantos]
                for adicional_id in escolhidos:
                    qtd = 2 if adicional_id == 2 and rnd.random() < 0.3 else 1
                    adicionais.append((adicional_id, qtd, adicional_valor[adicional_id]))
            adicionais_dia = sum((q * val for _, q, val in adicionais), Decimal("0"))
            diaria = diaria_categoria[v["categoria_id"]]

            loc = {
                "veiculo_id": v["id"], "categoria_id": v["categoria_id"],
                "cliente_id": sortear_cliente(retirada),
                "funcionario_id": rnd.choice(atendentes[filial_ret]),
                "filial_ret": filial_ret, "retirada": retirada, "prevista": prevista,
                "km_retirada": v["km"], "diaria": diaria, "adicionais": adicionais,
            }
            if aberta:
                loc.update(status="aberta", filial_dev=None, devolvido=None,
                           km_devolucao=None, total=None)
                v["status"] = "alugado"
                locacoes.append(loc)
                break

            loc.update(status="encerrada", filial_dev=filial_dev, devolvido=devolvido,
                       km_devolucao=v["km"] + km_rodados,
                       total=valor_locacao(diaria, adicionais_dia, retirada, prevista,
                                           devolvido, filial_dev != filial_ret))
            locacoes.append(loc)
            v["km"] += km_rodados
            v["filial_id"] = filial_dev
            momento = devolvido

            # eventual manutenção corretiva depois da devolução
            if rnd.random() < 0.035:
                inicio = devolvido.date() + timedelta(days=1)
                fim = inicio + timedelta(days=rnd.randint(1, 6))
                ainda_na_oficina = fim > AGORA.date()
                manutencoes.append((v["id"], "corretiva", rnd.choice(DESCRICOES_CORRETIVA), inicio,
                                    None if ainda_na_oficina else fim, dinheiro(rnd.uniform(250, 2800))))
                if ainda_na_oficina:
                    v["status"] = "manutencao"
                    break
                momento = datetime.combine(fim, datetime.min.time()) + timedelta(hours=8)
        if v["id"] == 7 and v["status"] == "disponivel":
            v["status"] = "inativo"

    # Ordena as locações pela data de retirada para que os ids sigam o tempo
    locacoes.sort(key=lambda l: l["retirada"])

    # Reservas: ~60% das locações nasceram de uma reserva
    reservas = []
    for loc in locacoes:
        if rnd.random() < 0.6:
            criada = loc["retirada"] - timedelta(days=rnd.randint(1, 30), hours=rnd.randint(0, 10))
            criada = max(criada, tabelas["cliente"][loc["cliente_id"] - 1][9])
            reservas.append({"cliente_id": loc["cliente_id"], "categoria_id": loc["categoria_id"],
                             "filial_id": loc["filial_ret"], "retirada": loc["retirada"],
                             "prevista": loc["prevista"], "status": "convertida",
                             "criada": criada, "locacao": loc})
    # reservas canceladas no passado e reservas futuras
    for _ in range(int(len(reservas) * 0.15)):
        quando = hora_comercial(INICIO_OPERACAO + timedelta(days=rnd.randint(10, 650)))
        if quando >= AGORA:
            continue
        cliente_id = sortear_cliente(quando)
        reservas.append({"cliente_id": cliente_id, "categoria_id": rnd.randint(1, 6),
                         "filial_id": rnd.choices(range(1, 6), PESO_FILIAL)[0],
                         "retirada": quando, "prevista": quando + timedelta(days=rnd.randint(1, 7)),
                         "status": "cancelada",
                         "criada": max(quando - timedelta(days=rnd.randint(1, 20)),
                                       tabelas["cliente"][cliente_id - 1][9]),
                         "locacao": None})
    for _ in range(28):
        quando = hora_comercial(AGORA.date() + timedelta(days=rnd.randint(1, 45)))
        cliente_id = sortear_cliente(AGORA)
        reservas.append({"cliente_id": cliente_id, "categoria_id": rnd.randint(1, 6),
                         "filial_id": rnd.choices(range(1, 6), PESO_FILIAL)[0],
                         "retirada": quando, "prevista": quando + timedelta(days=rnd.randint(1, 10)),
                         "status": rnd.choice(("pendente", "confirmada", "confirmada")),
                         "criada": AGORA - timedelta(days=rnd.randint(0, 20), hours=rnd.randint(0, 8)),
                         "locacao": None})
    reservas.sort(key=lambda r: r["criada"])
    for rid, r in enumerate(reservas, start=1):
        r["id"] = rid
        if r["locacao"]:
            r["locacao"]["reserva_id"] = rid
        tabelas["reserva"].append((r["cliente_id"], r["categoria_id"], r["filial_id"], r["retirada"],
                                   r["prevista"], r["status"], r["criada"]))

    # Locações, adicionais e pagamentos
    for lid, loc in enumerate(locacoes, start=1):
        tabelas["locacao"].append((
            loc.get("reserva_id"), loc["cliente_id"], loc["veiculo_id"], loc["funcionario_id"],
            loc["filial_ret"], loc["filial_dev"], loc["retirada"], loc["prevista"], loc["devolvido"],
            loc["km_retirada"], loc["km_devolucao"], loc["diaria"], loc["total"], loc["status"]))
        for adicional_id, qtd, valor in loc["adicionais"]:
            tabelas["locacao_adicional"].append((lid, adicional_id, qtd, valor))

        forma = rnd.choices(("pix", "credito", "debito", "dinheiro"), (40, 42, 12, 6))[0]
        if loc["status"] == "aberta":
            # caução/entrada paga na retirada
            entrada = dinheiro(loc["diaria"] * 2)
            tabelas["pagamento"].append((lid, entrada, forma, loc["retirada"] + timedelta(minutes=5)))
            continue
        total = loc["total"]
        if rnd.random() < 0.025:
            # inadimplência: pagou só uma parte
            tabelas["pagamento"].append((lid, dinheiro(total * Decimal("0.4")), forma,
                                         loc["retirada"] + timedelta(minutes=5)))
        elif rnd.random() < 0.3:
            entrada = min(dinheiro(loc["diaria"] * 2), total)
            tabelas["pagamento"].append((lid, entrada, forma, loc["retirada"] + timedelta(minutes=5)))
            if total - entrada > 0:
                tabelas["pagamento"].append((lid, total - entrada, rnd.choice(("pix", "credito")),
                                             loc["devolvido"] + timedelta(minutes=10)))
        else:
            tabelas["pagamento"].append((lid, total, forma, loc["devolvido"] + timedelta(minutes=10)))
    tabelas["pagamento"].sort(key=lambda p: p[3])

    tabelas["manutencao"] = sorted(manutencoes, key=lambda m: m[3])

    for v in veiculos:
        tabelas["veiculo"].append((v["modelo_id"], v["filial_id"], v["placa"], v["ano"], v["cor"],
                                   v["km"], v["status"], v["adquirido"], v["valor"]))
    return tabelas


COLUNAS = {
    "filial": "nome, cidade, uf, telefone",
    "funcionario": "filial_id, nome, cargo, admitido_em",
    "categoria": "nome, descricao, valor_diaria",
    "modelo": "categoria_id, marca, nome, combustivel, cambio, lugares",
    "veiculo": "modelo_id, filial_id, placa, ano, cor, km_atual, status, adquirido_em, valor_compra",
    "cliente": ("nome, cpf, email, telefone, data_nascimento, cnh_numero, cnh_validade, "
                "cidade, uf, cadastrado_em"),
    "adicional": "nome, valor_diaria",
    "reserva": "cliente_id, categoria_id, filial_id, retirada_prevista, devolucao_prevista, status, criada_em",
    "locacao": ("reserva_id, cliente_id, veiculo_id, funcionario_id, filial_retirada_id, "
                "filial_devolucao_id, retirada_em, devolucao_prevista, devolvido_em, km_retirada, "
                "km_devolucao, valor_diaria, valor_total, status"),
    "locacao_adicional": "locacao_id, adicional_id, quantidade, valor_diaria",
    "pagamento": "locacao_id, valor, forma, pago_em",
    "manutencao": "veiculo_id, tipo, descricao, inicio, fim, custo",
}


def escrever(tabelas):
    linhas = [
        "-- =====================================================================",
        "-- WelCar Locações - 02_dados.sql",
        "-- Dados fictícios gerados por gerador/gerar_dados.py (não edite à mão)",
        f"-- Data de referência da simulação: {AGORA:%d/%m/%Y %H:%M}",
        "-- =====================================================================",
        "",
        "SET NAMES utf8mb4;",
        "USE welcar_locacoes;",
        "SET FOREIGN_KEY_CHECKS = 0;",
        "",
    ]
    for tabela, colunas in COLUNAS.items():
        registros = tabelas[tabela]
        linhas.append(f"-- {tabela}: {len(registros)} registros")
        for i in range(0, len(registros), 500):
            bloco = registros[i:i + 500]
            valores = ",\n".join("(" + ", ".join(sql(v) for v in r) + ")" for r in bloco)
            linhas.append(f"INSERT INTO {tabela} ({colunas}) VALUES\n{valores};")
        linhas.append("")
    linhas.append("SET FOREIGN_KEY_CHECKS = 1;")
    SAIDA.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    for tabela in COLUNAS:
        print(f"{tabela:<18} {len(tabelas[tabela]):>6}")
    print(f"Arquivo gerado: {SAIDA}")


if __name__ == "__main__":
    escrever(gerar())
