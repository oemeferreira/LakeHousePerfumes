-- rotaperfume/src/silver/01-clientes.sql
-- Silver de clientes: normaliza CNPJ para 14 digitos, padroniza razao
-- social, resolve data de cadastro em dois formatos, e deduplica os 40
-- CNPJs que hoje tem dois cliente_id (mantendo o cadastro mais antigo).
--
-- ANSI mode esta ligado neste warehouse: to_date()/CAST(...AS DATE) sobre
-- data malformada ABORTA a query. Por isso toda conversao de data usa
-- try_to_date, nunca to_date.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH bronze_tipado AS (
  SELECT
    cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    regexp_replace(initcap(trim(razao_social)), ' {2,}', ' ') AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(
      try_to_date(data_cadastro, 'yyyy-MM-dd'),
      try_to_date(data_cadastro, 'dd/MM/yyyy')
    ) AS data_cadastro,
    (ativo = 'S') AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
ranqueado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY cnpj ORDER BY data_cadastro ASC, cliente_id ASC
    ) AS rn,
    collect_list(cliente_id) OVER (PARTITION BY cnpj) AS todos_os_ids_do_cnpj
  FROM bronze_tipado
),
total_bronze AS (
  SELECT COUNT(*) AS n FROM lakehouse_rotaperfume.bronze.clientes
)
SELECT
  cliente_id,
  cnpj,
  razao_social,
  segmento,
  cidade,
  uf,
  bairro,
  data_cadastro,
  ativo,
  filter(todos_os_ids_do_cnpj, id -> id != cliente_id) AS cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  total_bronze.n AS _linhas_origem
FROM ranqueado
CROSS JOIN total_bronze
WHERE rn = 1;

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados a partir de bronze.clientes. CNPJ normalizado para 14 digitos; 40 CNPJs tinham dois cliente_id -- mantido o cadastro mais antigo, o outro rastreavel via cliente_ids_duplicados.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cnpj IS
  'Normalizado para 14 digitos: trim, remove tudo que nao e digito, lpad com zero a esquerda. Nunca convertido para numero (perderia zeros a esquerda).';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.razao_social IS
  'Padronizada com initcap e espacos duplos colapsados -- a origem tem caixa e espacamento inconsistentes.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.data_cadastro IS
  'Convertida de dois formatos misturados na origem (ISO e dd/MM/yyyy) via try_to_date -- ANSI mode aborta com to_date/CAST direto sobre o formato errado.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cliente_ids_duplicados IS
  'IDs descartados na deduplicacao por CNPJ (array vazio quando o cliente nao tinha duplicata). Pedidos/oportunidades antigos podem apontar para um desses IDs em vez do cliente_id sobrevivente.';

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.ativo IS
  'Convertida de S/N (bronze) para boolean.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_cnpj_14_digitos CHECK (length(cnpj) = 14);

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_data_cadastro_nao_nula CHECK (data_cadastro IS NOT NULL);
