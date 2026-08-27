"""Testes unitarios locais para ml/modelo_lib.py."""
import numpy as np
import pandas as pd
import pytest

from ml.modelo_lib import (
    FAIXAS_LABELS,
    atribuir_faixas,
    calcular_baselines,
    calcular_calibragem_holdout,
    calcular_lift_top200,
    validar_asserts_modelo,
)


def test_calcular_baselines():
    """Valida o calculo dos 3 baselines com dados sinteticos."""
    np.random.seed(42)
    n = 100
    df = pd.DataFrame({
        "recencia_dias": np.random.uniform(5, 100, n),
        "valor_total": np.random.uniform(100, 5000, n),
        "atraso_relativo": [np.nan if i % 10 == 0 else np.random.uniform(0.5, 4.0) for i in range(n)],
    })
    # y correlacionado negativamente com recencia
    y = (df["recencia_dias"] < 40).astype(int)

    baselines = calcular_baselines(df, y)
    assert "auc_recencia" in baselines
    assert "auc_valor" in baselines
    assert "auc_atraso" in baselines

    assert 0.0 <= baselines["auc_recencia"] <= 1.0
    assert 0.0 <= baselines["auc_valor"] <= 1.0
    assert 0.0 <= baselines["auc_atraso"] <= 1.0
    assert baselines["auc_recencia"] > 0.8  # recencia bem correlacionada


def test_calcular_lift_top200():
    """Valida calculo do lift e acertos no top 200."""
    n = 1000
    y = np.zeros(n, dtype=int)
    y[:100] = 1  # 10% de taxa base
    np.random.seed(42)
    np.random.shuffle(y)

    # Probas perfeitas: alinha com y
    probas = y.astype(float) + np.random.uniform(0, 0.1, n)

    lift, acertos, taxa_top, taxa_base = calcular_lift_top200(y, probas, top_n=200)
    assert taxa_base == pytest.approx(0.10, abs=1e-3)
    assert acertos == 100
    assert taxa_top == pytest.approx(0.50, abs=1e-3)
    assert lift == pytest.approx(5.0, abs=1e-2)


def test_atribuir_faixas():
    """Valida atribuicao das 4 faixas pelos quartis."""
    probas = np.array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8])
    faixas = atribuir_faixas(probas)
    assert len(faixas) == len(probas)
    assert set(faixas).issubset(set(FAIXAS_LABELS))
    assert faixas[0] == "Fria"
    assert faixas[-1] == "Muito quente"


def test_calcular_calibragem_holdout():
    """Valida calculo da matriz de calibragem."""
    y = np.array([0, 0, 0, 0, 1, 1, 1, 1])
    probas = np.array([0.1, 0.15, 0.25, 0.35, 0.55, 0.65, 0.85, 0.95])
    calib = calcular_calibragem_holdout(y, probas)
    assert len(calib) == 4
    for row in calib:
        assert row["faixa"] in FAIXAS_LABELS
        assert "clientes" in row
        assert "compraram" in row
        assert "taxa_de_compra" in row
        assert "score_medio" in row


def test_validar_asserts_modelo():
    """Valida condicoes de sucesso e falha dos 3 asserts de negocio."""
    # Caso valido
    validar_asserts_modelo(auc=0.85, best_baseline_auc=0.75, lift_top200=3.2)

    # Falha teste 1: ganho sobre baseline insuficiente (< 0.05)
    with pytest.raises(AssertionError, match="Modelo falhou no teste 1"):
        validar_asserts_modelo(auc=0.78, best_baseline_auc=0.75, lift_top200=3.2)

    # Falha teste 2: vazamento de dados (AUC >= 0.99)
    with pytest.raises(AssertionError, match="vazamento de dados"):
        validar_asserts_modelo(auc=0.995, best_baseline_auc=0.75, lift_top200=3.2)

    # Falha teste 3: lift insuficiente (< 2.5)
    with pytest.raises(AssertionError, match="viabilidade comercial"):
        validar_asserts_modelo(auc=0.85, best_baseline_auc=0.75, lift_top200=2.1)
