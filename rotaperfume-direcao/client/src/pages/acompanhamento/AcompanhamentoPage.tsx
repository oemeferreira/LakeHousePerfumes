import { useMemo } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  BarChart,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { ChartLine } from 'lucide-react';
import { toNumber } from '../../lib/format';

type Linha = {
  vendedor: string;
  na_fila: number;
  trabalhados: number;
  vendeu: number;
  vai_pensar: number;
  sem_interesse: number;
  nao_atendeu: number;
};

function parseLinha(l: unknown): Linha {
  const d = l as Record<string, unknown>;
  return {
    vendedor: typeof d?.vendedor === 'string' ? d.vendedor : 'desconhecido',
    na_fila: toNumber(d?.na_fila),
    trabalhados: toNumber(d?.trabalhados),
    vendeu: toNumber(d?.vendeu),
    vai_pensar: toNumber(d?.vai_pensar),
    sem_interesse: toNumber(d?.sem_interesse),
    nao_atendeu: toNumber(d?.nao_atendeu),
  };
}

export function AcompanhamentoPage() {
  const a = useAnalyticsQuery('acompanhamento');

  const { linhas, trabalhados, vendeu } = useMemo(() => {
    const parsed = (a.data ?? []).map(parseLinha);
    let t = 0;
    let v = 0;
    for (const l of parsed) {
      t += l.trabalhados;
      v += l.vendeu;
    }
    return { linhas: parsed, trabalhados: t, vendeu: v };
  }, [a.data]);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Acompanhamento</h2>
        <p className="text-sm text-muted-foreground mt-1">
          O desfecho da fila da semana, por vendedor. Enquanto ninguém marcou retorno, zero não
          é erro — é o time ainda trabalhando.
        </p>
      </div>

      {a.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível carregar o acompanhamento</AlertTitle>
          <AlertDescription>{String(a.error)}</AlertDescription>
        </Alert>
      )}

      {a.loading && (
        <div className="space-y-2">
          <Skeleton className="h-4 w-64" />
          <Skeleton className="h-64 w-full" />
        </div>
      )}

      {!a.loading && !a.error && (
        <>
          {trabalhados === 0 ? (
            <Empty className="border rounded-lg">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <ChartLine />
                </EmptyMedia>
                <EmptyTitle>Ninguém marcou retorno ainda</EmptyTitle>
                <EmptyDescription>
                  O número aparece assim que o time marcar o retorno — e isso vira dado de
                  treino da semana que vem.
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <>
              <p className="text-sm text-foreground">
                <span className="font-semibold">{trabalhados.toLocaleString('pt-BR')}</span>{' '}
                dos 200 contatos trabalhados ·{' '}
                <span className="font-semibold">{vendeu.toLocaleString('pt-BR')}</span>{' '}
                viraram pedido.
              </p>

              <Card className="shadow-lg">
                <CardHeader>
                  <CardTitle>
                    Retorno por vendedor{' '}
                    <span className="text-sm font-normal text-muted-foreground">
                      (trabalhados × vendeu)
                    </span>
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <BarChart
                    queryKey="acompanhamento"
                    xKey="vendedor"
                    yKey={['trabalhados', 'vendeu']}
                    height={320}
                    showLegend
                  />
                </CardContent>
              </Card>

              <Card className="shadow-lg">
                <CardHeader>
                  <CardTitle>Desfecho por vendedor</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Vendedor</TableHead>
                          <TableHead className="text-right">Na fila</TableHead>
                          <TableHead className="text-right">Trabalhados</TableHead>
                          <TableHead className="text-right">Vendeu</TableHead>
                          <TableHead className="text-right">Vai pensar</TableHead>
                          <TableHead className="text-right">Sem interesse</TableHead>
                          <TableHead className="text-right">Não atendeu</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {linhas.map((l) => (
                          <TableRow key={l.vendedor}>
                            <TableCell className="font-medium">{l.vendedor}</TableCell>
                            <TableCell className="text-right">{l.na_fila.toLocaleString('pt-BR')}</TableCell>
                            <TableCell className="text-right font-semibold">{l.trabalhados.toLocaleString('pt-BR')}</TableCell>
                            <TableCell className="text-right">{l.vendeu.toLocaleString('pt-BR')}</TableCell>
                            <TableCell className="text-right">{l.vai_pensar.toLocaleString('pt-BR')}</TableCell>
                            <TableCell className="text-right">{l.sem_interesse.toLocaleString('pt-BR')}</TableCell>
                            <TableCell className="text-right">{l.nao_atendeu.toLocaleString('pt-BR')}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>
            </>
          )}
        </>
      )}
    </div>
  );
}
