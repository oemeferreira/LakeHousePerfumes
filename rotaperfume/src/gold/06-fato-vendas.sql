-- rotaperfume/src/gold/06-fato-vendas.sql
-- Contrato de Dados da Tabela Fato de Vendas:
--   Granularidade: uma linha por ITEM de pedido.
--   Filtro: exclui pedidos cancelados (silver.pedidos.cancelado = false).
--           NAO exclui devolucoes (itens com quantidade negativa).
--   Dimensões: data_pedido, ano, mes, canal, cliente_id, razao_social,
--              segmento, cidade, vendedor_id, sku, descricao, categoria,
--              marca, nota_olfativa.
--   Métricas:  quantidade, preco_praticado, desconto_pct, receita, custo,
--              margem, devolucao.
--   Regras de calculo:
--     receita = valor_bruto do item (ja negativo quando devolucao)
--     custo   = quantidade * custo_unitario do produto (negativo em devolucao)
--     margem  = receita - custo
--
--   POR QUE A DEVOLUCAO FICA DENTRO: se ela ficar de fora, a gold soma
--   R$ 103,6 mi e a silver R$ 102,3 mi (R$ 1,26 milhao de diferenca entre
--   duas camadas do mesmo pipeline). Quem quiser o faturamento bruto pede:
--     SUM(receita) FILTER (WHERE NOT devolucao)

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
PARTITIONED BY (ano, mes)
AS
SELECT
  p.pedido_id,
  i.item_id,
  p.data_pedido,
  p.ano,
  p.mes,
  p.canal,
  p.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  p.vendedor_id,
  i.sku,
  pr.descricao,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  i.desconto_pct,
  i.valor_bruto AS receita,
  CAST(i.quantidade * pr.custo_unitario AS DECIMAL(18,2)) AS custo,
  CAST(i.valor_bruto - (i.quantidade * pr.custo_unitario) AS DECIMAL(18,2)) AS margem,
  i.devolucao,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = i.pedido_id
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = p.cliente_id
WHERE NOT p.cancelado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Tabela fato de vendas no grao de item de pedido. Exclui pedidos cancelados e preserva devolucoes como valores negativos para conciliar perfeitamente com a receita liquida da camada silver.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.pedido_id IS
  'Identificador unico do pedido de venda emitido pelo ERP.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.item_id IS
  'Identificador unico da linha de item do pedido no ERP.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.data_pedido IS
  'Data em que o pedido foi emitido pelo cliente.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.ano IS
  'Ano da emissao do pedido, utilizado para particao da tabela.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.mes IS
  'Mes da emissao do pedido (1 a 12), utilizado para particao da tabela.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.canal IS
  'Canal comercial pelo qual a venda foi originada (ex: Representante, E-commerce, Televendas, Balcao).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cliente_id IS
  'Chave do cliente comprador cadastrado no CRM.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.razao_social IS
  'Nome ou razao social da empresa compradora.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.segmento IS
  'Classificacao comercial do cliente (Perfumaria, Farmacia, Shopping, Revendedora, E-commerce).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cidade IS
  'Cidade sede do cliente comprador.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.uf IS
  'Estado (UF) do cliente comprador.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.vendedor_id IS
  'Chave do vendedor ou representante responsavel pela transacao.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.sku IS
  'Codigo do produto vendido no catalogo de perfumaria.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.descricao IS
  'Nome comercial e descricao do perfume.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.categoria IS
  'Categoria do produto (Oleo Concentrado, Eau de Parfum, Kit Presente, etc).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.marca IS
  'Marca da casa de perfumaria arabe importada.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.nota_olfativa IS
  'Familia olfativa predominante (Amadeirado, Floral, Ambar, Oriental, etc).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.quantidade IS
  'Unidades vendidas do item. Valor negativo indica devolucao de mercadoria.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.preco_praticado IS
  'Preco unitario negociado para o item na venda.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.desconto_pct IS
  'Percentual de desconto comercial concedido sobre o item.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.receita IS
  'Faturamento liquido da linha (quantidade * preco_praticado com desconto aplicado). Negativo em caso de devolucao.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.custo IS
  'Custo de aquisicao das unidades vendidas (quantidade * custo_unitario). Negativo em devolucao para estornar o custo.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.margem IS
  'Receita menos custo do produto. Nao considera desconto financeiro posterior nem frete.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.devolucao IS
  'Flag booleana indicando se o item representa devolucao fisica de mercadoria (true) ou venda regular (false).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas._processado_em IS
  'Timestamp UTC do momento em que a tabela fato foi gerada no Lakehouse.';
