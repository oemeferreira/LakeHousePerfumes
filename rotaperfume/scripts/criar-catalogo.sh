#!/usr/bin/env bash
set -euo pipefail

# Cria o catalogo lakehouse_rotaperfume via SQL -- de proposito FORA do
# bundle (nao como resources.catalogs no databricks.yml).
#
# POR QUE NAO ESTA NO BUNDLE: quando o workspace tem o Default Storage
# habilitado (comum em contas Free Edition), a API do Unity Catalog usada
# pelo provider Terraform do bundle RECUSA criar catalogo -- ela exige um
# MANAGED LOCATION que essas contas nao tem, e falha com:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL abaixo nao passa por essa restricao.

if [ $# -lt 1 ]; then
  echo "uso: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
CATALOG="lakehouse_rotaperfume"       # mesmo default de var.catalog em databricks.yml
WAREHOUSE_ID="2c807bf97ff3fec4"       # mesmo default de var.warehouse_id em databricks.yml

databricks experimental aitools tools query \
  "CREATE CATALOG IF NOT EXISTS ${CATALOG}" \
  --warehouse "$WAREHOUSE_ID" \
  --profile "$PROFILE"
