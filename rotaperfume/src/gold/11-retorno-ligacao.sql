-- rotaperfume/src/gold/11-retorno-ligacao.sql
-- Gold · Prompt 1 da Noite 4: a tabela do caminho de volta
--
-- Todas as tabelas da gold até aqui nascem do pipeline: o job roda, a tabela
-- é recriada, o dado se recompõe. Esta é a ÚNICA exceção. Quem escreve aqui
-- é o time de vendas, pelo app da direção — uma linha por ligação feita.
--
-- Por isso o comando é CREATE TABLE IF NOT EXISTS e nunca CREATE OR REPLACE:
-- um redeploy do pipeline não pode apagar o que o vendedor registrou.
-- A tabela nasce VAZIA de propósito — ela é o destino do app, não da origem.
--
-- O CHECK na coluna status é o contrato do enum: se um valor fora da lista
-- chegar aqui ('Vendeu', 'vendido', 'ok'), o warehouse recusa na hora.
-- O app também valida (Zod), mas contrato em banco protege de qualquer
-- caminho que não seja o app. Em Delta, CHECK não vai inline no CREATE
-- (só PK/FK vão): é um ALTER TABLE com constraint de TABELA nomeada.
-- O DROP IF EXISTS antes do ADD torna o arquivo idempotente — ele roda a
-- cada execução do pipeline e nunca quebra por constraint já existente.

CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao (
  cliente_id     INT,
  vendedor       STRING,
  status         STRING,
  comentario     STRING,
  registrado_em  TIMESTAMP,
  registrado_por STRING,
  _referencia    DATE
);

-- Contrato do status: os quatro desfechos possíveis de uma ligação.
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao
  DROP CONSTRAINT IF EXISTS retorno_ligacao_status_valido;

ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao
  ADD CONSTRAINT retorno_ligacao_status_valido
    CHECK (status IN ('vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu'));

COMMENT ON TABLE lakehouse_rotaperfume.gold.retorno_ligacao IS
  'Responde: o que aconteceu depois da ligacao da fila semanal? Registro do vendedor para cada contato: vendeu, vai pensar, sem interesse ou nao atendeu. Comeca vazia e e preenchida pelo app da direcao.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.cliente_id IS
  'Identificador unico do cliente no CRM. Liga o retorno ao contato da gold.fila_semanal.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.vendedor IS
  'Nome do vendedor que fez a ligacao, como aparece na carteira.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.status IS
  'Desfecho da ligacao: vendeu, vai_pensar, sem_interesse ou nao_atendeu. Valores fora desse conjunto sao rejeitados por CHECK.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.comentario IS
  'Texto livre do vendedor sobre a ligacao (ate 500 caracteres no app). Pode ser vazio.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.registrado_em IS
  'Momento exato do registro, em current_timestamp(). Um cliente pode ter varios retornos: o mais recente e o estado atual.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao.registrado_por IS
  'E-mail de quem estava logado no app quando registrou o retorno.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.retorno_ligacao._referencia IS
  'A semana da fila a que o retorno se refere (mesma referencia da gold.fila_semanal), no formato aaaa-mm-dd.';
