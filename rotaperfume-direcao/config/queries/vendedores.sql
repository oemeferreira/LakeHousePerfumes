-- Vendedores com contatos na fila desta semana, para alimentar o filtro.
SELECT DISTINCT vendedor
FROM lakehouse_rotaperfume.gold.fila_semanal
ORDER BY vendedor
