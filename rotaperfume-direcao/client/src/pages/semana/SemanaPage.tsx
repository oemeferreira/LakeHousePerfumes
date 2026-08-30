import { useEffect, useState } from 'react';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { SemanaConteudo } from './SemanaConteudo';

// Componente PAI: guarda o filtro de vendedor, os comentários em andamento
// (por cliente_id) e o contador de recarga. O filho é remontado a cada
// gravação, porque useAnalyticsQuery não tem refetch. Sem parâmetro falso no
// SQL (:recarga >= 0 quebra versões antigas com UNBOUND_SQL_PARAMETER).
export function SemanaPage() {
  const [vendedor, setVendedor] = useState('Todos');
  const [comentarios, setComentarios] = useState<Record<string, string>>({});
  const [recarga, setRecarga] = useState(0);

  // Lista de vendedores continua no pai — só para encher o Select do filtro.
  const vendedores = useAnalyticsQuery('vendedores');

  // Só rola para o topo quando muda o filtro — gravações de retorno não.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [vendedor]);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div className="flex flex-col md:flex-row md:items-end md:justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold text-foreground">A semana</h2>
          <p className="text-sm text-muted-foreground mt-1">
            A fila global dos 200 contatos mais propensos. Quem tem carteira quente recebe
            mais contatos — e isso está certo.
          </p>
        </div>
        <div className="w-full md:w-64">
          <Select value={vendedor} onValueChange={setVendedor}>
            <SelectTrigger aria-label="Filtrar por vendedor">
              <SelectValue placeholder="Vendedor" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="Todos">Todos os vendedores</SelectItem>
              {(vendedores.data ?? []).map((v) => (
                <SelectItem key={v.vendedor} value={v.vendedor}>
                  {v.vendedor}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <SemanaConteudo
        // A key muda a cada gravação e remonta o filho: as queries (kpis e
        // fila) refazem o SELECT e o Badge/comentário novo aparece na linha.
        key={recarga}
        vendedor={vendedor}
        comentarios={comentarios}
        onMudaComentario={(clienteId, texto) =>
          setComentarios((prev) => ({ ...prev, [clienteId]: texto }))
        }
        onGravado={() => setRecarga((r) => r + 1)}
      />
    </div>
  );
}
