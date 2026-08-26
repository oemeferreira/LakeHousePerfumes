# Raw — Catálogo em Código, Módulo de Conferência Testável e Chegada do Dado no Volume — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`) para rastreamento.

**Goal:** Entregar o primeiro dos 6 prompts da noite 2: transformar o layout do Unity Catalog do bundle `rotaperfume` (schemas `bronze`/`silver`/`gold` + volume de pouso `bronze.raw`) em recursos reproduzíveis do bundle, subir os 10 CSVs reais de `dados/` para o Volume, e ter uma tarefa agendada que confere a chegada de cada arquivo — com a lógica de conferência isolada num módulo Python puro e testado com `pytest` de verdade, sem depender de cluster Databricks. Não criar a camada bronze ainda: hoje o dado só chega no Volume.

**Architecture:** `databricks.yml` já existe e já está correto (variables `catalog`/`warehouse_id`, targets `dev`/`prod`, `presets.trigger_pause_status: PAUSED` em vez do trap `mode: development`) — este plano só o valida, não o recria. Sobre ele, o bundle ganha `resources/catalogo.yml` (schemas + volume MANAGED `bronze.raw`) e `resources/pipeline.job.yml` (job `rotaperfume_pipeline`, uma tarefa serverless agendada). Como a API do Unity Catalog usada pelo provider do bundle recusa criar catálogo neste workspace (Free Edition, sem managed location), `scripts/criar-catalogo.sh` cria o catálogo via SQL fora do bundle, antes do primeiro deploy. Depois do deploy, `scripts/subir-raw.sh` copia os CSVs de `dados/erp` e `dados/crm` para o Volume. A conferência de chegada é dividida em duas camadas: `src/raw/conferencia_lib.py` é um módulo **puro** (só `os.path`/leitura de arquivo, recebe `base_dir` como parâmetro) testado com `pytest` comum em `tests_unit/` (isolado de `tests/conftest.py`, que abre uma sessão Spark real); `src/raw/conferencia.py` é o notebook serverless que roda como a única tarefa do job — ele só faz o que exige runtime Databricks (ler o widget `catalog`, montar `base_dir`, chamar as funções puras, gravar `bronze._raw_arquivos` via Spark).

**Tech Stack:** Databricks Asset Bundle (DAB) YAML, Databricks CLI v1.13.0 (perfil `Emerson`), bash, notebook Python serverless (PySpark/`dbutils`), Unity Catalog (catálogo/schema/volume), SQL warehouse serverless `2c807bf97ff3fec4`, `pytest` local via `uv`.

## Global Constraints

- **Profile obrigatório:** `Emerson` — único profile válido em `databricks auth profiles` (host `https://dbc-61d9738c-00ad.cloud.databricks.com`). Todo comando `databricks` passa `--profile Emerson` explicitamente — cada chamada de shell é independente, `export DATABRICKS_CONFIG_PROFILE=...` isolado num passo não sobrevive ao próximo. O prompt original da aula usa o profile `projeto-dados-ia`; **ignore-o**, ele é de outro workspace.
- **Warehouse:** `2c807bf97ff3fec4` (Serverless Starter Warehouse) — mesmo default já em `databricks.yml`.
- **Catálogo `lakehouse_rotaperfume` ainda não existe** neste workspace. Ambiente Free Edition: tudo serverless, nunca configurar cluster dedicado.
- **`databricks.yml` NÃO deve ser recriado nem editado.** Já foi lido nesta sessão de planejamento e está correto (variables, targets, comentário sobre o trap de `mode: development`). Idem para o `CLAUDE.md` da raiz do repo, que já documenta esse trap corretamente. A Tarefa 1 apenas valida.
- **`tests/conftest.py` abre uma `DatabricksSession` real incondicionalmente** para qualquer coleção de teste dentro de `rotaperfume/tests/` (seu `pytest_configure` não checa se algum teste pede a fixture `spark`). Por isso os testes do módulo puro de conferência (Tarefa 2) vivem em `rotaperfume/tests_unit/` — um diretório **irmão** de `tests/`, fora do alcance desse `conftest.py` (pytest só carrega `conftest.py` de diretórios entre o rootdir e o arquivo de teste coletado) — e são invocados com `uv run pytest tests_unit/` (nunca com `uv run pytest` genérico, que colide com `tests/` e ainda vai exigir sessão real, como já era o caso antes deste plano).
- **`uv`:** confirmado nesta sessão que nem o Git Bash nem o PowerShell reconheciam `uv` no PATH ainda (`command not found` nos dois), mesmo após o usuário reportar tê-lo instalado. Trate isso como um check rápido no início da Tarefa 2, não como bloqueio: rode `uv --version`; se falhar, abra um terminal novo antes de prosseguir (mudança de PATH não chega a sessões já abertas), sem precisar reinstalar.
- **Todos os comandos bash/`databricks` assumem `cwd = rotaperfume/`.**
- **Ações contra o workspace real** (`scripts/criar-catalogo.sh`, `databricks bundle deploy`, `scripts/subir-raw.sh`, `databricks bundle run`, e o passo de "quebrar de propósito" da Tarefa 8) criam/alteram/removem recursos de verdade — catálogo, schemas, volume, job, ~14,7 MB de dados. Cada um desses passos abaixo tem uma nota pedindo confirmação explícita do usuário antes de rodar; não são reversíveis com `git revert`.
- **Escopo travado no "Raw":** hoje o dado só chega no Volume. Não criar tabelas Delta de negócio na camada bronze — só a tabela de controle `bronze._raw_arquivos` (auditoria/conferência, não bronze de negócio).
- **Convenção de commit:** mensagens curtas em português, `feat(rotaperfume): <o que foi adicionado>`, `git add` de arquivos específicos (nunca `git add -A`).
- **Não mexer em `dados/`** — os 10 CSVs na raiz do repo já existem com os números de referência (10 arquivos, 313.551 linhas de dado, 14.700.966 bytes = 14,0 MiB — contagem de bytes e linhas verificada diretamente nos arquivos locais nesta sessão). Ignorar toda menção a `material/gerar_dataset.py` no prompt original: esse script/pasta não existe neste repositório e não é necessário.

---

## File Structure

```
rotaperfume/
├── databricks.yml                  # NÃO TOCAR — já correto, só validado na Tarefa 1
├── pyproject.toml                  # MODIFICAR — adiciona [tool.pytest.ini_options] pythonpath=["src"]
├── scripts/
│   ├── criar-catalogo.sh           # NOVO — cria o catálogo via SQL (fora do bundle)
│   └── subir-raw.sh                # NOVO — sobe dados/erp e dados/crm para o Volume
├── resources/
│   ├── catalogo.yml                # NOVO — schemas bronze/silver/gold + volume bronze.raw
│   └── pipeline.job.yml            # NOVO — job rotaperfume_pipeline (1 tarefa: raw_conferencia)
├── src/
│   └── raw/
│       ├── conferencia_lib.py      # NOVO — módulo puro: caminho_arquivo, conferir_arquivos
│       └── conferencia.py          # NOVO — notebook serverless que usa conferencia_lib
└── tests_unit/
    └── test_conferencia_lib.py     # NOVO — testes pytest reais, sem rede, sem tests/conftest.py
```

---

### Task 1: Confirmar que `databricks.yml` já está pronto (sem recriar)

**Files:**
- Read-only: `rotaperfume/databricks.yml` (nenhuma modificação)

**Interfaces:**
- Consumes: nada.
- Produces: confirmação de que `${var.catalog}` (default `lakehouse_rotaperfume`) e `${var.warehouse_id}` (default `2c807bf97ff3fec4`) estão declaradas e utilizáveis pelas Tarefas 4 e 7.

- [ ] **Step 1: Validar o bundle como está hoje**

Run (a partir de `rotaperfume/`):
```bash
databricks bundle validate --target dev --profile Emerson --strict
```
Expected: saída sem erro nem warning. Como `resources/` ainda está vazio (as Tarefas 4 e 7 ainda não existem), não deve listar nenhum recurso — só confirma que `bundle.name: rotaperfume`, as duas `variables` e os dois `targets` (`dev` default, `prod`) estão sintaticamente corretos e a autenticação com o profile `Emerson` funciona.

Não há Step de commit aqui — nenhum arquivo é criado ou modificado nesta tarefa.

---

### Task 2: `src/raw/conferencia_lib.py` — módulo puro de conferência + testes pytest reais

**Files:**
- Create: `rotaperfume/src/raw/conferencia_lib.py`
- Create: `rotaperfume/tests_unit/test_conferencia_lib.py`
- Modify: `rotaperfume/pyproject.toml`

**Interfaces:**
- Produces: `ARQUIVOS_ESPERADOS: dict[str, list[str]]`, `caminho_arquivo(base_dir: str, sistema: str, nome: str) -> str`, `conferir_arquivos(base_dir: str, esperados: dict) -> tuple[list[dict], list[str], list[str]]` (resultados, faltando, vazios) — consumidos pelo notebook `conferencia.py` (Tarefa 6).
- Consumes: nada externo — só `os` e `datetime` da stdlib, propositalmente sem `dbutils`/`spark`, para poder ser testado sem cluster.

- [ ] **Step 1: Criar o módulo puro**

```python
# rotaperfume/src/raw/conferencia_lib.py
"""Conferencia de chegada dos arquivos raw -- logica pura, sem dbutils/spark.

Recebe o diretorio-base como parametro (nunca monta '/Volumes/{catalog}/...'
internamente) para poder ser testada com pytest comum, apontando para um
tmp_path com CSVs falsos, sem precisar de um Volume real nem de cluster.

O notebook 'conferencia.py' (mesma pasta) e' quem monta
base_dir = f"/Volumes/{catalog}/bronze/raw", chama estas funcoes, e grava o
resultado com Spark -- essa parte sim exige o runtime Databricks.
"""
from __future__ import annotations

import os
from datetime import datetime, timezone

ARQUIVOS_ESPERADOS: dict[str, list[str]] = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}


def caminho_arquivo(base_dir: str, sistema: str, nome: str) -> str:
    """Monta o caminho do CSV dentro de base_dir/sistema/nome.csv."""
    return f"{base_dir}/{sistema}/{nome}.csv"


def conferir_arquivos(base_dir: str, esperados: dict[str, list[str]]):
    """Confere cada arquivo esperado: existe, tamanho em bytes, linhas de dado.

    Retorna (resultados, faltando, vazios). 'resultados' traz uma entrada por
    arquivo ENCONTRADO (mesmo vazio); 'faltando' e 'vazios' trazem os caminhos
    problematicos, para quem chamar decidir se interrompe.
    """
    resultados: list[dict] = []
    faltando: list[str] = []
    vazios: list[str] = []

    for sistema, nomes in esperados.items():
        for nome in nomes:
            caminho = caminho_arquivo(base_dir, sistema, nome)
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
                    "arquivo": f"{nome}.csv",
                    "bytes": tamanho_bytes,
                    "linhas": linhas_de_dado,
                    "conferido_em": datetime.now(timezone.utc),
                }
            )

    return resultados, faltando, vazios
```

- [ ] **Step 2: Adicionar `pythonpath` ao `pyproject.toml`**

Em `rotaperfume/pyproject.toml`, adicione ao final do arquivo (depois de `[tool.ruff]`):

```toml
[tool.pytest.ini_options]
# Faz 'from raw.conferencia_lib import ...' resolver em tests_unit/ sem
# __init__.py (namespace package implicito do Python 3). NAO define
# testpaths de proposito: 'uv run pytest' generico continua pegando tests/
# (que exige DatabricksSession real, como sempre exigiu); os testes puros
# so rodam isolados com 'uv run pytest tests_unit/' (ver Step 5).
pythonpath = ["src"]
```

- [ ] **Step 3: Criar os testes reais, sem rede**

```python
# rotaperfume/tests_unit/test_conferencia_lib.py
"""Testes rapidos do modulo puro de conferencia -- sem rede, sem Databricks.

Este arquivo mora em rotaperfume/tests_unit/, IRMAO de rotaperfume/tests/,
de proposito: o pytest so carrega conftest.py dos diretorios no caminho
entre o rootdir e o arquivo de teste coletado. Como tests/conftest.py nao
esta nesse caminho quando voce roda 'pytest tests_unit/', o hook
pytest_configure que abre uma DatabricksSession real nunca dispara aqui.
"""
import csv

from raw.conferencia_lib import ARQUIVOS_ESPERADOS, caminho_arquivo, conferir_arquivos


def _escrever_csv(caminho, linhas_de_dado: int) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with caminho.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["coluna_a", "coluna_b"])
        for i in range(linhas_de_dado):
            writer.writerow([i, f"valor_{i}"])


def _montar_10_arquivos_ok(tmp_path):
    for sistema, nomes in ARQUIVOS_ESPERADOS.items():
        for nome in nomes:
            _escrever_csv(tmp_path / sistema / f"{nome}.csv", linhas_de_dado=5)
    return tmp_path


def test_caminho_arquivo_monta_path_esperado():
    assert (
        caminho_arquivo("/Volumes/cat/bronze/raw", "erp", "produtos")
        == "/Volumes/cat/bronze/raw/erp/produtos.csv"
    )


def test_conferir_arquivos_10_ok_sem_faltando_sem_vazio(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert len(resultados) == 10
    assert faltando == []
    assert vazios == []
    produtos = next(r for r in resultados if r["arquivo"] == "produtos.csv")
    assert produtos["sistema"] == "erp"
    assert produtos["linhas"] == 5
    assert produtos["bytes"] > 0


def test_conferir_arquivos_detecta_arquivo_faltando(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)
    (base_dir / "erp" / "pagamentos.csv").unlink()

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert len(resultados) == 9
    assert faltando == [caminho_arquivo(str(base_dir), "erp", "pagamentos")]
    assert vazios == []


def test_conferir_arquivos_detecta_arquivo_vazio(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)
    _escrever_csv(base_dir / "crm" / "clientes.csv", linhas_de_dado=0)  # so cabecalho

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert faltando == []
    assert vazios == [caminho_arquivo(str(base_dir), "crm", "clientes")]
    clientes = next(r for r in resultados if r["arquivo"] == "clientes.csv")
    assert clientes["linhas"] == 0


def test_conferir_arquivos_e_reprodutivel_apos_faltar_e_restaurar(tmp_path):
    """Prova local (sem workspace) do mesmo ciclo que a Tarefa 8 faz de verdade:
    remover um arquivo quebra a conferencia, devolver o arquivo conserta."""
    base_dir = _montar_10_arquivos_ok(tmp_path)
    alvo = base_dir / "crm" / "visitas.csv"

    alvo.unlink()
    _, faltando_apos_remover, _ = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)
    assert faltando_apos_remover == [caminho_arquivo(str(base_dir), "crm", "visitas")]

    _escrever_csv(alvo, linhas_de_dado=3)
    resultados_apos_restaurar, faltando_apos_restaurar, vazios_apos_restaurar = conferir_arquivos(
        str(base_dir), ARQUIVOS_ESPERADOS
    )
    assert faltando_apos_restaurar == []
    assert vazios_apos_restaurar == []
    assert len(resultados_apos_restaurar) == 10
```

- [ ] **Step 4: Garantir `uv` disponível e sincronizar dependências**

Run:
```bash
uv --version
```
Se falhar (`command not found`), abra um terminal novo (mudança de PATH não chega a sessões já abertas) e rode de novo antes de continuar.

Depois, a partir de `rotaperfume/`:
```bash
uv sync --dev
```
Expected: cria `.venv/` e instala `pytest`, `ruff`, `databricks-dlt`, `databricks-connect`, `ipykernel` sem erro.

- [ ] **Step 5: Rodar os testes isolados (sem workspace, sem rede)**

Run (a partir de `rotaperfume/`):
```bash
uv run pytest tests_unit/ -v
```
Expected: **5 passed**, execução em menos de 2 segundos, sem nenhuma tentativa de conexão de rede ou prompt de autenticação Databricks (se aparecer qualquer menção a `DatabricksSession`/`serverless compute`/OAuth no output, algo está errado — `tests/conftest.py` não deveria ter sido carregado).

- [ ] **Step 6: Commit**

```bash
git add src/raw/conferencia_lib.py tests_unit/test_conferencia_lib.py pyproject.toml
git commit -m "feat(rotaperfume): modulo puro de conferencia de arquivos + testes pytest sem rede"
```

---

### Task 3: `scripts/criar-catalogo.sh` — cria o catálogo via SQL (fora do bundle)

**Files:**
- Create: `rotaperfume/scripts/criar-catalogo.sh`

**Interfaces:**
- Consumes: nenhuma (constantes próprias — `CATALOG`/`WAREHOUSE_ID` espelham os defaults de `databricks.yml`, confirmados na Tarefa 1).
- Produces: o catálogo `lakehouse_rotaperfume` existindo no workspace — pré-requisito para a Tarefa 4 (o bundle cria os *schemas* dentro dele, não o catálogo).

- [ ] **Step 1: Criar o script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Cria o catalogo lakehouse_rotaperfume via SQL -- de proposito FORA do
# bundle (nao como resources.catalogs no databricks.yml).
#
# POR QUE NAO ESTA NO BUNDLE: quando o workspace tem o Default Storage
# habilitado (comum em contas Free Edition), a API do Unity Catalog usada
# pelo provider Terraform do bundle RECUSA criar catalogo -- ela exige um
# MANAGED LOCATION que essas contas nao tem, e falha com:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL abaixo nao passa por essa restricao.

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

- [ ] **Step 2: Rodar contra o workspace real e conferir**

> Confirme com o usuário antes deste passo — cria um catálogo de verdade no workspace.

Run:
```bash
bash scripts/criar-catalogo.sh Emerson
databricks catalogs list --profile Emerson
```
Expected: a segunda saída lista `lakehouse_rotaperfume` junto de `workspace`/`samples`/`system`.

- [ ] **Step 3: Commit**

```bash
git add scripts/criar-catalogo.sh
git commit -m "feat(rotaperfume): script para criar o catalogo lakehouse_rotaperfume via SQL"
```

---

### Task 4: `resources/catalogo.yml` — schemas bronze/silver/gold e o Volume `bronze.raw`

**Files:**
- Create: `rotaperfume/resources/catalogo.yml`

**Interfaces:**
- Consumes: `${var.catalog}` (Tarefa 1); catálogo `lakehouse_rotaperfume` criado na Tarefa 3.
- Produces: schemas `bronze`/`silver`/`gold` e o volume MANAGED `bronze.raw` — a Tarefa 5 sobe arquivos para `/Volumes/lakehouse_rotaperfume/bronze/raw/{erp,crm}`, e a Tarefa 6 lê desse mesmo caminho.

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

Run:
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

### Task 5: `scripts/subir-raw.sh` — sobe os 10 CSVs de `dados/` para o Volume

**Files:**
- Create: `rotaperfume/scripts/subir-raw.sh`

**Interfaces:**
- Consumes: volume `lakehouse_rotaperfume.bronze.raw` (Tarefa 4); arquivos-fonte em `dados/erp/*.csv` e `dados/crm/*.csv` (raiz do repo, dois níveis acima de `rotaperfume/scripts/`).
- Produces: os 10 CSVs em `/Volumes/lakehouse_rotaperfume/bronze/raw/{erp,crm}/*.csv`, que a Tarefa 6 confere e lê.

- [ ] **Step 1: Criar o script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sobe dados/erp e dados/crm (raiz do repositorio) para o Volume de raw.
# databricks fs cp exige o esquema 'dbfs:' no destino, mesmo sendo um
# Volume do Unity Catalog (nao um path de DBFS classico).

if [ $# -lt 1 ]; then
  echo "uso: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
CATALOG="lakehouse_rotaperfume"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DADOS_DIR="$SCRIPT_DIR/../../dados"

if [ ! -d "$DADOS_DIR" ]; then
  echo "erro: $DADOS_DIR nao existe (esperado dados/erp e dados/crm na raiz do repo)" >&2
  exit 1
fi

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/erp" "dbfs:/Volumes/${CATALOG}/bronze/raw/erp" \
  --profile "$PROFILE"

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/crm" "dbfs:/Volumes/${CATALOG}/bronze/raw/crm" \
  --profile "$PROFILE"
```

- [ ] **Step 2: Rodar contra o workspace real e conferir**

> Confirme com o usuário antes deste passo — copia ~14,7 MB de dados reais para o Volume.

Run:
```bash
bash scripts/subir-raw.sh Emerson
databricks fs ls dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp --profile Emerson
databricks fs ls dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/crm --profile Emerson
```
Expected: `erp` lista `estoque.csv`, `itens_pedido.csv`, `pagamentos.csv`, `pedidos.csv`, `produtos.csv` (5 arquivos); `crm` lista `carteira.csv`, `clientes.csv`, `oportunidades.csv`, `vendedores.csv`, `visitas.csv` (5 arquivos).

- [ ] **Step 3: Commit**

```bash
git add scripts/subir-raw.sh
git commit -m "feat(rotaperfume): script para subir os CSVs de dados/ para o Volume bronze.raw"
```

---

### Task 6: `src/raw/conferencia.py` — notebook serverless que usa o módulo puro

**Files:**
- Create: `rotaperfume/src/raw/conferencia.py`

**Interfaces:**
- Consumes: `conferencia_lib.caminho_arquivo`/`conferir_arquivos`/`ARQUIVOS_ESPERADOS` (Tarefa 2, mesma pasta); `${var.catalog}` via widget; os 10 CSVs no Volume (Tarefa 5).
- Produces: tabela `{catalog}.bronze._raw_arquivos` (colunas `sistema`, `arquivo`, `bytes`, `linhas`, `conferido_em`) com `COMMENT`; consumida pela verificação da Tarefa 8 e pelo job da Tarefa 7.

- [ ] **Step 1: Criar o notebook**

```python
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
```

- [ ] **Step 2: Commit**

```bash
git add src/raw/conferencia.py
git commit -m "feat(rotaperfume): notebook de conferencia de chegada do raw"
```

(A validação real deste notebook — deploy + execução — acontece na Tarefa 8, junto com o job da Tarefa 7, porque um `notebook_task` sozinho fora de um job não roda via `bundle run`.)

---

### Task 7: `resources/pipeline.job.yml` — job `rotaperfume_pipeline`

**Files:**
- Create: `rotaperfume/resources/pipeline.job.yml`

**Interfaces:**
- Consumes: `${var.catalog}` (Tarefa 1); notebook `src/raw/conferencia.py` (Tarefa 6).
- Produces: job `rotaperfume_pipeline` (chave `resources.jobs.rotaperfume_pipeline`) com a tarefa `raw_conferencia` — chave que os próximos 5 prompts da série vão estender com novas tarefas.

- [ ] **Step 1: Criar o arquivo**

```yaml
# Job rotaperfume_pipeline -- cresce a cada prompt da serie "Jornada de Dados":
#   Prompt 1 (este arquivo): raw_conferencia -- confere a chegada dos 10 CSVs
#                             no Volume bronze.raw. NAO cria tabela bronze.
#   Prompt 2: + bronze_ingestao      -- CSV -> tabelas Delta em bronze
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
      schedule:
        quartz_cron_expression: "0 0 6 * * ?"
        timezone_id: America/Sao_Paulo
        pause_status: UNPAUSED
```

Nota: `pause_status: UNPAUSED` aqui é o estado "de produção" do recurso; no target `dev`, `presets.trigger_pause_status: PAUSED` (já em `databricks.yml`) sobrepõe isso e mantém o agendamento pausado sem precisar de `mode: development`.

- [ ] **Step 2: Validar**

Run:
```bash
databricks bundle validate --target dev --profile Emerson --strict
```
Expected: sem erros; lista o job `rotaperfume_pipeline` com a tarefa `raw_conferencia`.

- [ ] **Step 3: Commit**

```bash
git add resources/pipeline.job.yml
git commit -m "feat(rotaperfume): job rotaperfume_pipeline com a tarefa raw_conferencia"
```

---

### Task 8: Execução ordenada real, verificação dos números e prova de falha/recuperação

**Files:**
- Nenhum arquivo novo — esta tarefa só executa o que as Tarefas 1–7 já versionaram, contra o workspace real, na ordem exigida pelo prompt original (catálogo antes do deploy criar os schemas; Volume antes de subir arquivo nele).

**Interfaces:**
- Consumes: tudo (catálogo, schemas, volume, dados no volume, notebook, job).
- Produces: execução bem-sucedida do job com os 10 arquivos conferidos, mais evidência de que a conferência falha de verdade quando um arquivo some e volta a passar quando ele é restaurado.

- [ ] **Step 1: Rodar a sequência completa, na ordem**

> Confirme com o usuário antes deste passo — cada comando abaixo cria/altera recursos reais (catálogo, schemas, volume, job, dados, uma execução de job).

Run, um de cada vez, a partir de `rotaperfume/`:
```bash
bash scripts/criar-catalogo.sh Emerson
databricks bundle validate --target dev --profile Emerson --strict
databricks bundle deploy   --target dev --profile Emerson
bash scripts/subir-raw.sh  Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: os quatro primeiros comandos já foram individualmente confirmados nas Tarefas 3–7; o `bundle run` final termina com a tarefa `raw_conferencia` em sucesso (exit code 0).

- [ ] **Step 2: Verificar os números exatos**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
  SELECT COUNT(*) AS arquivos, SUM(linhas) AS linhas_de_dado,
         ROUND(SUM(bytes)/1024/1024, 1) AS mb
  FROM lakehouse_rotaperfume.bronze._raw_arquivos
"
```
Expected: `arquivos = 10`, `linhas_de_dado = 313551`, `mb = 14.0` — conferido nesta sessão de planejamento a partir dos arquivos locais em `dados/` (soma exata de bytes: 14.700.966; soma exata de linhas de dado por arquivo: produtos 292, pedidos 28.729, itens_pedido 197.724, pagamentos 27.772, estoque 8.400, clientes 3.040, vendedores 42, carteira 3.637, oportunidades 5.979, visitas 37.936 — total 313.551).

- [ ] **Step 3: Provar que a conferência falha de verdade — quebrar de propósito**

> Confirme com o usuário antes deste passo — remove um arquivo real do Volume (recuperável no Step 4).

Run:
```bash
databricks fs rm dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp/pagamentos.csv --profile Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: a tarefa `raw_conferencia` **FALHA** com a mensagem `Arquivos ausentes no Volume: [...pagamentos.csv]` — o job não fica "verde" com 9 arquivos, ele para.

- [ ] **Step 4: Restaurar e confirmar que volta a passar**

Run:
```bash
bash scripts/subir-raw.sh Emerson
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: sucesso novamente; repita o Step 2 e confirme que `bronze._raw_arquivos` volta a mostrar `arquivos = 10`, `linhas_de_dado = 313551`.

Não há Step de commit nesta tarefa (nenhum arquivo novo).

---

## Self-Review

**Cobertura do prompt da aula (7 itens):**
1. `databricks.yml` — já pronto; Tarefa 1 confirma via `validate`, sem recriar.
2. `scripts/criar-catalogo.sh` (SQL, motivo do Free Edition comentado) → Tarefa 3.
3. `resources/catalogo.yml` (schemas + volume, com `COMMENT`) → Tarefa 4.
4. `scripts/subir-raw.sh` (upload para o Volume, ignorando a menção a `material/gerar_dataset.py`) → Tarefa 5.
5. `src/raw/conferencia.py` (conferência de chegada, tabela de controle) → Tarefas 2 (lógica pura) + 6 (notebook).
6. `resources/pipeline.job.yml` (1 tarefa, agendamento diário 6h America/Sao_Paulo, comentário sobre os 5 prompts futuros) → Tarefa 7.
7. Ordem de execução exata (`criar-catalogo.sh` → `validate` → `deploy` → `subir-raw.sh` → `bundle run`) → Tarefa 8, Step 1.

**Ideia de design avaliada (módulo puro testável):** incorporada — é uma boa ideia porque dá feedback em segundos sobre a lógica de conferência sem depender de autenticação/cluster Databricks, o que importa especialmente numa aula ao vivo onde chamadas reais são lentas. Duas ressalvas resolvidas no desenho da Tarefa 2: (a) `tests/conftest.py` abre sessão Spark real incondicionalmente para qualquer teste sob `tests/`, então os testes puros foram colocados em `tests_unit/` — irmão, não descendente, de `tests/` — e devem ser invocados com `uv run pytest tests_unit/`, nunca `uv run pytest` genérico; (b) comparações de caminho nos testes usam sempre `caminho_arquivo(...)` de novo, nunca `pathlib` puro, para não quebrar no Windows por causa do separador de diretório.

**Prova de falha/recuperação:** dupla — local e rápida (`test_conferir_arquivos_detecta_arquivo_faltando`/`_vazio`/`_reprodutivel_apos_faltar_e_restaurar` na Tarefa 2, sem tocar o workspace) e real, contra o job de verdade (Tarefa 8, Steps 3–4: remove `pagamentos.csv` do Volume, `bundle run` falha com mensagem exata, `subir-raw.sh` restaura, `bundle run` volta a passar).

**Correção de números em relação ao rascunho anterior do plano** (`rotaperfume/docs/superpowers/plans/2026-08-25-raw-catalogo-volume.md`, já commitado): esse arquivo (a) ainda recria `databricks.yml` e edita o `CLAUDE.md` raiz — desnecessário, ambos já corretos, confirmado nesta sessão; (b) não tem o módulo puro/testes pytest; (c) estimava `mb ≈ 14.7–15.0` — o valor certo com o divisor `/1024/1024` usado na query é **14.0** (14.700.966 bytes ÷ 1024², contagem de bytes verificada diretamente nos 10 arquivos nesta sessão), corrigido aqui.

**Checagem de placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem código ou comando completo e uma saída esperada concreta.

**Consistência de tipos/nomes:** `conferir_arquivos(base_dir, esperados)` retorna `(resultados, faltando, vazios)` e é chamada assim tanto nos testes quanto no notebook; `CATALOG="lakehouse_rotaperfume"`/`WAREHOUSE_ID="2c807bf97ff3fec4"` nos dois scripts batem com os defaults de `${var.catalog}`/`${var.warehouse_id}` já em `databricks.yml`; a chave do job `rotaperfume_pipeline` e da tarefa `raw_conferencia` são as mesmas em todos os comandos de verificação.
