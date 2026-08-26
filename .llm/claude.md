# Imersão Dados + IA — Rota do Perfume

Projeto técnico da Imersão Jornada de Dados, **24 a 27 de agosto de 2026**,
19h30, ao vivo no YouTube. Quatro noites de 1h30 construindo uma área de dados
e vendas do zero.

Este arquivo é o contexto do projeto. Leia antes de escrever qualquer código.

---

## 1. O negócio

**Rota do Perfume** é uma distribuidora B2B de perfumaria árabe. Importa e
distribui no Brasil para perfumarias, farmácias, lojas de shopping,
revendedoras autônomas e e-commerces. Empresa em crescimento acelerado:
R$ 102 mi de receita em 24 meses, com a receita mais que dobrando no período.

Assumimos o papel de um **analista de dados recém-contratado**. A diretoria
comercial quer responder três perguntas:

1. **Quem vai comprar?** — propensão
2. **Quem está sumindo?** — churn
3. **Quanto vamos vender?** — previsão

### O que esse setor tem de peculiar

**Quatro picos de sazonalidade, não um.** O varejo compra *antes* da data, então
o pico da distribuidora é o mês anterior:

| Mês | Motivo |
|---|---|
| Abril | Reposição para o Dia das Mães |
| Junho | Dia dos Namorados |
| Outubro | Reposição para a Black Friday |
| Dezembro e janeiro | Vale — o varejo já está abastecido |

Outubro/2025 fez R$ 7,0 mi. Janeiro/2026 fez R$ 2,5 mi. **Quem não entende o
negócio lê o gráfico ao contrário.**

**Outros comportamentos reais do dado:**

- **Lançamento gera pico:** 47 SKUs lançados responderam por R$ 25,5 mi — 25%
  da receita com 16% dos produtos, concentrado nos 120 dias após o lançamento
- **Marca concentra:** Layali R$ 18,6 mi contra Attar Real R$ 5,2 mi
- **Margem varia muito:** Óleo Concentrado 49,9% contra Kit Presente 33,0%
- **Ruptura dói mais que em outros setores:** quando esgota o perfume da moda,
  a venda não migra para outro produto — ela some
- **Segunda e terça** concentram pedido; fim de semana é quase nulo
- **~11% dos clientes** entram em churn
- Ticket médio por pedido: R$ 3.684

---

## 2. Stack

| Ferramenta | Papel |
|---|---|
| Databricks Free Edition | Ambiente principal, compute serverless |
| Python 3.12 | **Não use 3.13** — bibliotecas do Databricks ainda quebram |
| SQL | Modelagem e análise |
| Delta Lake + Unity Catalog | Armazenamento e governança |
| Claude Code | Desenvolvimento |
| uv | Gerenciador de pacotes |
| Databricks Asset Bundles | Deploy e versionamento |
| DuckDB | Plano B local se o Databricks travar ao vivo |

**Catálogo:** `lakehouse_rotaperfume` · **Schemas:** `bronze`, `silver`, `gold`

---

## 3. Estrutura das 4 noites

| Noite | Data | Tema | Entregável |
|---|---|---|---|
| 1 | 24/08 seg | Objetivo e análise | Catálogo montado, primeira análise — **tudo pela interface** |
| 2 | 25/08 ter | Engenharia de dados | Bronze, silver, gold, pipeline agendado |
| 3 | 26/08 qua | Ciência de dados e agentes | Modelo de propensão e agente de IA |
| 4 | 27/08 qui | Deploy e próximos passos | Projeto no ar e monitorado |

**Carrinho abre na noite 3**, depois da entrega técnica — nunca antes.

### Por que a noite 1 é toda na interface

38% da base nunca escreveu uma query. Se a segunda-feira começa com CLI e
`uv venv`, metade da sala desiste antes de ver algo interessante. Além disso,
fazer na mão primeiro cria a dor que justifica a terça: *"vocês viram como foi
clicar em tudo isso? Se o dado atualizar, refaz tudo."*

---

## 4. O dataset

Gerado por `gerar_dataset.py --saida ./dados --seed 42`. **Seed fixa**: todos
os alunos chegam exatamente no mesmo resultado. Período: set/2024 a ago/2026.
~14 MB — dimensionado para caber no Free Edition.

### ERP — o que foi vendido

| Tabela | Linhas | Chave | Colunas principais |
|---|---|---|---|
| `produtos` | 292 | `sku` | descricao, categoria, marca, **nota_olfativa**, preco_tabela, custo_unitario, unidade, ativo, **data_lancamento** |
| `pedidos` | 28.729 | `pedido_id` | cliente_id, vendedor_id, data_pedido, canal, status, valor_total |
| `itens_pedido` | 197.724 | `item_id` | pedido_id, sku, quantidade, preco_praticado, desconto_pct, valor_bruto |
| `pagamentos` | 27.772 | `pagamento_id` | forma_pagamento, parcelas, valor, taxa_pct, valor_liquido, data_vencimento, data_pagamento, status_pagamento |
| `estoque` | 8.400 | `data_snapshot`+`sku` | saldo, ruptura |

### CRM — para quem vendemos

| Tabela | Linhas | Chave | Colunas principais |
|---|---|---|---|
| `clientes` | 3.040 | `cliente_id` | cnpj, razao_social, segmento, cidade, uf, bairro, data_cadastro, ativo |
| `vendedores` | 42 | `vendedor_id` | nome, regiao, uf, data_admissao, data_desligamento, meta_mensal |
| `carteira` | 3.637 | `carteira_id` | cliente_id, vendedor_id, data_inicio, data_fim |
| `oportunidades` | 5.979 | `oportunidade_id` | origem, data_abertura, etapa, probabilidade_pct, valor_estimado, data_fechamento, ciclo_dias, motivo_perda |
| `visitas` | 37.936 | `visita_id` | cliente_id, vendedor_id, data_visita, resultado, duracao_min |

### Relacionamentos

```
clientes 1─N pedidos 1─N itens_pedido N─1 produtos
clientes 1─N oportunidades
clientes 1─N visitas
clientes N─N vendedores  (via carteira, com vigência)
pedidos  1─1 pagamentos
```

### Funil comercial

1.487 oportunidades ganhas (R$ 81,0 mi estimados) contra 773 perdidas
(R$ 40,6 mi). Ciclo médio de 37,7 dias. As etapas na origem se chamam
`Fechado ganho` e `Fechado perdido` — não `Ganha`/`Perdida`. **Motivo de perda número 1: prazo de entrega.**

---

## 5. A sujeira é proposital

**Não "conserte" o gerador.** A limpeza é o conteúdo da noite 2.

| # | Sujeira | Onde |
|---|---|---|
| 1 | CNPJ em 3 formatos: puro, pontuado, com espaço | `clientes.cnpj` |
| 2 | Razão social em CAIXA ALTA ou sem acento | `clientes.razao_social` |
| 3 | Data em ISO e `dd/mm/aaaa` misturadas | `clientes.data_cadastro` |
| 4 | ~40 clientes duplicados: id novo, mesmo CNPJ | `clientes` |
| 5 | SKU descontinuado ainda em venda | `itens_pedido` × `produtos.ativo` |
| 6 | Devolução como quantidade negativa | `itens_pedido.quantidade` |
| 7 | Cancelado com `valor_total` zerado, sem flag | `pedidos` |
| 8 | ~12% das datas em formato brasileiro | `pedidos.data_pedido` |
| 9 | Vendedor desligado com carteira ativa | `carteira` × `vendedores` |
| 10 | Ruptura de estoque em ~11% dos snapshots | `estoque.saldo = 0` |

### A decisão sobre a devolução

Três caminhos possíveis, só um está certo:

- **Descartar a linha** → esconde receita negativa e infla o faturamento
- **Manter sem flag** → polui toda soma
- **Sinalizar e deixar a análise decidir** → correto

Crie as colunas `devolucao` (boolean) e `quantidade_abs`. Nunca descarte.

---

## 6. Arquitetura

```
Camada     Schema    O que tem                       Noite
──────────────────────────────────────────────────────────
Fontes     —         CSV de ERP e CRM                 —
Bronze     bronze    Ingestão crua, sujeira inclusa    2
Silver     silver    Limpo, deduplicado, tipado        2
Gold       gold      Fatos e dimensões para consumo    2
Features   gold      Features por cliente              3
Score      gold      Propensão gravada e versionada    3
Agente     —         Lê o score, decide e age          3
Deploy     —         Agendado e monitorado             4
```

**A lógica de construção é de trás para frente:**

```
Pergunta de negócio → Métrica → Dados necessários
→ Tabela Gold → Transformações → Silver → Bronze → Origem
```

Comece sempre perguntando **"como essa tabela vai ser usada?"**, nunca
"como eu crio essa tabela?".

---

## 7. Convenções

- Nomes de tabela e coluna em **snake_case e português**, como no CSV
- Caminho completo sempre: `lakehouse_rotaperfume.silver.pedidos`
- **Bronze preserva o dado como veio**, com `inferSchema=false`. Se o Spark
  inferir tipo, já erra nas datas em dois formatos e você perde a evidência
  da sujeira
- Bronze adiciona só metadado: `_ingerido_em` e `_arquivo_origem`
- Silver é onde a limpeza acontece
- Gold é modelada para consumo, particionada por `ano` e `mes`
- Notebooks em `src/{camada}/`, nomeados por tabela
- Jobs e dashboards em `resources/`, como YAML no bundle
- Testes em `src/testes/`

### Ao escrever código para este projeto

- **Comente pensando em quem está assistindo ao vivo pela primeira vez**
- **Prefira SQL legível a SQL esperto** — a aula é sobre entender, não impressionar
- Nunca gere número aleatório em análise: o dado é fixo por seed
- Ao mexer em data, lembre que existem dois formatos misturados na origem
- Ao analisar sazonalidade, lembre que o pico é o mês **anterior** à data
- O ambiente é Free Edition: nada que exija cluster dedicado

---

## 8. Números que servem como teste

Se uma query der resultado muito diferente disso, o erro está na query.

| Métrica | Valor esperado |
|---|---|
| Receita total 24 meses | R$ 102.303.828,05 |
| Outubro/2025 | R$ 7,0 mi |
| Janeiro/2026 | R$ 2,5 mi |
| Ticket médio por pedido | R$ 3.684 |
| Linhas na `gold.fato_vendas` | entre 140.000 e 250.000 |
| Marca líder | Layali, R$ 18,6 mi |
| Margem Óleo Concentrado | 49,9% |
| Margem Kit Presente | 33,0% |
| Oportunidades ganhas | 1.487 (R$ 81,0 mi estimados) |
| Clientes únicos após dedup | 3.000 |

---

## 9. Os 6 prompts da noite 2

Cada prompt entrega uma coisa que roda. **Enquanto o Claude Code trabalha, o
professor explica o conceito** — o tempo de espera vira aula.

| # | Entrega | Conceito explicado |
|---|---|---|
| 1 | Bronze: ingestão das 10 tabelas | Por que a bronze preserva a sujeira |
| 2 | Silver: limpeza e deduplicação | Engenharia é resolver bagunça, não escrever SQL bonito |
| 3 | Gold: data mart comercial | Contrato da Gold — granularidade, dimensões, métricas |
| 4 | Workflow: job com testes | Dependência explícita e falha que interrompe |
| 5 | Dashboard como código | Dashboard versionado tem diff, revisão e rollback |
| 6 | Genie: metadado e views de negócio | Metadado é o que faz a IA funcionar |

O momento "agora entendi" é o **prompt 1**: dez tabelas em Delta em menos de
dois minutos, contra uma tarde clicando.

O fechamento é o **prompt 6**: o Genie que errava com confiança na noite 1
agora acerta — e o motivo é tudo que foi construído nas duas horas anteriores.

---

## 10. Setup do ambiente

Pré-requisito da **noite 2**, não da noite 1. A segunda-feira é toda pelo
navegador.

```bash
# 1. CLI — precisa ser 0.205 ou superior
brew tap databricks/tap && brew trust databricks/tap && brew install databricks
databricks -v

# 2. Autenticação
databricks auth login --host https://SEU-WORKSPACE.cloud.databricks.com

# 3. Projeto — template default-python, serverless YES
databricks bundle init

# 4. Ambiente Python
uv venv --python 3.12 --seed && source .venv/bin/activate && uv sync

# 5. Git
git init && git add . && git commit -m "setup inicial"

# 6. Skills oficiais do Databricks
databricks aitools install

# 7. MCP conectado
databricks ucode
```

### Erros que todo mundo comete

| Erro | Solução |
|---|---|
| `stored credentials from older CLI` | Rode `databricks auth login` de novo |
| `command not found` | Reinicie o terminal |
| Versão abaixo de 0.205 | É a legacy CLI. Desinstale e reinstale. |
| Deploy falha por compute | Você respondeu `no` para serverless |
| Biblioteca não instala | Você está no Python 3.13. Volte para 3.12. |
| MCP não aparece | Falta `--transport http`, ou não reiniciou o Claude Code |
| Compute desligado | Cota do Free Edition estourou |

### Guard rails antes de conectar o MCP

Coloque as travas **antes** de dar acesso ao workspace. Em
`.claude/settings.json`, negue `databricks bundle destroy`,
`databricks bundle deploy --target prod`, `git push --force` e `rm -rf`.

E um hook em `.claude/hooks/` que bloqueie `DROP`, `TRUNCATE` e `DELETE` sem
`WHERE`. **Hook é determinístico** — diferente de skill e MCP, que são
probabilísticos. Se ele bloqueia, bloqueia sempre.

---

## 11. Riscos ao vivo

| Risco | Mitigação |
|---|---|
| Cota do Free Edition estoura | Aviso na noite 1; plano B em DuckDB aberto em outra aba |
| Query trava ao vivo | Resultado pré-computado numa célula abaixo |
| Um prompt não entrega | Branch `gabarito` com o resultado pronto: `git checkout gabarito -- src/` |
| Aula estoura 1h30 | Corte contexto, nunca a entrega |
| Metade da base é iniciante | Trilha de fundamentos indicada no grupo |

**Regra de ouro do ao vivo:** 90 minutos são 75 minutos úteis. Sempre há
atraso de início, pergunta no chat e aluno travado no setup.

---

## 12. Definição de pronto

- [ ] `gerar_dataset.py` rodando e produzindo o mesmo dado com seed 42
- [ ] Bronze, silver e gold no catálogo `lakehouse_rotaperfume`
- [ ] Pipeline agendado com os 5 testes de qualidade passando
- [ ] Dashboard como código, versionado no bundle
- [ ] Genie space configurado com metadado e instruções
- [ ] Modelo de propensão com AUC registrado (noite 3)
- [ ] Agente respondendo em cima do score real (noite 3)
- [ ] Job de produção agendado e monitorado (noite 4)
- [ ] README explicando o projeto para quem chegar de fora

---

## 13. Dados reais da noite 1 (24/08)

A primeira aula aconteceu. Números que devem calibrar as noites seguintes:

| Métrica | Valor |
|---|---|
| Espectadores simultâneos | 914 no pico, 771 de média |
| Duração | 1h45 |
| Certificados emitidos | 445 (377 e-mails únicos) |
| Nota média | 9,4 · 81,6% deram 9 ou 10 |
| Mensagens no chat | 1.261 |
| Visualizações em 24h | 5,5 mil |

### A composição da sala é mais técnica que a base de inscritos

| Perfil | % dos que emitiram certificado |
|---|---|
| Já trabalha com dados | 46,7% |
| Está migrando para dados | 26,1% |
| Trabalha com tecnologia, não com dados | 21,1% |
| Não trabalha com tecnologia | 6,1% |

**73% é público-alvo real**, contra 42% que a base de inscritos sugeria. A live
filtrou naturalmente.

**Consequência prática: pode ir mais fundo do que o plano original previa.**
22 pessoas deram nota 7 ou menos, e 18 delas já trabalham com dados. Um
comentário resume: *"pouco tempo"*. O público sênior achou a aula 1 rasa.

### Sinal comercial

107 pessoas (24%) pediram informação espontaneamente, sem nenhum pitch:
55 sobre a trilha de Claude Code e IA, 52 sobre a formação completa.

Cuidado ao trabalhar essa lista: 29 delas ganham até R$3 mil e 9 estão sem
renda. Os 45 que já trabalham com dados e os 28 acima de R$6 mil são o núcleo
comercial de verdade.

### O que a noite 1 deixou como gancho

Referencie isso na noite 2 para criar continuidade:

- Subiram as 10 tabelas **clicando, uma por uma** → o prompt 1 é a resposta
- Viram o CNPJ em 3 formatos e a data em 2 → o prompt 2 é a resposta
- O Genie foi plugado na bronze com o aviso de que podia errar → o prompt 6 é a resposta
- Você falou que *one-shot prompt* é o jeito errado → os 6 prompts são o jeito certo

### O catálogo criado ao vivo

Na noite 1 o catálogo foi criado com o nome **`lakehouse_rotaperfume`**, com
os schemas `bronze`, `silver` e `gold`. Use esse nome em todo código a partir
daqui.