# Os 3 prompts da Noite 4 — "E quem não escreve SQL?"

**Imersão Jornada de Dados · Apps e agentes · Quinta 27/08 · 19h30**

> **A noite inteira responde uma pergunta só:**
>
> *"O pipeline roda, o modelo escolhe os 200. Como o diretor vê isso —
> e como o vendedor devolve o que aconteceu?"*

Três prompts, três deploys. O bundle da terça ganha uma tabela e uma tarefa
(**16 tarefas**), e nasce um segundo artefato ao lado dele: **um Databricks
App**, com deploy próprio.

```
prompt 1   + genie_direcao      o Genie da direção · gold.retorno_ligacao
prompt 2   + app                a fila dos 200 na tela, com o Genie dentro
prompt 3   + POST /api/retorno  o resultado da ligação volta para a gold
```

**Nada de dado novo.** Toda a noite consome o que as três anteriores
construíram: `gold.fila_semanal`, `gold.score_propensao`,
`gold.modelo_metricas`. A única tabela que nasce hoje é a que recebe a resposta
do time — e ela nasce vazia de propósito.

---

## As armadilhas medidas

1. **O app é um usuário do Unity Catalog, e começa sem permissão nenhuma.**
   `permission: CAN_USE` no warehouse **não** dá acesso aos dados. Sem os três
   `GRANT` para o service principal, toda tela carrega vazia com erro de
   permissão. É o erro nº 1 de apps, e está no prompt 2.

2. **O service principal muda a cada app criado.** Não copie o id de outro
   ambiente: leia com `databricks apps get`.

3. **`useAnalyticsQuery` não tem `refetch`.** Depois de gravar o retorno, a
   tela não se atualiza sozinha. A saída é um parâmetro de recarga que muda a
   chave do cache — está no prompt 3.

4. **O typegen precisa do warehouse ligado.** Com o warehouse parado ele
   degrada para `OFFLINE` e gera `{}` como tipo — e o `tsc` quebra com erros
   que não têm nada a ver com o problema real. Ligue o warehouse antes.

5. **`databricks bundle deploy` não sobe o app.** Ele cria o app com
   `no_compute` e o deixa parado, sem URL. Para app, o comando é
   `databricks apps deploy`.

6. **O target do app se chama `default`, não `dev`.** O bundle do app é gerado
   pelo `apps init` e não segue os targets do bundle da noite 2.