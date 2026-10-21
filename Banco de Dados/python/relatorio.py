"""
Relatório gerencial da WelCar Locações.

Lê as views do banco, salva os resultados em CSV (para abrir no Excel ou
carregar num Power BI) e gera dois gráficos em PNG.

Uso:  python python/relatorio.py
Saída: pasta docs/ (gráficos) e python/saida/ (CSVs)
"""

import csv
import os
from pathlib import Path

import matplotlib
import mysql.connector

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
PASTA_CSV = RAIZ / "python" / "saida"
PASTA_GRAFICOS = RAIZ / "docs"

AZUL = "#2a78d6"
TEXTO = "#52514e"
GRADE = "#e4e3df"
FUNDO = "#fcfcfb"

CONSULTAS = {
    "faturamento_mensal": """
        SELECT mes, SUM(locacoes) AS locacoes, SUM(receita) AS receita
        FROM vw_faturamento_mensal GROUP BY mes ORDER BY mes""",
    "faturamento_por_filial": """
        SELECT filial, SUM(locacoes) AS locacoes, SUM(receita) AS receita,
               ROUND(SUM(receita) / SUM(locacoes), 2) AS ticket_medio
        FROM vw_faturamento_mensal GROUP BY filial ORDER BY receita DESC""",
    "resultado_por_veiculo": """
        SELECT placa, modelo, categoria, receita, custo_manutencao, retorno_pct
        FROM vw_resultado_veiculo ORDER BY retorno_pct DESC""",
    "disponibilidade_agora": "SELECT * FROM vw_disponibilidade ORDER BY filial, categoria",
}


def conectar():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", "welcar123"),
        database="welcar_locacoes",
    )


def exportar_csv(cursor, nome, sql):
    cursor.execute(sql)
    colunas = [c[0] for c in cursor.description]
    linhas = cursor.fetchall()
    PASTA_CSV.mkdir(parents=True, exist_ok=True)
    with open(PASTA_CSV / f"{nome}.csv", "w", newline="", encoding="utf-8-sig") as arq:
        escritor = csv.writer(arq, delimiter=";")
        escritor.writerow(colunas)
        escritor.writerows(linhas)
    print(f"  {nome}.csv ({len(linhas)} linhas)")
    return colunas, linhas


def estilo(ax, titulo):
    ax.set_title(titulo, loc="left", fontsize=13, color="#0b0b0b", pad=12)
    ax.set_facecolor(FUNDO)
    for lado in ("top", "right", "left"):
        ax.spines[lado].set_visible(False)
    ax.spines["bottom"].set_color(GRADE)
    ax.tick_params(colors=TEXTO, labelsize=9, length=0)
    ax.yaxis.grid(True, color=GRADE, linewidth=0.8)
    ax.set_axisbelow(True)


def grafico_faturamento(linhas):
    meses = [m for m, _, _ in linhas]
    receita = [float(r) / 1000 for _, _, r in linhas]
    fig, ax = plt.subplots(figsize=(10, 4.2), facecolor=FUNDO)
    ax.bar(meses, receita, color=AZUL, width=0.7)
    estilo(ax, "Faturamento mensal (R$ mil) - outubro/26 ainda parcial")
    ax.set_xticks(range(len(meses)))
    ax.set_xticklabels([f"{m[5:]}/{m[2:4]}" for m in meses], rotation=0, fontsize=8)
    # rótulo só no maior mês, para não poluir
    maior = receita.index(max(receita))
    ax.annotate(f"R$ {receita[maior]:.0f} mil", (maior, receita[maior]), ha="center",
                xytext=(0, 4), textcoords="offset points", fontsize=9, color="#0b0b0b")
    fig.tight_layout()
    fig.savefig(PASTA_GRAFICOS / "grafico-faturamento.png", dpi=150)
    plt.close(fig)


def grafico_filiais(linhas):
    filiais = [f for f, *_ in linhas][::-1]
    receita = [float(r) / 1000 for _, _, r, _ in linhas][::-1]
    fig, ax = plt.subplots(figsize=(10, 3.6), facecolor=FUNDO)
    ax.barh(filiais, receita, color=AZUL, height=0.6)
    estilo(ax, "Receita acumulada por filial (R$ mil)")
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, color=GRADE, linewidth=0.8)
    for i, valor in enumerate(receita):
        ax.text(valor + 8, i, f"{valor:,.0f}".replace(",", "."), va="center", fontsize=9, color=TEXTO)
    fig.tight_layout()
    fig.savefig(PASTA_GRAFICOS / "grafico-filiais.png", dpi=150)
    plt.close(fig)


def main():
    PASTA_GRAFICOS.mkdir(exist_ok=True)
    con = conectar()
    cursor = con.cursor()
    print("Exportando CSVs para python/saida/")
    resultados = {nome: exportar_csv(cursor, nome, sql) for nome, sql in CONSULTAS.items()}
    con.close()

    grafico_faturamento(resultados["faturamento_mensal"][1])
    grafico_filiais(resultados["faturamento_por_filial"][1])
    print("Gráficos salvos em docs/")


if __name__ == "__main__":
    main()
