-- rotaperfume/src/ml/13-fila.sql
-- ML · Prompt 3: Fila Semanal de Ligacoes, Ferramentas no Unity Catalog e Testes
--
-- 1. Cria gold.fila_semanal com os 200 contatos mais propensos (filtrando antes vendedores desligados)
-- 2. Cria as 4 funcoes SQL do Unity Catalog para os agentes de IA
-- 3. Executa 3 testes que interrompem o pipeline com raise_error() em caso de divergencia

-- ---------------------------------------------------------------------
-- 1. TABELA DA SEMANA: gold.fila_semanal
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fila_semanal AS
WITH clientes_elegiveis AS (
  SELECT
    s.cliente_id,
    s.score,
    s.faixa,
    s.versao,
    v.nome AS vendedor,
    c.razao_social,
    c.cidade,
    c.uf,
    fc.ticket_medio,
    fc.atraso_relativo,
    fc.intervalo_medio_dias,
    fc.recencia_dias,
    fc.comprou_lancamento,
    fc.valor_total
  FROM lakehouse_rotaperfume.gold.score_propensao s
  JOIN lakehouse_rotaperfume.silver.carteira ca ON ca.cliente_id = s.cliente_id
  JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = ca.vendedor_id
  JOIN lakehouse_rotaperfume.gold.dim_cliente c ON c.cliente_id = s.cliente_id
  JOIN lakehouse_rotaperfume.gold.features_cliente fc ON fc.cliente_id = s.cliente_id
  WHERE ca.vigente = true
    AND NOT ca.orfao_vendedor_desligado
),
top200_clientes AS (
  SELECT *
  FROM clientes_elegiveis
  ORDER BY score DESC
  LIMIT 200
),
ultimo_estoque AS (
  SELECT sku, saldo, ruptura
  FROM lakehouse_rotaperfume.silver.estoque
  WHERE data_snapshot = (SELECT max(data_snapshot) FROM lakehouse_rotaperfume.silver.estoque)
),
marca_preferida AS (
  SELECT cliente_id, marca
  FROM (
    SELECT
      cliente_id,
      marca,
      row_number() OVER (PARTITION BY cliente_id ORDER BY sum(receita) DESC) AS rk
    FROM lakehouse_rotaperfume.gold.fato_vendas
    WHERE cliente_id IN (SELECT cliente_id FROM top200_clientes)
    GROUP BY cliente_id, marca
  )
  WHERE rk = 1
),
skus_marca_cliente AS (
  SELECT
    f.cliente_id,
    f.sku,
    f.descricao,
    sum(f.quantidade) AS total_qtd,
    max(f.data_pedido) AS ultima_compra,
    (max(f.data_pedido) >= date_sub(to_date('2026-08-31'), 90)) AS comprou_90d
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN marca_preferida mp ON mp.cliente_id = f.cliente_id AND mp.marca = f.marca
  WHERE f.cliente_id IN (SELECT cliente_id FROM top200_clientes)
  GROUP BY f.cliente_id, f.sku, f.descricao
),
sugestao_ranqueada AS (
  SELECT
    cliente_id,
    sku,
    descricao,
    comprou_90d,
    row_number() OVER (
      PARTITION BY cliente_id
      ORDER BY comprou_90d ASC, total_qtd DESC
    ) AS rk
  FROM skus_marca_cliente
),
sugestao_final AS (
  SELECT
    sr.cliente_id,
    sr.sku,
    sr.descricao,
    coalesce(ue.saldo, 0) AS saldo_estoque,
    concat(sr.descricao, ' (SKU ', sr.sku, ' · Saldo estoque: ', coalesce(ue.saldo, 0), ' un)') AS sugestao_texto
  FROM sugestao_ranqueada sr
  LEFT JOIN ultimo_estoque ue ON ue.sku = sr.sku
  WHERE sr.rk = 1
)
SELECT
  t.vendedor,
  ROW_NUMBER() OVER (PARTITION BY t.vendedor ORDER BY t.score DESC) AS ordem,
  t.cliente_id,
  t.razao_social,
  t.cidade,
  t.uf,
  t.score,
  t.faixa,
  t.ticket_medio,
  CASE
    WHEN t.atraso_relativo > 3 THEN
      concat('Compra a cada ', cast(round(t.intervalo_medio_dias, 0) as int), ' dias e está há ', cast(round(t.recencia_dias, 0) as int), ' sem pedido. Risco de perder para o concorrente.')
    WHEN t.atraso_relativo > 1.5 THEN
      concat('Está ', format_number(t.atraso_relativo, 1), ' vezes mais atrasado que o ritmo dele.')
    WHEN t.comprou_lancamento = 1.0 THEN
      'Comprou lançamento recente. Alta chance de repetir.'
    WHEN t.valor_total > 50000 THEN
      concat('Cliente grande, R$ ', format_number(t.valor_total, 2), ' no ano. Manter próximo.')
    ELSE
      'Dentro do ritmo. Contato de manutenção.'
  END AS motivo,
  coalesce(sf.sugestao_texto, 'Consultar mix no catálogo.') AS sugestao,
  t.versao AS modelo_versao,
  current_timestamp() AS _gerado_em
FROM top200_clientes t
LEFT JOIN sugestao_final sf ON sf.cliente_id = t.cliente_id
ORDER BY t.score DESC;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fila_semanal IS
  'Fila semanal dos 200 clientes mais propensos a comprar, priorizada por score de ML e distribuida por vendedor ativo, com motivo dinamico e sugestao de reposicao.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.vendedor IS
  'Nome do vendedor responsavel pela carteira ativa do cliente.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.ordem IS
  'Posicao de prioridade do cliente na fila individual do vendedor (1 = maior score daquele vendedor).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.cliente_id IS
  'Identificador unico do cliente no CRM.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.razao_social IS
  'Razao social da empresa compradora.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.cidade IS
  'Cidade sede do cliente.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.uf IS
  'Estado (UF) do cliente.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.score IS
  'Probabilidade estimada de compra calculada pelo modelo de Machine Learning.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.faixa IS
  'Classificacao comercial da propensao (Fria, Morna, Quente, Muito quente).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.ticket_medio IS
  'Ticket medio historico do cliente.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.motivo IS
  'Justificativa comercial em portugues para a realizacao do contato.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.sugestao IS
  'Produto recomendado para oferta com saldo atualizado no estoque.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.modelo_versao IS
  'Versao do modelo no Unity Catalog utilizada para gerar as probabilidades.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal._gerado_em IS
  'Data e hora em que a fila semanal foi calculada.';

-- ---------------------------------------------------------------------
-- 2. AS QUATRO FERRAMENTAS DO UNITY CATALOG
-- ---------------------------------------------------------------------

-- Ferramenta 1: priorizar_carteira
CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.priorizar_carteira(
  p_vendedor STRING,
  p_quantos INT DEFAULT 10
)
RETURNS TABLE (
  ordem INT,
  cliente_id INT,
  razao_social STRING,
  cidade STRING,
  uf STRING,
  score DOUBLE,
  faixa STRING,
  ticket_medio DOUBLE,
  motivo STRING,
  sugestao STRING
)
COMMENT 'Retorna a fatia da fila semanal priorizada para um vendedor especifico, ordenada por score decrescente.'
RETURN
  SELECT
    ordem,
    cliente_id,
    razao_social,
    cidade,
    uf,
    score,
    faixa,
    ticket_medio,
    motivo,
    sugestao
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor
    AND ordem <= p_quantos
  ORDER BY ordem ASC;

-- Ferramenta 2: contexto_cliente
CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.contexto_cliente(
  p_cliente_id INT
)
RETURNS TABLE (
  cliente_id INT,
  razao_social STRING,
  segmento STRING,
  cidade STRING,
  uf STRING,
  total_pedidos BIGINT,
  receita_acumulada DECIMAL(18,2),
  ticket_medio DECIMAL(18,2),
  data_ultimo_pedido DATE,
  dias_sem_comprar INT,
  marcas_preferidas STRING
)
COMMENT 'Retorna o perfil detalhado e historico comercial do cliente, incluindo receita acumulada, ticket medio e principais marcas compradas.'
RETURN
  WITH marcas AS (
    SELECT
      cliente_id,
      concat_ws(', ', collect_list(marca)) AS marcas_preferidas
    FROM (
      SELECT cliente_id, marca, sum(receita) AS rec
      FROM lakehouse_rotaperfume.gold.fato_vendas
      WHERE cliente_id = p_cliente_id
      GROUP BY cliente_id, marca
      ORDER BY rec DESC
      LIMIT 3
    )
    GROUP BY cliente_id
  )
  SELECT
    c.cliente_id,
    c.razao_social,
    c.segmento,
    c.cidade,
    c.uf,
    c.total_pedidos,
    c.receita_acumulada,
    CAST(c.receita_acumulada / nullif(c.total_pedidos, 0) AS DECIMAL(18,2)) AS ticket_medio,
    c.data_ultimo_pedido,
    c.dias_sem_comprar,
    coalesce(m.marcas_preferidas, 'N/A') AS marcas_preferidas
  FROM lakehouse_rotaperfume.gold.dim_cliente c
  LEFT JOIN marcas m ON m.cliente_id = c.cliente_id
  WHERE c.cliente_id = p_cliente_id;

-- Ferramenta 3: sugerir_produtos
CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.sugerir_produtos(
  p_cliente_id INT
)
RETURNS TABLE (
  sku STRING,
  descricao STRING,
  categoria STRING,
  marca STRING,
  quantidade_historica BIGINT,
  comprado_ultimos_90d BOOLEAN,
  status_sugestao STRING
)
COMMENT 'Analisa os produtos historicos do cliente e identifica oportunidades de recompra de SKUs favoritos parados ha mais de 90 dias.'
RETURN
  WITH compras_90d AS (
    SELECT DISTINCT sku
    FROM lakehouse_rotaperfume.gold.fato_vendas
    WHERE cliente_id = p_cliente_id
      AND data_pedido >= date_sub(to_date('2026-08-31'), 90)
  ),
  historico_skus AS (
    SELECT
      f.sku,
      f.descricao,
      f.categoria,
      f.marca,
      sum(f.quantidade) AS quantidade_historica,
      (c90.sku IS NOT NULL) AS comprado_ultimos_90d
    FROM lakehouse_rotaperfume.gold.fato_vendas f
    LEFT JOIN compras_90d c90 ON c90.sku = f.sku
    WHERE f.cliente_id = p_cliente_id
    GROUP BY f.sku, f.descricao, f.categoria, f.marca, (c90.sku IS NOT NULL)
  )
  SELECT
    sku,
    descricao,
    categoria,
    marca,
    quantidade_historica,
    comprado_ultimos_90d,
    CASE
      WHEN NOT comprado_ultimos_90d THEN 'Parou de comprar (Oportunidade de Recompra)'
      ELSE 'Compra recorrente ativa'
    END AS status_sugestao
  FROM historico_skus
  ORDER BY comprado_ultimos_90d ASC, quantidade_historica DESC;

-- Ferramenta 4: checar_disponibilidade
CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.checar_disponibilidade(
  p_sku STRING
)
RETURNS TABLE (
  sku STRING,
  descricao STRING,
  marca STRING,
  saldo INT,
  ruptura BOOLEAN,
  data_snapshot DATE
)
COMMENT 'Consulta o saldo atual em estoque e situacao de ruptura de um SKU no snapshot mais recente.'
RETURN
  WITH ultimo_snapshot AS (
    SELECT max(data_snapshot) AS max_dt FROM lakehouse_rotaperfume.silver.estoque
  )
  SELECT
    p.sku,
    p.descricao,
    p.marca,
    e.saldo,
    e.ruptura,
    e.data_snapshot
  FROM lakehouse_rotaperfume.silver.produtos p
  JOIN lakehouse_rotaperfume.silver.estoque e ON e.sku = p.sku
  CROSS JOIN ultimo_snapshot u
  WHERE e.data_snapshot = u.max_dt
    AND p.sku = p_sku;

-- ---------------------------------------------------------------------
-- 3. TRES TESTES DE INTEGRIDADE COM RAISE_ERROR()
-- ---------------------------------------------------------------------

-- Teste 1: a fila tem exatamente 200 linhas
SELECT 'ml_fila · contagem exata de 200 contatos' AS teste,
       CAST(total AS STRING) AS calculado, '200' AS esperado,
       CASE WHEN total = 200 THEN 'PASSOU'
            ELSE raise_error(concat('A fila semanal gerou ', total, ' linhas em vez de exatamente 200.'))
       END AS resultado
FROM (SELECT count(*) AS total FROM lakehouse_rotaperfume.gold.fila_semanal);

-- Teste 2: nenhuma linha com motivo nulo ou vazio
SELECT 'ml_fila · integridade do motivo de ligacao' AS teste,
       CAST(sem_motivo AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN sem_motivo = 0 THEN 'PASSOU'
            ELSE raise_error(concat('A fila semanal contem ', sem_motivo, ' contatos com motivo nulo ou vazio.'))
       END AS resultado
FROM (
  SELECT count(*) AS sem_motivo
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE motivo IS NULL OR trim(motivo) = ''
);

-- Teste 3: nenhum score fora do intervalo [0, 1]
SELECT 'ml_fila · validade do score de propensao' AS teste,
       CAST(scores_invalidos AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN scores_invalidos = 0 THEN 'PASSOU'
            ELSE raise_error(concat('A fila semanal contem ', scores_invalidos, ' scores fora do intervalo [0, 1].'))
       END AS resultado
FROM (
  SELECT count(*) AS scores_invalidos
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE score < 0.0 OR score > 1.0 OR score IS NULL
);
