import { useEffect, useState } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  GenieChat,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { Info } from 'lucide-react';

export function PerguntarPage() {
  const [email, setEmail] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let ativo = true;
    fetch('/api/quem-sou')
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json() as Promise<{ email?: string }>;
      })
      .then((d) => {
        if (ativo) setEmail(d.email || 'usuário desconhecido');
      })
      .catch((e: unknown) => {
        if (ativo) setErro(e instanceof Error ? e.message : String(e));
      });
    return () => {
      ativo = false;
    };
  }, []);

  return (
    <div className="space-y-6 w-full max-w-4xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Pergunte em português para o Genie da direção — sobre a fila, o modelo e o retorno
          das ligações.
        </p>
      </div>

      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>Resposta gerada por IA</AlertTitle>
        <AlertDescription>
          As respostas são geradas por IA (Databricks Genie) e cada resposta traz o SQL que a
          produziu. Confira o SQL antes de tomar decisão.
        </AlertDescription>
      </Alert>

      <div className="text-sm text-muted-foreground">
        Logado como:{' '}
        {erro ? (
          <span className="text-destructive">não foi possível identificar ({erro})</span>
        ) : email ? (
          <span className="font-medium text-foreground">{email}</span>
        ) : (
          <Skeleton className="inline-block h-4 w-48 align-middle" />
        )}
      </div>

      <div className="h-[min(600px,70vh)] border rounded-lg overflow-hidden">
        <GenieChat alias="default" />
      </div>
    </div>
  );
}
