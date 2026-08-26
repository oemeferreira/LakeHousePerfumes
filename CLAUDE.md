# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> O contexto de negócio completo (o quê, por quê, cronograma das 4 noites, dicionário de dados, números de referência) já é carregado automaticamente a partir de `../CLAUDE.md` (um nível acima desta pasta). Este arquivo não repete aquele conteúdo — documenta apenas a estrutura técnica deste repositório e como operar nele.

## Estrutura do repositório

Este repositório (`LakeHousePerfumes`) tem duas partes com propósitos bem diferentes:

- **`dados/`** — os 10 CSVs brutos gerados pelo `gerar_dataset.py` (seed 42), organizados em `dados/erp/` (produtos, pedidos, itens_pedido, pagamentos, estoque) e `dados/crm/` (clientes, vendedores, carteira, oportunidades, visitas). É a fonte de verdade local — nada aqui é editado à mão.
- **`rotaperfume/`** — o Databricks Asset Bundle (DAB) que efetivamente é implantado no workspace. **Todo comando de desenvolvimento (uv, pytest, databricks bundle) roda com `cwd = rotaperfume/`**, não na raiz do repo.

O bundle está no estágio inicial do template `default-python`: `src/` e `resources/` existem como pastas vazias, ainda sem os notebooks/jobs da camada bronze/silver/gold. Antes de assumir que um recurso existe, confira em `rotaperfume/resources/*.yml` e `rotaperfume/src/` — não presuma pelo que os planos em `docs/superpowers/plans/` descrevem, pois eles podem ainda não ter sido executados.

## Comandos

Todos a partir de `rotaperfume/`:

```bash
# instalar dependências (uv, Python 3.10–3.12 — nunca 3.13)
uv sync --dev

# testes — atenção: conftest.py abre uma DatabricksSession real (databricks-connect),
# não há mocks. Precisa de auth configurada (databricks auth login) antes de rodar.
uv run pytest
uv run pytest tests/test_arquivo.py::test_funcao   # um teste específico

# lint
uv run ruff check .

# bundle: validar antes de qualquer deploy
databricks bundle validate --target dev --profile Emerson --strict

# deploy e execução (dev é o target default)
databricks bundle deploy --target dev --profile Emerson
databricks bundle run <job_key> --target dev --profile Emerson
```

**`--profile Emerson`** é o único profile válido neste ambiente (`databricks auth profiles`). Passe-o explicitamente em todo comando `databricks` — cada chamada de shell é independente, então `export DATABRICKS_CONFIG_PROFILE=...` feito num passo não sobrevive ao próximo.

## Arquitetura do bundle (`rotaperfume/`)

- **`databricks.yml`** declara duas variáveis usadas por todos os `resources/*.yml`: `catalog` (default `lakehouse_rotaperfume`) e `warehouse_id` (default `2c807bf97ff3fec4`, Serverless Starter Warehouse).
- **`dev` e `prod` apontam para o mesmo catálogo e os mesmos schemas** (`lakehouse_rotaperfume.{bronze,silver,gold}`) — não há catálogo por ambiente. Os dois targets se diferenciam só pelo agendamento do job e pelo `root_path`/permissões de deploy.
- **Nunca use `mode: development` no target `dev`.** Esse modo prefixa todo recurso implantado — inclusive os *schemas* do Unity Catalog — com `dev_<usuario>_`, quebrando qualquer SQL que espere `lakehouse_rotaperfume.bronze`. Em vez disso, `dev` usa `presets.trigger_pause_status: PAUSED` para manter o job pausado sem tocar em nomes de schema.
- **`resources/*.yml`** é incluído via `include:` no `databricks.yml` — cada arquivo YAML nessa pasta vira jobs, pipelines, schemas ou volumes do bundle.
- **A criação do catálogo em si fica fora do bundle**, via um script SQL separado (não via `resources.catalogs`) — o provider Terraform do bundle recusa criar catálogo em workspaces com Default Storage habilitado (comum em contas Free Edition), que exigem managed location explícita. Os schemas/volumes dentro do catálogo, sim, são recursos do bundle.
- **`tests/conftest.py` roda contra um cluster/serverless real** — sem camada de mock para Spark. Isso significa que os testes deste projeto validam contra o workspace de verdade, não contra fixtures isoladas; trate-os como testes de integração.
- **`rotaperfume/CLAUDE.md` importa `rotaperfume/AGENTS.md`** (`@AGENTS.md`), que por sua vez manda ler a skill `databricks-core` (instalada em `.databricks/aitools/skills/`, via `databricks aitools install`) antes de qualquer ação — ela cobre autenticação de CLI, seleção de profile e o fluxo de deploy do bundle.
- **`docs/superpowers/plans/`** guarda planos de implementação escritos pelo fluxo `superpowers:writing-plans`/`executing-plans` (um arquivo por feature, com data no nome). Eles descrevem passo a passo o que *vai* ser construído — confira o estado real dos arquivos antes de assumir que um plano já foi executado.

## Cuidado com ações irreversíveis no workspace

Comandos como `databricks bundle deploy`, `databricks bundle run`, criação de catálogo/schema/volume e upload para Volumes alteram um workspace Databricks real (o mesmo já referenciado em `databricks.yml`). Confirme com o usuário antes de rodar qualquer um desses contra o workspace — não são revertidos por `git revert`.
