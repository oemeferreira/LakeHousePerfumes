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
