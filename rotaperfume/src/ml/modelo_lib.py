"""Modulo puro para modelagem de propensao de compra -- logica analitica e metricas.

Contem o calculo de baselines heuristicos, validacao out-of-fold para lift top 200,
tabela de calibragem de probabilidades, atribuicao de faixas comerciais e validacao dos asserts de negocio.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

FAIXAS_LABELS: list[str] = ["Fria", "Morna", "Quente", "Muito quente"]

COMMENT_SCORE_PROPENSAO = (
    "Tabela de escoragem de propensao de compra dos clientes, contendo probabilidade prevista (score), "
    "faixa comercial (Fria, Morna, Quente, Muito quente) e versao do modelo no Unity Catalog."
)

COMMENT_MODELO_METRICAS = (
    "Metricas de avaliacao do modelo de propensao de compra registrado no MLflow, incluindo AUC de holdout, "
    "lift e acertos no top 200, comparativo com baselines heuristicos e feature mais importante."
)

COMMENT_CALIBRAGEM_HOLDOUT = (
    "Tabela de calibragem de probabilidades no conjunto de holdout (25%), demonstrando a taxa real "
    "de conversao observada por faixa de score predito."
)


def calcular_baselines(X_holdout: pd.DataFrame, y_holdout: pd.Series | np.ndarray) -> dict[str, float]:
    """Calcula o ROC AUC de tres regras simples usadas como score:
    1. -recencia_dias: compra mais recente = maior propensao
    2. valor_total: maior receita acumulada = maior propensao
    3. atraso_relativo: maior atraso em relacao ao ritmo proprio = maior propensao
    """
    y_arr = np.array(y_holdout)

    # a) -recencia_dias
    score_recencia = -X_holdout["recencia_dias"].to_numpy()
    auc_recencia = float(roc_auc_score(y_arr, score_recencia))

    # b) valor_total
    score_valor = X_holdout["valor_total"].to_numpy()
    auc_valor = float(roc_auc_score(y_arr, score_valor))

    # c) atraso_relativo (substitui NaN por 0.0 para clientes de 1 pedido)
    score_atraso = X_holdout["atraso_relativo"].fillna(0.0).to_numpy()
    auc_atraso = float(roc_auc_score(y_arr, score_atraso))

    return {
        "auc_recencia": auc_recencia,
        "auc_valor": auc_valor,
        "auc_atraso": auc_atraso,
    }


def calcular_lift_top200(
    y_true: pd.Series | np.ndarray, probas: np.ndarray, top_n: int = 200
) -> tuple[float, int, float, float]:
    """Calcula o Lift e quantidade de acertos no Top N clientes com maior probabilidade.

    Retorna: (lift_topN, acertos_topN, taxa_topN, taxa_base)
    """
    y_arr = np.array(y_true)
    probas_arr = np.array(probas)

    indices_ordenados = np.argsort(-probas_arr)
    top_indices = indices_ordenados[:top_n]

    acertos_top = int(np.sum(y_arr[top_indices]))
    taxa_top = float(acertos_top / top_n)
    taxa_base = float(np.mean(y_arr))

    lift = float(taxa_top / taxa_base) if taxa_base > 0 else 0.0
    return lift, acertos_top, taxa_top, taxa_base


def atribuir_faixas(probas: np.ndarray) -> list[str]:
    """Atribui faixas comerciais em 4 quartis: Fria, Morna, Quente, Muito quente."""
    probas_arr = np.array(probas)
    q25, q50, q75 = np.percentile(probas_arr, [25, 50, 75])

    faixas: list[str] = []
    for p in probas_arr:
        if p <= q25:
            faixas.append(FAIXAS_LABELS[0])  # Fria
        elif p <= q50:
            faixas.append(FAIXAS_LABELS[1])  # Morna
        elif p <= q75:
            faixas.append(FAIXAS_LABELS[2])  # Quente
        else:
            faixas.append(FAIXAS_LABELS[3])  # Muito quente
    return faixas


def calcular_calibragem_holdout(
    y_holdout: pd.Series | np.ndarray, probas_holdout: np.ndarray
) -> list[dict[str, object]]:
    """Gera dados de calibragem no holdout agrupando por 4 faixas de score predito."""
    y_arr = np.array(y_holdout)
    probas_arr = np.array(probas_holdout)

    faixas = atribuir_faixas(probas_arr)
    df_calib = pd.DataFrame({
        "faixa": faixas,
        "y": y_arr,
        "proba": probas_arr,
    })

    resultados: list[dict[str, object]] = []
    for faixa_nome in FAIXAS_LABELS:
        sub = df_calib[df_calib["faixa"] == faixa_nome]
        total_clientes = len(sub)
        compraram = int(sub["y"].sum()) if total_clientes > 0 else 0
        taxa = float(compraram / total_clientes) if total_clientes > 0 else 0.0
        score_medio = float(sub["proba"].mean()) if total_clientes > 0 else 0.0

        resultados.append({
            "faixa": faixa_nome,
            "clientes": total_clientes,
            "compraram": compraram,
            "taxa_de_compra": round(taxa, 4),
            "score_medio": round(score_medio, 4),
        })
    return resultados


def validar_asserts_modelo(auc: float, best_baseline_auc: float, lift_top200: float) -> None:
    """Executa os 3 testes de negocio que garantem a qualidade e viabilidade do modelo."""
    assert auc >= best_baseline_auc + 0.05, (
        f"Modelo falhou no teste 1: AUC ({auc:.4f}) precisa superar o melhor baseline ({best_baseline_auc:.4f}) "
        f"por pelo menos 0.05 (ganho obtido: {auc - best_baseline_auc:.4f})"
    )
    assert auc < 0.99, (
        f"Modelo falhou no teste 2 (vazamento de dados): AUC ({auc:.4f}) >= 0.99 e suspeito de data leakage"
    )
    assert lift_top200 >= 2.5, (
        f"Modelo falhou no teste 3 (viabilidade comercial): lift_top200 ({lift_top200:.2f}) precisa ser >= 2.5 "
        "para justificar o projeto"
    )
