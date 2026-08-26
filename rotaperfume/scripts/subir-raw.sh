#!/usr/bin/env bash
set -euo pipefail

# Sobe dados/erp e dados/crm (raiz do repositorio) para o Volume de raw.
# databricks fs cp exige o esquema 'dbfs:' no destino, mesmo sendo um
# Volume do Unity Catalog (nao um path de DBFS classico).

if [ $# -lt 1 ]; then
  echo "uso: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
CATALOG="lakehouse_rotaperfume"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DADOS_DIR="$SCRIPT_DIR/../../dados"

if [ ! -d "$DADOS_DIR" ]; then
  echo "erro: $DADOS_DIR nao existe (esperado dados/erp e dados/crm na raiz do repo)" >&2
  exit 1
fi

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/erp" "dbfs:/Volumes/${CATALOG}/bronze/raw/erp" \
  --profile "$PROFILE"

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/crm" "dbfs:/Volumes/${CATALOG}/bronze/raw/crm" \
  --profile "$PROFILE"
