"""Testes rapidos do modulo puro de ingestao -- sem rede, sem Databricks.

Mora em tests_unit/ pelo mesmo motivo de test_conferencia_lib.py: irmao de
tests/, fora do alcance de tests/conftest.py (que abriria uma
DatabricksSession real). Roda com 'uv run pytest tests_unit/'.
"""
from bronze.ingestao_lib import comparar_contagens, nome_tabela


def test_nome_tabela_monta_3_niveis():
    assert nome_tabela("lakehouse_rotaperfume", "produtos") == "lakehouse_rotaperfume.bronze.produtos"


def test_comparar_contagens_vazio_quando_tudo_bate():
    assert (
        comparar_contagens(
            {"produtos": 292, "pedidos": 28729}, {"produtos": 292, "pedidos": 28729}
        )
        == []
    )


def test_comparar_contagens_detecta_valor_diferente():
    divergencias = comparar_contagens({"produtos": 291}, {"produtos": 292})
    assert divergencias == ["produtos: bronze tem 291 linha(s), bronze._raw_arquivos esperava 292"]


def test_comparar_contagens_detecta_tabela_so_no_bronze():
    divergencias = comparar_contagens({"produtos": 292, "extra": 5}, {"produtos": 292})
    assert divergencias == [
        "extra: tabela bronze existe (linhas=5) mas nao tem registro em bronze._raw_arquivos"
    ]


def test_comparar_contagens_detecta_tabela_so_no_controle():
    divergencias = comparar_contagens({"produtos": 292}, {"produtos": 292, "faltando": 10})
    assert divergencias == [
        "faltando: existe em bronze._raw_arquivos (linhas=10) mas nao foi ingerido em bronze"
    ]


def test_bronze_nao_redefine_a_lista_de_tabelas():
    """Prova real de que bronze/ingestao_lib.py nao tem sua propria copia de
    ARQUIVOS_ESPERADOS -- a lista de tabelas so existe em raw.conferencia_lib,
    evitando que as duas camadas divirjam com o tempo."""
    import bronze.ingestao_lib as lib

    assert not hasattr(lib, "ARQUIVOS_ESPERADOS"), (
        "bronze/ingestao_lib.py ganhou sua propria lista de tabelas -- "
        "ela deve vir de raw.conferencia_lib para nao divergir"
    )
