Continue o app rotaperfume-direcao. Ele lê a fila; agora ele precisa registrar
o que aconteceu na ligação.

1. A ROTA QUE ESCREVE — uma só, em server/server.ts, dentro de onPluginsReady

   POST /api/retorno, com o corpo validado por Zod ANTES de tocar no banco:
     cliente_id  int (use z.coerce.number(): a tela manda o id que veio do
                 warehouse, e ele chega como STRING mesmo tipado como number)
     vendedor    string não vazia
     status      enum: vendeu | vai_pensar | sem_interesse | nao_atendeu
     comentario  string, no máximo 500 caracteres, opcional
     referencia  string no formato aaaa-mm-dd

   Corpo inválido devolve 400 sem consultar o warehouse. O enum é o contrato:
   é ele que impede a tabela de ter "vendeu", "Vendeu" e "vendido".

   O INSERT vai por
   getExecutionContext().client.statementExecution.executeStatement, com
   warehouse_id vindo do próprio contexto, e TODO valor passado como
   parameters — nunca concatenado na string do SQL.

   registrado_por sai do header x-forwarded-email (com um valor local de
   desenvolvimento como reserva), registrado_em de current_timestamp().

   Mantenha também GET /api/quem-sou, que a aba Perguntar já usa.

   NÃO crie endpoint para ler nada: leitura continua sendo arquivo .sql.

2. OS BOTÕES, na tabela da aba "A semana"

   Uma coluna "Como foi a ligação". Para o cliente sem retorno: um campo de
   texto curto para o comentário e quatro botões — Vendeu, Vai pensar, Sem
   interesse, Não atendeu. O clique grava e desabilita enquanto grava.
   Para quem já tem retorno: mostre o status como Badge e o comentário
   embaixo, sem os botões.

   Se a gravação falhar, mostre um Alert com uma frase em português. Nunca
   engula o erro.

3. A RECARGA — sem isso a tela mente

   useAnalyticsQuery não tem refetch, e o AppKit guarda o resultado da
   consulta. Depois de gravar, a tela continua mostrando o número de antes.

   NÃO resolva isso com um parâmetro falso no SQL (:recarga >= 0). Funciona,
   mas quem estiver com a página aberta de uma versão anterior passa a mandar
   a consulta sem o parâmetro, e o warehouse recusa com UNBOUND_SQL_PARAMETER
   — a tela quebra sozinha depois de um deploy.

   Faça as duas coisas:
   a) desligue o cache de leitura no createApp: cache: { enabled: false }.
      São 200 linhas, e todas mudam quando alguém clica
   b) recarregue em React: guarde filtro e comentários no componente PAI e
      remonte o filho com uma `key` que muda a cada gravação. Remontar refaz
      a consulta, sem inventar coluna nem parâmetro

4. A ABA "Acompanhamento" (rota /acompanhamento)

   Lê acompanhamento.sql:
   - no topo, uma frase: quantos dos 200 foram trabalhados e quantos viraram
     pedido
   - um gráfico de barras por vendedor: trabalhados e vendeu
   - a tabela com o desfecho por vendedor

   Enquanto ninguém registrou nada, mostre um Empty dizendo que o número
   aparece assim que o time marcar o retorno — e que isso vira dado de treino
   da semana que vem. Zero não é erro.

5. A PERMISSÃO DE ESCRITA — escopada em uma tabela só

   GRANT MODIFY ON TABLE lakehouse_rotaperfume.gold.retorno_ligacao TO `<sp>`

   Em TABLE, não em SCHEMA. O app não pode alterar mais nada da gold.

6. Suba:
   databricks apps validate --profile projeto-dados-ia
   databricks apps deploy -t default --profile projeto-dados-ia