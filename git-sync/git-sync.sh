#!/bin/bash

# ╔══════════════════════════════════════════════════════════╗
# ║  git-sync.sh — Sincroniza repositorio com GitHub        ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

V='\033[0;32m'  A='\033[0;34m'  AM='\033[1;33m'
VM='\033[0;31m'  M='\033[0;35m'  R='\033[0m'

_REPO_DIR="${1:-.}"

if ! cd "$_REPO_DIR" 2>/dev/null; then
    echo -e "${VM}Erro: diretorio '$_REPO_DIR' nao existe.${R}"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo -e "${VM}Erro: nao e um repositorio git.${R}"
    exit 1
fi

_branch=$(git branch --show-current 2>/dev/null || echo "main")
_changes=$(git status --porcelain)

echo -e "${M}═══ git-sync ═══${R}"
echo -e "${A}Branch: ${R}$_branch"

if [ -z "$_changes" ]; then
    echo -e "${AM}Nada para sincronizar.${R}"
    exit 0
fi

echo -e "${A}Mudancas:${R}"
echo "$_changes"
echo ""

echo -ne "${A}Mensagem do commit${R} [Atualizacao]: "
read -r _msg
_msg="${_msg:-Atualizacao}"

echo -e "\n${A}git add -A${R}"
git add -A

echo -e "${A}git commit -m \"$_msg\"${R}"
git commit -m "$_msg"

echo -e "${A}git pull origin $_branch${R}"
git pull origin "$_branch" 2>/dev/null || true

echo -e "${A}git push origin $_branch${R}"
if git push origin "$_branch"; then
    echo -e "\n${V}✔ Sincronizado com sucesso!${R}"
else
    echo -e "\n${VM}✘ Falha no push. Verifique o token/remote.${R}"
    exit 1
fi
