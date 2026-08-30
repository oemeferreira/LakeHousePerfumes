-- @param vendedor STRING 'Todos'
-- A fila desta semana, com leitura humana: motivo e sugestão em texto, e o
-- retorno MAIS RECENTE de cada cliente (um cliente pode ter mais de um).
-- A fila é GLOBAL: quando o parâmetro é 'Todos', nada é filtrado.
SELECT
  ROW_NUMBER() OVER (ORDER BY f.score DESC) AS ordem_geral,
  f.vendedor,
  f.ordem            AS ordem_vendedor,
  f.cliente_id,
  f.razao_social,
  CONCAT(f.cidade, '/', f.uf) AS cidade_uf,
  f.score,
  f.faixa,
  f.ticket_medio,
  f.motivo,
  f.sugestao,
  r.status           AS retorno_status,
  r.comentario       AS retorno_comentario
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN (
  SELECT cliente_id, status, comentario
  FROM (
    SELECT
      cliente_id, status, comentario,
      ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rk
    FROM lakehouse_rotaperfume.gold.retorno_ligacao
  )
  WHERE rk = 1
) r ON r.cliente_id = f.cliente_id
WHERE (:vendedor = 'Todos' OR f.vendedor = :vendedor)
ORDER BY f.score DESC
