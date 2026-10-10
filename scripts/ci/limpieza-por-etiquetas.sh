#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Plan B del destroy: si el state de Terraform se perdio (artifact vencido o
# borrado), elimina los recursos del proyecto buscandolos por la etiqueta
# Proyecto=<project_name> que Terraform pone en todo (default_tags).
#
# Orden: instancias EC2 -> esperar -> Security Groups.
# ---------------------------------------------------------------------------
set -uo pipefail

PROYECTO="${PROJECT_NAME:-andys-motors}"
echo "== Limpieza por etiquetas: Proyecto=$PROYECTO =="

IDS="$(aws ec2 describe-instances \
  --filters "Name=tag:Proyecto,Values=$PROYECTO" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"

if [[ -n "$IDS" ]]; then
  echo "Terminando instancias: $IDS"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $IDS
  echo "Instancias terminadas."
else
  echo "No hay instancias con esa etiqueta."
fi

# Las bases RDS (si se encendio enable_rds) se borran sin snapshot final.
for DB in $(aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier, '$PROYECTO')].DBInstanceIdentifier" --output text 2>/dev/null); do
  echo "Eliminando RDS $DB"
  aws rds delete-db-instance --db-instance-identifier "$DB" --skip-final-snapshot >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$DB"
done

# Security Groups: se referencian entre si, asi que hay que reintentar hasta que
# se liberen las dependencias.
for INTENTO in 1 2 3 4 5; do
  SGS="$(aws ec2 describe-security-groups --filters "Name=tag:Proyecto,Values=$PROYECTO" \
         --query 'SecurityGroups[].GroupId' --output text)"
  [[ -z "$SGS" ]] && { echo "Sin Security Groups restantes."; break; }
  for SG in $SGS; do
    # Quita primero las reglas que referencian a otros grupos.
    aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" \
      --query 'SecurityGroupRules[?!IsEgress].SecurityGroupRuleId' --output text 2>/dev/null \
      | tr '\t' '\n' | while read -r REGLA; do
          [[ -n "$REGLA" ]] && aws ec2 revoke-security-group-ingress --group-id "$SG" \
            --security-group-rule-ids "$REGLA" >/dev/null 2>&1
        done
  done
  for SG in $SGS; do
    aws ec2 delete-security-group --group-id "$SG" >/dev/null 2>&1 \
      && echo "SG eliminado: $SG" || echo "SG $SG aun tiene dependencias (intento $INTENTO)"
  done
  sleep 10
done
echo "== Limpieza terminada. Revisa la consola de EC2 para confirmar. =="
