# Silver — Limpeza, Tipagem e Contrato de Dados — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`) para rastreamento.

**Goal:** Entregar o terceiro dos 6 prompts da série "Jornada de Dados": criar a camada silver do bundle `rotaperfume` — 10 tabelas Delta em `lakehouse_rotaperfume.silver.*`, uma por assunto de negócio, limpas e tipadas a partir da bronze (sem nenhuma limpeza), com o contrato de dados declarado via `ALTER TABLE ... ADD CONSTRAINT`. Quatro tarefas `sql_task` novas entram no job `rotaperfume_pipeline`, todas dependentes só de `bronze_ingestao`, rodando em paralelo entre si.

**Architecture:** Cada assunto de negócio vira um arquivo `.sql` em `src/silver/` (`01-clientes.sql`, `02-pedidos.sql`, `03-itens-e-produtos.sql`, `04-crm-e-financeiro.sql`), executado como `sql_task` (não `notebook_task` — este prompt não usa Python). Cada arquivo lê direto de `bronze.*` (nunca de outra tabela silver, mesmo dentro do próprio arquivo, quando um arquivo cria mais de uma tabela) — isso é o que garante que as 4 tarefas possam rodar em paralelo de verdade, sem dependência de dados entre si. `CREATE OR REPLACE TABLE` reprocessa cada tabela do zero a cada run (silver não é incremental neste prompt). Diferente dos dois prompts anteriores, não há módulo Python puro + pytest aqui: não existe lógica Python para extrair, e a validação certa já está definida pelo próprio prompt da aula — as `ALTER TABLE ... ADD CONSTRAINT` reais, rodando contra dado real, são o teste (se uma constraint falhar ao ser adicionada, o pipeline falha e expõe a suposição errada, em vez de silenciosamente aceitar dado ruim).

**Descoberta crítica desta sessão de planejamento (testada ao vivo, não é suposição):** `sql_task.file` com `source: WORKSPACE` só executa um arquivo `.sql` com múltiplas instruções separadas por `;` (necessário aqui: `CREATE TABLE` + `COMMENT` + `ALTER TABLE ADD CONSTRAINT` no mesmo arquivo) quando o Databricks trata o arquivo como um objeto de workspace do tipo **FILE**. Se o arquivo for sincronizado como **NOTEBOOK** (o que acontece automaticamente se a primeira linha for o marcador especial `-- Databricks notebook source`, o mesmo padrão usado nos notebooks Python dos prompts 1 e 2), o `sql_task` falha com `Unable to fetch SQL file from path`. Testado nesta sessão com um job descartável real: subi o mesmo arquivo primeiro como NOTEBOOK (falhou) e depois como FILE puro (rodou as 3 instruções com sucesso, confirmado via `SHOW TBLPROPERTIES` e `COMMENT`). Conclusão: nenhum arquivo em `src/silver/*.sql` pode começar com `-- Databricks notebook source` nem qualquer outro marcador de notebook — só comentários `--` normais.

**Tech Stack:** Databricks Asset Bundle (DAB) YAML, Databricks CLI v1.13.0 (perfil `Emerson`), SQL puro (`sql_task`), Unity Catalog (schema `silver`, Delta tables, `CHECK` constraints), SQL warehouse serverless `2c807bf97ff3fec4`.

## Global Constraints

- **Profile obrigatório:** `Emerson` — único profile válido em `databricks auth profiles`. Todo comando `databricks` passa `--profile Emerson` explicitamente. O prompt original da aula usa `projeto-dados-ia`; **ignore-o**.
- **ANSI mode está ligado neste warehouse — confirmado com um erro real nesta sessão:** `SELECT to_date('16/10/2024', 'yyyy-MM-dd')` retornou `BAD_REQUEST [CANNOT_PARSE_TIMESTAMP] Text '16/10/2024' could not be parsed at index 0. Use try_to_date to tolerate invalid input string and return NULL instead.` **Toda conversão de data em todo arquivo usa `try_to_date`, nunca `to_date`, `date_trunc` sobre string, ou `CAST(... AS DATE)`.**
- **`sql_task.file` não substitui variável de bundle dentro do conteúdo do `.sql`** — todo caminho de tabela é escrito literalmente `lakehouse_rotaperfume.silver.x` (nunca `${var.catalog}`) nos 4 arquivos `.sql`. Só o YAML do job usa `${var.warehouse_id}`.
- **Nenhum arquivo `.sql` em `src/silver/` pode começar com `-- Databricks notebook source`** (ou qualquer marcador de notebook) — isso faria o bundle sincronizá-lo como NOTEBOOK em vez de FILE, e `sql_task.file` falha ao tentar buscar um NOTEBOOK (confirmado nesta sessão, ver "Descoberta crítica" acima). Comentários de cabeçalho normais (`-- rotaperfume/src/silver/...`) são o suficiente e seguros.
- **`CREATE OR REPLACE TABLE`, nunca `CREATE TABLE IF NOT EXISTS`** — cada run reprocessa a tabela inteira a partir da bronze.
- **As 4 tarefas `sql_task` rodam em paralelo** — todas com `depends_on: bronze_ingestao`, nenhuma dependendo de outra tarefa `sql_task`. Dentro de `03-itens-e-produtos.sql` e `04-crm-e-financeiro.sql` (que criam mais de uma tabela cada), toda tabela lê direto de `bronze.*`, nunca da silver criada por um `CREATE` anterior no mesmo arquivo — mantém cada arquivo livre de ordem de execução interna e sem dependência cruzada com os outros 3 arquivos.
- **Números de referência (seed 42, TODOS verificados agora com queries reais contra a bronze — não são do prompt, são medidos):**
  - `clientes`: 3.040 linhas na bronze; 1.111 CNPJ pontuados; 223 CNPJ com espaço em volta; 309 CNPJ (dos 14 dígitos normalizados) começam com `0`; 40 CNPJs normalizados aparecem em 2 `cliente_id` cada → **3.000 clientes únicos** esperados em silver.
  - `pedidos`: 28.729 linhas; **3.443** com `data_pedido` em `dd/MM/yyyy`; **957** com `status = 'Cancelado'` (maiúscula exata); **135** pedidos com `valor_total` NEGATIVO na própria bronze, NENHUM deles cancelado (são `'Entregue'`/`'Faturado'` com devolução) — a constraint certa (`NOT cancelado OR valor_liquido = 0`) não falha nessas 135 linhas; a versão ingênua `valor_liquido >= 0` FALHARIA.
  - `itens_pedido`: 197.724 linhas; **2.327** com `quantidade` negativa (devolução); 0 linhas com `quantidade = 0` (a constraint `quantidade_abs > 0` não falha em nenhuma linha); **76** linhas cujo `sku` aponta para um produto com `bronze.produtos.ativo = 'N'`.
  - `produtos`: 292 linhas, `sku` é único (292 distintos); todo `sku` de `itens_pedido` tem correspondente em `produtos` (JOIN/LEFT JOIN não perde nem duplica linha).
  - `carteira`: 3.637 linhas; todo `vendedor_id` de `carteira` tem correspondente em `vendedores` (INNER JOIN não perde linha, confirmado: `COUNT(*) = COUNT(* com JOIN) = 3637`); **441** linhas com `data_fim IS NULL` (carteira "ativa" pela data) e o vendedor correspondente com `data_desligamento IS NOT NULL`.
  - `oportunidades`: valores distintos reais de `etapa` (confirmado com `SELECT DISTINCT`): `'Fechado ganho'`, `'Fechado perdido'`, `'Negociação'`, `'Proposta enviada'`, `'Prospecção'`, `'Qualificação'` — nunca `'Ganha'`/`'Perdida'`.
  - `vendedores`/`carteira`/`data_desligamento`/`data_fim`: quando vazios no CSV original, viram SQL `NULL` de verdade em bronze (confirmado: 0 linhas com string vazia `''`, só `NULL`) — não precisa checar `= ''` em lugar nenhum.
- **Todos os comandos bash/`databricks` assumem `cwd = rotaperfume/`.** Use caminho absoluto ao fazer `cd` — nunca `cd rotaperfume` relativo (já causou pasta aninhada bugada numa sessão anterior).
- **NÃO mexer em:** `databricks.yml`, `resources/catalogo.yml`, `scripts/*.sh`, `src/raw/*`, `src/bronze/*`, `tests_unit/*` — todos já prontos, corretos e deployados.
- **Ações contra o workspace real** (`databricks bundle deploy`, `databricks bundle run`) alteram recursos de verdade — cada uma tem nota pedindo confirmação, mas a execução completa deste plano via Subagent-Driven Development já está autorizada pelo usuário fora deste documento.
- **Convenção de commit:** mensagens curtas em português, `feat(rotaperfume): <o que foi adicionado>`. `git add` de arquivos específicos, nunca `git add -A`.

---

## File Structure

```
rotaperfume/
├── resources/
│   └── pipeline.job.yml                # MODIFICAR — + 4 tarefas sql_task paralelas, depends_on bronze_ingestao
└── src/
    └── silver/
        ├── 01-clientes.sql             # NOVO
        ├── 02-pedidos.sql              # NOVO
        ├── 03-itens-e-produtos.sql     # NOVO
        └── 04-crm-e-financeiro.sql     # NOVO
```

---

### Task 1: `src/silver/01-clientes.sql` — CNPJ, razão social, dedup

**Files:**
- Create: `rotaperfume/src/silver/01-clientes.sql`

**Interfaces:**
- Consumes: `lakehouse_rotaperfume.bronze.clientes` (todas colunas STRING).
- Produces: `lakehouse_rotaperfume.silver.clientes` (3.000 linhas esperadas), com `cliente_ids_duplicados` (array de bigint) rastreando os `cliente_id` descartados na deduplicação por CNPJ.

- [ ] **Step 1: Criar o arquivo**

```sql
-- rotaperfume/src/silver/01-clientes.sql
-- Silver de clientes: normaliza CNPJ para 14 digitos, padroniza razao
-- social, resolve data de cadastro em dois formatos, e deduplica os 40
-- CNPJs que hoje tem dois cliente_id (mantendo o cadastro mais antigo).
--
-- ANSI mode esta ligado neste warehouse: to_date()/CAST(...AS DATE) sobre
-- data malformada ABORTA a query. Por isso toda conversao de data usa
-- try_to_date, nunca to_date.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH bronze_tipado AS (
  SELECT
    cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    regexp_replace(initcap(trim(razao_social)), ' {2,}', ' ') AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(
      try_to_date(data_cadastro, 'yyyy-MM-dd'),
      try_to_date(data_cadastro, 'dd/MM/yyyy')
    ) AS data_cadastro,
    (ativo = 'S') AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
ranqueado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY cnpj ORDER BY data_cadastro ASC, cliente_id ASC
    ) AS rn,
    collect_list(cliente_id) OVER (PARTITION BY cnpj) AS todos_os_ids_do_cnpj
  FROM bronze_tipado
),
total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.clientes
)
SELECT
  cliente_id,
  cnpj,
  razao_social,
  segmento,
  cidade,
  uf,
  bairro,
  data_cadastro,
  ativo,
  filter(todos_os_ids_do_cnpj, id -> id != cliente_id) AS cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM ranqueado
CROSS JOIN total_bronze
WHERE rn = 1;

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados a partir de bronze.clientes. CNPJ normalizado para 14 digitos; 40 CNPJs tinham dois cliente_id -- mantido o cadastro mais antigo, o outro rastreavel via cliente_ids_duplicados.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cnpj IS
  'Normalizado para 14 digitos: trim, remove tudo que nao e digito, lpad com zero a esquerda. Nunca convertido para numero (perderia zeros a esquerda).';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.razao_social IS
  'Padronizada com initcap e espacos duplos colapsados -- a origem tem caixa e espacamento inconsistentes.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.data_cadastro IS
  'Convertida de dois formatos misturados na origem (ISO e dd/MM/yyyy) via try_to_date -- ANSI mode aborta com to_date/CAST direto sobre o formato errado.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cliente_ids_duplicados IS
  'IDs descartados na deduplicacao por CNPJ (array vazio quando o cliente nao tinha duplicata). Pedidos/oportunidades antigos podem apontar para um desses IDs em vez do cliente_id sobrevivente.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.ativo IS
  'Convertida de S/N (bronze) para boolean.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_cnpj_14_digitos CHECK (length(cnpj) = 14);

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_data_cadastro_nao_nula CHECK (data_cadastro IS NOT NULL);
```

- [ ] **Step 2: Confirmar contra a bronze real (leitura pura, sem confirmação necessária)**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN cnpj LIKE '%.%' THEN 1 ELSE 0 END) AS pontuados,
  SUM(CASE WHEN cnpj != trim(cnpj) THEN 1 ELSE 0 END) AS com_espaco
FROM lakehouse_rotaperfume.bronze.clientes
"
```
Expected: `total=3040`, `pontuados=1111`, `com_espaco=223` (já verificado nesta sessão — este passo é só uma reconfirmação antes de commitar).

- [ ] **Step 3: Commit**

```bash
git add src/silver/01-clientes.sql
git commit -m "feat(rotaperfume): silver clientes -- cnpj normalizado, dedup por cnpj mantendo mais antigo"
```

---

### Task 2: `src/silver/02-pedidos.sql` — data, valor_total, cancelado, valor_liquido

**Files:**
- Create: `rotaperfume/src/silver/02-pedidos.sql`

**Interfaces:**
- Consumes: `lakehouse_rotaperfume.bronze.pedidos`.
- Produces: `lakehouse_rotaperfume.silver.pedidos` (28.729 linhas esperadas, mesma contagem da bronze).

- [ ] **Step 1: Criar o arquivo**

```sql
-- rotaperfume/src/silver/02-pedidos.sql
-- Silver de pedidos: resolve data em dois formatos, tipa valor_total, e
-- cria as colunas de negocio que a bronze nao tem: cancelado (a partir
-- do status), valor_liquido (zero quando cancelado), e ano/mes para
-- corte temporal.
--
-- ANSI mode esta ligado neste warehouse: to_date()/CAST(...AS DATE) sobre
-- data malformada ABORTA a query. Por isso toda conversao de data usa
-- try_to_date, nunca to_date.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
WITH bronze_tipado AS (
  SELECT
    pedido_id,
    cliente_id,
    vendedor_id,
    coalesce(
      try_to_date(data_pedido, 'yyyy-MM-dd'),
      try_to_date(data_pedido, 'dd/MM/yyyy')
    ) AS data_pedido,
    canal,
    status,
    (status = 'Cancelado') AS cancelado,
    CAST(valor_total AS DECIMAL(18,2)) AS valor_total
  FROM lakehouse_rotaperfume.bronze.pedidos
),
total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.pedidos
)
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  data_pedido,
  canal,
  status,
  cancelado,
  valor_total,
  CASE WHEN cancelado THEN CAST(0 AS DECIMAL(18,2)) ELSE valor_total END AS valor_liquido,
  year(data_pedido) AS ano,
  month(data_pedido) AS mes,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM bronze_tipado
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Pedidos tipados a partir de bronze.pedidos. cancelado e valor_liquido resolvem o problema de pedido cancelado com valor_total preenchido sem flag clara na origem.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.data_pedido IS
  'Convertida de dois formatos misturados na origem (ISO e dd/MM/yyyy) via try_to_date -- ANSI mode aborta com to_date/CAST direto sobre o formato errado.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.cancelado IS
  'true quando status = "Cancelado". A origem zera valor_total de pedidos cancelados sem nenhuma flag explicita -- esta coluna torna a regra de negocio visivel.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.valor_liquido IS
  'Zero quando cancelado; valor_total nos demais casos. PODE SER NEGATIVO em pedidos nao cancelados: 135 pedidos tem devolucao que deixou o saldo do pedido negativo -- comportamento de negocio legitimo, nao sujeira. A constraint desta tabela exige valor ZERO apenas quando cancelado, nunca "valor_liquido >= 0".';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.ano IS
  'Extraido de data_pedido (ja convertida) para corte temporal em relatorios.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.mes IS
  'Extraido de data_pedido (ja convertida) para corte temporal em relatorios.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_data_pedido_nao_nula CHECK (data_pedido IS NOT NULL);

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_cancelado_valor_zero CHECK (NOT cancelado OR valor_liquido = 0);
```

- [ ] **Step 2: Confirmar contra a bronze real (leitura pura, sem confirmação necessária)**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  SUM(CASE WHEN data_pedido NOT LIKE '____-__-__' THEN 1 ELSE 0 END) AS formato_br,
  SUM(CASE WHEN status = 'Cancelado' THEN 1 ELSE 0 END) AS cancelados,
  SUM(CASE WHEN CAST(valor_total AS DECIMAL(18,2)) < 0 AND status != 'Cancelado' THEN 1 ELSE 0 END) AS nao_cancelados_negativos
FROM lakehouse_rotaperfume.bronze.pedidos
"
```
Expected: `formato_br=3443`, `cancelados=957`, `nao_cancelados_negativos=135` (já verificado nesta sessão).

- [ ] **Step 3: Commit**

```bash
git add src/silver/02-pedidos.sql
git commit -m "feat(rotaperfume): silver pedidos -- data dupla, cancelado, valor_liquido, ano/mes"
```

---

### Task 3: `src/silver/03-itens-e-produtos.sql` — produtos, devolução, SKU descontinuado

**Files:**
- Create: `rotaperfume/src/silver/03-itens-e-produtos.sql`

**Interfaces:**
- Consumes: `lakehouse_rotaperfume.bronze.produtos`, `lakehouse_rotaperfume.bronze.itens_pedido`.
- Produces: `lakehouse_rotaperfume.silver.produtos` (292 linhas), `lakehouse_rotaperfume.silver.itens_pedido` (197.724 linhas).

- [ ] **Step 1: Criar o arquivo**

```sql
-- rotaperfume/src/silver/03-itens-e-produtos.sql
-- Silver de produtos e itens_pedido: tipagem de produtos, e o par
-- devolucao/quantidade_abs que preserva quantidade negativa (devolucao)
-- em vez de trata-la como erro. sku_descontinuado marca itens vendidos
-- de um produto que hoje esta inativo -- join direto com bronze.produtos,
-- sem depender da silver.produtos criada acima no mesmo arquivo.
--
-- ANSI mode esta ligado neste warehouse: to_date()/CAST(...AS DATE) sobre
-- data malformada ABORTA a query. Por isso toda conversao de data usa
-- try_to_date, nunca to_date.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.produtos
)
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18,2)) AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18,2)) AS custo_unitario,
  unidade,
  (ativo = 'S') AS ativo,
  try_to_date(data_lancamento, 'yyyy-MM-dd') AS data_lancamento,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Produtos tipados a partir de bronze.produtos.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.produtos.ativo IS
  'Convertida de S/N (bronze) para boolean. Usada por silver.itens_pedido para marcar sku_descontinuado.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.produtos.data_lancamento IS
  'NULL e legitimo: produto lancado antes do inicio da serie historica ou ainda nao lancado.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.itens_pedido
)
SELECT
  i.item_id,
  i.pedido_id,
  i.sku,
  CAST(i.quantidade AS INT) AS quantidade,
  abs(CAST(i.quantidade AS INT)) AS quantidade_abs,
  (CAST(i.quantidade AS INT) < 0) AS devolucao,
  CAST(i.preco_praticado AS DECIMAL(18,2)) AS preco_praticado,
  CAST(i.desconto_pct AS DECIMAL(5,2)) AS desconto_pct,
  CAST(i.valor_bruto AS DECIMAL(18,2)) AS valor_bruto,
  coalesce(p.ativo = 'N', false) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.itens_pedido i
LEFT JOIN lakehouse_rotaperfume.bronze.produtos p ON p.sku = i.sku
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Itens de pedido tipados a partir de bronze.itens_pedido. Linhas com quantidade negativa (devolucao) sao mantidas, nunca descartadas.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.devolucao IS
  'true quando a quantidade original (bronze) e negativa. A origem usa quantidade negativa para representar devolucao, nao erro de digitacao.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.quantidade_abs IS
  'Valor absoluto de quantidade, sempre positivo, para uso em somas de volume sem o sinal de devolucao atrapalhar.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.sku_descontinuado IS
  'true quando o produto (bronze.produtos.ativo = "N") nao esta mais ativo hoje -- o item foi vendido quando o produto ainda existia no catalogo. LEFT JOIN + coalesce evita NULL caso o sku nao exista em produtos.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT itens_pedido_quantidade_abs_positiva CHECK (quantidade_abs > 0);
```

- [ ] **Step 2: Confirmar contra a bronze real (leitura pura, sem confirmação necessária)**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido WHERE CAST(quantidade AS INT) < 0) AS devolucoes,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido WHERE CAST(quantidade AS INT) = 0) AS quantidade_zero,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido i JOIN lakehouse_rotaperfume.bronze.produtos p ON i.sku = p.sku WHERE p.ativo = 'N') AS sku_descontinuado
"
```
Expected: `devolucoes=2327`, `quantidade_zero=0` (a constraint `quantidade_abs > 0` não vai falhar em nenhuma linha), `sku_descontinuado=76` (já verificado nesta sessão).

- [ ] **Step 3: Commit**

```bash
git add src/silver/03-itens-e-produtos.sql
git commit -m "feat(rotaperfume): silver produtos e itens_pedido -- devolucao, quantidade_abs, sku_descontinuado"
```

---

### Task 4: `src/silver/04-crm-e-financeiro.sql` — vendedores, carteira, oportunidades, visitas, pagamentos, estoque

**Files:**
- Create: `rotaperfume/src/silver/04-crm-e-financeiro.sql`

**Interfaces:**
- Consumes: `lakehouse_rotaperfume.bronze.{vendedores,carteira,oportunidades,visitas,pagamentos,estoque}`.
- Produces: as 6 tabelas silver correspondentes, mesma contagem de linhas da bronze em cada uma (42, 3.637, 5.979, 37.936, 27.772, 8.400).

- [ ] **Step 1: Criar o arquivo**

```sql
-- rotaperfume/src/silver/04-crm-e-financeiro.sql
-- Silver de CRM e financeiro: vendedores, carteira, oportunidades,
-- visitas, pagamentos, estoque -- seis tabelas do mesmo assunto de
-- negocio (quem vende, para quem, e o que fica pendente/parado).
--
-- ANSI mode esta ligado neste warehouse: to_date()/CAST(...AS DATE) sobre
-- data malformada ABORTA a query. Por isso toda conversao de data usa
-- try_to_date, nunca to_date.

-- ---------------------------------------------------------------------
-- silver.vendedores -- so tipagem. data_desligamento NULL = ainda ativo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.vendedores
)
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  try_to_date(data_admissao, 'yyyy-MM-dd') AS data_admissao,
  try_to_date(data_desligamento, 'yyyy-MM-dd') AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18,2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Vendedores tipados a partir de bronze.vendedores.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.vendedores.data_desligamento IS
  'NULL = vendedor ainda ativo. silver.carteira usa esta informacao (via join com bronze.vendedores) para calcular vigente/orfao_vendedor_desligado.';

-- ---------------------------------------------------------------------
-- silver.carteira -- vigente e orfao_vendedor_desligado EXPOEM o
-- problema (vendedor desligado com carteira sem data_fim) em vez de
-- consertar o dado. Join direto com bronze.vendedores, nao com a
-- silver.vendedores criada acima -- cada tabela deste arquivo le direto
-- da bronze, sem depender da ordem de execucao dos CREATE dentro do
-- proprio script. Confirmado nesta sessao: todo vendedor_id de carteira
-- tem correspondente em vendedores (INNER JOIN nao perde linha).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.carteira
)
SELECT
  c.carteira_id,
  c.cliente_id,
  c.vendedor_id,
  try_to_date(c.data_inicio, 'yyyy-MM-dd') AS data_inicio,
  try_to_date(c.data_fim, 'yyyy-MM-dd') AS data_fim,
  (c.data_fim IS NULL AND v.data_desligamento IS NULL) AS vigente,
  (c.data_fim IS NULL AND v.data_desligamento IS NOT NULL) AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.carteira c
JOIN lakehouse_rotaperfume.bronze.vendedores v ON v.vendedor_id = c.vendedor_id
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Carteira de clientes por vendedor, tipada a partir de bronze.carteira. Existem vendedores desligados com carteira sem data_fim -- o dado NAO foi corrigido, apenas exposto (ver orfao_vendedor_desligado).';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.vigente IS
  'true somente quando a carteira nao tem data_fim E o vendedor nao tem data_desligamento. Respeita as DUAS datas de proposito.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.orfao_vendedor_desligado IS
  'true quando a carteira segue sem data_fim mas o vendedor ja foi desligado -- expoe o problema para o gestor em vez de corrigi-lo silenciosamente.';

-- ---------------------------------------------------------------------
-- silver.oportunidades -- as etapas de fechamento na origem sao
-- "Fechado ganho"/"Fechado perdido" (confirmado com SELECT DISTINCT
-- etapa contra a bronze antes de escrever este CASE) -- NUNCA
-- "Ganha"/"Perdida".
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.oportunidades
)
SELECT
  oportunidade_id,
  cliente_id,
  vendedor_id,
  origem,
  try_to_date(data_abertura, 'yyyy-MM-dd') AS data_abertura,
  etapa,
  CASE etapa
    WHEN 'Fechado ganho' THEN true
    WHEN 'Fechado perdido' THEN false
    ELSE NULL
  END AS ganha,
  CAST(probabilidade_pct AS DECIMAL(5,2)) AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18,2)) AS valor_estimado,
  try_to_date(data_fechamento, 'yyyy-MM-dd') AS data_fechamento,
  CAST(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Oportunidades tipadas a partir de bronze.oportunidades. Etapas de fechamento na origem sao "Fechado ganho" e "Fechado perdido" (nao "Ganha"/"Perdida") -- confirmado com SELECT DISTINCT etapa antes de escrever o CASE abaixo.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.oportunidades.ganha IS
  'true = etapa "Fechado ganho", false = etapa "Fechado perdido", NULL = oportunidade ainda em andamento (Prospeccao, Qualificacao, Proposta enviada, Negociacao).';

-- ---------------------------------------------------------------------
-- silver.visitas -- so tipagem (data e duracao).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.visitas
)
SELECT
  visita_id,
  cliente_id,
  vendedor_id,
  try_to_date(data_visita, 'yyyy-MM-dd') AS data_visita,
  resultado,
  CAST(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Visitas tipadas a partir de bronze.visitas -- so conversao de tipo, sem sujeira conhecida nesta tabela.';

-- ---------------------------------------------------------------------
-- silver.pagamentos -- so tipagem (datas e valores). data_pagamento NULL
-- e legitimo: pagamento ainda nao realizado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.pagamentos
)
SELECT
  pagamento_id,
  pedido_id,
  forma_pagamento,
  CAST(parcelas AS INT) AS parcelas,
  CAST(valor AS DECIMAL(18,2)) AS valor,
  CAST(taxa_pct AS DECIMAL(5,2)) AS taxa_pct,
  CAST(valor_liquido AS DECIMAL(18,2)) AS valor_liquido,
  try_to_date(data_vencimento, 'yyyy-MM-dd') AS data_vencimento,
  try_to_date(data_pagamento, 'yyyy-MM-dd') AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Pagamentos tipados a partir de bronze.pagamentos.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pagamentos.data_pagamento IS
  'NULL e legitimo: pagamento agendado (data_vencimento preenchida) mas ainda nao realizado.';

-- ---------------------------------------------------------------------
-- silver.estoque -- ruptura recalculada do zero a partir de saldo = 0,
-- IGNORANDO a coluna ruptura ja existente em bronze (a instrucao desta
-- entrega pede explicitamente para nao reaproveitar o valor cru).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
WITH total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.estoque
)
SELECT
  try_to_date(data_snapshot, 'yyyy-MM-dd') AS data_snapshot,
  sku,
  CAST(saldo AS INT) AS saldo,
  (CAST(saldo AS INT) = 0) AS ruptura,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque
CROSS JOIN total_bronze;

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Snapshots diarios de estoque tipados a partir de bronze.estoque.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.estoque.ruptura IS
  'Recalculada do zero a partir de saldo = 0 -- nao reaproveita a coluna ruptura ja existente em bronze.estoque (string S/N), por instrucao explicita desta entrega.';
```

- [ ] **Step 2: Confirmar contra a bronze real (leitura pura, sem confirmação necessária)**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT DISTINCT etapa FROM lakehouse_rotaperfume.bronze.oportunidades ORDER BY etapa
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT COUNT(*) AS carteiras_orfas
FROM lakehouse_rotaperfume.bronze.carteira c
JOIN lakehouse_rotaperfume.bronze.vendedores v ON v.vendedor_id = c.vendedor_id
WHERE c.data_fim IS NULL AND v.data_desligamento IS NOT NULL
"
```
Expected: a primeira query lista exatamente `Fechado ganho`, `Fechado perdido`, `Negociação`, `Proposta enviada`, `Prospecção`, `Qualificação` (6 valores); a segunda retorna `carteiras_orfas = 441` (já verificado nesta sessão).

- [ ] **Step 3: Commit**

```bash
git add src/silver/04-crm-e-financeiro.sql
git commit -m "feat(rotaperfume): silver crm/financeiro -- vigente, orfao_vendedor_desligado, ganha, ruptura"
```

---

### Task 5: `resources/pipeline.job.yml` — 4 tarefas `sql_task` paralelas

**Files:**
- Modify: `rotaperfume/resources/pipeline.job.yml`

**Interfaces:**
- Consumes: `${var.warehouse_id}` (já declarado em `databricks.yml`); os 4 arquivos `src/silver/*.sql` (Tarefas 1–4); tarefa `bronze_ingestao` já existente.
- Produces: job `rotaperfume_pipeline` com 6 tarefas: `raw_conferencia` → `bronze_ingestao` → (`silver_clientes`, `silver_pedidos`, `silver_itens_e_produtos`, `silver_crm_e_financeiro` em paralelo, todas com `depends_on: bronze_ingestao`).

- [ ] **Step 1: Editar o arquivo — conteúdo integral resultante**

```yaml
# Job rotaperfume_pipeline -- cresce a cada prompt da serie "Jornada de Dados":
#   Prompt 1: raw_conferencia -- confere a chegada dos 10 CSVs no Volume
#             bronze.raw. NAO cria tabela bronze.
#   Prompt 2: + bronze_ingestao -- CSV -> tabelas Delta em bronze, sem
#             limpeza, so depois de raw_conferencia passar.
#   Prompt 3 (este arquivo): + silver_clientes / silver_pedidos /
#             silver_itens_e_produtos / silver_crm_e_financeiro -- limpeza,
#             tipagem e contrato (CHECK) em silver. As 4 rodam EM
#             PARALELO: todas dependem so de bronze_ingestao, nenhuma
#             depende das outras -- cada .sql le direto da bronze, nunca
#             da silver de outro arquivo.
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
        - task_key: silver_clientes
          depends_on:
            - task_key: bronze_ingestao
          sql_task:
            file:
              path: ../src/silver/01-clientes.sql
              source: WORKSPACE
            warehouse_id: ${var.warehouse_id}
        - task_key: silver_pedidos
          depends_on:
            - task_key: bronze_ingestao
          sql_task:
            file:
              path: ../src/silver/02-pedidos.sql
              source: WORKSPACE
            warehouse_id: ${var.warehouse_id}
        - task_key: silver_itens_e_produtos
          depends_on:
            - task_key: bronze_ingestao
          sql_task:
            file:
              path: ../src/silver/03-itens-e-produtos.sql
              source: WORKSPACE
            warehouse_id: ${var.warehouse_id}
        - task_key: silver_crm_e_financeiro
          depends_on:
            - task_key: bronze_ingestao
          sql_task:
            file:
              path: ../src/silver/04-crm-e-financeiro.sql
              source: WORKSPACE
            warehouse_id: ${var.warehouse_id}
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
Expected: sem erros nem warnings; lista o job `rotaperfume_pipeline` com 6 tarefas, as 4 `silver_*` mostrando `depends_on: bronze_ingestao` e nenhuma dependência entre si.

- [ ] **Step 3: Commit**

```bash
git add resources/pipeline.job.yml
git commit -m "feat(rotaperfume): 4 tarefas sql_task de silver, paralelas, dependentes de bronze_ingestao"
```

---

### Task 6: Deploy, execução real e verificação de todos os números e das 5 constraints

**Files:** nenhum arquivo novo — só executa o que as Tarefas 1–5 versionaram, contra o workspace real.

**Interfaces:**
- Consumes: tudo (4 arquivos `.sql`, job atualizado, bronze já populada).
- Produces: as 10 tabelas Delta em `lakehouse_rotaperfume.silver` com as contagens exatas e as 5 constraints ativas.

- [ ] **Step 1: Deploy**

> Confirme com o usuário antes deste passo — publica as 4 novas tarefas do job no workspace real.

Run (a partir de `rotaperfume/`):
```bash
databricks bundle deploy --target dev --profile Emerson
```
Expected: sem erro; `databricks bundle summary --target dev --profile Emerson -o json` mostra as 6 tarefas em `resources.jobs.rotaperfume_pipeline.tasks`.

- [ ] **Step 2: Confirmar que os 4 `.sql` foram sincronizados como FILE, não NOTEBOOK**

> Este passo é só leitura — não altera nada, mas é crítico: se algum `.sql` virou NOTEBOOK, o Step 4 vai falhar com `Unable to fetch SQL file from path` (comportamento confirmado nesta sessão de planejamento com um teste real).

Run:
```bash
databricks workspace list /Workspace/Users/emersonfab06@gmail.com/.bundle/rotaperfume/dev/files/src/silver --profile Emerson -o json
```
Expected: 4 entradas, todas com `"object_type": "FILE"` (nunca `"NOTEBOOK"`), uma para cada `01-clientes.sql`, `02-pedidos.sql`, `03-itens-e-produtos.sql`, `04-crm-e-financeiro.sql`. Se alguma aparecer como `NOTEBOOK`: pare, não prossiga para o Step 4 — isso significa que o arquivo `.sql` correspondente ganhou um marcador de notebook por engano; volte à Tarefa correspondente (1–4) e confira a primeira linha do arquivo.

- [ ] **Step 3: Rodar o pipeline completo**

> Confirme com o usuário antes deste passo — dispara uma execução real do job (cria/substitui 10 tabelas silver e tenta aplicar 5 constraints contra dado real).

Run:
```bash
databricks bundle run rotaperfume_pipeline --target dev --profile Emerson
```
Expected: termina com sucesso (exit code 0); as 6 tarefas aparecem como `SUCCESS`, as 4 `silver_*` com horários de início sobrepostos (prova visual de paralelismo no DAG, visível na `run_page_url` retornada).

- [ ] **Step 4: Contagem geral por tabela silver**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
WITH silver_contagens AS (
  SELECT 'clientes' AS tabela, COUNT(*) AS linhas FROM lakehouse_rotaperfume.silver.clientes
  UNION ALL SELECT 'pedidos', COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos
  UNION ALL SELECT 'itens_pedido', COUNT(*) FROM lakehouse_rotaperfume.silver.itens_pedido
  UNION ALL SELECT 'produtos', COUNT(*) FROM lakehouse_rotaperfume.silver.produtos
  UNION ALL SELECT 'vendedores', COUNT(*) FROM lakehouse_rotaperfume.silver.vendedores
  UNION ALL SELECT 'carteira', COUNT(*) FROM lakehouse_rotaperfume.silver.carteira
  UNION ALL SELECT 'oportunidades', COUNT(*) FROM lakehouse_rotaperfume.silver.oportunidades
  UNION ALL SELECT 'visitas', COUNT(*) FROM lakehouse_rotaperfume.silver.visitas
  UNION ALL SELECT 'pagamentos', COUNT(*) FROM lakehouse_rotaperfume.silver.pagamentos
  UNION ALL SELECT 'estoque', COUNT(*) FROM lakehouse_rotaperfume.silver.estoque
)
SELECT * FROM silver_contagens ORDER BY linhas DESC
"
```
Expected: `itens_pedido=197724`, `visitas=37936`, `pedidos=28729`, `pagamentos=27772`, `estoque=8400`, `clientes=3000` (única que encolhe, por dedup), `carteira=3637`, `oportunidades=5979`, `produtos=292`, `vendedores=42` — todas iguais à bronze, exceto `clientes`.

- [ ] **Step 5: CNPJ — formatos, duplicados e únicos**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  COUNT(*) AS total_clientes_bronze,
  SUM(CASE WHEN cnpj LIKE '%.%' THEN 1 ELSE 0 END) AS cnpj_pontuados,
  SUM(CASE WHEN cnpj != trim(cnpj) THEN 1 ELSE 0 END) AS cnpj_com_espaco,
  SUM(CASE WHEN lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') LIKE '0%' THEN 1 ELSE 0 END) AS cnpj_zero_a_esquerda
FROM lakehouse_rotaperfume.bronze.clientes
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT COUNT(*) AS clientes_unicos_silver FROM lakehouse_rotaperfume.silver.clientes
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT COUNT(*) AS clientes_com_duplicados_rastreados
FROM lakehouse_rotaperfume.silver.clientes
WHERE size(cliente_ids_duplicados) > 0
"
```
Expected: `total_clientes_bronze=3040`, `cnpj_pontuados=1111`, `cnpj_com_espaco=223`, `cnpj_zero_a_esquerda=309`; `clientes_unicos_silver=3000`; `clientes_com_duplicados_rastreados=40`.

- [ ] **Step 6: Datas em `dd/MM/yyyy` e sucesso da conversão**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT SUM(CASE WHEN data_pedido NOT LIKE '____-__-__' THEN 1 ELSE 0 END) AS pedidos_formato_br
FROM lakehouse_rotaperfume.bronze.pedidos
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT COUNT(*) AS pedidos_data_null FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL
"
```
Expected: `pedidos_formato_br=3443`; `pedidos_data_null=0` (prova que os 3.443 converteram com sucesso, nenhum virou NULL — e a constraint `pedidos_data_pedido_nao_nula` não falharia).

- [ ] **Step 7: Cancelados e a armadilha dos 135 valores negativos**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  SUM(CASE WHEN cancelado THEN 1 ELSE 0 END) AS pedidos_cancelados,
  SUM(CASE WHEN NOT cancelado AND valor_liquido < 0 THEN 1 ELSE 0 END) AS nao_cancelados_valor_negativo
FROM lakehouse_rotaperfume.silver.pedidos
"
```
Expected: `pedidos_cancelados=957`, `nao_cancelados_valor_negativo=135` — prova que a constraint `NOT cancelado OR valor_liquido = 0` foi adicionada com sucesso (Step 9 confirma) mesmo com essas 135 linhas de valor negativo intactas.

- [ ] **Step 8: Devolução, SKU descontinuado e carteira órfã**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT
  SUM(CASE WHEN devolucao THEN 1 ELSE 0 END) AS itens_devolucao,
  SUM(CASE WHEN sku_descontinuado THEN 1 ELSE 0 END) AS itens_sku_descontinuado
FROM lakehouse_rotaperfume.silver.itens_pedido
"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT SUM(CASE WHEN orfao_vendedor_desligado THEN 1 ELSE 0 END) AS carteiras_orfas
FROM lakehouse_rotaperfume.silver.carteira
"
```
Expected: `itens_devolucao=2327`, `itens_sku_descontinuado=76`, `carteiras_orfas=441`.

- [ ] **Step 9: Confirmar as 5 constraints ativas com a expressão exata**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.clientes"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.pedidos"
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.itens_pedido"
```
Expected: `silver.clientes` lista `delta.constraints.clientes_cnpj_14_digitos = 'length(cnpj) = 14'` e `delta.constraints.clientes_data_cadastro_nao_nula = 'data_cadastro IS NOT NULL'`; `silver.pedidos` lista `delta.constraints.pedidos_data_pedido_nao_nula` e `delta.constraints.pedidos_cancelado_valor_zero = 'NOT cancelado OR valor_liquido = 0'` (não a versão ingênua `valor_liquido >= 0`); `silver.itens_pedido` lista `delta.constraints.itens_pedido_quantidade_abs_positiva = 'quantidade_abs > 0'`.

- [ ] **Step 10: Etapas de oportunidades — confirmação final**

Run:
```bash
databricks experimental aitools tools query --warehouse 2c807bf97ff3fec4 --profile Emerson "
SELECT etapa, ganha, COUNT(*) AS n
FROM lakehouse_rotaperfume.silver.oportunidades
GROUP BY etapa, ganha
ORDER BY etapa
"
```
Expected: 6 grupos (`Fechado ganho`/true, `Fechado perdido`/false, e as 4 etapas abertas/NULL), nenhum rótulo `Ganha`/`Perdida`.

Não há Step de commit aqui — nenhum arquivo novo.

---

## Self-Review

**Cobertura literal do prompt da aula (`.llm/prompt03.md`):**
- `01-clientes.sql` (cnpj 3 formatos → 14 dígitos, `razao_social` initcap+espaço, `data_cadastro` duplo `try_to_date`, dedup por `row_number()` mantendo o mais antigo, `cliente_ids_duplicados`, `ativo` boolean) → Tarefa 1.
- `02-pedidos.sql` (data dupla, `valor_total` DECIMAL, `cancelado`, `valor_liquido`, `ano`/`mes`) → Tarefa 2.
- `03-itens-e-produtos.sql` (produtos tipado, `data_lancamento`, `devolucao`/`quantidade_abs`, `sku_descontinuado` via join) → Tarefa 3.
- `04-crm-e-financeiro.sql` (6 tabelas, `vigente`/`orfao_vendedor_desligado`, etapas reais de oportunidades, `ruptura` recalculada) → Tarefa 4.
- Auditoria (`_processado_em`/`_linhas_origem`), `COMMENT` em tabela+colunas de decisão, 5 `ALTER TABLE ADD CONSTRAINT` → em cada um dos 4 arquivos.
- Caminho completo `lakehouse_rotaperfume.silver.x` literal em todo SQL (nunca `${var.catalog}`) → todas as Tarefas 1–4.
- 4 `sql_task` paralelas, `depends_on: bronze_ingestao` → Tarefa 5.
- `bundle deploy`/`bundle run` com profile `Emerson` (não `projeto-dados-ia`) → Tarefa 6.
- Todos os 8 números de "O QUE PRECISA BATER" (3.443, 1.111, 223, 309, 40→3.000, 2.327, 957, 76, 441 — 9 contando o total de clientes únicos) + o caso dos 135 negativos → Tarefa 6, Steps 4–10.

**Descoberta crítica não pedida pelo prompt, mas essencial para ele funcionar:** o prompt não menciona a distinção FILE vs. NOTEBOOK para `sql_task.file`. Testada nesta sessão contra o workspace real: um arquivo `.sql` sincronizado como NOTEBOOK faz `sql_task` falhar com `Unable to fetch SQL file from path`; o mesmo arquivo como FILE puro roda todas as instruções corretamente (confirmado com 3 instruções reais: `CREATE TABLE`, `COMMENT`, `ALTER TABLE ADD CONSTRAINT`, todas com efeito visível depois). Nenhum dos 4 arquivos deste plano começa com `-- Databricks notebook source`, então devem sincronizar como FILE — o Step 2 da Tarefa 6 confirma isso explicitamente antes de rodar o pipeline, para falhar cedo e com diagnóstico claro caso a suposição não se confirme.

**Armadilha do ANSI mode:** todo `try_to_date` — nenhum `to_date`/`date_trunc`/`CAST(...AS DATE)` em nenhum dos 4 arquivos. Confirmado com um erro real desta sessão (`CANNOT_PARSE_TIMESTAMP`) reproduzindo exatamente o que o prompt avisou.

**Armadilha da constraint de `valor_liquido`:** a constraint escrita é `NOT cancelado OR valor_liquido = 0` (Tarefa 2), nunca `valor_liquido >= 0`. Tarefa 6/Step 7 mede explicitamente os 135 pedidos não cancelados com valor negativo e confirma que continuam presentes; Step 9 confirma a expressão exata gravada em `delta.constraints.pedidos_cancelado_valor_zero` via `SHOW TBLPROPERTIES`.

**Armadilha da substituição de variável em `sql_task`:** todos os 4 arquivos `.sql` usam `lakehouse_rotaperfume` literal; só o YAML (Tarefa 5) usa `${var.warehouse_id}`, que é um campo de bundle, não texto de arquivo.

**Paralelismo real, não só sintático:** todas as 4 tarefas `silver_*` dependem exclusivamente de `bronze_ingestao`; dentro de `03-itens-e-produtos.sql` e `04-crm-e-financeiro.sql` (os dois arquivos que criam mais de uma tabela), todo `JOIN`/referência lê de `bronze.*`, nunca de uma tabela silver criada por um `CREATE` anterior no mesmo script — preservando a garantia de que nenhuma tarefa (nem nenhuma tabela dentro de uma tarefa) depende de dado produzido por outra tarefa do mesmo run.

**Decisão de design — `cliente_ids_duplicados` via `filter()` + `collect_list()` de janela:** evita uma segunda passada/self-join na tabela para montar a lista de descartados; `row_number() ... ORDER BY data_cadastro ASC, cliente_id ASC` garante desempate determinístico (mesmo `data_cadastro`, mesmo seed 42) para que `CREATE OR REPLACE TABLE` produza sempre os mesmos 3.000 sobreviventes em reruns. Se `data_cadastro` viesse NULL para alguma linha (não observado nos dados verificados), a ordenação ASC trataria NULL como "mais antigo" por padrão do Spark — risco mitigado pela própria constraint `data_cadastro IS NOT NULL`, que falharia e exporia o problema em vez de escondê-lo, consistente com a filosofia do prompt ("se uma constraint falhar, ela fez o trabalho dela").

**Decisão de design — `coalesce(p.ativo = 'N', false)` em `sku_descontinuado`:** protege contra um `sku` em `itens_pedido` sem produto correspondente em `bronze.produtos` (LEFT JOIN sem match resultaria em `NULL`, não `false`, sem o `coalesce`) — verificado nesta sessão que hoje isso nunca acontece (0 órfãos), mas o `LEFT JOIN`+`coalesce` é a versão que não quebra se acontecer no futuro.

**`_linhas_origem` sempre da bronze, nunca da silver resultante:** em todo arquivo, calculado via `CROSS JOIN` com uma CTE `total_bronze` que faz `COUNT(*)` direto na tabela bronze de origem antes de qualquer filtro/dedup — em `silver.clientes` isso grava `3040` em toda linha, mesmo a tabela resultante tendo `3000`.

**`COMMENT` só nas colunas que exigiram decisão:** `clientes` (5 colunas), `pedidos` (5), `produtos` (2), `itens_pedido` (3), `vendedores` (1), `carteira` (2), `oportunidades` (1), `pagamentos` (1), `estoque` (1); `visitas` só tem comentário de tabela (nenhuma coluna teve decisão de limpeza).

**Checagem de placeholders:** nenhum "TBD"/"implementar depois" — todo SQL e todo YAML está escrito por extenso, executável como está.

**Consistência de nomes:** `task_key` dos 4 `sql_task` (`silver_clientes`, `silver_pedidos`, `silver_itens_e_produtos`, `silver_crm_e_financeiro`) usados de forma idêntica no YAML e nas expectativas de execução da Tarefa 6; nomes de coluna (`cancelado`, `valor_liquido`, `devolucao`, `quantidade_abs`, `sku_descontinuado`, `vigente`, `orfao_vendedor_desligado`, `ganha`, `ruptura`, `cliente_ids_duplicados`) usados de forma idêntica entre a definição em cada `.sql` e as queries de verificação da Tarefa 6; nomes das 5 constraints idênticos entre a definição (`ALTER TABLE ADD CONSTRAINT <nome>`) e a query de confirmação (`SHOW TBLPROPERTIES`, Step 9).

### Critical Files for Implementation
- `rotaperfume/src/silver/01-clientes.sql`
- `rotaperfume/src/silver/02-pedidos.sql`
- `rotaperfume/src/silver/03-itens-e-produtos.sql`
- `rotaperfume/src/silver/04-crm-e-financeiro.sql`
- `rotaperfume/resources/pipeline.job.yml`
