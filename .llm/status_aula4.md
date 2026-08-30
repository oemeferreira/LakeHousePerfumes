# Status da Noite 4 — handoff (29/08/2026)

> Leia isto antes de continuar. Os prompts da noite estão em `.llm/`:
> `app_prompt01.md` (FEITO), `app_prompt02.md` (FEITO), `app_prompt03.md` (FEITO).
> **A noite 4 está completa.**

## O que já foi feito

### Prompt 1 — tabela + Genie da direção ✅

- `rotaperfume/src/gold/11-retorno-ligacao.sql` — `CREATE TABLE IF NOT EXISTS`
  `gold.retorno_ligacao` (7 colunas), CHECK `retorno_ligacao_status_valido`
  no enum de status (DROP IF EXISTS + ADD CONSTRAINT, idempotente), COMMENT
  na tabela e nas 7 colunas.
- `rotaperfume/resources/pipeline.job.yml` — tarefa `gold_retorno_ligacao`
  depois de `gold_marts`. O job tem **16 tarefas**.
- `rotaperfume/resources/genie-direcao.genie_space.yml` +
  `direcao.geniespace.json` — space **"Rota do Perfume · Direção"**, 7 fontes,
  instruções completas, 5 sample_questions + 5 pares pergunta→SQL, ids md5
  UTF-8 determinísticos, tudo ordenado pelas regras da API.
- Deploy OK (validade --strict, deploy sem deletar nada, tarefa SUCCESS).
  Tabela verificada no ar com 0 linhas; CHECK testado (INSERT 'Vendeu'
  rejeitado com DELTA_VIOLATE_CONSTRAINT_WITH_VALUES).

### Prompt 2 — app rotaperfume-direcao ✅

- App **no ar**: https://rotaperfume-direcao-111196643652189.aws.databricksapps.com
- Pasta nova `rotaperfume-direcao/` na raiz do repo (irmã de `rotaperfume/`),
  AppKit 0.57, plugins `analytics,genie`.
- 4 queries em `config/queries/`: `kpis_semana.sql` (TRY_CAST(versao AS BIGINT)),
  `vendedores.sql`, `fila.sql` (param `vendedor`, 'Todos' não filtra, retorno
  mais recente), `acompanhamento.sql`.
- Tela **"A semana"** (`/`): 4 cartões, filtro de vendedor, tabela da fila com
  badge de retorno. Tela **"Perguntar"** (`/perguntar`): GenieChat,
  `/api/quem-sou` (header `x-forwarded-email`), aviso permanente de IA.
- Lint e typecheck limpos. Deploy verde (target `default`, `apps deploy`).
- Queries testadas contra o warehouse: 200 contatos, 35 vendedores,
  R$ 573.290,39 esperados, lift 3,80x, 77 acertos, taxa base 10,1%, retornos 0.

### Prompt 3 — POST /api/retorno + aba Acompanhamento ✅ (29/08)

- **`server/server.ts`**: `cache: { enabled: false }` no createApp; POST
  `/api/retorno` com Zod antes do warehouse (`z.coerce.number()` no
  `cliente_id`, enum nos 4 status, `comentario` ≤500 opcional, `referencia`
  regex aaaa-mm-dd; 400 sem tocar no banco). INSERT com parâmetros nomeados
  (`:nome`) via `getExecutionContext().client.statementExecution.executeStatement`
  — `warehouseId` vem de `ctx.warehouseId` (Promise, precisa de await + guarda).
  `registrado_por` do header `x-forwarded-email` (fallback `dev@local`);
  `registrado_em` de `current_timestamp()`. GET `/api/quem-sou` mantido.
  **Nenhum endpoint de leitura criado.**
- **`client/src/pages/semana/`**: virou pai (`SemanaPage`: filtro, comentários
  por cliente_id, contador `recarga`) + filho (`SemanaConteudo`: queries e
  tabela, remontado por `key={recarga}` a cada gravação — sem parâmetro falso
  no SQL). Coluna "Como foi a ligação": Badge + comentário se tem retorno;
  Input curto + 4 botões desabilitando durante a gravação se não tem; Alert
  pt-br por linha em caso de falha.
- **Aba nova** `/acompanhamento`: frase no topo (trabalhados × vendeu),
  `BarChart` appkit-ui em modo query (`queryKey="acompanhamento"`,
  xKey vendedor, yKey [trabalhados, vendeu]), tabela de desfecho, Empty
  amigável enquanto zero retornos. Nav atualizada em `App.tsx`.
- **GRANT MODIFY ON TABLE** `gold.retorno_ligacao` ao SP — confirmado via
  `SHOW GRANTS ON TABLE` (MODIFY em TABLE; SELECT em SCHEMA já existia).
- **Smoke local (porta 8000, tsx direto)**: 400 em corpo inválido sem tocar
  no warehouse; POST válido gravou (cliente 2685, `dev@local`); DELETE deixou
  a tabela em 0 linhas. Detalhe Windows: `npm run dev` falha com `'NODE_ENV'
  não é reconhecido` — rodar `tsx.cmd watch` direto com `$env:NODE_ENV` setado.
- **Deploy verde**: validate (typegen+lint+tsc+build+test) e
  `apps deploy -t default --profile Emerson`; app RUNNING/ACTIVE.
  Lint e typecheck limpos antes do deploy.

## Ids e valores do ambiente (verificados, não copiar de outro lugar)

| Item | Valor |
|---|---|
| Profile CLI (único válido) | `Emerson` — os prompts dizem `projeto-dados-ia`; **sempre substituir** |
| Warehouse | `2c807bf97ff3fec4` (Serverless Starter; o `666be37e...` do prompt 2 não existe) |
| Genie space Direção | `01f1a28f15a71c06afb18010a393eae6` |
| Service principal do app | `b0efe647-b997-4fad-a049-2a3f4754fc5e` (USE CATALOG, USE SCHEMA, SELECT na gold + MODIFY em `gold.retorno_ligacao`) |
| Nome do app | `rotaperfume-direcao` |

## Imprevistos já resolvidos (podem reaparecer)

1. Genie space valida as tabelas-fonte na criação — criar/ter a tabela antes do deploy.
2. CHECK em Delta: não vai inline no CREATE nem via `ALTER COLUMN SET CHECK`;
   é `ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)` (com DROP IF EXISTS antes).
3. `bash scripts/rodar-tarefa.sh` não acha o `databricks` (PATH do Git Bash);
   rodar o comando equivalente direto no PowerShell.
4. `npm run typegen` não carrega o `.env`: exportar
   `DATABRICKS_CONFIG_PROFILE=Emerson` no shell antes (ou `--wait` falha).
5. O `prebuild` do app roda typegen **como o service principal** — sem GRANT o
   deploy falha no build. Se um novo deploy falhar com INSUFFICIENT_PERMISSIONS,
   conferir os GRANTs do SP.
6. Statement Execution API executa UMA instrução por chamada (dividir o SQL
   nos `;`). Scripts python usados estão em `C:\Users\emers\AppData\Local\Temp\opencode\`.
7. `npm run dev` do app **quebra no Windows** (`'NODE_ENV' não é reconhecido`):
   o script usa sintaxe POSIX. Para dev local, rodar direto
   `node_modules\.bin\tsx.cmd watch --tsconfig ./tsconfig.server.json
   --env-file-if-exists=./.env ./server/server.ts` com `$env:NODE_ENV='development'`.
8. `appkit` **não exporta `getWarehouseId`** (só `getExecutionContext`); o
   warehouse é `ctx.warehouseId` — uma `Promise<string> | undefined`, pede
   guarda + await.

## O que falta

**Nada — os 3 prompts da noite 4 estão completos e no ar.**

## Estado do Git (nada commitado ainda)

- Modificado: `rotaperfume/resources/pipeline.job.yml`
- Novos: `rotaperfume/src/gold/11-retorno-ligacao.sql`,
  `rotaperfume/resources/genie-direcao.genie_space.yml`,
  `rotaperfume/resources/direcao.geniespace.json`,
  `rotaperfume-direcao/` (o `.gitignore` do app já cobre node_modules e .env)
- Dentro de `rotaperfume-direcao/`, o prompt 3 tocou: `server/server.ts`,
  `client/src/App.tsx`, `client/src/pages/semana/SemanaPage.tsx` (virou pai);
  novos `client/src/pages/semana/SemanaConteudo.tsx` e
  `client/src/pages/acompanhamento/AcompanhamentoPage.tsx`.
- `.llm/` com os 4 arquivos de contexto
