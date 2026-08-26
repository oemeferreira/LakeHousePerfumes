# Databricks notebook source
# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
import os
import sys

# Mesma ideia de sys.path de raw/conferencia.py, mas agora precisamos
# importar DUAS pastas -- bronze/ (este notebook, mesma pasta) e raw/
# (pasta irma). Por isso subimos ate src/ (pai das duas) e importamos com
# prefixo de pacote -- exatamente como o pytest resolve com
# pythonpath=["src"] em pyproject.toml.
_NOTEBOOK_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
_SRC_DIR = os.path.dirname(_NOTEBOOK_DIR)  # sobe de src/bronze para src/
if _SRC_DIR not in sys.path:
    sys.path.append(_SRC_DIR)

assert os.path.isdir(os.path.join(_SRC_DIR, "raw")), (
    f"esperava a pasta 'raw' dentro de {_SRC_DIR} (pai de bronze/ e raw/) "
    f"para o import cruzado funcionar -- conteudo encontrado: {os.listdir(_SRC_DIR)}"
)

# COMMAND ----------
from pyspark.sql.functions import current_timestamp, lit

from bronze.ingestao_lib import comparar_contagens, nome_tabela
from raw.conferencia_lib import ARQUIVOS_ESPERADOS, caminho_arquivo


def ingerir_tabela(spark, base_dir_raw: str, catalog: str, sistema: str, nome: str) -> int:
    """Le um CSV como string pura (sem inferSchema -- default do reader ja
    e' False; sem multiLine -- os arquivos sao CRLF, com header, sem campo
    com quebra de linha real) e grava Delta em bronze, modo overwrite. So
    adiciona _ingerido_em/_arquivo_origem. Nenhuma limpeza, nenhuma
    conversao de tipo -- isso e' assunto do proximo prompt (silver).
    Retorna a contagem de linhas gravadas na tabela Delta resultante."""
    caminho_csv = caminho_arquivo(base_dir_raw, sistema, nome)
    tabela = nome_tabela(catalog, nome)

    df = (
        spark.read.option("header", "true")
        .option("inferSchema", "false")
        .csv(caminho_csv)
        .withColumn("_ingerido_em", current_timestamp())
        .withColumn("_arquivo_origem", lit(caminho_csv))
    )
    df.write.mode("overwrite").saveAsTable(tabela)
    spark.sql(
        f"COMMENT ON TABLE {tabela} IS "
        f"'Bronze sem transformacao: ingerida do sistema {sistema}, arquivo "
        f"{nome}.csv. Todas as colunas originais como string; nenhuma "
        f"limpeza ou conversao de tipo.'"
    )
    return spark.table(tabela).count()


# COMMAND ----------
# Escreve a funcao de ingestao UMA vez (acima) e itera sobre as 10 tabelas
# -- a mesma lista ja usada por raw/conferencia.py, sem redefini-la aqui.
base_dir_raw = f"/Volumes/{catalog}/bronze/raw"
contagens_bronze: dict[str, int] = {}
for sistema, nomes in ARQUIVOS_ESPERADOS.items():
    for nome in nomes:
        contagens_bronze[nome] = ingerir_tabela(spark, base_dir_raw, catalog, sistema, nome)

# COMMAND ----------
# Compara contra o que raw_conferencia (tarefa anterior no MESMO run, via
# depends_on) acabou de registrar. bronze._raw_arquivos.linhas ja e'
# "linhas do arquivo menos o header" -- comparamos direto contra COUNT(*)
# da tabela bronze, sem subtrair de novo.
linhas_controle = spark.sql(
    f"SELECT arquivo, linhas FROM {catalog}.bronze._raw_arquivos"
).collect()
contagens_esperadas = {row["arquivo"].removesuffix(".csv"): row["linhas"] for row in linhas_controle}

divergencias = comparar_contagens(contagens_bronze, contagens_esperadas)

# COMMAND ----------
print(f"{'tabela':<16} {'linhas_bronze':>14} {'linhas_controle':>16}  status")
for nome in sorted(contagens_bronze, key=lambda n: -contagens_bronze[n]):
    esperado = contagens_esperadas.get(nome)
    status = "OK" if esperado == contagens_bronze[nome] else "DIVERGENTE"
    print(f"{nome:<16} {contagens_bronze[nome]:>14} {esperado!s:>16}  {status}")

if divergencias:
    raise Exception("Divergencia entre bronze e bronze._raw_arquivos:\n" + "\n".join(divergencias))
