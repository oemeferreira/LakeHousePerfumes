# Bronze — Ingestão CSV → Delta, Contagens Conferidas e `depends_on` Real — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`) para rastreamento.

**Goal:** Entregar o segundo dos 6 prompts da série "Jornada de Dados": criar a camada bronze do bundle `rotaperfume` — 10 tabelas Delta (`{catalog}.bronze.{tabela}`), uma por CSV já conferido no Volume `bronze.raw`, sem nenhuma limpeza ou conversão de tipo (tudo string, só ganham `_ingerido_em`/`_arquivo_origem`), com `COMMENT` indicando o sistema de origem. A tarefa `bronze_ingestao` entra no job `rotaperfume_pipeline` com `depends_on: raw_conferencia`, de forma que uma conferência que falhar impede a bronze de rodar — provado contra o workspace real, não só lido no YAML.

**Architecture:** Mesma divisão em duas camadas já validada no prompt anterior (`raw/conferencia_lib.py` + `raw/conferencia.py`): `src/bronze/ingestao_lib.py` é um módulo **puro** (`nome_tabela`, `comparar_contagens`), sem `dbutils`/`spark`, testável com `pytest` comum em `tests_unit/`; `src/bronze/ingestao.py` é o notebook serverless fino que só faz o que exige runtime Databricks (ler CSV com Spark, escrever Delta, gravar `COMMENT`). O módulo puro **reaproveita** `ARQUIVOS_ESPERADOS`/`caminho_arquivo` de `raw.conferencia_lib` (pacote irmão) em vez de redefinir a lista das 10 tabelas — único ponto novo de design em relação ao prompt anterior é o **import cruzado entre duas pastas-irmãs** (`src/bronze/` precisa importar tanto `bronze.ingestao_lib`, mesma pasta, quanto `raw.conferencia_lib`, pasta irmã). A solução adotada — subir `sys.path` até `src/` (pai de ambas) e importar com prefixo de pacote (`from raw.conferencia_lib import ...`, `from bronze.ingestao_lib import ...`) — é a mesma convenção que `pyproject.toml` já usa para os testes (`pythonpath = ["src"]`), então fica consistente entre pytest e notebook real. Confirmado nesta sessão via `databricks bundle summary -o json` que o notebook `raw/conferencia` já deployado fica em `.../dev/files/src/raw/conferencia` — ou seja, o bundle sincroniza a árvore inteira de `src/` preservando a estrutura de pastas, então `os.path.dirname(_NOTEBOOK_DIR)` (subir de `src/bronze` para `src/`) chega exatamente no diretório que contém as duas pastas-irmãs `raw/` e `bronze/`. Como resíduo de risco (o `conferencia.py` original só provou que `__file__` funciona para import *na mesma pasta*; isso é a primeira vez que o import cruza para uma pasta *irmã*), o notebook ganha um `assert` defensivo logo após montar `_SRC_DIR`, que falha com mensagem acionável (lista o conteúdo do diretório) em vez de um `ModuleNotFoundError` genérico — a prova definitiva ainda assim vem do deploy+run real da Tarefa 4. Não foi escolhida a alternativa de duplicar `ARQUIVOS_ESPERADOS` dentro de `bronze/` (arriscaria a lista de tabelas divergir entre raw e bronze) nem a de fundir os dois módulos puros em um só (misturaria responsabilidades de duas camadas já commitadas e validadas separadamente).

**Tech Stack:** Databricks Asset Bundle (DAB) YAML, Databricks CLI v1.13.0 (perfil `Emerson`), notebook Python serverless (PySpark), Unity Catalog (schema `bronze`, Delta tables), SQL warehouse serverless `2c807bf97ff3fec4`, `pytest` local via `uv`.

## Global Constraints

- **Profile obrigatório:** `Emerson` — único profile válido em `databricks auth profiles` (host `https://dbc-61d9738c-00ad.cloud.databricks.com`, confirmado nesta sessão). Todo comando `databricks` passa `--profile Emerson` explicitamente. O prompt original da aula usa `projeto-dados-ia`; **ignore-o**, é de outro workspace.
- **Warehouse:** `2c807bf97ff3fec4`.
- **`uv` não está no PATH** neste ambiente (confirmado em sessão anterior) — o atalho do WinGet não foi criado. Rode `uv --version` primeiro; se falhar, use o caminho completo `/c/Users/emers/AppData/Local/Microsoft/WinGet/Packages/astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe/uv.exe` em vez de `uv` nos comandos abaixo.
- **`uv run pytest` pode dar `PermissionError`** no diretório padrão de temp do Windows neste ambiente sandboxed (não é bug no código) — se acontecer, adicione `--basetemp=<diretório gravável>` (por exemplo, um subdiretório do scratchpad da sessão, ou de dentro do próprio repo, fora do que é commitado).
- **`tests/conftest.py` abre uma `DatabricksSession` real incondicionalmente** para qualquer teste dentro de `rotaperfume/tests/`. Os testes puros deste prompt vivem em `rotaperfume/tests_unit/` (irmão de `tests/`) e são invocados com `uv run pytest tests_unit/`, nunca `uv run pytest` genérico.
- **Todos os comandos bash/`databricks` assumem `cwd = rotaperfume/`.** Use caminho absoluto ao fazer `cd` — nunca `cd rotaperfume` relativo (já causou pasta aninhada `rotaperfume/rotaperfume/` numa sessão anterior).
- **NÃO mexer em:** `databricks.yml`, `resources/catalogo.yml`, `scripts/criar-catalogo.sh`, `scripts/subir-raw.sh`, `src/raw/conferencia.py`, `src/raw/conferencia_lib.py`, `tests_unit/test_conferencia_lib.py` — todos já prontos, corretos e deployados.
- **Escopo travado no "Bronze sem limpeza":** nenhuma conversão de tipo, nenhuma remoção de sujeira — tudo como string, exceto `_ingerido_em`/`_arquivo_origem`. Sujeira é assunto do próximo prompt (silver).
- **Ações contra o workspace real** (`databricks bundle deploy`, `databricks bundle run`, `databricks fs rm`) alteram recursos de verdade — cada uma tem nota pedindo confirmação explícita do usuário antes de rodar.
- **Convenção de commit:** mensagens curtas em português, `feat(rotaperfume): <o que foi adicionado>`, `git add` de arquivos específicos (nunca `git add -A`).
- **Contagens de referência (seed 42, já conferidas em `bronze._raw_arquivos` nesta sessão):** produtos 292 · pedidos 28.729 · itens_pedido 197.724 · pagamentos 27.772 · estoque 8.400 · clientes 3.040 · vendedores 42 · carteira 3.637 · oportunidades 5.979 · visitas 37.936 — total 313.551.

---

## File Structure

```
rotaperfume/
├── resources/
│   └── pipeline.job.yml            # MODIFICAR — + tarefa bronze_ingestao, depends_on raw_conferencia
├── src/
│   └── bronze/
│       ├── ingestao_lib.py         # NOVO — modulo puro: nome_tabela, comparar_contagens
│       └── ingestao.py             # NOVO — notebook serverless: le CSV, grava Delta, confere contagens
└── tests_unit/
    └── test_ingestao_lib.py        # NOVO — testes pytest reais do modulo puro
```

---

### Task 1: `src/bronze/ingestao_lib.py` — módulo puro + testes pytest reais

**Files:**
- Create: `rotaperfume/src/bronze/ingestao_lib.py`
- Create: `rotaperfume/tests_unit/test_ingestao_lib.py`

**Interfaces:**
- Produces: `nome_tabela(catalog: str, nome: str) -> str`, `comparar_contagens(contagens_bronze: dict[str, int], contagens_esperadas: dict[str, int]) -> list[str]` — consumidos pelo notebook `ingestao.py` (Tarefa 2).
- Consumes: nada de novo — só stdlib. Os testes importam `ARQUIVOS_ESPERADOS` de `raw.conferencia_lib` (pacote irmão, já existente) para provar que a lista de tabelas não foi redefinida.

- [ ] **Step 1: Criar o módulo puro**

```python
# rotaperfume/src/bronze/ingestao_lib.py
"""Ingestao bronze -- logica pura, sem dbutils/spark.

Mesma divisao de raw/conferencia_lib.py: aqui fica so o que nao depende de
Spark (montar nome de tabela, comparar duas contagens), para testar com
pytest comum, sem cluster. O notebook 'ingestao.py' (mesma pasta) e' quem
le CSV com Spark, escreve Delta e chama estas funcoes.

Reaproveita ARQUIVOS_ESPERADOS/caminho_arquivo de raw.conferencia_lib
(pacote irmao) em vez de redefinir a lista das 10 tabelas -- o import
cruzado (via sys.path em src/, pai de raw/ e bronze/) acontece no notebook
ingestao.py, nao aqui.
"""
from __future__ import annotations


def nome_tabela(catalog: str, nome: str) -> str:
    """Monta o nome completo de 3 niveis {catalog}.bronze.{nome}."""
    return f"{catalog}.bronze.{nome}"


def comparar_contagens(
    contagens_bronze: dict[str, int], contagens_esperadas: dict[str, int]
) -> list[str]:
    """Compara contagem de linhas por tabela. Retorna lista de mensagens de
    divergencia (vazia se tudo bate). Cobre tanto valor diferente quanto uma
    tabela existir so de um lado (bronze sem controle correspondente, ou
    controle sem tabela bronze ingerida)."""
    divergencias: list[str] = []
    todas_as_chaves = sorted(set(contagens_bronze) | set(contagens_esperadas))
    for nome in todas_as_chaves:
        bronze = contagens_bronze.get(nome)
        esperado = contagens_esperadas.get(nome)
        if bronze is None:
            divergencias.append(
                f"{nome}: existe em bronze._raw_arquivos (linhas={esperado}) "
                "mas nao foi ingerido em bronze"
            )
        elif esperado is None:
            divergencias.append(
                f"{nome}: tabela bronze existe (linhas={bronze}) mas nao tem "
                "registro em bronze._raw_arquivos"
            )
        elif bronze != esperado:
            divergencias.append(
                f"{nome}: bronze tem {bronze} linha(s), "
                f"bronze._raw_arquivos esperava {esperado}"
            )
    return divergencias
```

- [ ] **Step 2: Criar os testes reais, sem rede**

```python
# rotaperfume/tests_unit/test_ingestao_lib.py
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
```

- [ ] **Step 3: Rodar os testes isolados (sem workspace, sem rede)**

Run (a partir de `rotaperfume/`):
```bash
uv run pytest tests_unit/ -v
```
Se `uv` não for encontrado, use o caminho completo (ver Global Constraints). Se der `PermissionError` de tempdir, adicione `--basetemp=<dir gravável>`.

Expected: **11 passed** (5 de `test_conferencia_lib.py` já existentes + 6 novos de `test_ingestao_lib.py`), execução em menos de 1 segundo, sem tentativa de conexão de rede.

- [ ] **Step 4: Commit**

```bash
git add src/bronze/ingestao_lib.py tests_unit/test_ingestao_lib.py
git commit -m "feat(rotaperfume): modulo puro de ingestao bronze (nome_tabela, comparar_contagens) + testes"
```

---

### Task 2: `src/bronze/ingestao.py` — notebook serverless de ingestão CSV → Delta

**Files:**
- Create: `rotaperfume/src/bronze/ingestao.py`

**Interfaces:**
- Consumes: `ARQUIVOS_ESPERADOS`, `caminho_arquivo` de `raw.conferencia_lib` (pasta irmã); `nome_tabela`, `comparar_contagens` de `bronze.ingestao_lib` (mesma pasta, Tarefa 1); os 10 CSVs em `/Volumes/{catalog}/bronze/raw/{sistema}/{nome}.csv`; a tabela `{catalog}.bronze._raw_arquivos` já gravada por `raw_conferencia` no mesmo run.
- Produces: 10 tabelas Delta `{catalog}.bronze.{nome}` (overwrite), cada uma com `COMMENT` citando o sistema de origem; falha (`raise Exception`) se alguma contagem divergir de `bronze._raw_arquivos`.

- [ ] **Step 1: Criar o notebook**

```python
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

from raw.conferencia_lib import ARQUIVOS_ESPERADOS, caminho_arquivo
from bronze.ingestao_lib import nome_tabela, comparar_contagens

# COMMAND ----------
from pyspark.sql.functions import current_timestamp, lit


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
    print(f"{nome:<16} {contagens_bronze[nome]:>14} {str(esperado):>16}  {status}")

if divergencias:
    raise Exception("Divergencia entre bronze e bronze._raw_arquivos:\n" + "\n".join(divergencias))
```

- [ ] **Step 2: Commit**

```bash
git add src/bronze/ingestao.py
git commit -m "feat(rotaperfume): notebook de ingestao bronze (CSV -> Delta, sem limpeza)"
```

(A validação real deste notebook — deploy + execução — acontece na Tarefa 4, junto com a tarefa `bronze_ingestao` da Tarefa 3, porque um `notebook_task` sozinho fora de um job não roda via `bundle run`.)

---

### Task 3: `resources/pipeline.job.yml` — tarefa `bronze_ingestao` com `depends_on`

**Files:**
- Modify: `rotaperfume/resources/pipeline.job.yml`

**Interfaces:**
- Consumes: `${var.catalog}`; notebook `src/bronze/ingestao.py` (Tarefa 2); tarefa `raw_conferencia` já existente (referenciada por `task_key`).
- Produces: job `rotaperfume_pipeline` com 2 tarefas (`raw_conferencia` → `bronze_ingestao`), onde a segunda só roda se a primeira suceder.

- [ ] **Step 1: Editar o arquivo — conteúdo integral resultante**

```yaml
# Job rotaperfume_pipeline -- cresce a cada prompt da serie "Jornada de Dados":
#   Prompt 1: raw_conferencia -- confere a chegada dos 10 CSVs no Volume
#             bronze.raw. NAO cria tabela bronze.
#   Prompt 2 (este arquivo): + bronze_ingestao -- CSV -> tabelas Delta em
#             bronze, sem limpeza, so depois de raw_conferencia passar.
#   Prompt 3: + silver_transformacao -- limpeza e conformidade em silver
#   Prompt 4: + gold_agregacao       -- metricas de negocio em gold
#   Prompt 5: + qualidade_dados      -- testes de qualidade dos dados
#   Prompt 6: + orquestracao final e documentacao (dashboard/Genie)
resources:
  jobs:
    rotaperfume_pipeline:
      name: rotaperfume_pipeline
      tasks:
        - task_key: raw_conferencia
          notebook_task:
            notebook_path: ../src/raw/conferencia.py
            base_parameters:
              catalog: ${var.catalog}
        - task_key: bronze_ingestao
          depends_on:
            - task_key: raw_conferencia
          notebook_task:
            notebook_path: ../src/bronze/ingestao.py
            base_parameters:
              catalog: ${var.catalog}
      schedule:
        quartz_cron_expression: "0 0 6 * * ?"
        timezone_id: America/Sao_Paulo
        pause_status: UNPAUSED
```

- [ ] **Step 2: Validar (estrito)**

Run:
```bash
databricks bundle validate --target dev --profile Emerson --strict
```
Expected: sem erros nem warnings; lista o job `rotaperfume_pipeline` com as duas tarefas, `bronze_ingestao` mostrando `depends_on: raw_conferencia`.

- [ ] **Step 3: Commit**

```bash
git add resources/pipeline.job.yml
git commit -m "feat(rotaperfume): tarefa bronze_ingestao no job, dependente de raw_conferencia"
```

---

### Task 4: Deploy, execução real e verificação das 10 contagens exatas

**Files:** nenhum arquivo novo — só executa o que as Tarefas 1–3 versionaram, contra o workspace real.

**Interfaces:**
- Consumes: tudo (notebook, tarefa, dados no Volume, `bronze._raw_arquivos`).
- Produces: as 10 tabelas Delta em `lakehouse_rotaperfume.bronze` com as contagens exatas de referência e `COMMENT` preenchido.

- [ ] **Step 1: Deploy**

> Confirme com o usuário antes deste passo — publica a nova tarefa do job no workspace real.

Run (a partir de `rotaperfume/`):
```bash
databricks bundle deploy --target dev --profile Emerson
```
Expected: sem erro; `databricks bundle summary --target dev --profile Emerson -o json` mostra as duas tarefas em `resources.jobs.rotaperfume_pipeline.tasks`.

- [ ] **Step 2: Rodar o pipeline completo**

> Confirme com o usuário antes deste passo — dispara uma execução real do job (lê o Volume, escreve 10 tabelas Delta).

Run:
```bash
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: termina com sucesso (exit code 0); as duas tarefas (`raw_conferencia`, depois `bronze_ingestao`) aparecem como `SUCCESS`.

- [ ] **Step 3: Verificar as 10 contagens exatas contra `bronze._raw_arquivos`**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
WITH bronze_contagens AS (
  SELECT 'produtos' AS tabela, COUNT(*) AS linhas FROM lakehouse_rotaperfume.bronze.produtos
  UNION ALL SELECT 'pedidos', COUNT(*) FROM lakehouse_rotaperfume.bronze.pedidos
  UNION ALL SELECT 'itens_pedido', COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido
  UNION ALL SELECT 'pagamentos', COUNT(*) FROM lakehouse_rotaperfume.bronze.pagamentos
  UNION ALL SELECT 'estoque', COUNT(*) FROM lakehouse_rotaperfume.bronze.estoque
  UNION ALL SELECT 'clientes', COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes
  UNION ALL SELECT 'vendedores', COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores
  UNION ALL SELECT 'carteira', COUNT(*) FROM lakehouse_rotaperfume.bronze.carteira
  UNION ALL SELECT 'oportunidades', COUNT(*) FROM lakehouse_rotaperfume.bronze.oportunidades
  UNION ALL SELECT 'visitas', COUNT(*) FROM lakehouse_rotaperfume.bronze.visitas
)
SELECT b.tabela, b.linhas AS linhas_bronze, r.linhas AS linhas_controle,
       CASE WHEN b.linhas = r.linhas THEN 'OK' ELSE 'DIVERGENTE' END AS status
FROM bronze_contagens b
JOIN lakehouse_rotaperfume.bronze._raw_arquivos r ON r.arquivo = b.tabela || '.csv'
ORDER BY b.linhas DESC
"
```
Expected: 10 linhas, todas `status = 'OK'`, com `linhas_bronze` batendo exatamente com as contagens de referência (produtos 292, pedidos 28.729, itens_pedido 197.724, pagamentos 27.772, estoque 8.400, clientes 3.040, vendedores 42, carteira 3.637, oportunidades 5.979, visitas 37.936).

Run (total):
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT SUM(linhas) AS total_linhas FROM lakehouse_rotaperfume.bronze._raw_arquivos
"
```
Expected: `total_linhas = 313551`.

- [ ] **Step 4: Verificar metadados — `_ingerido_em`/`_arquivo_origem` e `COMMENT`**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT _ingerido_em, _arquivo_origem FROM lakehouse_rotaperfume.bronze.produtos LIMIT 1
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT table_name, comment FROM lakehouse_rotaperfume.information_schema.tables
WHERE table_schema = 'bronze' AND table_name != '_raw_arquivos'
ORDER BY table_name
"
```
Expected: a primeira query devolve um timestamp recente em `_ingerido_em` e um caminho terminando em `/erp/produtos.csv` em `_arquivo_origem`; a segunda lista as 10 tabelas, cada uma com `comment` não nulo citando o sistema de origem (`erp` ou `crm`).

Não há Step de commit aqui — nenhum arquivo novo.

---

### Task 5: Prova real de que `depends_on` bloqueia a bronze quando a conferência falha

**Files:** nenhum arquivo novo — usa o que as Tarefas 1–4 já deployaram, quebrando e restaurando um arquivo real no Volume.

**Interfaces:**
- Consumes: job `rotaperfume_pipeline` deployado (Tarefa 4); `scripts/subir-raw.sh` (já existente, não tocado).
- Produces: evidência de que `bronze_ingestao` fica `SKIPPED` quando `raw_conferencia` falha, e que tudo volta a `SUCCESS` após restaurar o arquivo.

- [ ] **Step 1: Quebrar de propósito — remover um arquivo real do Volume**

> Confirme com o usuário antes deste passo — remove um arquivo real do Volume (recuperável no Step 4 com `scripts/subir-raw.sh`).

Run:
```bash
databricks fs rm dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp/pagamentos.csv --profile Emerson
```

- [ ] **Step 2: Rodar o pipeline e confirmar que ele falha**

> Confirme com o usuário antes deste passo — dispara uma execução real que deve falhar de propósito.

Run:
```bash
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: termina com erro (exit code != 0); a mensagem de erro referencia a tarefa `raw_conferencia` e cita `pagamentos.csv` como arquivo ausente.

- [ ] **Step 3: Confirmar via API que `bronze_ingestao` ficou `SKIPPED` (não rodou e não falhou)**

Run (comandos e parsing já testados nesta sessão contra o job real):
```bash
JOB_ID=$(databricks bundle summary --target dev --profile Emerson -o json \
  | python -c "import json,sys; print(json.load(sys.stdin)['resources']['jobs']['rotaperfume_pipeline']['id'])")

RUN_ID=$(databricks jobs list-runs --job-id "$JOB_ID" --profile Emerson --limit 1 -o json \
  | python -c "import json,sys; print(json.load(sys.stdin)[0]['run_id'])")

databricks jobs get-run "$RUN_ID" --profile Emerson -o json \
  | python -c "
import json, sys
run = json.load(sys.stdin)
for t in run['tasks']:
    st = t['state']
    print(t['task_key'], '->', st.get('life_cycle_state'), st.get('result_state'))
"
```
Expected:
```
raw_conferencia -> TERMINATED FAILED
bronze_ingestao -> SKIPPED None
```
Isso prova que a ordem (`depends_on`) foi respeitada: `bronze_ingestao` nunca chegou a executar porque `raw_conferencia` falhou — não é um job "verde" com 9 arquivos, é um job que para.

- [ ] **Step 4: Restaurar e confirmar que tudo volta a passar**

Run:
```bash
bash scripts/subir-raw.sh Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: sucesso (exit code 0).

Repita a checagem de estado das tarefas:
```bash
RUN_ID=$(databricks jobs list-runs --job-id "$JOB_ID" --profile Emerson --limit 1 -o json \
  | python -c "import json,sys; print(json.load(sys.stdin)[0]['run_id'])")

databricks jobs get-run "$RUN_ID" --profile Emerson -o json \
  | python -c "
import json, sys
run = json.load(sys.stdin)
for t in run['tasks']:
    st = t['state']
    print(t['task_key'], '->', st.get('life_cycle_state'), st.get('result_state'))
"
```
Expected:
```
raw_conferencia -> TERMINATED SUCCESS
bronze_ingestao -> TERMINATED SUCCESS
```

Repita a query de contagens da Tarefa 4, Step 3, e confirme de novo `total_linhas = 313551` e as 10 linhas com `status = 'OK'`.

Não há Step de commit nesta tarefa (nenhum arquivo novo).

---

## Self-Review

**Cobertura dos 3 itens do prompt da aula:**
1. `src/bronze/ingestao.py` (leitura como string, sem inferSchema, sem multiLine, `_ingerido_em`/`_arquivo_origem`, função única em loop sobre as 10 tabelas, comparação de contagens com `bronze._raw_arquivos`, `COMMENT` por tabela) → Tarefas 1 (lógica pura) + 2 (notebook).
2. `resources/pipeline.job.yml` com `bronze_ingestao` e `depends_on: raw_conferencia` → Tarefa 3.
3. Rodar `bundle deploy`/`bundle run` e mostrar a saída (usando profile `Emerson`, não `projeto-dados-ia`) → Tarefa 4.

**Correção explícita de uma armadilha do prompt original:** "linhas da tabela = linhas do arquivo menos o header" já está pré-calculado em `bronze._raw_arquivos.linhas` (o `conferir_arquivos` de `raw/conferencia_lib.py` já faz `total_linhas - 1`). O notebook e a query de verificação (Tarefa 4, Step 3) comparam `COUNT(*)` da tabela bronze **diretamente** contra `bronze._raw_arquivos.linhas`, sem subtrair de novo — evitando um off-by-one que descontaria o header duas vezes.

**Ideia de design (módulo puro + reaproveitamento cruzado + `sys.path` em `src/`):** verificado nesta sessão via `databricks bundle summary -o json` que o bundle sincroniza `src/` preservando a árvore de diretórios — logo `os.path.dirname(_NOTEBOOK_DIR)` a partir de `src/bronze` chega no mesmo `src/` que contém `raw/`, igual ao `pythonpath=["src"]` do pytest. Risco residual mitigado com um `assert` que falha com mensagem acionável (lista `os.listdir(_SRC_DIR)`) em vez de um `ModuleNotFoundError` opaco, caso a suposição de estrutura de diretórios não se confirme em produção. Alternativas descartadas: duplicar `ARQUIVOS_ESPERADOS` em `bronze/` (arriscaria divergência entre raw e bronze com o tempo); fundir os dois módulos puros em um só (misturaria responsabilidades de camadas já commitadas separadamente).

**Prova de `depends_on`:** dupla — sintática (`databricks bundle validate --strict` na Tarefa 3 mostra o `depends_on` no YAML) e real contra o job (Tarefa 5: remove `pagamentos.csv`, `bundle run` falha, `jobs get-run` confirma `bronze_ingestao` como `SKIPPED` via API — não apenas inferido do exit code — depois restaura e confirma `SUCCESS`/`SUCCESS` nas duas tarefas).

**Comandos pré-validados ao vivo nesta sessão de planejamento (somente leitura, sem alterar nada):** `databricks bundle summary -o json` (estrutura confirmada: `resources.jobs.rotaperfume_pipeline.id` = `"1108850796216084"`), `databricks jobs list-runs --job-id -o json` (lista bare, `[0]['run_id']` confirmado), `databricks jobs get-run RUN_ID -o json` com o parsing Python exato do plano (retornou `raw_conferencia -> TERMINATED SUCCESS` contra o run real existente), `python --version` (3.14.6, disponível no PATH), e os CSVs confirmados CRLF via `xxd` (`0d0a` na quebra de linha de `produtos.csv`).

**Checagem de placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem código ou comando completo e uma saída esperada concreta.

**Consistência de tipos/nomes:** `comparar_contagens(contagens_bronze, contagens_esperadas) -> list[str]` é chamada com a mesma assinatura nos testes e no notebook; `nome_tabela(catalog, nome)` é usada tanto para escrever quanto para nomear a query de verificação; a chave do job `rotaperfume_pipeline` e das tarefas `raw_conferencia`/`bronze_ingestao` são as mesmas em todos os comandos de verificação da Tarefa 4 e 5.

### Critical Files for Implementation
- `rotaperfume/src/bronze/ingestao_lib.py`
- `rotaperfume/src/bronze/ingestao.py`
- `rotaperfume/resources/pipeline.job.yml`
- `rotaperfume/tests_unit/test_ingestao_lib.py`
- `rotaperfume/src/raw/conferencia_lib.py` (referência read-only para o import cruzado)
