# Databricks notebook source
# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
import os
import sys

# Databricks normalmente ja adiciona a pasta do proprio notebook ao
# sys.path, mas fazemos isso explicito (idempotente) para nao depender
# disso: 'conferencia_lib.py' esta na MESMA pasta deste notebook.
_NOTEBOOK_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _NOTEBOOK_DIR not in sys.path:
    sys.path.append(_NOTEBOOK_DIR)

from conferencia_lib import ARQUIVOS_ESPERADOS, conferir_arquivos

# COMMAND ----------
# A conferencia de chegada roda sobre o Volume de raw -- ainda nao existe
# camada bronze de negocio, so o pouso do arquivo cru.
base_dir = f"/Volumes/{catalog}/bronze/raw"
resultados, faltando, vazios = conferir_arquivos(base_dir, ARQUIVOS_ESPERADOS)

if faltando:
    raise Exception(f"Arquivos ausentes no Volume: {faltando}")
if vazios:
    raise Exception(f"Arquivos vazios (sem linhas de dado): {vazios}")

# COMMAND ----------
df = spark.createDataFrame(resultados)
tabela = f"{catalog}.bronze._raw_arquivos"
df.write.mode("overwrite").saveAsTable(tabela)
spark.sql(
    f"COMMENT ON TABLE {tabela} IS "
    "'Conferencia de chegada dos arquivos raw no Volume: tamanho e "
    "contagem de linhas por arquivo, gravado a cada execucao do job.'"
)

# COMMAND ----------
print(f"{'sistema':<8} {'arquivo':<20} {'bytes':>10} {'linhas':>10}  conferido_em")
for r in sorted(resultados, key=lambda x: -x["linhas"]):
    print(
        f"{r['sistema']:<8} {r['arquivo']:<20} {r['bytes']:>10} {r['linhas']:>10}  "
        f"{r['conferido_em'].isoformat()}"
    )
