-- Desfecho da fila por vendedor: quantos contatos tinha, quantos foram
-- trabalhados e o resultado de cada status. Lê só o retorno mais recente.
SELECT
  f.vendedor,
  COUNT(*)                          AS na_fila,
  COUNT(r.status)                   AS trabalhados,
  COUNT_IF(r.status = 'vendeu')        AS vendeu,
  COUNT_IF(r.status = 'vai_pensar')    AS vai_pensar,
  COUNT_IF(r.status = 'sem_interesse') AS sem_interesse,
  COUNT_IF(r.status = 'nao_atendeu')   AS nao_atendeu
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN (
  SELECT cliente_id, status
  FROM (
    SELECT
      cliente_id, status,
      ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rk
    FROM lakehouse_rotaperfume.gold.retorno_ligacao
  )
  WHERE rk = 1
) r ON r.cliente_id = f.cliente_id
GROUP BY f.vendedor
ORDER BY trabalhados DESC, na_fila DESC
