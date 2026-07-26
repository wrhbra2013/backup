#!/bin/bash

# ╔══════════════════════════════════════════════════════════╗
# ║  git-sync.sh — Sincroniza repositorio com GitHub        ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

V='\033[0;32m'  A='\033[0;34m'  AM='\033[1;33m'
VM='\033[0;31m'  M='\033[0;35m'  R='\033[0m'  B='\033[1m'

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
_remote_url=$(git remote get-url origin 2>/dev/null || echo "")

echo -e "${M}═══ git-sync ═══${R}"
echo -e "${A}Branch:${R}  $_branch"
echo -e "${A}Remote:${R}  ${_remote_url:-nenhum}"

# ── Verificar token ──
_token="${GIT_SYNC_TOKEN:-}"
_token_file="$HOME/.git-sync-token"

# Tentar carregar token salvo
if [ -z "$_token" ] && [ -f "$_token_file" ]; then
    _token=$(cat "$_token_file" 2>/dev/null || echo "")
fi

# Se nao tem token, pedir
if [ -z "$_token" ]; then
    echo ""
    echo -e "${AM}  GitHub nao aceita mais senha. Necessario token.${R}"
    echo -e "${A}  Abrindo navegador para gerar token...${R}"
    echo -e "${A}  Permissoes: repo, read:org, workflow${R}"
    echo ""

    # Abrir navegador no link do token
    if command -v xdg-open &>/dev/null; then
        xdg-open "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    elif command -v sensible-browser &>/dev/null; then
        sensible-browser "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    elif command -v gnome-open &>/dev/null; then
        gnome-open "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    elif command -v firefox &>/dev/null; then
        firefox "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    elif command -v chromium-browser &>/dev/null; then
        chromium-browser "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    elif command -v google-chrome &>/dev/null; then
        google-chrome "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=git-sync" &
    fi

    echo -ne "${A}  Token GitHub:${R} "
    read -rs _token
    echo ""

    if [ -z "$_token" ]; then
        echo -e "${VM}  Token vazio. Abortado.${R}"
        exit 1
    fi

    # Salvar token
    echo "$_token" > "$_token_file"
    chmod 600 "$_token_file"
    echo -e "${V}  Token salvo em $_token_file${R}"

    # Configurar remote com token
    if [ -n "$_remote_url" ]; then
        _repo_path=$(echo "$_remote_url" | sed -E 's|https?://github.com/||;s|\.git$||;s|\.git/||')
        _new_url="https://${_token}@github.com/${_repo_path}.git"
        git remote set-url origin "$_new_url"
        echo -e "${V}  Remote atualizado com token.${R}"
    fi
else
    # Se ja tem token mas remote nao tem, atualizar
    if [ -n "$_remote_url" ] && [[ "$_remote_url" != *"@"* ]]; then
        _repo_path=$(echo "$_remote_url" | sed -E 's|https?://github.com/||;s|\.git$||;s|\.git/||')
        _new_url="https://${_token}@github.com/${_repo_path}.git"
        git remote set-url origin "$_new_url"
        echo -e "${V}  Remote atualizado com token.${R}"
    fi
fi

# ── Verificar mudancas ──
echo ""
_changes=$(git status --porcelain)

if [ -z "$_changes" ]; then
    echo -e "${AM}Nada para sincronizar.${R}"

    # Mesmo sem mudancas, oferecer pull
    echo -ne "\n${A}Fazer pull mesmo assim? [s/N]:${R} "
    read -r _do_pull
    if [ "${_do_pull,,}" = "s" ]; then
        echo -e "${A}git pull origin $_branch${R}"
        git pull origin "$_branch" 2>/dev/null && echo -e "${V}✔ Pull concluido.${R}" || echo -e "${AM}Pull nao precisou ou houve conflito.${R}"
    fi
    exit 0
fi

echo -e "${A}Mudancas:${R}"
echo "$_changes"
echo ""

# ── Commit message ──
echo -ne "${A}Mensagem do commit${R} [Atualizacao]: "
read -r _msg
_msg="${_msg:-Atualizacao}"

echo ""
echo -e "${A}git add -A${R}"
git add -A

echo -e "${A}git commit -m \"$_msg\"${R}"
git commit -m "$_msg"

# ── Pull antes do push ──
echo ""
echo -e "${A}git pull origin $_branch --rebase${R}"
git pull origin "$_branch" --rebase 2>/dev/null || echo -e "${AM}Pull nao precisou ou houve conflito.${R}"

# ── Push ──
echo ""
echo -e "${A}git push origin $_branch${R}"
if git push origin "$_branch" 2>&1; then
    echo -e "\n${V}${B}✔ Sincronizado com sucesso!${R}"
else
    echo -e "\n${VM}✘ Falha no push.${R}"
    echo -e "${A}Verifique: https://github.com/settings/tokens${R}"
    exit 1
fi
