# 🔮 Dia 3: Ciência de dados e agentes de IA | Imersão Jornada de Dados

Ontem o pipeline passou a rodar sozinho. Ele responde muito bem uma pergunta:
**o que aconteceu.** Receita por mês, margem por categoria, quem parou de
comprar.

Hoje ele passa a responder outra — e é a única que o diretor comercial fez:

> **"Tenho 3.000 clientes. O time consegue ligar para 200 por semana.
> Quais 200?"**

> **Promessa da noite:** o dado vira fila de ligação.
> **Formato:** [3 prompts, 3 deploys](prd/3-prompts-noite-3.md). O mesmo bundle
> da terça — o job sai de 12 tarefas e chega a 15.

---

## 🧠 A ideia da noite: ML é camada, não projeto

A tentação, quando entra machine learning num projeto de dados, é abrir um
repositório novo, um notebook solto, um ambiente à parte. É assim que nasce o
modelo que ninguém consegue colocar em produção.

Aqui ML entra como **mais uma camada do mesmo pipeline**: mesmo bundle, mesmo
job, mesmos testes que quebram, mesma auditoria de metadado.

```
raw → bronze → silver ×4 → dimensões → fato → marts → testes
                                             ├→ métricas → auditoria
                                             └→ ml_features → ml_modelo → ml_fila
```

---

## 📋 Os três prompts

Cada um num arquivo próprio, com o prompt copiável, os slides que o
acompanham, o que falar enquanto o Claude Code trabalha, como validar ao vivo
e uma tabela **"se der errado"**.

| # | Entrega | Slides | Arquivo |
|---|---|---|---|
| 1 | **Features** — o que descreve um cliente | 16–23 | [`prompt-01-features.md`](prd/prompt-01-features.md) |
| 2 | **Modelo e MLflow** — o baseline que choca | 24–36 | [`prompt-02-modelo.md`](prd/prompt-02-modelo.md) |
| 3 | **A fila e o agente** — os 200, com motivo | 37–45 | [`prompt-03-fila-e-agente.md`](prd/prompt-03-fila-e-agente.md) |

### Prompt 1 · Features — *o que descreve um cliente*

Transforma o fato de vendas, que tem uma linha por **item**, em uma tabela com
uma linha por **cliente** e 20 colunas de comportamento: RFM, ritmo, CRM e mix.
Tudo sai de UMA função `montar_features(referencia)`, chamada duas vezes com
datas diferentes — é o que garante que treino e score nunca divirjam.

> **Entrega:** `gold.features_treino` (corte 01/08, com o alvo `comprou_em_7d`)
> e `gold.features_cliente` (corte 31/08, sem alvo — é quem vai ser pontuado).
> **O número da vez:** a taxa base de **10,1%** — vinte de cada duzentas
> ligações às cegas viram pedido.

### Prompt 2 · Modelo e MLflow — *o baseline que choca*

Mede as respostas da sala **antes** de treinar qualquer coisa, treina, registra
o modelo no Unity Catalog e pontua os 3.000 clientes. O treino tem três
`assert` que interrompem a tarefa: o modelo precisa ganhar do baseline, não
pode ser bom demais (vazamento) e a fila precisa se pagar.

> **Entrega:** o modelo `gold.propensao_compra` no catálogo com alias `@prod`,
> mais `gold.score_propensao`, `gold.modelo_metricas` e
> `gold.calibragem_holdout`.
> **O número da vez:** **`lift_top200`** — não o AUC. É ele que responde a
> pergunta do diretor.

### Prompt 3 · A fila e o agente — *os 200, com motivo*

Cruza o score com a carteira de cada vendedor e escreve a lista da semana em
português. A fila é **global** — os 200 maiores scores da base inteira — e só
depois é dividida por vendedor: quem tem carteira quente recebe mais, quem tem
carteira fria recebe menos, e é isso que está certo. Cria também as quatro
funções que o agente consulta, e ensina o Genie a nunca inventar número.

> **Entrega:** `gold.fila_semanal` com `motivo` e `sugestao` por cliente, mais
> `priorizar_carteira`, `contexto_cliente`, `sugerir_produtos` e
> `checar_disponibilidade` como funções do Unity Catalog.
> **O número da vez:** **200 contatos entre ~36 vendedores, de 2 a 10 cada** —
> e três testes que quebram o job se a fila vier torta.

## As armadilhas do Free Edition

Medidas contra o workspace. Estão dentro dos prompts, mas vale saber antes:

1. **`mlflow.pyfunc.spark_udf` não funciona no serverless.** Levanta
   `InvalidVersion: '18.x-aarch64-photon-scala2'`. É o caminho que toda
   documentação recomenda. A saída é `load_model` + pandas — e para 3.000
   clientes isso é a escolha certa de qualquer forma.

2. **XGBoost treina e registra, mas não carrega de volta.** Conflito com o
   scikit-learn 1.6.1 do serverless (`__sklearn_tags__`). Só se descobre uma
   tarefa depois. Use `HistGradientBoostingClassifier`.

3. **`mlflow.set_experiment` não cria a pasta pai.** O erro é
   `BAD_REQUEST: For input string: "None"`, que não menciona pasta nenhuma.
   `WorkspaceClient().workspace.mkdirs(...)` antes resolve.

4. **`DECIMAL` não serializa em JSON.** A gold usa `DECIMAL(18,2)`; toda
   feature numérica precisa de `.cast("double")`.

5. **`pyfunc.predict()` devolve a classe, não a probabilidade.** A coluna
   inteira vira zero e um, e a fila vira sorteio. Use `predict_proba()`.

6. **Não há endpoint de modelo próprio no Free Edition.** Por isso o consumo é
   batch, gravando `gold.score_propensao`. Para uma pergunta que muda uma vez
   por dia, é a arquitetura correta de qualquer forma.