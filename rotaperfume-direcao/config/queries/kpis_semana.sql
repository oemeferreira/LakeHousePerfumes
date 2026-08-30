-- KPIs da semana para os quatro cartões da aba "A semana".
-- A receita esperada é ESTIMATIVA (SUM(score * ticket_medio)), nunca receita
-- realizada. As métricas do modelo vêm SEMPRE da última versão de
-- gold.modelo_metricas: versao é STRING, então TRY_CAST garante a ordem
-- numérica certa (sem isso, "9" ordena depois de "10").
WITH metricas AS (
  SELECT lift_top200, acertos_top200, taxa_base
  FROM lakehouse_rotaperfume.gold.modelo_metricas
  QUALIFY ROW_NUMBER() OVER (ORDER BY TRY_CAST(versao AS BIGINT) DESC) = 1
),
retornos AS (
  SELECT
    COUNT(*)                    AS retornos_registrados,
    COUNT_IF(status = 'vendeu') AS retornos_vendeu
  FROM lakehouse_rotaperfume.gold.retorno_ligacao
)
SELECT
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fila_semanal)                    AS contatos,
  (SELECT COUNT(DISTINCT vendedor) FROM lakehouse_rotaperfume.gold.fila_semanal)    AS vendedores,
  (SELECT ROUND(SUM(score * ticket_medio), 2)
   FROM lakehouse_rotaperfume.gold.fila_semanal)                                    AS receita_esperada,
  (SELECT CAST(MAX(_gerado_em) AS STRING)
   FROM lakehouse_rotaperfume.gold.fila_semanal)                                    AS referencia_fila,
  m.lift_top200,
  m.acertos_top200,
  m.taxa_base,
  r.retornos_registrados,
  r.retornos_vendeu
FROM metricas m
CROSS JOIN retornos r
