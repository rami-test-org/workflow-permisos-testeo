#!/bin/bash
set -euo pipefail

ORG="rami-test-org"

echo "Asignación de permisos en GitHub"

: "${GITHUB_TOKEN:?❌ Falta GITHUB_TOKEN}"
: "${TEAM:?❌ Falta TEAM}"
: "${PERMISSION:?❌ Falta PERMISSION}"
: "${REPOS:?❌ Falta REPOS}"

case "$PERMISSION" in
  pull|push|admin) ;;
  *) echo "❌ PERMISSION inválido (usar: pull | push | admin)"; exit 1 ;;
esac

echo "-----------------------------------"
echo "Team: $TEAM | Permiso solicitado: $PERMISSION"
echo "Repos: $REPOS"
echo "-----------------------------------"

# Teams con permiso para usar ADMIN
SPECIAL_TEAMS=("cybersec-team" "security-team", "test-team") # ajustar luego

if [[ "$PERMISSION" == "admin" ]]; then
  if [[ ! " ${SPECIAL_TEAMS[@]} " =~ " ${TEAM} " ]]; then
    echo "❌ El team '$TEAM' NO tiene permitido asignar permisos admin"
    exit 1
  fi
fi

# Validar que el TEAM exista
team_check=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/orgs/$ORG/teams/$TEAM")

[ "$team_check" -eq 200 ] || { echo "❌ Team no existe o sin acceso (HTTP $team_check)"; exit 1; }

# Convertir repos en array
IFS=',' read -ra REPO_LIST <<< "$REPOS"

for repo in "${REPO_LIST[@]}"; do
  repo="$(echo "$repo" | xargs)"
  [ -z "$repo" ] && { echo "❌ Formato inválido en lista de repositorios"; exit 1; }

  echo "-----------------------------------"
  echo "Repositorio: $repo"

  # Verificar repo
  code_repo=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$ORG/$repo")

  [ "$code_repo" -eq 200 ] || { echo "❌ Repo inválido o sin acceso: $repo (HTTP $code_repo)"; exit 1; }

  # NUEVO: Verificar relación team-repo (endpoint correcto)
  response=$(curl -s \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$ORG/$repo/teams")

  current_permission=$(echo "$response" | jq -r --arg TEAM "$TEAM" '
    .[] | select(.slug == $TEAM) | .permission
  ')

  if [ -z "$current_permission" ]; then
    echo "ℹ️ El team no está asociado al repo → se creará relación"
    current_permission="none"
  else
    echo "Permiso actual: $current_permission"
  fi

  # Lógica de decisión
  if [[ "$current_permission" == "$PERMISSION" ]]; then
    echo "✅ Ya tiene el permiso solicitado → No hay nada que aplicar."
    continue
  fi

  echo "➡️ Aplicando permiso: $PERMISSION"

  code_apply=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$ORG/teams/$TEAM/repos/$ORG/$repo" \
    -d "{\"permission\":\"$PERMISSION\"}")

  if [ "$code_apply" -eq 204 ]; then
    echo "✅ Permiso aplicado correctamente"

  elif [ "$code_apply" -eq 404 ]; then
    echo "❌ ERROR 404 en $repo"
    echo "   → Repo o team no existen"
    exit 1

  elif [ "$code_apply" -eq 403 ]; then
    echo "❌ ERROR 403 en $repo"
    echo "   → Token sin permisos suficientes"
    exit 1

  else
    echo "❌ ERROR inesperado (HTTP $code_apply)"
    exit 1
  fi

done

echo "-----------------------------------"
echo "Proceso finalizado"
