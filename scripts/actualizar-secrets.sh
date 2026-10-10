#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Carga los secrets del repositorio con la GitHub CLI (gh), sin copiar y pegar
# en la web. Pensado para el Learner Lab: las credenciales de AWS CAMBIAN en cada
# sesion, asi que este script se corre cada vez que inicias el laboratorio.
#
# Requisitos: gh instalado y autenticado (gh auth login), dentro del repo clonado.
#
# Uso:
#   # Cada sesion del lab: solo credenciales AWS (pega el bloque de AWS Details
#   # > AWS CLI en un archivo .aws-credentials, que esta en .gitignore)
#   ./scripts/actualizar-secrets.sh
#   ./scripts/actualizar-secrets.sh ruta/a/credenciales
#
#   # Primera vez: ademas carga labsuser.pem, tu IP, y las claves de la BD y Grafana
#   ./scripts/actualizar-secrets.sh --inicial [ruta/a/labsuser.pem]
# ---------------------------------------------------------------------------
set -euo pipefail

command -v gh >/dev/null || { echo "ERROR: instala la GitHub CLI (https://cli.github.com) y corre 'gh auth login'." >&2; exit 1; }

INICIAL=0
if [[ "${1:-}" == "--inicial" ]]; then INICIAL=1; shift; fi

# --- 1. Credenciales temporales de AWS (siempre) ------------------------------
if [[ $INICIAL -eq 1 ]]; then CREDS="${CREDS_FILE:-.aws-credentials}"; PEM="${1:-labsuser.pem}"
else CREDS="${1:-.aws-credentials}"; PEM=""; fi

[[ -f "$CREDS" ]] || { echo "ERROR: no existe $CREDS. Copia ahi el bloque de AWS Details > AWS CLI." >&2; exit 1; }

valor() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$CREDS" | head -1 | cut -d= -f2- | tr -d '[:space:]'; }
KEY="$(valor aws_access_key_id)"; SECRET="$(valor aws_secret_access_key)"; TOKEN="$(valor aws_session_token)"
[[ -n "$KEY" && -n "$SECRET" && -n "$TOKEN" ]] || { echo "ERROR: faltan campos en $CREDS (se necesitan los 3)." >&2; exit 1; }

printf '%s' "$KEY"    | gh secret set AWS_ACCESS_KEY_ID
printf '%s' "$SECRET" | gh secret set AWS_SECRET_ACCESS_KEY
printf '%s' "$TOKEN"  | gh secret set AWS_SESSION_TOKEN
echo "OK: credenciales AWS actualizadas."

# --- 2. Secrets de una sola vez (solo con --inicial) -------------------------
if [[ $INICIAL -eq 1 ]]; then
  [[ -f "$PEM" ]] || { echo "ERROR: no encuentro $PEM (descargalo en AWS Details > Download PEM)." >&2; exit 1; }
  gh secret set LABSUSER_PEM < "$PEM"
  echo "OK: LABSUSER_PEM cargado desde $PEM."

  MI_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
  read -r -p "Tu IP publica es $MI_IP. Usar $MI_IP/32 como ADMIN_CIDR? [S/n] " R
  if [[ "${R:-S}" =~ ^[sSyY]?$ ]]; then CIDR="$MI_IP/32"; else read -r -p "ADMIN_CIDR (ej. 200.1.2.3/32): " CIDR; fi
  printf '%s' "$CIDR" | gh secret set ADMIN_CIDR

  echo "Claves (12 a 41 caracteres; solo letras, numeros, _ . ~ -)."
  read -r -s -p "DB_PASSWORD: " P1; echo; printf '%s' "$P1" | gh secret set DB_PASSWORD
  read -r -s -p "GRAFANA_ADMIN_PASSWORD: " P2; echo; printf '%s' "$P2" | gh secret set GRAFANA_ADMIN_PASSWORD
  echo "OK: secrets iniciales cargados."
fi

gh secret list
