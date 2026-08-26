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
