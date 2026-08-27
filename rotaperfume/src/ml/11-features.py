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

import pyspark.sql.functions as F
from pyspark.sql import DataFrame, Window

from ml.features_lib import (
    ALL_FEATURES,
    COMMENT_FEATURES_CLIENTE,
    COMMENT_FEATURES_TREINO,
    ID_COLUMN,
    REFERENCIA_COLUMN,
    TARGET_COLUMN,
    calcular_taxa_base,
    nome_tabela_features,
    validar_features_geradas,
)


# COMMAND ----------
def montar_features(spark, catalog: str, referencia: str) -> DataFrame:
    """Transforma fato_vendas, oportunidades e visitas em uma linha por cliente com 20 features.

    Filtra estritamente na primeira linha da leitura com base na data de corte (< referencia).
    Nao acessa gold.dim_cliente para evitar vazamento de dados.
    Todas as features numericas recebem cast explicito para double, evitando falhas de serializacao
    de tipos Decimal no MLflow.
    """
    ref_dt = F.to_date(F.lit(referencia))

    # 1. Leituras com filtro temporal estrito na PRIMEIRA linha
    fato = spark.table(f"{catalog}.gold.fato_vendas").filter(F.col("data_pedido") < ref_dt)
    oportunidades = spark.table(f"{catalog}.silver.oportunidades").filter(F.col("data_abertura") < ref_dt)
    visitas = spark.table(f"{catalog}.silver.visitas").filter(F.col("data_visita") < ref_dt)
    produtos = spark.table(f"{catalog}.gold.dim_produto")

    # 2. RFM (6 features)
    rfm = fato.groupBy(ID_COLUMN).agg(
        F.datediff(ref_dt, F.max("data_pedido")).cast("double").alias("recencia_dias"),
        F.countDistinct("pedido_id").cast("double").alias("frequencia_pedidos"),
        F.sum("receita").cast("double").alias("valor_total"),
        (F.sum("receita") / F.countDistinct("pedido_id")).cast("double").alias("ticket_medio"),
        F.sum("margem").cast("double").alias("margem_total"),
        F.when(
            F.sum("receita") > 0,
            F.sum("margem") / F.sum("receita")
        ).otherwise(F.lit(0.0)).cast("double").alias("margem_percentual"),
    )

    # 3. Ritmo (4 features)
    # Gaps entre datas distintas de pedido
    pedidos_datas = fato.select(ID_COLUMN, "data_pedido").distinct()
    w_cliente_data = Window.partitionBy(ID_COLUMN).orderBy("data_pedido")
    pedidos_gaps = pedidos_datas.withColumn(
        "gap_dias",
        F.datediff(F.col("data_pedido"), F.lag("data_pedido", 1).over(w_cliente_data))
    )

    ritmo_gaps = pedidos_gaps.groupBy(ID_COLUMN).agg(
        F.avg("gap_dias").cast("double").alias("intervalo_medio_dias"),
        F.stddev("gap_dias").cast("double").alias("desvio_intervalo_dias")
    )

    # Pedidos nos ultimos 90 dias antes do corte
    dt_90d = F.date_sub(ref_dt, 90)
    ritmo_90d = fato.groupBy(ID_COLUMN).agg(
        F.countDistinct(
            F.when((F.col("data_pedido") >= dt_90d) & (F.col("data_pedido") < ref_dt), F.col("pedido_id"))
        ).cast("double").alias("pedidos_ultimos_90d")
    )

    ritmo = rfm.select(ID_COLUMN, "recencia_dias") \
        .join(ritmo_gaps, on=ID_COLUMN, how="left") \
        .join(ritmo_90d, on=ID_COLUMN, how="left")

    # ARMADILHA: F.least ignora nulos, o que colocaria clientes de 1 pedido no topo da fila (com 10.0).
    # Protecao explicita com when():
    ritmo = ritmo.withColumn(
        "atraso_relativo",
        F.when(
            F.col("intervalo_medio_dias").isNotNull() & (F.col("intervalo_medio_dias") > 0),
            F.least(F.lit(10.0), F.col("recencia_dias") / F.col("intervalo_medio_dias"))
        ).otherwise(F.lit(None)).cast("double")
    ).select(
        ID_COLUMN,
        "intervalo_medio_dias",
        "desvio_intervalo_dias",
        "atraso_relativo",
        "pedidos_ultimos_90d"
    )

    # 4. CRM (5 features)
    crm_ops = oportunidades.groupBy(ID_COLUMN).agg(
        F.sum(F.when(F.col("ganha").isNull(), 1).otherwise(0)).cast("double").alias("oportunidades_abertas"),
        F.sum(F.when(F.col("ganha") == True, 1).otherwise(0)).cast("double").alias("oportunidades_ganhas"),
        F.count("*").cast("double").alias("total_oportunidades")
    ).withColumn(
        "taxa_ganho",
        F.when(
            F.col("total_oportunidades") > 0,
            F.col("oportunidades_ganhas") / F.col("total_oportunidades")
        ).otherwise(F.lit(0.0)).cast("double")
    ).drop("total_oportunidades")

    crm_vis = visitas.groupBy(ID_COLUMN).agg(
        F.sum(F.when(F.col("data_visita") >= dt_90d, 1).otherwise(0)).cast("double").alias("visitas_90d"),
        F.sum(F.when(F.col("resultado") == "Pedido realizado", 1).otherwise(0)).cast("double").alias("visitas_com_pedido"),
        F.count("*").cast("double").alias("total_visitas")
    ).withColumn(
        "conversao_visita",
        F.when(
            F.col("total_visitas") > 0,
            F.col("visitas_com_pedido") / F.col("total_visitas")
        ).otherwise(F.lit(0.0)).cast("double")
    ).drop("visitas_com_pedido", "total_visitas")

    # 5. Mix (5 features)
    mix_contagens = fato.groupBy(ID_COLUMN).agg(
        F.countDistinct("sku").cast("double").alias("skus_distintos"),
        F.countDistinct("categoria").cast("double").alias("categorias_distintas"),
        F.countDistinct("marca").cast("double").alias("marcas_distintas")
    )

    # Concentracao na marca top: receita da marca top / valor_total
    receita_por_marca = fato.groupBy(ID_COLUMN, "marca").agg(
        F.sum("receita").cast("double").alias("receita_marca")
    )
    w_marca = Window.partitionBy(ID_COLUMN).orderBy(F.col("receita_marca").desc())
    marca_top = receita_por_marca.withColumn("rk", F.row_number().over(w_marca)) \
        .filter(F.col("rk") == 1) \
        .select(ID_COLUMN, F.col("receita_marca").alias("receita_marca_top"))

    # Comprou lancamento: SKUs cuja data_lancamento em dim_produto nos 120 dias antes do corte
    dt_120d = F.date_sub(ref_dt, 120)
    fato_com_produtos = fato.join(produtos.select("sku", "data_lancamento"), on="sku", how="inner")
    lancamentos = fato_com_produtos.groupBy(ID_COLUMN).agg(
        F.max(
            F.when(
                (F.col("data_lancamento") >= dt_120d) & (F.col("data_lancamento") < ref_dt),
                1.0
            ).otherwise(0.0)
        ).cast("double").alias("comprou_lancamento")
    )

    mix = mix_contagens \
        .join(marca_top, on=ID_COLUMN, how="left") \
        .join(lancamentos, on=ID_COLUMN, how="left") \
        .join(rfm.select(ID_COLUMN, "valor_total"), on=ID_COLUMN, how="left") \
        .withColumn(
            "concentracao_marca_top",
            F.when(
                F.col("valor_total") > 0,
                F.col("receita_marca_top") / F.col("valor_total")
            ).otherwise(F.lit(0.0)).cast("double")
        ).withColumn(
            "comprou_lancamento",
            F.coalesce(F.col("comprou_lancamento"), F.lit(0.0)).cast("double")
        ).select(
            ID_COLUMN,
            "skus_distintos",
            "categorias_distintas",
            "marcas_distintas",
            "concentracao_marca_top",
            "comprou_lancamento"
        )

    # 6. Consolidacao final de todas as 20 features
    df_features = rfm \
        .join(ritmo, on=ID_COLUMN, how="inner") \
        .join(crm_ops, on=ID_COLUMN, how="left") \
        .join(crm_vis, on=ID_COLUMN, how="left") \
        .join(mix, on=ID_COLUMN, how="inner") \
        .withColumn("oportunidades_abertas", F.coalesce(F.col("oportunidades_abertas"), F.lit(0.0)).cast("double")) \
        .withColumn("oportunidades_ganhas", F.coalesce(F.col("oportunidades_ganhas"), F.lit(0.0)).cast("double")) \
        .withColumn("taxa_ganho", F.coalesce(F.col("taxa_ganho"), F.lit(0.0)).cast("double")) \
        .withColumn("visitas_90d", F.coalesce(F.col("visitas_90d"), F.lit(0.0)).cast("double")) \
        .withColumn("conversao_visita", F.coalesce(F.col("conversao_visita"), F.lit(0.0)).cast("double")) \
        .withColumn(REFERENCIA_COLUMN, ref_dt)

    colunas_finais = [ID_COLUMN, REFERENCIA_COLUMN] + ALL_FEATURES
    return df_features.select(*colunas_finais)


# COMMAND ----------
# 1. Gerar features de TREINO (corte: 2026-08-01) com alvo comprou_em_7d (2026-08-01 a 2026-08-07)
ref_treino = "2026-08-01"
df_treino_base = montar_features(spark, catalog, ref_treino)

# Identificar compradores no horizonte de 7 dias (2026-08-01 a 2026-08-07 inclusive)
compradores_7d = spark.table(f"{catalog}.gold.fato_vendas") \
    .filter(
        (F.col("data_pedido") >= F.to_date(F.lit("2026-08-01"))) &
        (F.col("data_pedido") <= F.to_date(F.lit("2026-08-07")))
    ).select(ID_COLUMN).distinct().withColumn(TARGET_COLUMN, F.lit(1))

df_treino = df_treino_base.join(compradores_7d, on=ID_COLUMN, how="left") \
    .withColumn(TARGET_COLUMN, F.coalesce(F.col(TARGET_COLUMN), F.lit(0)).cast("int"))

tabela_treino = nome_tabela_features(catalog, "treino")
df_treino.write.mode("overwrite").saveAsTable(tabela_treino)
spark.sql(f"COMMENT ON TABLE {tabela_treino} IS '{COMMENT_FEATURES_TREINO}'")

# COMMAND ----------
# 2. Gerar features de CLIENTE (corte: 2026-08-31) sem alvo (base de escoragem)
ref_cliente = "2026-08-31"
df_cliente = montar_features(spark, catalog, ref_cliente)

tabela_cliente = nome_tabela_features(catalog, "cliente")
df_cliente.write.mode("overwrite").saveAsTable(tabela_cliente)
spark.sql(f"COMMENT ON TABLE {tabela_cliente} IS '{COMMENT_FEATURES_CLIENTE}'")

# COMMAND ----------
# Validacoes e exibicao de metricas
erros_treino = validar_features_geradas(df_treino.columns, eh_treino=True)
erros_cliente = validar_features_geradas(df_cliente.columns, eh_treino=False)

if erros_treino or erros_cliente:
    raise Exception(f"Erros na validacao do esquema de features:\nTreino: {erros_treino}\nCliente: {erros_cliente}")

total_treino = df_treino.count()
total_compradores = df_treino.filter(F.col(TARGET_COLUMN) == 1).count()
taxa_base = calcular_taxa_base(total_treino, total_compradores)
total_cliente = df_cliente.count()

print("=== Camada de ML - Features Geradas com Sucesso ===")
print(f"Tabela Treino  : {tabela_treino} ({total_treino} clientes, {total_compradores} compradores em 7d, taxa base: {taxa_base:.1%})")
print(f"Tabela Cliente : {tabela_cliente} ({total_cliente} clientes prontos para escoragem)")
