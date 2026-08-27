#!/usr/bin/env bash
# rotaperfume/scripts/rodar-tarefa.sh
# Executa uma tarefa especifica do job rotaperfume_pipeline
# Uso: bash scripts/rodar-tarefa.sh <perfil> <task_key>
# Exemplo: bash scripts/rodar-tarefa.sh Emerson ml_modelo

set -euo pipefail

PERFIL="${1:-Emerson}"
TASK_KEY="${2:-ml_modelo}"

echo "🚀 Disparando tarefa '${TASK_KEY}' no profile '${PERFIL}'..."
databricks bundle run rotaperfume_pipeline \
  --only "${TASK_KEY}" \
  --target dev \
  --profile "${PERFIL}"
