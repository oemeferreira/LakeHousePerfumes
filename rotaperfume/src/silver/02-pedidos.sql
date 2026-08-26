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
  'Pedidos tipados a partir de bronze.pedidos. A origem ja zera valor_total nos pedidos cancelados mas nao traz nenhuma flag explicita disso -- cancelado e valor_liquido tornam essa regra de negocio visivel e a constraint pedidos_cancelado_valor_zero a garante como contrato, mesmo que a origem mude no futuro.';

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
