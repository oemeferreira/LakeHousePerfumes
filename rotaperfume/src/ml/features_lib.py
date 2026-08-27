"""Modulo puro para engenharia de features de ML -- sem spark/dbutils.

Contem a definicao das 20 features comportamentais do cliente (RFM, Ritmo, CRM e Mix),
metadados de documentacao semantica para o Unity Catalog e funcoes puras de validacao e metricas.
"""
from __future__ import annotations

# Grupos de features comportamentais
RFM_FEATURES: list[str] = [
    "recencia_dias",
    "frequencia_pedidos",
    "valor_total",
    "ticket_medio",
    "margem_total",
    "margem_percentual",
]

RITMO_FEATURES: list[str] = [
    "intervalo_medio_dias",
    "desvio_intervalo_dias",
    "atraso_relativo",
    "pedidos_ultimos_90d",
]

CRM_FEATURES: list[str] = [
    "oportunidades_abertas",
    "oportunidades_ganhas",
    "taxa_ganho",
    "visitas_90d",
    "conversao_visita",
]

MIX_FEATURES: list[str] = [
    "skus_distintos",
    "categorias_distintas",
    "marcas_distintas",
    "concentracao_marca_top",
    "comprou_lancamento",
]

ALL_FEATURES: list[str] = RFM_FEATURES + RITMO_FEATURES + CRM_FEATURES + MIX_FEATURES

ID_COLUMN = "cliente_id"
TARGET_COLUMN = "comprou_em_7d"
REFERENCIA_COLUMN = "_referencia"

# Documentacao semantica para Unity Catalog
COMMENT_FEATURES_TREINO = (
    "Tabela de features de treino com 20 variaveis comportamentais (RFM, Ritmo, CRM e Mix) "
    "calculadas estritamente com dados anteriores a 2026-08-01, acompanhada do alvo "
    "comprou_em_7d (compras realizadas entre 2026-08-01 e 2026-08-07). Taxa base ~10,1%."
)

COMMENT_FEATURES_CLIENTE = (
    "Tabela de features de clientes para escoragem em producao com 20 variaveis comportamentais "
    "(RFM, Ritmo, CRM e Mix) calculadas com corte em 2026-08-31 sem alvo."
)


def nome_tabela_features(catalog: str, tipo: str) -> str:
    """Monta o nome completo de 3 niveis para as tabelas de features na camada gold."""
    if tipo not in ("treino", "cliente"):
        raise ValueError(f"tipo deve ser 'treino' ou 'cliente', recebido: '{tipo}'")
    return f"{catalog}.gold.features_{tipo}"


def calcular_taxa_base(total_clientes: int, compradores_alvo: int) -> float:
    """Calcula a taxa base de conversao do alvo."""
    if total_clientes <= 0:
        return 0.0
    return compradores_alvo / total_clientes


def validar_features_geradas(colunas_presentes: list[str], eh_treino: bool = False) -> list[str]:
    """Valida se todas as 20 features e identificadores obrigatorios estao presentes."""
    erros: list[str] = []
    esperadas = [ID_COLUMN, REFERENCIA_COLUMN] + ALL_FEATURES
    if eh_treino:
        esperadas.append(TARGET_COLUMN)

    colunas_set = set(colunas_presentes)
    for col in esperadas:
        if col not in colunas_set:
            erros.append(f"Coluna obrigatoria ausente: '{col}'")
    return erros
