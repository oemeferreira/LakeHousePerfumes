-- rotaperfume/src/gold/10-auditoria-metadado.sql
-- Gold · Auditoria de Metadados e Documentacao Semantica
--
-- Metadado faltando e BUG, nao pendencia de documentacao.
-- O agente de IA (Genie) le a descricao de tabelas e colunas para escolher
-- qual usar. Se faltar comentario, o teste falha e aborta o pipeline.

-- 1. Toda tabela e toda view da gold precisa de COMMENT
SELECT 'metadado · tabelas e views da gold' AS teste,
       CAST(sem_comment AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment, ' objetos da gold estao sem COMMENT. O Genie vai errar neles.'))
       END AS resultado
FROM (SELECT count(*) AS sem_comment
      FROM lakehouse_rotaperfume.information_schema.tables
      WHERE table_schema = 'gold' AND (comment IS NULL OR trim(comment) = ''));

-- 2. Toda coluna do fato e das views de negocio precisa de COMMENT
SELECT 'metadado · colunas do fato e das views' AS teste,
       CAST(sem_comment AS STRING) AS calculado, '0' AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment, ' colunas sem COMMENT em fato_vendas ou nas views de negocio'))
       END AS resultado
FROM (SELECT count(*) AS sem_comment
      FROM lakehouse_rotaperfume.information_schema.columns
      WHERE table_schema = 'gold'
        AND table_name IN ('fato_vendas', 'receita_mensal', 'ranking_marcas',
                           'margem_por_categoria', 'clientes_em_risco',
                           'efeito_lancamento', 'ruptura_por_marca')
        AND (comment IS NULL OR trim(comment) = ''));

-- 3. Relatorio de cobertura de documentacao por objeto na camada gold
SELECT table_name AS objeto,
       count(*) AS colunas,
       sum(CASE WHEN comment IS NOT NULL AND trim(comment) <> '' THEN 1 ELSE 0 END) AS documentadas,
       round(avg(CASE WHEN comment IS NOT NULL AND trim(comment) <> '' THEN 1.0 ELSE 0.0 END), 2) AS cobertura
FROM lakehouse_rotaperfume.information_schema.columns
WHERE table_schema = 'gold'
GROUP BY table_name
ORDER BY cobertura, table_name;
