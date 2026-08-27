"""Testes unitarios puros para ml/features_lib.py -- sem necessidade de cluster Databricks."""
import pytest

from ml.features_lib import (
    ALL_FEATURES,
    COMMENT_FEATURES_CLIENTE,
    COMMENT_FEATURES_TREINO,
    CRM_FEATURES,
    ID_COLUMN,
    MIX_FEATURES,
    REFERENCIA_COLUMN,
    RFM_FEATURES,
    RITMO_FEATURES,
    TARGET_COLUMN,
    calcular_taxa_base,
    nome_tabela_features,
    validar_features_geradas,
)


def test_contagem_exata_de_features():
    """Garante que a lista ALL_FEATURES contem exatamente 20 variaveis unicas."""
    assert len(ALL_FEATURES) == 20
    assert len(set(ALL_FEATURES)) == 20


def test_grupos_de_features():
    """Valida a quantidade de features por grupo tematico."""
    assert len(RFM_FEATURES) == 6
    assert len(RITMO_FEATURES) == 4
    assert len(CRM_FEATURES) == 5
    assert len(MIX_FEATURES) == 5

    assert set(RFM_FEATURES) == {
        "recencia_dias",
        "frequencia_pedidos",
        "valor_total",
        "ticket_medio",
        "margem_total",
        "margem_percentual",
    }
    assert set(RITMO_FEATURES) == {
        "intervalo_medio_dias",
        "desvio_intervalo_dias",
        "atraso_relativo",
        "pedidos_ultimos_90d",
    }
    assert set(CRM_FEATURES) == {
        "oportunidades_abertas",
        "oportunidades_ganhas",
        "taxa_ganho",
        "visitas_90d",
        "conversao_visita",
    }
    assert set(MIX_FEATURES) == {
        "skus_distintos",
        "categorias_distintas",
        "marcas_distintas",
        "concentracao_marca_top",
        "comprou_lancamento",
    }


def test_nomes_tabelas_features():
    """Valida geracao correta dos nomes de tabela de 3 niveis."""
    assert nome_tabela_features("lakehouse_rotaperfume", "treino") == "lakehouse_rotaperfume.gold.features_treino"
    assert nome_tabela_features("lakehouse_rotaperfume", "cliente") == "lakehouse_rotaperfume.gold.features_cliente"
    with pytest.raises(ValueError, match="tipo deve ser 'treino' ou 'cliente'"):
        nome_tabela_features("lakehouse_rotaperfume", "invalido")


def test_calcular_taxa_base():
    """Valida o calculo da taxa base com dados simulados."""
    assert calcular_taxa_base(0, 0) == 0.0
    assert calcular_taxa_base(2815, 285) == pytest.approx(0.101243, abs=1e-5)


def test_validar_features_geradas():
    """Valida deteccao de colunas faltantes."""
    colunas_cliente = [ID_COLUMN, REFERENCIA_COLUMN] + ALL_FEATURES
    assert validar_features_geradas(colunas_cliente, eh_treino=False) == []

    # Falta o alvo no treino
    erros_treino = validar_features_geradas(colunas_cliente, eh_treino=True)
    assert len(erros_treino) == 1
    assert "comprou_em_7d" in erros_treino[0]

    # Com alvo no treino
    colunas_treino = colunas_cliente + [TARGET_COLUMN]
    assert validar_features_geradas(colunas_treino, eh_treino=True) == []


def test_comentarios_tabela_preenchidos():
    """Valida que os comentarios das tabelas estao definidos em portugues e nao vazios."""
    assert len(COMMENT_FEATURES_TREINO) > 20
    assert "features de treino" in COMMENT_FEATURES_TREINO
    assert len(COMMENT_FEATURES_CLIENTE) > 20
    assert "features de clientes" in COMMENT_FEATURES_CLIENTE
