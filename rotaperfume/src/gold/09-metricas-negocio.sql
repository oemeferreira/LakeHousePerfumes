-- rotaperfume/src/gold/09-metricas-negocio.sql
-- Gold · Views com nomes de negocio para consumo por IA e analise
--
-- O COMMENT de cada view diz QUAL PERGUNTA ela responde, para o Genie
-- escolher onde procurar. Sintaxe compacta define comentarios em todas as colunas.

-- ---------------------------------------------------------------------
-- gold.receita_mensal
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.receita_mensal (
  ano            COMMENT 'Ano do pedido.',
  mes            COMMENT 'Mês do pedido, de 1 a 12.',
  mes_pico_setor COMMENT 'TRUE em abril, junho e outubro. São os picos da distribuidora, porque o varejo compra ANTES da data comemorativa.',
  mes_vale_setor COMMENT 'TRUE em dezembro e janeiro. Vale esperado do setor, não queda de desempenho.',
  receita        COMMENT 'Receita do mês, com devolução descontada.',
  margem         COMMENT 'Margem do mês: receita menos custo do produto.',
  margem_pct     COMMENT 'Margem sobre receita, de 0 a 1.',
  pedidos        COMMENT 'Pedidos distintos faturados no mês.',
  ticket_medio   COMMENT 'Receita dividida pelo número de pedidos.'
)
COMMENT 'Responde: qual foi a receita e a margem por mês? Como a sazonalidade se comportou?'
AS
SELECT f.ano, f.mes,
       (f.mes IN (4, 6, 10)) AS mes_pico_setor,
       (f.mes IN (12, 1))    AS mes_vale_setor,
       ROUND(SUM(f.receita), 2) AS receita,
       ROUND(SUM(f.margem), 2)  AS margem,
       ROUND(SUM(f.margem) / NULLIF(SUM(f.receita), 0), 4) AS margem_pct,
       COUNT(DISTINCT f.pedido_id) AS pedidos,
       ROUND(SUM(f.receita) / NULLIF(COUNT(DISTINCT f.pedido_id), 0), 2) AS ticket_medio
FROM lakehouse_rotaperfume.gold.fato_vendas f
GROUP BY f.ano, f.mes;

-- ---------------------------------------------------------------------
-- gold.ranking_marcas
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ranking_marcas (
  marca           COMMENT 'Marca do produto.',
  receita         COMMENT 'Receita total da marca no período.',
  margem          COMMENT 'Margem total da marca no período.',
  margem_pct      COMMENT 'Margem sobre receita, de 0 a 1.',
  participacao_pct COMMENT 'Fatia da marca na receita total da empresa, de 0 a 1.',
  skus            COMMENT 'Quantidade de SKUs distintos vendidos da marca.',
  pedidos         COMMENT 'Pedidos distintos que contiveram a marca.'
)
COMMENT 'Responde: quais marcas mais venderam? Quanto cada uma representa do faturamento?'
AS
SELECT marca,
       ROUND(SUM(receita), 2) AS receita,
       ROUND(SUM(margem), 2)  AS margem,
       ROUND(SUM(margem) / NULLIF(SUM(receita), 0), 4) AS margem_pct,
       ROUND(SUM(receita) / SUM(SUM(receita)) OVER (), 4) AS participacao_pct,
       COUNT(DISTINCT sku)       AS skus,
       COUNT(DISTINCT pedido_id) AS pedidos
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY marca;

-- ---------------------------------------------------------------------
-- gold.margem_por_categoria
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.margem_por_categoria (
  categoria         COMMENT 'Categoria do produto.',
  receita           COMMENT 'Receita da categoria no período.',
  margem            COMMENT 'Margem da categoria no período.',
  margem_pct        COMMENT 'Margem sobre receita, de 0 a 1. Kit Presente fica em 0,33 e Óleo Concentrado em 0,50.',
  margem_tabela_pct COMMENT 'Margem teórica do catálogo. A diferença para a praticada é o efeito do desconto comercial.',
  pecas             COMMENT 'Peças movimentadas, em valor absoluto.'
)
COMMENT 'Responde: onde a empresa ganha e onde perde margem? Qual categoria vende muito e ganha pouco?'
AS
SELECT f.categoria,
       ROUND(SUM(f.receita), 2) AS receita,
       ROUND(SUM(f.margem), 2)  AS margem,
       ROUND(SUM(f.margem) / NULLIF(SUM(f.receita), 0), 4) AS margem_pct,
       ROUND(AVG((p.preco_tabela - p.custo_unitario) / NULLIF(p.preco_tabela, 0)), 4) AS margem_tabela_pct,
       SUM(abs(f.quantidade))   AS pecas
FROM lakehouse_rotaperfume.gold.fato_vendas f
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = f.sku
GROUP BY f.categoria;

-- ---------------------------------------------------------------------
-- gold.clientes_em_risco
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.clientes_em_risco (
  cliente_id       COMMENT 'Identificador do cliente.',
  razao_social     COMMENT 'Nome do cliente.',
  segmento         COMMENT 'Tipo de varejo do cliente.',
  cidade           COMMENT 'Cidade do cliente.',
  ultimo_pedido    COMMENT 'Data do último pedido do cliente.',
  dias_sem_comprar COMMENT 'Dias entre o último pedido do cliente e a data atual.',
  total_pedidos    COMMENT 'Quantos pedidos o cliente já fez.',
  receita_acumulada COMMENT 'Quanto o cliente já comprou no total.',
  receita_mensal_media COMMENT 'Quanto o cliente comprava por mês, em média, enquanto estava ativo. É a receita que se perde por mês se ele não voltar.'
)
COMMENT 'Responde: quais clientes pararam de comprar, e quanta receita a empresa perde com isso? Risco = mais de 90 dias sem pedido.'
AS
SELECT c.cliente_id, c.razao_social, c.segmento, c.cidade,
       c.data_ultimo_pedido AS ultimo_pedido, c.dias_sem_comprar, c.total_pedidos,
       ROUND(c.receita_acumulada, 2) AS receita_acumulada,
       ROUND(c.receita_acumulada
             / NULLIF(months_between(c.data_ultimo_pedido, c.data_primeiro_pedido), 0), 2) AS receita_mensal_media
FROM lakehouse_rotaperfume.gold.dim_cliente c
WHERE c.dias_sem_comprar > 90;

-- ---------------------------------------------------------------------
-- gold.efeito_lancamento
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.efeito_lancamento (
  sku              COMMENT 'Código do produto.',
  descricao        COMMENT 'Nome do produto.',
  marca            COMMENT 'Marca do produto.',
  data_lancamento  COMMENT 'Data em que o SKU entrou na linha.',
  receita_120_dias COMMENT 'Receita gerada nos primeiros 120 dias após o lançamento.',
  receita_depois   COMMENT 'Receita gerada do 121º dia em diante.',
  receita_total    COMMENT 'Receita total do SKU no período.',
  peso_do_lancamento COMMENT 'Fatia da receita do SKU que veio dos 120 primeiros dias, de 0 a 1.'
)
COMMENT 'Responde: o quanto o lançamento de um produto puxa a receita? Quanto do faturamento vem da janela de novidade?'
AS
SELECT p.sku, p.descricao, p.marca, p.data_lancamento,
       ROUND(SUM(CASE WHEN datediff(f.data_pedido, p.data_lancamento) BETWEEN 0 AND 120
                      THEN f.receita ELSE 0 END), 2) AS receita_120_dias,
       ROUND(SUM(CASE WHEN datediff(f.data_pedido, p.data_lancamento) > 120
                      THEN f.receita ELSE 0 END), 2) AS receita_depois,
       ROUND(SUM(f.receita), 2) AS receita_total,
       ROUND(SUM(CASE WHEN datediff(f.data_pedido, p.data_lancamento) BETWEEN 0 AND 120
                      THEN f.receita ELSE 0 END) / NULLIF(SUM(f.receita), 0), 4) AS peso_do_lancamento
FROM lakehouse_rotaperfume.gold.fato_vendas f
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = f.sku
WHERE p.data_lancamento IS NOT NULL
GROUP BY p.sku, p.descricao, p.marca, p.data_lancamento;

-- ---------------------------------------------------------------------
-- gold.ruptura_por_marca
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ruptura_por_marca (
  marca             COMMENT 'Marca do produto.',
  snapshots         COMMENT 'Quantidade de leituras semanais de estoque para a marca.',
  snapshots_em_ruptura COMMENT 'Quantas dessas leituras estavam com saldo zerado.',
  ruptura_pct       COMMENT 'Fatia das leituras em ruptura, de 0 a 1.',
  saldo_medio       COMMENT 'Saldo médio em unidades nas leituras.'
)
COMMENT 'Responde: quais marcas mais faltam no estoque? Em perfumaria, ruptura não migra a venda para outro produto — ela some.'
AS
SELECT p.marca,
       COUNT(*) AS snapshots,
       SUM(CASE WHEN e.ruptura THEN 1 ELSE 0 END) AS snapshots_em_ruptura,
       ROUND(AVG(CASE WHEN e.ruptura THEN 1.0 ELSE 0.0 END), 4) AS ruptura_pct,
       ROUND(AVG(e.saldo), 1) AS saldo_medio
FROM lakehouse_rotaperfume.silver.estoque e
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = e.sku
GROUP BY p.marca;
