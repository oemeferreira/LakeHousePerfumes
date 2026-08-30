// ATENÇÃO: o warehouse devolve número como STRING no JSON, mesmo que o tipo
// gerado diga `number`. Todo valor passa por Number() antes de formatar ou
// somar — sem isso "7" + "12" vira "712" e toLocaleString devolve a string.

export function toNumber(valor: unknown): number {
  const n = Number(valor);
  return Number.isFinite(n) ? n : 0;
}

export function formatBRL(valor: unknown): string {
  return toNumber(valor).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}

// score vem em 0–1; vira porcentagem inteira. Ninguém decide ligação lendo
// 0.9740085224443632.
export function formatPct(valor: unknown, casas = 0): string {
  return `${(toNumber(valor) * 100).toLocaleString('pt-BR', {
    maximumFractionDigits: casas,
  })}%`;
}
