"""
Gera docs/dicionario-de-dados.md lendo o próprio banco (information_schema),
assim a documentação nunca fica desatualizada em relação às tabelas.

Uso:  python python/dicionario_dados.py
"""

from pathlib import Path

from relatorio import conectar

SAIDA = Path(__file__).resolve().parent.parent / "docs" / "dicionario-de-dados.md"


def main():
    con = conectar()
    cur = con.cursor()
    cur.execute("""
        SELECT table_name, table_comment, table_rows
        FROM information_schema.tables
        WHERE table_schema = 'welcar_locacoes' AND table_type = 'BASE TABLE'
        ORDER BY FIELD(table_name, 'filial', 'funcionario', 'categoria', 'modelo', 'veiculo',
                       'cliente', 'adicional', 'reserva', 'locacao', 'locacao_adicional',
                       'pagamento', 'manutencao', 'log_status_veiculo')""")
    tabelas = cur.fetchall()

    linhas = ["# Dicionário de dados - welcar_locacoes", "",
              "Gerado automaticamente por `python/dicionario_dados.py` a partir do banco.", ""]
    for nome, comentario, _ in tabelas:
        cur.execute("""
            SELECT c.column_name, c.column_type, c.is_nullable, c.column_key,
                   c.column_default, c.column_comment,
                   (SELECT CONCAT(k.referenced_table_name, '.', k.referenced_column_name)
                      FROM information_schema.key_column_usage k
                     WHERE k.table_schema = c.table_schema AND k.table_name = c.table_name
                       AND k.column_name = c.column_name AND k.referenced_table_name IS NOT NULL
                     LIMIT 1) AS referencia
            FROM information_schema.columns c
            WHERE c.table_schema = 'welcar_locacoes' AND c.table_name = %s
            ORDER BY c.ordinal_position""", (nome,))
        linhas += [f"## {nome}", "", comentario or "", "",
                   "| Coluna | Tipo | Nulo | Chave | Padrão | Referência | Descrição |",
                   "|---|---|---|---|---|---|---|"]
        for coluna, tipo, nulo, chave, padrao, desc, ref in cur.fetchall():
            chave = {"PRI": "PK", "UNI": "UK", "MUL": "FK" if ref else "índice"}.get(chave, "")
            linhas.append(
                f"| {coluna} | `{tipo}` | {'sim' if nulo == 'YES' else 'não'} | {chave} | "
                f"{'' if padrao is None else padrao} | {ref or ''} | {desc} |")
        linhas.append("")
    con.close()
    SAIDA.write_text("\n".join(linhas), encoding="utf-8")
    print(f"Gerado {SAIDA} ({len(tabelas)} tabelas)")


if __name__ == "__main__":
    main()
