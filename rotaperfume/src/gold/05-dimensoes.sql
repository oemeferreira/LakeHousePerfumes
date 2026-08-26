-- rotaperfume/src/gold/05-dimensoes.sql
-- Dimensoes conformadas da camada gold a partir de silver.*:
--   gold.dim_cliente    uma linha por cliente
--   gold.dim_produto    uma linha por SKU
--   gold.dim_vendedor   uma linha por vendedor
--   gold.dim_calendario uma linha por dia dos 24 meses

-- ---------------------------------------------------------------------
-- gold.dim_cliente
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
WITH metricas_pedidos AS (
  SELECT
    cliente_id,
    min(data_pedido) AS data_primeiro_pedido,
    max(data_pedido) AS data_ultimo_pedido,
    count(distinct pedido_id) AS total_pedidos,
    sum(valor_liquido) AS receita_acumulada
  FROM lakehouse_rotaperfume.silver.pedidos
  WHERE NOT cancelado
  GROUP BY cliente_id
)
SELECT
  c.cliente_id,
  c.cnpj,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  m.data_primeiro_pedido,
  m.data_ultimo_pedido,
  coalesce(m.total_pedidos, 0) AS total_pedidos,
  coalesce(m.receita_acumulada, CAST(0 AS DECIMAL(18,2))) AS receita_acumulada,
  CASE
    WHEN m.data_ultimo_pedido IS NOT NULL THEN datediff(current_date(), m.data_ultimo_pedido)
    ELSE NULL
  END AS dias_sem_comprar,
  c.ativo,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN metricas_pedidos m ON m.cliente_id = c.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Dimensao conformada de clientes com metricas historicas de compras (pedidos nao cancelados). Clientes sem compras possuem total_pedidos = 0 e datas/dias_sem_comprar nulos.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.dias_sem_comprar IS
  'Dias decorridos entre a data do ultimo pedido valido e a data atual (current_date). Usada como indicador direto de recencia e risco de churn.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.receita_acumulada IS
  'Soma do valor liquido de todos os pedidos nao cancelados do cliente no historico (considerando deducoes por devolucao).';

-- ---------------------------------------------------------------------
-- gold.dim_produto
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  (NOT ativo) AS descontinuado,
  ativo,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Dimensao conformada de produtos/SKUs com caracteristicas olfativas, precos e status de catalogo.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_produto.descontinuado IS
  'true quando o produto nao esta mais ativo no portfolio atual da distribuidora (ativo = false).';

-- ---------------------------------------------------------------------
-- gold.dim_vendedor
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  data_admissao,
  data_desligamento,
  meta_mensal,
  (data_desligamento IS NULL) AS ativo,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Dimensao conformada de vendedores com regiao de atuacao, metas comerciais e situacao contratual.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_vendedor.ativo IS
  'true quando o vendedor nao possui data_desligamento registrada.';

-- ---------------------------------------------------------------------
-- gold.dim_calendario
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
WITH datas AS (
  SELECT explode(sequence(to_date('2024-09-01'), to_date('2026-08-31'), interval 1 day)) AS data
)
SELECT
  data,
  year(data) AS ano,
  month(data) AS mes,
  CASE month(data)
    WHEN 1 THEN 'Janeiro'
    WHEN 2 THEN 'Fevereiro'
    WHEN 3 THEN 'Março'
    WHEN 4 THEN 'Abril'
    WHEN 5 THEN 'Maio'
    WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho'
    WHEN 8 THEN 'Agosto'
    WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro'
    WHEN 11 THEN 'Novembro'
    WHEN 12 THEN 'Dezembro'
  END AS nome_mes,
  quarter(data) AS trimestre,
  CASE dayofweek(data)
    WHEN 1 THEN 'Domingo'
    WHEN 2 THEN 'Segunda-feira'
    WHEN 3 THEN 'Terça-feira'
    WHEN 4 THEN 'Quarta-feira'
    WHEN 5 THEN 'Quinta-feira'
    WHEN 6 THEN 'Sexta-feira'
    WHEN 7 THEN 'Sábado'
  END AS dia_semana,
  (month(data) IN (4, 6, 10)) AS mes_pico_setor,
  current_timestamp() AS _processado_em
FROM datas;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Dimensao de calendario cobrindo os 24 meses da serie historica (set/2024 a ago/2026) com atributos temporais e sazonalidade comercial do setor.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_calendario.mes_pico_setor IS
  'true para os meses de reposicao antecipada do varejo: Abril (Dia das Maes), Junho (Dia dos Namorados) e Outubro (Black Friday).';
