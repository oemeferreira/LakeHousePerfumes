-- rotaperfume/src/gold/08-testes.sql
-- Suite de 9 Testes de Qualidade de Dados e Integridade do Pipeline:
--   1. Receita da gold = receita da silver = R$ 102.303.828,05 (tolerancia 0,01)
--   2. CNPJ unico na silver.clientes (0 duplicados)
--   3. Nenhuma data_pedido nula na silver.pedidos
--   4. Receita negativa so onde devolucao = true
--   5. Volume da gold.fato_vendas entre 140.000 e 250.000 linhas
--   6. Nenhum pedido_id na gold que nao exista na silver.pedidos
--   7. Nenhum cliente_id na gold que nao exista na silver.clientes
--   8. mart_produto_performance soma o mesmo que fato_vendas
--   9. Todo CNPJ com exatamente 14 digitos na silver.clientes

WITH metricas AS (
  SELECT
    -- Teste 1: Receita total
    (SELECT round(sum(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS rec_gold,
    (SELECT round(sum(valor_liquido), 2) FROM lakehouse_rotaperfume.silver.pedidos WHERE NOT cancelado) AS rec_silver,

    -- Teste 2: CNPJ duplicado na silver
    (SELECT count(*) FROM (
      SELECT cnpj FROM lakehouse_rotaperfume.silver.clientes GROUP BY cnpj HAVING count(*) > 1
    )) AS cnpjs_duplicados,

    -- Teste 3: Data de pedido nula na silver
    (SELECT count(*) FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL) AS datas_pedidos_nulas,

    -- Teste 4: Receita negativa sem flag devolucao
    (SELECT count(*) FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao) AS receita_negativa_sem_flag,

    -- Teste 5: Linhas na fato_vendas
    (SELECT count(*) FROM lakehouse_rotaperfume.gold.fato_vendas) AS qtd_linhas_fato,

    -- Teste 6: Orfaos de pedido_id
    (SELECT count(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
     LEFT JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
     WHERE p.pedido_id IS NULL) AS orfaos_pedido,

    -- Teste 7: Orfaos de cliente_id
    (SELECT count(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
     LEFT JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
     WHERE c.cliente_id IS NULL) AS orfaos_cliente,

    -- Teste 8: Reconciliacao Mart Produto x Fato Vendas
    (SELECT round(sum(receita), 2) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS rec_mart_produto,

    -- Teste 9: CNPJs com tamanho diferente de 14 digitos
    (SELECT count(*) FROM lakehouse_rotaperfume.silver.clientes WHERE length(cnpj) != 14) AS cnpjs_tamanho_invalido
),
resultado_testes AS (
  SELECT
    1 AS teste_num,
    'Receita Gold = Silver = R$ 102.303.828,05' AS nome,
    concat('Gold: R$ ', cast(rec_gold as string), ' | Silver: R$ ', cast(rec_silver as string)) AS valor_calculado,
    'R$ 102303828.05 (ambas as camadas)' AS valor_esperado,
    (abs(rec_gold - 102303828.05) <= 0.01 AND abs(rec_silver - 102303828.05) <= 0.01 AND abs(rec_gold - rec_silver) <= 0.01) AS passou
  FROM metricas

  UNION ALL

  SELECT
    2 AS teste_num,
    'CNPJ unico na silver.clientes' AS nome,
    cast(cnpjs_duplicados as string) AS valor_calculado,
    '0 duplicados' AS valor_esperado,
    (cnpjs_duplicados = 0) AS passou
  FROM metricas

  UNION ALL

  SELECT
    3 AS teste_num,
    'Nenhuma data_pedido nula na silver.pedidos' AS nome,
    cast(datas_pedidos_nulas as string) AS valor_calculado,
    '0 nulas' AS valor_esperado,
    (datas_pedidos_nulas = 0) AS passou
  FROM metricas

  UNION ALL

  SELECT
    4 AS teste_num,
    'Receita negativa apenas onde devolucao = true' AS nome,
    cast(receita_negativa_sem_flag as string) AS valor_calculado,
    '0 linhas inconsistentes' AS valor_esperado,
    (receita_negativa_sem_flag = 0) AS passou
  FROM metricas

  UNION ALL

  SELECT
    5 AS teste_num,
    'Volume da gold.fato_vendas entre 140k e 250k linhas' AS nome,
    cast(qtd_linhas_fato as string) AS valor_calculado,
    '140.000 a 250.000 linhas' AS valor_esperado,
    (qtd_linhas_fato BETWEEN 140000 AND 250000) AS passou
  FROM metricas

  UNION ALL

  SELECT
    6 AS teste_num,
    'Integridade referencial: pedido_id da fato existe na silver.pedidos' AS nome,
    cast(orfaos_pedido as string) AS valor_calculado,
    '0 orfaos' AS valor_esperado,
    (orfaos_pedido = 0) AS passou
  FROM metricas

  UNION ALL

  SELECT
    7 AS teste_num,
    'Integridade referencial: cliente_id da fato existe na silver.clientes' AS nome,
    cast(orfaos_cliente as string) AS valor_calculado,
    '0 orfaos' AS valor_esperado,
    (orfaos_cliente = 0) AS passou
  FROM metricas

  UNION ALL

  SELECT
    8 AS teste_num,
    'Receita do mart_produto_performance = fato_vendas' AS nome,
    concat('Mart: R$ ', cast(rec_mart_produto as string), ' | Fato: R$ ', cast(rec_gold as string)) AS valor_calculado,
    'Reconciliacao identica (diferenca <= 0.01)' AS valor_esperado,
    (abs(rec_mart_produto - rec_gold) <= 0.01) AS passou
  FROM metricas

  UNION ALL

  SELECT
    9 AS teste_num,
    'Todo CNPJ com exatamente 14 digitos na silver.clientes' AS nome,
    cast(cnpjs_tamanho_invalido as string) AS valor_calculado,
    '0 invalidos' AS valor_esperado,
    (cnpjs_tamanho_invalido = 0) AS passou
  FROM metricas
)
SELECT
  teste_num,
  nome,
  valor_calculado,
  valor_esperado,
  CASE WHEN passou THEN 'PASSED' ELSE 'FAILED' END AS status,
  CASE
    WHEN NOT passou THEN raise_error(concat('FALHA NO TESTE ', teste_num, ' (', nome, '): obtido [', valor_calculado, '] esperado [', valor_esperado, ']'))
    ELSE 'OK'
  END AS validacao
FROM resultado_testes
ORDER BY teste_num;
