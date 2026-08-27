# Databricks notebook source
# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
import os
import sys

_NOTEBOOK_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
_SRC_DIR = os.path.dirname(_NOTEBOOK_DIR)
if _SRC_DIR not in sys.path:
    sys.path.append(_SRC_DIR)

import mlflow
import mlflow.sklearn
import numpy as np
import pandas as pd
import pyspark.sql.functions as F
from databricks.sdk import WorkspaceClient
from mlflow.models import infer_signature
from mlflow.tracking import MlflowClient
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold, train_test_split

from ml.features_lib import ALL_FEATURES, ID_COLUMN, REFERENCIA_COLUMN, TARGET_COLUMN
from ml.modelo_lib import (
    COMMENT_CALIBRAGEM_HOLDOUT,
    COMMENT_MODELO_METRICAS,
    COMMENT_SCORE_PROPENSAO,
    atribuir_faixas,
    calcular_baselines,
    calcular_calibragem_holdout,
    calcular_lift_top200,
    validar_asserts_modelo,
)

# COMMAND ----------
# 1. Leitura da tabela de treino para pandas
df_treino_spark = spark.table(f"{catalog}.gold.features_treino")
df_treino = df_treino_spark.toPandas()

X = df_treino[ALL_FEATURES]
y = df_treino[TARGET_COLUMN].values

# Split 75% treino / 25% holdout estratificado
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

# 2. BASELINES no holdout
baselines = calcular_baselines(X_test, y_test)
best_baseline_name = max(baselines, key=baselines.get)
best_baseline_auc = baselines[best_baseline_name]

print("=== 1. Comparativo de Baselines (Holdout 25%) ===")
print(f"{'Estrategia':<25} {'ROC AUC':>10}")
print("-" * 37)
print(f"{'Moeda (Aleatorio)':<25} {'0.5000':>10}")
print(f"{'-recencia_dias':<25} {baselines['auc_recencia']:>10.4f}")
print(f"{'valor_total':<25} {baselines['auc_valor']:>10.4f}")
print(f"{'atraso_relativo':<25} {baselines['auc_atraso']:>10.4f}")
print("-" * 37)
print(f"Melhor baseline: {best_baseline_name} (AUC = {best_baseline_auc:.4f})\n")

# COMMAND ----------
# 3. Validacao cruzada out-of-fold (5 folds) para lift_top200
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
oof_probas = np.zeros(len(df_treino))

for fold, (train_idx, val_idx) in enumerate(skf.split(X, y)):
    clf_fold = HistGradientBoostingClassifier(random_state=42)
    clf_fold.fit(X.iloc[train_idx], y[train_idx])
    oof_probas[val_idx] = clf_fold.predict_proba(X.iloc[val_idx])[:, 1]

lift_top200, acertos_top200, taxa_top200, taxa_base = calcular_lift_top200(y, oof_probas, top_n=200)

# 4. Treino do modelo final nos 75% de treino
modelo = HistGradientBoostingClassifier(random_state=42)
modelo.fit(X_train, y_train)

# Avaliacao no holdout de 25%
probas_test = modelo.predict_proba(X_test)[:, 1]
auc = float(roc_auc_score(y_test, probas_test))

# 5. Importancia por permutacao no holdout
perm_imp = permutation_importance(modelo, X_test, y_test, n_repeats=5, random_state=42, scoring="roc_auc")
indices_importancia = np.argsort(-perm_imp.importances_mean)
feature_no_1 = ALL_FEATURES[indices_importancia[0]]

print("=== 2. Top 10 Features por Importancia de Permutacao ===")
for rank, idx in enumerate(indices_importancia[:10], 1):
    print(f"  {rank:2d}. {ALL_FEATURES[idx]:<25} ({perm_imp.importances_mean[idx]:+.4f})")

print("\n=== 3. Metricas Principais do Modelo ===")
print(f"  AUC Holdout   : {auc:.4f} (Ganho sobre baseline: {auc - best_baseline_auc:+.4f})")
print(f"  Lift Top 200  : {lift_top200:.2f}x (Taxa Top 200: {taxa_top200:.1%} vs Taxa Base: {taxa_base:.1%})")
print(f"  Acertos Top200: {acertos_top200} de 200 ligacoes")

# 6. TRES ASSERTS DE NEGOCIO QUE INTERROMPEM A TAREFA
validar_asserts_modelo(auc, best_baseline_auc, lift_top200)
print("\n-> Asserts de negocio aprovados com sucesso!\n")

# COMMAND ----------
# 7. MLFLOW & UNITY CATALOG MODEL REGISTRY
w = WorkspaceClient()
try:
    user_name = spark.sql("SELECT current_user()").collect()[0][0]
    exp_dir = f"/Users/{user_name}/experiments"
    w.workspace.mkdirs(exp_dir)
    mlflow.set_experiment(f"{exp_dir}/rotaperfume_propensao")
except Exception as e:  # noqa: BLE001
    print(f"Aviso ao inicializar pasta do experimento: {e}")

mlflow.set_registry_uri("databricks-uc")
full_model_name = f"{catalog}.gold.propensao_compra"

with mlflow.start_run(run_name="hist_gradient_boosting_prod") as run:
    mlflow.log_params(modelo.get_params())
    mlflow.log_metrics({
        "auc": auc,
        "lift_top200": lift_top200,
        "acertos_top200": float(acertos_top200),
        "taxa_base": taxa_base,
        "best_baseline_auc": best_baseline_auc,
        "auc_recencia": baselines["auc_recencia"],
        "auc_valor": baselines["auc_valor"],
        "auc_atraso": baselines["auc_atraso"],
    })

    signature = infer_signature(X_train, modelo.predict_proba(X_train)[:, 1])

    model_info = mlflow.sklearn.log_model(
        sk_model=modelo,
        artifact_path="modelo",
        registered_model_name=full_model_name,
        signature=signature,
    )

client = MlflowClient()
model_versions = client.search_model_versions(f"name = '{full_model_name}'")
latest_version = max(int(mv.version) for mv in model_versions)

client.set_registered_model_alias(name=full_model_name, alias="prod", version=str(latest_version))
print("=== 4. Modelo Registrado no Unity Catalog ===")
print(f"Nome: {full_model_name} | Versao: {latest_version} | Alias: @prod\n")

# COMMAND ----------
# 8. ESCORAGEM EM PRODUCAO (gold.score_propensao)
modelo_prod = mlflow.sklearn.load_model(f"models:/{full_model_name}@prod")

df_cliente_spark = spark.table(f"{catalog}.gold.features_cliente")
df_cliente = df_cliente_spark.toPandas()

features_esperadas = list(modelo_prod.feature_names_in_)
X_cliente = df_cliente[features_esperadas]

probas_cliente = modelo_prod.predict_proba(X_cliente)[:, 1]
faixas_cliente = atribuir_faixas(probas_cliente)

df_score = pd.DataFrame({
    "cliente_id": df_cliente[ID_COLUMN].astype(int),
    "score": probas_cliente.astype(float),
    "faixa": faixas_cliente,
    "_referencia": pd.to_datetime(df_cliente[REFERENCIA_COLUMN]).dt.date,
    "versao": str(latest_version),
})

df_score_spark = spark.createDataFrame(df_score)
tabela_score = f"{catalog}.gold.score_propensao"
df_score_spark.write.mode("overwrite").saveAsTable(tabela_score)
spark.sql(f"COMMENT ON TABLE {tabela_score} IS '{COMMENT_SCORE_PROPENSAO}'")
print(f"Tabela de escoragem gravada: {tabela_score} ({len(df_score)} clientes escorados)")

# COMMAND ----------
# 9. TABELAS DE METRICAS E CALIBRAGEM
# a) gold.modelo_metricas
df_metricas = pd.DataFrame([{
    "versao": str(latest_version),
    "auc": float(auc),
    "lift_top200": float(lift_top200),
    "acertos_top200": int(acertos_top200),
    "taxa_base": float(taxa_base),
    "auc_recencia": float(baselines["auc_recencia"]),
    "auc_valor": float(baselines["auc_valor"]),
    "auc_atraso": float(baselines["auc_atraso"]),
    "feature_no_1": str(feature_no_1),
}])

df_metricas_spark = spark.createDataFrame(df_metricas).withColumn("_treinado_em", F.current_timestamp())
tabela_metricas = f"{catalog}.gold.modelo_metricas"
df_metricas_spark.write.mode("overwrite").saveAsTable(tabela_metricas)
spark.sql(f"COMMENT ON TABLE {tabela_metricas} IS '{COMMENT_MODELO_METRICAS}'")

# b) gold.calibragem_holdout
calibragem_dados = calcular_calibragem_holdout(y_test, probas_test)
df_calib = pd.DataFrame(calibragem_dados)
df_calib_spark = spark.createDataFrame(df_calib)
tabela_calib = f"{catalog}.gold.calibragem_holdout"
df_calib_spark.write.mode("overwrite").saveAsTable(tabela_calib)
spark.sql(f"COMMENT ON TABLE {tabela_calib} IS '{COMMENT_CALIBRAGEM_HOLDOUT}'")

print("Tabelas analiticas gravadas com sucesso:")
print(f"  - {tabela_metricas}")
print(f"  - {tabela_calib}")
