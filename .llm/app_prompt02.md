Crie um Databricks App para a direção comercial da Rota do Perfume. Ele lê o que a noite 3 produziu — nenhuma tabela
nova.

1. O SCAFFOLD

   databricks apps init --name rotaperfume-direcao \
     --features analytics,genie \
     --set analytics.sql-warehouse.id=666be37e3fededf2 \
     --set genie.genie-space.id=<o id do space "Rota do Perfume · Direção"> \
     --set genie.genie-space.name="Rota do Perfume · Direção" \
     --description "A fila dos 200 na tela do diretor" \
     --run none --profile projeto-dados-ia

   Pegue o id do space com `databricks bundle summary --target dev` no bundle
   da noite 2, ou com `databricks genie list-spaces`. NÃO invente o id.

2. AS QUERIES, uma por arquivo em config/queries/ — nunca SQL dentro do React

   kpis_semana.sql   contatos, vendedores, receita esperada
                     (SUM(score*ticket_medio)), a referência da fila, mais
                     acertos_top200/lift_top200/taxa_base da ÚLTIMA versão de
                     gold.modelo_metricas (QUALIFY ROW_NUMBER() OVER
                     (ORDER BY versao DESC) = 1) e a contagem de
                     gold.retorno_ligacao
   vendedores.sql    vendedor -> contatos, para alimentar o filtro
   fila.sql          os 200 com todas as colunas de leitura humana (motivo,
                     sugestao), LEFT JOIN com o retorno mais recente de cada
                     cliente. Parâmetro `vendedor`, onde 'Todos' não filtra
   acompanhamento.sql  por vendedor: na_fila, trabalhados e a contagem de
                     cada status

   Anote os parâmetros com -- @param e dê valor de exemplo (= Todos), senão o
   typegen não consegue descrever a query.

   Rode `npm run typegen` com o WAREHOUSE LIGADO e me mostre a saída. Se
   aparecer OFFLINE ou "degraded", pare: os tipos saem como {} e o tsc quebra
   longe da causa real.

3. AS TELAS — três, no menu do topo, em português

   "A semana" (rota /):
     - quatro cartões no topo: contatos da semana (com o número de
       vendedores), receita esperada em reais, conversão prevista
       (acertos_top200/contatos em %) com a taxa base ao lado como
       comparação, e já trabalhados (com quantos viraram pedido)
     - um Select com os vendedores, mais a opção "Todos os vendedores"
     - a tabela da fila: ordem, cliente (razão social + cidade/UF + ticket),
       vendedor, chance em %, motivo e sugestão

   "Perguntar" (rota /perguntar):
     - o GenieChat do space do prompt 1
     - o e-mail de quem está logado, lido de uma rota /api/quem-sou que
       devolve o header x-forwarded-email
     - um aviso permanente de que a resposta é gerada por IA e traz o SQL que
       a produziu

   Toda tela precisa tratar os quatro estados: carregando (Skeleton), vazio
   (Empty, com uma frase útil — para um vendedor sem contatos, explique que a
   fila é global), erro (Alert, nunca painel em branco) e o dado.

   Formate em português: R$ com toLocaleString('pt-BR'), score como
   porcentagem inteira. Ninguém decide ligação lendo 0.9740085224443632.

   ATENÇÃO, e isto vale para TODA a tela: o warehouse devolve número como
   STRING no JSON, mesmo que o tipo gerado diga `number`. Passe por Number()
   antes de formatar ou somar — senão toLocaleString devolve a string intacta
   (R$ some e aparece 582799.4988012867) e "7" + "12" vira "712".

4. AS PERMISSÕES — sem isso o app sobe e mostra tela vazia

   Depois do primeiro deploy, leia o service principal do app com
   `databricks apps get rotaperfume-direcao -o json` (campo
   service_principal_client_id) e conceda:

     GRANT USE CATALOG ON CATALOG lakehouse_rotaperfume TO `<sp>`
     GRANT USE SCHEMA  ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`
     GRANT SELECT      ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`

   Leia o id do workspace, não copie de lugar nenhum: ele muda a cada app.

5. SUBA E ME MOSTRE A URL

   databricks apps validate --profile projeto-dados-ia
   databricks apps deploy -t default --profile projeto-dados-ia

   O target chama `default`, não `dev`. E é `apps deploy`, não
   `bundle deploy`: um bundle deploy cria o app parado, sem URL.