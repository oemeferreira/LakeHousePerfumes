import { useMemo, useState } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  Input,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { sql } from '@databricks/appkit-ui/js';
import { PhoneOff } from 'lucide-react';
import { formatBRL, formatPct, toNumber } from '../../lib/format';

// LABEL mostrado na tela ↔ VALOR do enum no banco. O CHECK em
// gold.retorno_ligacao rejeita qualquer valor fora da lista — e é o rótulo
// interno (snake_case) que fica no dado de treino da semana que vem.
const rotuloStatus: Record<string, string> = {
  vendeu: 'Vendeu',
  vai_pensar: 'Vai pensar',
  sem_interesse: 'Sem interesse',
  nao_atendeu: 'Não atendeu',
};

const STATUS = ['vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu'] as const;

type LinhaFila = Record<string, unknown>;

function KpiCard({
  titulo,
  valor,
  subtitulo,
  carregando,
}: {
  titulo: string;
  valor: string;
  subtitulo: string;
  carregando: boolean;
}) {
  return (
    <Card className="shadow-lg">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">{titulo}</CardTitle>
      </CardHeader>
      <CardContent>
        {carregando ? (
          <Skeleton className="h-8 w-24" />
        ) : (
          <div className="text-2xl font-bold text-primary">{valor}</div>
        )}
        <p className="mt-1 text-xs text-muted-foreground">{subtitulo}</p>
      </CardContent>
    </Card>
  );
}

// A célula de "Como foi a ligação": Badge + comentário para quem já tem
// retorno; quatro botões + campo curto para quem ainda não. Erro nunca é
// engolido: um Alert em português aparece na própria linha da tabela.
function RetornoCell({
  clienteId,
  retornoStatus,
  retornoComentario,
  comentarioLocal,
  salvando,
  onSalvar,
  onMudaComentario,
  erro,
  onLimpaErro,
}: {
  clienteId: string;
  retornoStatus: string | null;
  retornoComentario: string | null;
  comentarioLocal: string | undefined;
  salvando: boolean;
  onSalvar: (status: string) => void;
  onMudaComentario: (texto: string) => void;
  erro: string | null;
  onLimpaErro: () => void;
}) {
  if (retornoStatus) {
    return (
      <div className="space-y-1 min-w-56">
        <Badge variant="secondary">{rotuloStatus[retornoStatus] ?? retornoStatus}</Badge>
        {retornoComentario ? (
          <p className="text-xs text-muted-foreground">{retornoComentario}</p>
        ) : null}
      </div>
    );
  }
  return (
    <div className="min-w-64 space-y-2">
      {erro ? (
        <Alert variant="destructive" className="py-1">
          <AlertDescription className="text-xs">{erro}</AlertDescription>
          <button
            className="text-xs underline ml-2"
            onClick={onLimpaErro}
            type="button"
          >
            dispensar
          </button>
        </Alert>
      ) : null}
      <Input
        className="h-8 text-xs"
        maxLength={500}
        placeholder="Comentário (opcional)"
        value={comentarioLocal ?? ''}
        onChange={(e) => onMudaComentario(e.target.value)}
        disabled={salvando}
        onKeyDown={(e) => e.stopPropagation()}
      />
      <div className="flex flex-wrap gap-1">
        {STATUS.map((s) => (
            <Button
              key={`${clienteId}-${s}`}
              size="sm"
              variant="secondary"
              className="h-7 px-2 text-xs"
              disabled={salvando}
              onClick={() => onSalvar(s)}
            >
              {rotuloStatus[s]}
            </Button>
          ))}
      </div>
    </div>
  );
}

export function SemanaConteudo({
  vendedor,
  comentarios,
  onMudaComentario,
  onGravado,
}: {
  vendedor: string;
  comentarios: Record<string, string>;
  onMudaComentario: (clienteId: string, texto: string) => void;
  onGravado: () => void;
}) {
  const [salvandoId, setSalvandoId] = useState<string | null>(null);
  const [erroRetorno, setErroRetorno] = useState<Record<string, string | null>>({});

  const kpis = useAnalyticsQuery('kpis_semana');
  const fila = useAnalyticsQuery('fila', {
    vendedor: sql.string(vendedor),
  });

  // CAST(MAX(_gerado_em) AS STRING) devolve 'aaaa-mm-ddTHH:…'. Só os 10
  // primeiros caracteres interessam como 'referencia' da fila.
  const referencia = useMemo(() => {
    const k = kpis.data?.[0];
    const raw = typeof k?.referencia_fila === 'string' ? k.referencia_fila : '';
    return raw.slice(0, 10) || '1970-01-01';
  }, [kpis.data]);

  function marcaErro(clienteId: string, msg: string | null) {
    setErroRetorno((prev) => ({ ...prev, [clienteId]: msg }));
  }

  async function gravar(linha: LinhaFila, status: string) {
    const clienteId =
      typeof linha?.cliente_id === 'string' || typeof linha?.cliente_id === 'number'
        ? String(linha.cliente_id)
        : '';
    const vendedorDaLinha =
      typeof linha?.vendedor === 'string' ? linha.vendedor : '';
    const comentario = (comentarios[clienteId] || '').trim() || undefined;
    setSalvandoId(clienteId);
    try {
      const res = await fetch('/api/retorno', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          cliente_id: clienteId,
          vendedor: vendedorDaLinha,
          status,
          comentario,
          referencia,
        }),
      });
      const body = (await res.json().catch(() => ({}))) as { erro?: string };
      if (!res.ok) {
        marcaErro(clienteId, body.erro || `HTTP ${res.status}`);
        return;
      }
      marcaErro(clienteId, null);
      onMudaComentario(clienteId, '');
      onGravado();
    } catch (e: unknown) {
      marcaErro(clienteId, e instanceof Error ? e.message : String(e));
    } finally {
      setSalvandoId(null);
    }
  }

  const k = kpis.data?.[0] as Record<string, unknown> | undefined;
  const contatos = toNumber(k?.contatos);
  const acertos = toNumber(k?.acertos_top200);
  const conversaoPrevista = contatos > 0 ? acertos / contatos : 0;

  const linhasFila = fila.data ?? [];

  return (
    <>
      {kpis.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível carregar os números da semana</AlertTitle>
          <AlertDescription>{String(kpis.error)}</AlertDescription>
        </Alert>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <KpiCard
          titulo="Contatos da semana"
          valor={contatos.toLocaleString('pt-BR')}
          subtitulo={`para ${toNumber(k?.vendedores)} vendedores`}
          carregando={kpis.loading}
        />
        <KpiCard
          titulo="Receita esperada"
          valor={formatBRL(k?.receita_esperada)}
          subtitulo="estimativa: score × ticket médio — não é receita realizada"
          carregando={kpis.loading}
        />
        <KpiCard
          titulo="Conversão prevista"
          valor={formatPct(conversaoPrevista)}
          subtitulo={`taxa base do modelo: ${formatPct(k?.taxa_base, 1)}`}
          carregando={kpis.loading}
        />
        <KpiCard
          titulo="Já trabalhados"
          valor={toNumber(k?.retornos_registrados).toLocaleString('pt-BR')}
          subtitulo={`${toNumber(k?.retornos_vendeu)} viraram pedido`}
          carregando={kpis.loading}
        />
      </div>

      {fila.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível carregar a fila</AlertTitle>
          <AlertDescription>{String(fila.error)}</AlertDescription>
        </Alert>
      )}

      {fila.loading && (
        <Card className="shadow-lg">
          <CardContent className="space-y-2 pt-6">
            {Array.from({ length: 8 }, (_, i) => (
              <Skeleton key={i} className="h-6 w-full" />
            ))}
          </CardContent>
        </Card>
      )}

      {!fila.loading && !fila.error && linhasFila.length === 0 && (
        <Empty className="border rounded-lg">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <PhoneOff />
            </EmptyMedia>
            <EmptyTitle>Nenhum contato nesta seleção</EmptyTitle>
            <EmptyDescription>
              {vendedor === 'Todos'
                ? 'A fila desta semana ainda não foi gerada. Ela nasce do pipeline, com os 200 clientes mais propensos.'
                : `${vendedor} não tem contatos na fila desta semana. A fila é global — vendedores com carteira quente recebem mais contatos, e alguns recebem menos.`}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {!fila.loading && !fila.error && linhasFila.length > 0 && (
        <Card className="shadow-lg">
          <CardHeader>
            <CardTitle>
              Fila da semana{' '}
              <span className="text-sm font-normal text-muted-foreground">
                ({vendedor === 'Todos' ? 'todos os vendedores' : vendedor})
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-16">#</TableHead>
                    <TableHead>Cliente</TableHead>
                    <TableHead>Vendedor</TableHead>
                    <TableHead className="text-right">Chance</TableHead>
                    <TableHead>Motivo</TableHead>
                    <TableHead>Sugestão</TableHead>
                    <TableHead>Como foi a ligação</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {linhasFila.map((cLinha: LinhaFila) => {
                    const clienteId = String(cLinha.cliente_id);
                    return (
                      <TableRow key={clienteId}>
                        <TableCell className="font-medium">{toNumber(cLinha.ordem_geral)}</TableCell>
                        <TableCell>
                          <div className="font-medium">{cLinha.razao_social as string}</div>
                          <div className="text-xs text-muted-foreground">
                            {cLinha.cidade_uf as string} · ticket {formatBRL(cLinha.ticket_medio)}
                          </div>
                        </TableCell>
                        <TableCell>{cLinha.vendedor as string}</TableCell>
                        <TableCell className="text-right font-semibold">
                          {formatPct(cLinha.score)}
                          <div className="text-xs font-normal text-muted-foreground">{cLinha.faixa as string}</div>
                        </TableCell>
                        <TableCell className="max-w-72 text-sm text-muted-foreground">
                          {cLinha.motivo as string}
                        </TableCell>
                        <TableCell className="max-w-72 text-sm text-muted-foreground">
                          {cLinha.sugestao as string}
                        </TableCell>
                        <TableCell>
                          <RetornoCell
                            clienteId={clienteId}
                            retornoStatus={(cLinha.retorno_status as string | null) ?? null}
                            retornoComentario={(cLinha.retorno_comentario as string | null) ?? null}
                            comentarioLocal={comentarios[clienteId]}
                            salvando={salvandoId !== null}
                            erro={erroRetorno[clienteId] ?? null}
                            // eslint-disable-next-line @typescript-eslint/no-misused-promises
                            onSalvar={(s) => gravar(cLinha, s)}
                            onMudaComentario={(t) => onMudaComentario(clienteId, t)}
                            onLimpaErro={() => marcaErro(clienteId, null)}
                          />
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}
    </>
  );
}
