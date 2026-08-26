-- rotaperfume/src/gold/07-marts.sql
-- Data Marts de Negocio da Camada Gold:
--   gold.mart_vendas_por_vendedor    grao vendedor x mes
--   gold.mart_produto_performance    grao SKU x mes (com Curva ABC)
--   gold.mart_financeiro_recebimento grao mes de vencimento

-- ---------------------------------------------------------------------
-- gold.mart_vendas_por_vendedor
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
WITH vendas_vendedor AS (
  SELECT
    vendedor_id,
    ano,
    mes,
    sum(receita) AS receita,
    sum(margem) AS margem,
    count(distinct cliente_id) AS clientes_atendidos,
    count(distinct pedido_id) AS total_pedidos
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY vendedor_id, ano, mes
)
SELECT
  v.vendedor_id,
  ven.nome AS vendedor_nome,
  ven.regiao,
  v.ano,
  v.mes,
  v.receita,
  v.margem,
  ven.meta_mensal AS meta,
  CAST(round(v.receita / nullif(ven.meta_mensal, 0) * 100, 2) AS DECIMAL(10,2)) AS atingimento,
  v.clientes_atendidos,
  CAST(round(v.receita / nullif(v.total_pedidos, 0), 2) AS DECIMAL(18,2)) AS ticket_medio,
  current_timestamp() AS _processado_em
FROM vendas_vendedor v
LEFT JOIN lakehouse_rotaperfume.silver.vendedores ven ON ven.vendedor_id = v.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Data mart para a Diretoria Comercial com metricas mensais de desempenho de vendedores: receita, margem, atingimento de meta, clientes atendidos e ticket medio.';

-- ---------------------------------------------------------------------
-- gold.mart_produto_performance
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH agregacao_sku AS (
  SELECT
    sku,
    descricao,
    categoria,
    marca,
    ano,
    mes,
    sum(quantidade) AS quantidade,
    sum(receita) AS receita,
    sum(margem) AS margem
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, descricao, categoria, marca, ano, mes
),
acumulado AS (
  SELECT
    *,
    sum(receita) OVER (
      PARTITION BY ano, mes
      ORDER BY receita DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS receita_acumulada_mes,
    sum(receita) OVER (
      PARTITION BY ano, mes
    ) AS receita_total_mes
  FROM agregacao_sku
)
SELECT
  sku,
  descricao,
  categoria,
  marca,
  ano,
  mes,
  quantidade,
  receita,
  margem,
  CAST(round(margem / nullif(receita, 0) * 100, 2) AS DECIMAL(10,2)) AS margem_pct,
  CASE
    WHEN receita_acumulada_mes / nullif(receita_total_mes, 0) <= 0.70 THEN 'A'
    WHEN receita_acumulada_mes / nullif(receita_total_mes, 0) <= 0.90 THEN 'B'
    ELSE 'C'
  END AS curva_abc,
  current_timestamp() AS _processado_em
FROM acumulado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Data mart de produto com receita, margem, quantidade vendida e classificacao de curva ABC mensal (A ate 70%, B ate 90%, C acima de 90% da receita acumulada). A soma total de receita e identica a da fato_vendas.';

-- ---------------------------------------------------------------------
-- gold.mart_financeiro_recebimento
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  year(data_vencimento) AS ano_vencimento,
  month(data_vencimento) AS mes_vencimento,
  sum(valor) AS valor_a_receber,
  sum(CASE WHEN data_pagamento IS NOT NULL THEN valor_liquido ELSE CAST(0 AS DECIMAL(18,2)) END) AS recebido,
  CAST(round(avg(CASE WHEN data_pagamento > data_vencimento THEN datediff(data_pagamento, data_vencimento) END), 2) AS DECIMAL(10,2)) AS atraso_medio,
  sum(valor - valor_liquido) AS custo_taxa,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Data mart para a Diretoria Financeira com fluxo de recebimento projetado e realizado por mes de vencimento, atraso medio de liquidacao e custo de taxas de intermediacao/cartao.';
