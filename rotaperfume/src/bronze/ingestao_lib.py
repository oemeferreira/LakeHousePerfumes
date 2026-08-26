"""Ingestao bronze -- logica pura, sem dbutils/spark.

Mesma divisao de raw/conferencia_lib.py: aqui fica so o que nao depende de
Spark (montar nome de tabela, comparar duas contagens), para testar com
pytest comum, sem cluster. O notebook 'ingestao.py' (mesma pasta) e' quem
le CSV com Spark, escreve Delta e chama estas funcoes.

Reaproveita ARQUIVOS_ESPERADOS/caminho_arquivo de raw.conferencia_lib
(pacote irmao) em vez de redefinir a lista das 10 tabelas -- o import
cruzado (via sys.path em src/, pai de raw/ e bronze/) acontece no notebook
ingestao.py, nao aqui.
"""
from __future__ import annotations


def nome_tabela(catalog: str, nome: str) -> str:
    """Monta o nome completo de 3 niveis {catalog}.bronze.{nome}."""
    return f"{catalog}.bronze.{nome}"


def comparar_contagens(
    contagens_bronze: dict[str, int], contagens_esperadas: dict[str, int]
) -> list[str]:
    """Compara contagem de linhas por tabela. Retorna lista de mensagens de
    divergencia (vazia se tudo bate). Cobre tanto valor diferente quanto uma
    tabela existir so de um lado (bronze sem controle correspondente, ou
    controle sem tabela bronze ingerida)."""
    divergencias: list[str] = []
    todas_as_chaves = sorted(set(contagens_bronze) | set(contagens_esperadas))
    for nome in todas_as_chaves:
        bronze = contagens_bronze.get(nome)
        esperado = contagens_esperadas.get(nome)
        if bronze is None:
            divergencias.append(
                f"{nome}: existe em bronze._raw_arquivos (linhas={esperado}) "
                "mas nao foi ingerido em bronze"
            )
        elif esperado is None:
            divergencias.append(
                f"{nome}: tabela bronze existe (linhas={bronze}) mas nao tem "
                "registro em bronze._raw_arquivos"
            )
        elif bronze != esperado:
            divergencias.append(
                f"{nome}: bronze tem {bronze} linha(s), "
                f"bronze._raw_arquivos esperava {esperado}"
            )
    return divergencias
