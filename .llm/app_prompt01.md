Continue o bundle em .
A noite 3 deixou gold.fila_semanal com 200 contatos e gold.score_propensao
com a nota de todos os clientes. Hoje eu quero duas coisas: a tabela onde o
time registra o que aconteceu depois da ligação, e um Genie space feito para
a direção.

1. src/gold/11-retorno-ligacao.sql — a tabela do caminho de volta

   CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao com:
     cliente_id      INT
     vendedor        STRING
     status          STRING     vendeu | vai_pensar | sem_interesse | nao_atendeu
     comentario      STRING     texto livre do vendedor
     registrado_em   TIMESTAMP
     registrado_por  STRING     e-mail de quem estava logado
     _referencia     DATE       a semana da fila

   IF NOT EXISTS, e não CREATE OR REPLACE: é a ÚNICA tabela do projeto cujo
   dado não vem do pipeline. Um redeploy não pode apagar o que o time
   respondeu.

   COMMENT em toda coluna e na tabela — a auditoria de metadado da noite 2
   quebra o job se faltar, e é o COMMENT que o Genie lê para escolher coluna.

   Acrescente ao pipeline a tarefa gold_retorno_ligacao, depois de gold_marts.
   O job vai de 15 para 16 tarefas.

2. resources/direcao.geniespace.json + resources/genie-direcao.genie_space.yml

   Um SEGUNDO Genie space, chamado "Rota do Perfume · Direção". Não altere o
   genie_comercial que já existe — a chave dele não pode mudar.

   Fontes, e só estas sete:
     gold.fila_semanal      o assunto principal
     gold.score_propensao   a nota de todos, para o cliente fora da fila
     gold.modelo_metricas   lift_top200, acertos_top200, taxa_base
     gold.retorno_ligacao   o que aconteceu depois
     gold.clientes_em_risco, gold.ranking_marcas, gold.receita_mensal

   As instruções, em português, cobrindo:
   - quem pergunta: a direção comercial, que não escreve SQL e decide ligação
   - o que é score (0 a 1, chance de comprar em 7 dias), faixa, ordem, motivo
   - por que a fila é GLOBAL e não cota por vendedor: quem tem carteira quente
     recebe mais contatos, e isso está certo
   - receita esperada da fila = SUM(score * ticket_medio), e é ESTIMATIVA,
     nunca receita realizada
   - a métrica da direção é lift_top200. NUNCA cite AUC para responder
     pergunta de negócio: AUC é métrica de quem treina
   - retorno_ligacao começa VAZIA. Se a resposta for zero, diga que ninguém
     registrou retorno ainda — não invente número, e não use a fila como se
     fosse retorno
   - um cliente pode ter mais de um retorno: para o estado atual, use o mais
     recente por registrado_em
   - a sazonalidade é INVERTIDA: o pico é o mês ANTERIOR à data comemorativa
   - nunca use o schema bronze

   5 sample_questions e 5 pares pergunta -> SQL já validado, incluindo
   "Quem eu ligo essa semana?", "Quanto vale a fila desta semana?" e
   "Quantas ligações já foram registradas e quantas viraram pedido?".

   AS QUATRO REGRAS DA API QUE FAZEM O DEPLOY FALHAR:
   a) data_sources.tables ORDENADO por identifier
   b) column_configs de cada tabela ordenado por column_name
   c) todo id com 32 caracteres hexadecimais minúsculos, sem hífen
   d) as listas de perguntas e instruções também ordenadas por id

   Gere os ids com md5 do conteúdo — determinístico. Um redeploy não pode
   recriar as perguntas nem sujar o diff do Git.

3. Rode, e me mostre o resultado:
   databricks bundle validate --target dev --profile projeto-dados-ia
   databricks bundle deploy   --target dev --profile projeto-dados-ia
   bash scripts/rodar-tarefa.sh projeto-dados-ia gold_retorno_ligacao

   NÃO use --auto-approve. Se o deploy pedir para apagar o dashboard ou o
   genie_comercial, pare e me avise.