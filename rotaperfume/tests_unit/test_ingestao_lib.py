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


def test_comparar_contagens_reaproveita_lista_de_10_tabelas_de_conferencia_lib():
    """Prova de que a lista de tabelas nao foi redefinida aqui: usa
    ARQUIVOS_ESPERADOS do modulo irmao raw.conferencia_lib, nao uma copia
    local -- se algum dia bronze/ ganhar sua propria lista duplicada, este
    teste continua passando, mas o import em si so funciona porque
    pythonpath=["src"] resolve 'raw' como pacote irmao de 'bronze'."""
    from raw.conferencia_lib import ARQUIVOS_ESPERADOS

    todos_os_nomes = [nome for nomes in ARQUIVOS_ESPERADOS.values() for nome in nomes]
    contagens_ok = {nome: 1 for nome in todos_os_nomes}
    assert comparar_contagens(contagens_ok, contagens_ok) == []
    assert len(todos_os_nomes) == 10
