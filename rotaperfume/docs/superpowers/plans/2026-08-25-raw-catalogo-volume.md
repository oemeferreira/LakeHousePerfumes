# Raw — Catálogo em Código e Chegada do Dado no Volume — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o layout do Unity Catalog do `rotaperfume` (catálogo + schemas bronze/silver/gold + volume de pouso) em um Databricks Asset Bundle reproduzível, subir os 10 CSVs reais de `dados/` para o Volume, e ter uma tarefa agendada que confere a chegada de cada arquivo antes de qualquer camada bronze existir.

**Architecture:** O bundle `rotaperfume` ganha `resources/catalogo.yml` (schemas `bronze`/`silver`/`gold` + volume `bronze.raw`, do tipo MANAGED) e `resources/pipeline.job.yml` (job `rotaperfume_pipeline`, uma tarefa serverless). Como a API do Unity Catalog usada pelo bundle recusa criar o catálogo neste workspace (falta managed location), um script separado (`scripts/criar-catalogo.sh`) cria o catálogo via SQL antes do primeiro deploy. Depois do deploy, `scripts/subir-raw.sh` copia os CSVs de `dados/erp` e `dados/crm` (raiz do repo) para o Volume, e o notebook serverless `src/raw/conferencia.py` — rodando como a única tarefa do job — confere que os 10 arquivos chegaram não vazios e grava o resultado na tabela de controle `bronze._raw_arquivos`.

**Tech Stack:** Databricks Asset Bundle (DAB) YAML, Databricks CLI v1.13.0, bash, notebook Python serverless (PySpark/`dbutils`), Unity Catalog (catálogo/schema/volume), SQL warehouse serverless.

## Global Constraints

- **Profile obrigatório:** `Emerson` — único profile válido em `databricks auth profiles`, aponta para `https://dbc-61d9738c-00ad.cloud.databricks.com` (mesmo host já presente em `databricks.yml`). Todo comando `databricks` deve passar `--profile Emerson` explicitamente — cada chamada Bash roda em uma shell separada, então `export DATABRICKS_CONFIG_PROFILE=...` isolado em um passo não sobrevive ao próximo.
- **Warehouse:** `2c807bf97ff3fec4` (Serverless Starter Warehouse) — descoberto via `databricks warehouses list --profile Emerson`, substitui o `666be37e3fededf2` de exemplo do prompt da aula (que é de outro workspace).
- **Catálogo:** `lakehouse_rotaperfume` — ainda não existe neste workspace (`databricks catalogs list` só mostra `workspace`/`samples`/`system`). Compartilhado por `dev` e `prod`: os dois targets apontam para o MESMO catálogo e os MESMOS schemas `bronze`/`silver`/`gold` — eles se diferenciam pelo status de agendamento do job e pelo `root_path`/permissões de deploy, não por catálogo ou schema separados.
- **NÃO use `mode: development` no target `dev`** — ele prefixa todo recurso implantado (inclusive os SCHEMAS do Unity Catalog) com `[dev <usuario>]`/`dev_<usuario>_`, quebrando o SQL que espera `lakehouse_rotaperfume.bronze`. Use `presets: { trigger_pause_status: PAUSED }` em vez disso.
- **Todos os comandos `bash`/`databricks` dos passos abaixo assumem `cwd = rotaperfume/`**, seguindo a convenção já documentada em `CLAUDE.md`.
- **Ações contra workspace real:** os passos que rodam `criar-catalogo.sh`, `bundle deploy`, `subir-raw.sh` e `bundle run` criam/alteram recursos de verdade no workspace Databricks do usuário (catálogo, schemas, volume, job, dados). Confirme com o usuário antes de rodar cada um desses passos ao executar este plano — não são reversíveis com um simples `git revert`.
- **Sem testes pytest para os passos de infraestrutura/notebook:** este projeto já testa contra um cluster real (`rotaperfume/tests/conftest.py` inicializa uma `DatabricksSession` de verdade, sem camada de mock) — não existe unidade isolada por trás de um YAML de bundle ou de um notebook orientado a `dbutils`/`spark`. A verificação desses passos é o próprio `databricks bundle validate/deploy/run` mais consultas SQL/CLI contra o workspace real, exatamente como o material de referência (`.llm/prompt01.md`) já verifica a feature.
- **Escopo travado no "Raw":** hoje o dado só chega no Volume — não criar tabelas Delta na camada bronze (fica para o próximo prompt da série).
- **Repositório git:** já inicializado na raiz do repo (`git init` + commit inicial rodados como setup, antes da Tarefa 1) — branch `master`, sem remoto, sem push.

---

## File Structure

```
rotaperfume/
├── databricks.yml                  # MODIFICAR — variables (catalog/warehouse_id), targets dev/prod
├── scripts/
│   ├── criar-catalogo.sh           # NOVO — cria o catálogo via SQL (fora do bundle)
│   └── subir-raw.sh                # NOVO — sobe dados/erp e dados/crm para o Volume
├── resources/
│   ├── catalogo.yml                # NOVO — schemas bronze/silver/gold + volume bronze.raw
│   └── pipeline.job.yml            # NOVO — job rotaperfume_pipeline (1 tarefa: raw_conferencia)
└── src/
    └── raw/
        └── conferencia.py          # NOVO — notebook serverless de conferência de chegada

CLAUDE.md                           # MODIFICAR (raiz) — atualiza a convenção de catálogo/schema
```

---

### Task 1: `databricks.yml` — variáveis e targets prontos para o medallion

**Files:**
- Modify: `rotaperfume/databricks.yml`
- Modify: `CLAUDE.md:57-60` (raiz do repo)

**Interfaces:**
- Produces: variáveis de bundle `${var.catalog}` (default `lakehouse_rotaperfume`) e `${var.warehouse_id}` (default `2c807bf97ff3fec4`), consumidas pelas Tarefas 3 e 5 nos arquivos `resources/*.yml`.
- Produces: target `dev` sem `mode: development`, com `presets.trigger_pause_status: PAUSED` — a Tarefa 5 depende disso para o job nascer pausado em dev.

- [ ] **Step 1: Editar `rotaperfume/databricks.yml`**

Substitua o conteúdo inteiro do arquivo por:

```yaml
# This is a Declarative Automation Bundle definition for rotaperfume.
# See https://docs.databricks.com/dev-tools/bundles/index.html for documentation.
bundle:
  name: rotaperfume
  uuid: 029afe05-def4-4552-add8-dfa440bc6ea5

include:
  - resources/*.yml

# Variable declarations. dev e prod compartilham o MESMO catalogo e os MESMOS
# schemas (bronze/silver/gold) -- nao ha um catalogo por ambiente aqui.
variables:
  catalog:
    description: Catalogo do Unity Catalog com os schemas bronze/silver/gold
    default: lakehouse_rotaperfume
  warehouse_id:
    description: SQL warehouse usado para consultas ad-hoc de setup
    default: 2c807bf97ff3fec4 # Serverless Starter Warehouse

targets:
  dev:
    default: true
    # NAO use 'mode: development' aqui: ele prefixa o nome de TODO recurso
    # implantado com '[dev <usuario>]' -- inclusive os SCHEMAS do Unity
    # Catalog, que virariam 'dev_fulano_bronze' e quebrariam todo o SQL que
    # espera 'lakehouse_rotaperfume.bronze'. Isolamos so o agendamento do
    # job (pausado em dev), nao o catalogo/schema.
    presets:
      trigger_pause_status: PAUSED
    workspace:
      host: https://dbc-61d9738c-00ad.cloud.databricks.com
  prod:
    mode: production
    workspace:
      host: https://dbc-61d9738c-00ad.cloud.databricks.com
      # We explicitly deploy to /Workspace/Users/emersonfab06@gmail.com to make sure we only have a single copy.
      root_path: /Workspace/Users/emersonfab06@gmail.com/.bundle/${bundle.name}/${bundle.target}
    permissions:
      - user_name: emersonfab06@gmail.com
        level: CAN_MANAGE
```

- [ ] **Step 2: Atualizar a convenção de catálogo/schema em `CLAUDE.md` (raiz)**

Em `CLAUDE.md`, na seção `### Bundle configuration (databricks.yml)`, troque:

```markdown
- Two targets, both pointed at the same workspace host:
  - `dev` (default): `mode: development`, catalog `lakehouse_rotaperfume`, schema `dev`.
  - `prod`: `mode: production`, catalog `lakehouse_rotaperfume`, schema `prod`, deploys to a fixed `root_path` under the workspace user, `CAN_MANAGE` permission scoped to that user.
- New pipelines/jobs should follow this catalog/schema convention (`lakehouse_rotaperfume.<dev|prod>`) rather than inventing new catalogs.
```

por:

```markdown
- Two targets, both pointed at the same workspace host and sharing the same catalog/schemas (`lakehouse_rotaperfume.{bronze,silver,gold}`):
  - `dev` (default): no `mode: development` (it would prefix Unity Catalog schema names and break the medallion SQL) — `presets.trigger_pause_status: PAUSED` keeps the job schedule off instead.
  - `prod`: `mode: production`, deploys to a fixed `root_path` under the workspace user, `CAN_MANAGE` permission scoped to that user.
- New pipelines/jobs should use the medallion schemas `lakehouse_rotaperfume.{bronze,silver,gold}` (shared by dev and prod) rather than inventing new catalogs or schemas.
```

- [ ] **Step 3: Validar**

Run (a partir de `rotaperfume/`):
```bash
databricks bundle validate --target dev --profile Emerson
```
Expected: saída sem erro, sem recursos listados ainda (nenhum `resources/*.yml` existe até a Tarefa 3) — apenas confirma que o `databricks.yml` está sintaticamente correto e a autenticação funciona.

- [ ] **Step 4: Commit**

```bash
git add databricks.yml ../CLAUDE.md
git commit -m "feat(rotaperfume): variaveis catalog/warehouse_id e targets sem trap de mode:development"
```

---

### Task 2: `scripts/criar-catalogo.sh` — cria o catálogo via SQL (real, fora do bundle)

**Files:**
- Create: `rotaperfume/scripts/criar-catalogo.sh`

**Interfaces:**
- Consumes: nenhuma (constantes próprias — `CATALOG`/`WAREHOUSE_ID` espelham os defaults declarados em `databricks.yml` na Tarefa 1).
- Produces: o catálogo `lakehouse_rotaperfume` existindo no workspace, pré-requisito para a Tarefa 3 (o bundle cria schemas *dentro* dele, não o catálogo em si).

- [ ] **Step 1: Criar o script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Cria o catalogo lakehouse_rotaperfume via SQL -- de proposito FORA do
# bundle (nao como resources.catalogs no databricks.yml).
#
# POR QUE NAO ESTA NO BUNDLE: quando o workspace tem o Default Storage
# habilitado (comum em contas gratuitas / Free Edition), a API do Unity
# Catalog usada pelo provider Terraform do bundle RECUSA criar catalogo --
# ela exige um MANAGED LOCATION que essas contas nao tem, e falha com:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL abaixo nao passa por essa restricao: usa o storage padrao
# do metastore implicitamente, sem exigir managed location explicita.

if [ $# -lt 1 ]; then
  echo "uso: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
CATALOG="lakehouse_rotaperfume"       # mesmo default de var.catalog em databricks.yml
WAREHOUSE_ID="2c807bf97ff3fec4"       # mesmo default de var.warehouse_id em databricks.yml

databricks experimental aitools tools query \
  "CREATE CATALOG IF NOT EXISTS ${CATALOG}" \
  --warehouse "$WAREHOUSE_ID" \
  --profile "$PROFILE"
```

- [ ] **Step 2: Tornar executável**

```bash
chmod +x scripts/criar-catalogo.sh
```

- [ ] **Step 3: Rodar contra o workspace real e conferir**

> Confirme com o usuário antes deste passo — cria um catálogo de verdade no workspace.

Run:
```bash
bash scripts/criar-catalogo.sh Emerson
databricks catalogs list --profile Emerson
```
Expected: a segunda saída lista `lakehouse_rotaperfume` junto de `workspace`/`samples`/`system`.

- [ ] **Step 4: Commit**

```bash
git add scripts/criar-catalogo.sh
git commit -m "feat(rotaperfume): script para criar o catalogo lakehouse_rotaperfume via SQL"
```

---

### Task 3: `resources/catalogo.yml` — schemas bronze/silver/gold e o Volume `bronze.raw`

**Files:**
- Create: `rotaperfume/resources/catalogo.yml`

**Interfaces:**
- Consumes: `${var.catalog}` declarada na Tarefa 1; catálogo `lakehouse_rotaperfume` criado na Tarefa 2.
- Produces: schemas `bronze`, `silver`, `gold` (bundle resource keys `resources.schemas.bronze|silver|gold`) e o volume MANAGED `bronze.raw` (`resources.volumes.raw`) — a Tarefa 4 sobe arquivos para `/Volumes/lakehouse_rotaperfume/bronze/raw/{erp,crm}`, e a Tarefa 5 lê desse mesmo caminho e grava a tabela `bronze._raw_arquivos`.

- [ ] **Step 1: Criar o arquivo**

```yaml
resources:
  schemas:
    bronze:
      name: bronze
      catalog_name: ${var.catalog}
      comment: >-
        Raw ingerido sem transformacao: arquivo como chegou do sistema de
        origem, guardado byte a byte, para auditoria e reprocessamento.
    silver:
      name: silver
      catalog_name: ${var.catalog}
      comment: >-
        Dados limpos e conformados: tipos corrigidos, duplicatas e nulos
        tratados, prontos para modelagem, ainda no grao original.
    gold:
      name: gold
      catalog_name: ${var.catalog}
      comment: >-
        Metricas de negocio agregadas para consumo direto por dashboards
        e times de analise.

  volumes:
    raw:
      name: raw
      catalog_name: ${var.catalog}
      # Referencia o recurso (nao a string literal 'bronze') para o deploy
      # criar o schema bronze antes do volume, garantindo a ordem certa.
      schema_name: ${resources.schemas.bronze.name}
      volume_type: MANAGED
      comment: >-
        Pouso dos arquivos brutos (CSV) dos sistemas de origem, exatamente
        como saem do ERP e do CRM, antes de qualquer leitura em tabela.
```

- [ ] **Step 2: Validar (estrito)**

Run (de `rotaperfume/`):
```bash
databricks bundle validate --target dev --profile Emerson --strict
```
Expected: sem erros nem warnings; lista os 4 recursos novos (`bronze`, `silver`, `gold`, `raw`).

- [ ] **Step 3: Deploy e conferência**

> Confirme com o usuário antes deste passo — cria schemas e um volume de verdade no workspace.

Run:
```bash
databricks bundle deploy --target dev --profile Emerson
databricks schemas list lakehouse_rotaperfume --profile Emerson
databricks volumes list lakehouse_rotaperfume.bronze --profile Emerson
```
Expected: `schemas list` mostra `bronze`, `silver`, `gold`; `volumes list` mostra `raw`.

- [ ] **Step 4: Commit**

```bash
git add resources/catalogo.yml
git commit -m "feat(rotaperfume): schemas bronze/silver/gold e volume bronze.raw como recursos do bundle"
```

---

### Task 4: `scripts/subir-raw.sh` — sobe os 10 CSVs de `dados/` para o Volume

**Files:**
- Create: `rotaperfume/scripts/subir-raw.sh`

**Interfaces:**
- Consumes: volume `lakehouse_rotaperfume.bronze.raw` criado na Tarefa 3; arquivos-fonte em `dados/erp/*.csv` e `dados/crm/*.csv` (raiz do repo, dois níveis acima de `rotaperfume/scripts/`).
- Produces: os 10 CSVs em `/Volumes/lakehouse_rotaperfume/bronze/raw/{erp,crm}/*.csv`, que a Tarefa 5 confere e lê.

- [ ] **Step 1: Criar o script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sobe dados/erp e dados/crm (raiz do repositorio) para o Volume de raw.
# O destino exige o esquema 'dbfs:' mesmo sendo um Volume do Unity Catalog.

if [ $# -lt 1 ]; then
  echo "uso: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
CATALOG="lakehouse_rotaperfume"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DADOS_DIR="$SCRIPT_DIR/../../dados"

if [ ! -d "$DADOS_DIR" ]; then
  echo "erro: $DADOS_DIR nao existe" >&2
  exit 1
fi

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/erp" "dbfs:/Volumes/${CATALOG}/bronze/raw/erp" \
  --profile "$PROFILE"

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/crm" "dbfs:/Volumes/${CATALOG}/bronze/raw/crm" \
  --profile "$PROFILE"
```

- [ ] **Step 2: Tornar executável**

```bash
chmod +x scripts/subir-raw.sh
```

- [ ] **Step 3: Rodar contra o workspace real e conferir**

> Confirme com o usuário antes deste passo — copia ~15 MB de dados reais para o Volume.

Run:
```bash
bash scripts/subir-raw.sh Emerson
databricks fs ls dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp --profile Emerson
databricks fs ls dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/crm --profile Emerson
```
Expected: `erp` lista `estoque.csv`, `itens_pedido.csv`, `pagamentos.csv`, `pedidos.csv`, `produtos.csv` (5 arquivos); `crm` lista `carteira.csv`, `clientes.csv`, `oportunidades.csv`, `vendedores.csv`, `visitas.csv` (5 arquivos).

- [ ] **Step 4: Commit**

```bash
git add scripts/subir-raw.sh
git commit -m "feat(rotaperfume): script para subir os CSVs de dados/ para o Volume bronze.raw"
```

---

### Task 5: Notebook de conferência + job `rotaperfume_pipeline`

**Files:**
- Create: `rotaperfume/src/raw/conferencia.py`
- Create: `rotaperfume/resources/pipeline.job.yml`

**Interfaces:**
- Consumes: `${var.catalog}` (Tarefa 1); os 10 CSVs já no Volume `lakehouse_rotaperfume.bronze.raw` (Tarefa 4).
- Produces: tabela `bronze._raw_arquivos` (colunas `sistema`, `arquivo`, `bytes`, `linhas`, `conferido_em`); job `rotaperfume_pipeline` (bundle resource key `resources.jobs.rotaperfume_pipeline`) com a tarefa `raw_conferencia` — chave que os próximos 5 prompts da série vão estender com novas tarefas.

- [ ] **Step 1: Criar o notebook `src/raw/conferencia.py`**

```python
# Databricks notebook source
# COMMAND ----------
dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------
import os
from datetime import datetime, timezone

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}


def caminho_arquivo(catalog: str, sistema: str, nome: str) -> str:
    return f"/Volumes/{catalog}/bronze/raw/{sistema}/{nome}.csv"


def conferir_arquivos(catalog: str, esperados: dict[str, list[str]]):
    """Confere cada arquivo esperado: existe, tamanho em bytes, linhas de dado.

    Retorna (resultados, faltando, vazios) -- puramente com os.path, sem
    dbutils/spark, para nao depender de um cluster ao ser chamada.
    """
    resultados = []
    faltando = []
    vazios = []

    for sistema, nomes in esperados.items():
        for nome in nomes:
            caminho = caminho_arquivo(catalog, sistema, nome)
            arquivo = f"{nome}.csv"
            if not os.path.exists(caminho):
                faltando.append(caminho)
                continue
            tamanho_bytes = os.path.getsize(caminho)
            with open(caminho, "r", encoding="utf-8") as f:
                total_linhas = sum(1 for _ in f)
            linhas_de_dado = total_linhas - 1  # desconta o cabecalho
            if linhas_de_dado <= 0:
                vazios.append(caminho)
            resultados.append(
                {
                    "sistema": sistema,
                    "arquivo": arquivo,
                    "bytes": tamanho_bytes,
                    "linhas": linhas_de_dado,
                    "conferido_em": datetime.now(timezone.utc),
                }
            )
    return resultados, faltando, vazios


# COMMAND ----------
resultados, faltando, vazios = conferir_arquivos(catalog, ARQUIVOS_ESPERADOS)

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
```

- [ ] **Step 2: Criar `resources/pipeline.job.yml`**

```yaml
# Job rotaperfume_pipeline -- cresce a cada prompt da serie "Jornada de Dados":
#   Prompt 1 (este arquivo): raw_conferencia -- confere a chegada dos 10 CSVs
#                             no Volume bronze.raw. NAO cria tabela bronze.
#   Prompt 2: + bronze_ingestao      -- CSV -> tabelas Delta em bronze
#   Prompt 3: + silver_transformacao -- limpeza e conformidade em silver
#   Prompt 4: + gold_agregacao       -- metricas de negocio em gold
#   Prompt 5: + qualidade_dados      -- testes de qualidade dos dados
#   Prompt 6: + orquestracao final e documentacao
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
      schedule:
        quartz_cron_expression: "0 0 6 * * ?"
        timezone_id: America/Sao_Paulo
        pause_status: UNPAUSED
```

- [ ] **Step 3: Validar**

Run (de `rotaperfume/`):
```bash
databricks bundle validate --target dev --profile Emerson --strict
```
Expected: sem erros; lista o job `rotaperfume_pipeline` com a tarefa `raw_conferencia`.

- [ ] **Step 4: Deploy e execução real**

> Confirme com o usuário antes deste passo — implanta e roda um job de verdade.

Run:
```bash
databricks bundle deploy --target dev --profile Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: a execução termina com sucesso (a tarefa `raw_conferencia` fica verde).

- [ ] **Step 5: Verificar os números exatos**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
  SELECT COUNT(*) AS arquivos, SUM(linhas) AS linhas_de_dado,
         ROUND(SUM(bytes)/1024/1024, 1) AS mb
  FROM lakehouse_rotaperfume.bronze._raw_arquivos
"
```
Expected: `arquivos = 10`, `linhas_de_dado = 313551`, `mb` ≈ `14.7`-`15.0` (bate com `dados/` local: 313.551 linhas de dado, ~15 MB — conferido nesta sessão de planejamento).

- [ ] **Step 6: Provar que a conferência funciona de verdade — quebrar de propósito**

Run:
```bash
databricks fs rm dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp/pagamentos.csv --profile Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: a tarefa `raw_conferencia` FALHA com a mensagem `Arquivos ausentes no Volume: [...pagamentos.csv]` e o job para (não fica "verde" com 9 arquivos).

Run para restaurar e confirmar que volta a passar:
```bash
bash scripts/subir-raw.sh Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: sucesso novamente, com os 10 arquivos de volta em `bronze._raw_arquivos`.

- [ ] **Step 7: Commit**

```bash
git add src/raw/conferencia.py resources/pipeline.job.yml
git commit -m "feat(rotaperfume): notebook de conferencia de chegada + job rotaperfume_pipeline"
```

---

## Self-Review

**Cobertura do `.llm/prompt01.md`:**
1. `databricks.yml` (variables catalog/warehouse_id, targets dev/prod, armadilha do `mode: development`) → Tarefa 1.
2. `scripts/criar-catalogo.sh` (SQL, motivo do Free-Edition comentado) → Tarefa 2.
3. `resources/catalogo.yml` (schemas + volume, com COMMENT) → Tarefa 3.
4. `scripts/subir-raw.sh` (upload para o Volume) → Tarefa 4.
5. `src/raw/conferencia.py` (conferência de chegada, tabela de controle) → Tarefa 5, Step 1.
6. `resources/pipeline.job.yml` (job com 1 tarefa, agendamento diário 6h America/Sao_Paulo, comentário sobre crescimento futuro) → Tarefa 5, Step 2.
7. Ordem de execução (`criar-catalogo.sh` → `validate` → `deploy` → `subir-raw.sh` → `bundle run`) → respeitada entre as Tarefas 2 → 3 → 4 → 5.
8. As 5 verificações do "Como verificar a feature" (schemas/volume existem, arquivos chegaram, conferência registrou, apagar-e-recriar prova reprodutibilidade, quebrar-de-propósito prova a conferência) → cobertas pelos testes de cada tarefa e pelos Steps 5–6 da Tarefa 5. O item "apague e traga de volta" (`DROP SCHEMA gold` + `deploy`) fica como verificação manual opcional pós-plano — não é necessário para provar a entrega, só reforça o mesmo ponto já provado pelo `deploy` idempotente da Tarefa 3.

**Desvios deliberados do `.llm/prompt01.md`** (justificados no início do plano/Global Constraints):
- Caminho do projeto: `rotaperfume/` na raiz do repo, não `aulas/aula-02-engenharia-de-dados/rotaperfume/` (esse caminho não existe neste repositório).
- Profile `Emerson` (real) em vez de `projeto-dados-ia` (de outro workspace); warehouse `2c807bf97ff3fec4` em vez de `666be37e3fededf2`.
- Sem `material/gerar_dataset.py`: `dados/` já existe na raiz com os mesmos números citados no prompt (313.551 linhas, ~15 MB, `itens_pedido.csv` com 197.724 linhas) — conferido nesta sessão.
- `schema_name` do volume referencia `${resources.schemas.bronze.name}` (não a string literal `bronze`) para garantir a ordem de criação no mesmo deploy.

**Checagem de placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem código ou comando completo e uma saída esperada concreta.

**Consistência de tipos/nomes:** `conferir_arquivos(catalog, esperados)` retorna `(resultados, faltando, vazios)` e é chamada assim no Step 3 do notebook; `CATALOG="lakehouse_rotaperfume"` e `WAREHOUSE_ID="2c807bf97ff3fec4"` nos dois scripts batem com os defaults de `${var.catalog}`/`${var.warehouse_id}` no `databricks.yml` da Tarefa 1; a chave do job `rotaperfume_pipeline` e da tarefa `raw_conferencia` são as mesmas em todos os comandos de verificação.
