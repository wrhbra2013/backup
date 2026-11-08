#!/bin/bash
# update-docs.sh — Regenera a documentacao e opcionalmente faz commit
# Uso: ./update-docs.sh [--commit]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Verificando Python..."
if ! command -v python3 &>/dev/null; then
  echo "ERRO: python3 nao encontrado"
  exit 1
fi

echo "==> Escaneando scripts .sh no repositorio..."
SH_COUNT=$(find . -name "*.sh" -not -path "./.git/*" -not -path "./docs/*" | wc -l)
echo "    Encontrados: $SH_COUNT scripts"

echo "==> Gerando documentacao..."
python3 generate-docs.py

echo "==> Verificando alteracoes no git..."
if git diff --quiet docs/ 2>/dev/null; then
  echo "    Nenhuma alteracao detectada na pasta docs/"
else
  CHANGED=$(git diff --stat docs/ | tail -1)
  echo "    Alteracoes: $CHANGED"
fi

if [[ "${1:-}" == "--commit" ]]; then
  echo "==> Fazendo commit das alteracoes..."
  git add docs/
  git commit -m "docs: auto-update — $SH_COUNT scripts documentados" --no-verify
  echo "==> Commit realizado com sucesso!"
  echo "    Para enviar ao remote: git push"
else
  echo ""
  echo "==> Pronto! Para commitar as alteracoes, rode:"
  echo "    ./update-docs.sh --commit"
fi

echo ""
echo "==> Abrindo docs/index.html..."
if command -v xdg-open &>/dev/null; then
  xdg-open "$SCRIPT_DIR/docs/index.html" 2>/dev/null &
elif command -v open &>/dev/null; then
  open "$SCRIPT_DIR/docs/index.html" 2>/dev/null &
fi
