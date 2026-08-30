import { createApp, analytics, genie, server, getExecutionContext } from '@databricks/appkit';
import { z } from 'zod';

createApp({
  plugins: [analytics(), genie(), server()],
  // A tela manda 200 linhas que mudam a cada clique do vendedor. Cache de
  // leitura só serviria para mentir: depois de gravar o retorno, a tela
  // precisa ler de novo e ver o que acabou de mudar.
  cache: { enabled: false },
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // Quem está logado. Em produção o Databricks injeta o e-mail do usuário
      // no header x-forwarded-email; em desenvolvimento local não existe
      // header, então devolvemos um valor de reserva para a tela não quebrar.
      app.get('/api/quem-sou', (req, res) => {
        const raw = req.headers['x-forwarded-email'];
        const email = Array.isArray(raw) ? raw[0] : raw;
        res.json({ email: email || 'dev@local' });
      });

      // Contrato do corpo: o Zod valida ANTES de qualquer chamada ao
      // warehouse. Corpo inválido responde 400 e o banco nem fica sabendo.
      // cliente_id chega como STRING vindo do warehouse (mesmo tipado como
      // number), então z.coerce.number() normaliza antes de checar int > 0.
      const retornoSchema = z.object({
        cliente_id: z.coerce.number().int().positive(),
        vendedor: z.string().min(1),
        status: z.enum(['vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu']),
        comentario: z.string().max(500).optional(),
        // A semana da fila a que o retorno se refere, no formato aaaa-mm-dd.
        referencia: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      });

      // POST /api/retorno — a única rota que escreve no app. Leitura continua
      // nos arquivos .sql de config/queries/ (plug-in analytics); aqui só
      // entra o caminho de volta para a gold.
      app.post('/api/retorno', async (req, res) => {
        const parsed = retornoSchema.safeParse(req.body);
        if (!parsed.success) {
          return res.status(400).json({
            erro: 'Corpo inválido. Envie cliente_id, vendedor, status válido e referencia aaaa-mm-dd; comentario é opcional (até 500 caracteres).',
            detalhes: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`),
          });
        }
        const { cliente_id, vendedor, status, comentario, referencia } = parsed.data;

        // registrado_por sai do mesmo header do /quem-sou; fallback local é
        // 'dev@local', para desenvolvimento sem proxieda direção.
        const rawEmail = req.headers['x-forwarded-email'];
        const email = Array.isArray(rawEmail) ? rawEmail[0] : rawEmail;
        const registradoPor = email || 'dev@local';

        try {
          const ctx = getExecutionContext();
          const client = ctx.client;
          if (!ctx.warehouseId) {
            return res.status(500).json({
              erro: 'Warehouse não configurado no app (DATABRICKS_WAREHOUSE_ID ausente).',
            });
          }
          const warehouseId = await ctx.warehouseId;

          // Todo valor vai como parâmetro nomeado (:nome) — nunca concatenado
          // na string do SQL. current_timestamp() preenche registrado_em.
          const sql = `INSERT INTO lakehouse_rotaperfume.gold.retorno_ligacao
            (cliente_id, vendedor, status, comentario, registrado_em, registrado_por, _referencia)
          VALUES (:cliente_id, :vendedor, :status, :comentario, current_timestamp(), :registrado_por, :referencia)`;

          const resp = await client.statementExecution.executeStatement({
            warehouse_id: warehouseId,
            statement: sql,
            parameters: [
              { name: 'cliente_id', value: String(cliente_id), type: 'INT' },
              { name: 'vendedor', value: vendedor, type: 'STRING' },
              { name: 'status', value: status, type: 'STRING' },
              // value omitido (null) é aceito pela API — comentário é opcional
              { name: 'comentario', value: comentario, type: 'STRING' },
              { name: 'registrado_por', value: registradoPor, type: 'STRING' },
              { name: 'referencia', value: referencia, type: 'DATE' },
            ],
          });

          const state = resp?.status?.state;
          if (state !== 'SUCCEEDED') {
            const msg = resp?.status?.error?.message ?? `state=${state ?? 'desconhecido'}`;
            return res.status(500).json({ erro: `O warehouse não confirmou a gravação (${msg}).` });
          }

          return res.json({ ok: true });
        } catch (e: unknown) {
          const msg = e instanceof Error ? e.message : String(e);
          return res.status(500).json({ erro: `Falha ao gravar o retorno: ${msg}` });
        }
      });
    });
  },
}).catch(console.error);
