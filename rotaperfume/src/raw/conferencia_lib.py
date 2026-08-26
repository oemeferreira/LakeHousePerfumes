# rotaperfume/src/raw/conferencia_lib.py
"""Conferencia de chegada dos arquivos raw -- logica pura, sem dbutils/spark.

Recebe o diretorio-base como parametro (nunca monta '/Volumes/{catalog}/...'
internamente) para poder ser testada com pytest comum, apontando para um
tmp_path com CSVs falsos, sem precisar de um Volume real nem de cluster.

O notebook 'conferencia.py' (mesma pasta) e' quem monta
base_dir = f"/Volumes/{catalog}/bronze/raw", chama estas funcoes, e grava o
resultado com Spark -- essa parte sim exige o runtime Databricks.
"""
from __future__ import annotations

import os
from datetime import datetime, timezone

ARQUIVOS_ESPERADOS: dict[str, list[str]] = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}


def caminho_arquivo(base_dir: str, sistema: str, nome: str) -> str:
    """Monta o caminho do CSV dentro de base_dir/sistema/nome.csv."""
    return f"{base_dir}/{sistema}/{nome}.csv"


def conferir_arquivos(base_dir: str, esperados: dict[str, list[str]]):
    """Confere cada arquivo esperado: existe, tamanho em bytes, linhas de dado.

    Retorna (resultados, faltando, vazios). 'resultados' traz uma entrada por
    arquivo ENCONTRADO (mesmo vazio); 'faltando' e 'vazios' trazem os caminhos
    problematicos, para quem chamar decidir se interrompe.
    """
    resultados: list[dict] = []
    faltando: list[str] = []
    vazios: list[str] = []

    for sistema, nomes in esperados.items():
        for nome in nomes:
            caminho = caminho_arquivo(base_dir, sistema, nome)
            if not os.path.exists(caminho):
                faltando.append(caminho)
                continue

            tamanho_bytes = os.path.getsize(caminho)
            with open(caminho, "r", encoding="utf-8") as f:
                total_linhas = sum(1 for _ in f)
            linhas_de_dado = total_linhas - 1  # desconta o cabecalho

            if linhas_de_dado <= 0:
                vazios.append(caminho)

            resultados.append(
                {
                    "sistema": sistema,
                    "arquivo": f"{nome}.csv",
                    "bytes": tamanho_bytes,
                    "linhas": linhas_de_dado,
                    "conferido_em": datetime.now(timezone.utc),
                }
            )

    return resultados, faltando, vazios
