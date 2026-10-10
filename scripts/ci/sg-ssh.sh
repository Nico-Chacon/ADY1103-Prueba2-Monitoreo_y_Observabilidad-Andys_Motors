#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Abre / cierra el puerto 22 de uno o varios Security Groups SOLO para la IP del
# runner de GitHub Actions, para poder entrar por SSH con labsuser.pem.
#
# El runner tiene una IP distinta en cada ejecucion, por eso no se puede dejar
# fija en Terraform. La regla es temporal: se abre al principio y se cierra
# siempre al final (paso con "if: always()").
#
# Uso:  sg-ssh.sh abrir|cerrar <nombre-del-sg> [<nombre-del-sg> ...]
# ---------------------------------------------------------------------------
set -uo pipefail

ACCION="${1:?Falta la accion: abrir | cerrar}"
shift
[[ $# -ge 1 ]] || { echo "Falta al menos un nombre de Security Group" >&2; exit 1; }

IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
[[ -n "$IP" ]] || { echo "No se pudo obtener la IP del runner" >&2; exit 1; }
CIDR="$IP/32"
echo "IP del runner: $CIDR"

for NOMBRE in "$@"; do
  SG="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NOMBRE" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  if [[ -z "$SG" || "$SG" == "None" ]]; then
    echo "AVISO: no existe el Security Group '$NOMBRE' (se omite)."
    continue
  fi
  case "$ACCION" in
    abrir)
      aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 \
        --cidr "$CIDR" >/dev/null 2>&1 \
        && echo "SSH abierto en $NOMBRE ($SG) para $CIDR" \
        || echo "SSH ya estaba abierto en $NOMBRE para $CIDR (o la regla ya existia)"
      ;;
    cerrar)
      aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port 22 \
        --cidr "$CIDR" >/dev/null 2>&1 \
        && echo "SSH cerrado en $NOMBRE ($SG) para $CIDR" \
        || echo "Nada que cerrar en $NOMBRE para $CIDR"
      ;;
    *) echo "Accion invalida: $ACCION" >&2; exit 1 ;;
  esac
done
