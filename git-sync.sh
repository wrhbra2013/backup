#!/bin/bash

# ╔══════════════════════════════════════════════════════════╗
# ║  git-sync.sh — Sincroniza repositorio com GitHub        ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

# ══════════════════════════════════════════════════════════
#  .ENV EMBUTIDO
# ══════════════════════════════════════════════════════════
GIT_SYNC_TOKEN="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"

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

# ══════════════════════════════════════════════════════════
#  INFORMACOES DO AMBIENTE
# ══════════════════════════════════════════════════════════

_branch=$(git branch --show-current 2>/dev/null || echo "main")
_remote_url=$(git remote get-url origin 2>/dev/null || echo "")
_git_user=$(git config user.name 2>/dev/null || echo "desconhecido")
_git_email=$(git config user.email 2>/dev/null || echo "desconhecido")
_repo_name=$(basename -s .git "$_remote_url" 2>/dev/null || echo "local")

# ══════════════════════════════════════════════════════════
#  STATUS DO TOKEN
# ══════════════════════════════════════════════════════════

_token="${GIT_SYNC_TOKEN:-}"

if [ -n "$_token" ]; then
    _token_status="${V}ok${R} (existe)"
else
    _token_status="${VM}nok${R} (nao existe)"
fi

# ══════════════════════════════════════════════════════════
#  VERIFICACAO DE ALINHAMENTO PRE-SYNC
# ══════════════════════════════════════════════════════════

_verificar_alinhamento() {
    echo ""
    echo -e "${M}══════════════════════════════════════${R}"
    echo -e "${M}     Verificacao de Alinhamento       ${R}"
    echo -e "${M}══════════════════════════════════════${R}"
    echo ""

    local _erros=0
    local _avisos=0

    # ── 1. Fetch remoto ──
    echo -e "${A}[1/5]${R} Buscando atualizacoes do remoto..."
    if git fetch origin "$_branch" 2>/dev/null; then
        echo -e "  ${V}ok${R} — fetch concluido"
    else
        echo -e "  ${VM}falha${R} — nao foi possivel acessar o remoto"
        (( _erros++ ))
    fi

    # ── 2. Verificar divergencia local vs remoto ──
    echo ""
    echo -e "${A}[2/5]${R} Comparando branch local com remoto..."
    _local_hash=$(git rev-parse HEAD 2>/dev/null)
    _remote_hash=$(git rev-parse "origin/$_branch" 2>/dev/null || echo "")
    _base_hash=$(git merge-base HEAD "origin/$_branch" 2>/dev/null || echo "")

    if [ -n "$_remote_hash" ] && [ "$_local_hash" = "$_remote_hash" ]; then
        echo -e "  ${V}ok${R} — local e remoto estao identicos"
    elif [ -n "$_base_hash" ] && [ "$_local_hash" != "$_remote_hash" ]; then
        _local_ahead=$(git rev-list --count "origin/$_branch..HEAD" 2>/dev/null || echo "0")
        _local_behind=$(git rev-list --count "HEAD..origin/$_branch" 2>/dev/null || echo "0")

        if [ "$_local_behind" -gt 0 ] && [ "$_local_ahead" -gt 0 ]; then
            echo -e "  ${VM}CONFLITO${R} — branches divergentes: $_local_ahead commits à frente, $_local_behind atras"
            (( _erros++ ))
        elif [ "$_local_behind" -gt 0 ]; then
            echo -e "  ${AM}AVISO${R} — local esta $_local_behind commit(s) atras do remoto (pull necessario)"
            (( _avisos++ ))
        elif [ "$_local_ahead" -gt 0 ]; then
            echo -e "  ${AM}AVISO${R} — local esta $_local_ahead commit(s) a frente do remoto (push necessario)"
            (( _avisos++ ))
        fi
    else
        echo -e "  ${VM}erro${R} — nao foi possivel comparar branches"
        (( _erros++ ))
    fi

    # ── 3. Verificar arquivos nao rastreados (untracked) ──
    echo ""
    echo -e "${A}[3/5]${R} Verificando arquivos nao rastreados..."
    _untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    if [ "$_untracked" -gt 0 ]; then
        echo -e "  ${AM}AVISO${R} — $_untracked arquivo(s) nao rastreado(s) sera(o) ignorado(s) no pull"
        (( _avisos++ ))
    else
        echo -e "  ${V}ok${R} — todos os arquivos estao rastreados"
    fi

    # ── 4. Verificar stash pendente ──
    echo ""
    echo -e "${A}[4/5]${R} Verificando stash pendente..."
    _stash_count=$(git stash list 2>/dev/null | wc -l)
    if [ "$_stash_count" -gt 0 ]; then
        echo -e "  ${AM}AVISO${R} — $_stash_count stash(es) pendente(s) — considere usar stash pop"
        (( _avisos++ ))
    else
        echo -e "  ${V}ok${R} — nenhum stash pendente"
    fi

    # ── 5. Verificar conflitos de merge anteriores ──
    echo ""
    echo -e "${A}[5/5]${R} Verificando conflitos de merge..."
    _unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
    if [ "$_unmerged" -gt 0 ]; then
        echo -e "  ${VM}ERRO${R} — $_unmerged arquivo(s) com conflito de merge nao resolvido(s)"
        (( _erros++ ))
    else
        echo -e "  ${V}ok${R} — nenhum conflito de merge"
    fi

    # ── Resultado ──
    echo ""
    echo -e "${M}──────────────────────────────────────${R}"
    if [ "$_erros" -gt 0 ]; then
        echo -e "  ${VM}RESULTADO: $_erros erro(s), $_avisos aviso(s)${R}"
        echo -e "  ${VM}Corrija os erros antes de sincronizar.${R}"
        echo ""
        return 1
    elif [ "$_avisos" -gt 0 ]; then
        echo -e "  ${AM}RESULTADO: 0 erros, $_avisos aviso(s)${R}"
        echo -e "  ${AM}Prosseguir com cuidado.${R}"
        echo ""
        return 0
    else
        echo -e "  ${V}RESULTADO: tudo alinhado, pronto para sync${R}"
        echo ""
        return 0
    fi
}

# ══════════════════════════════════════════════════════════
#  PAINEL DE CONTROLE
# ══════════════════════════════════════════════════════════

echo ""
echo -e "${M}══════════════════════════════════════${R}"
echo -e "${M}        git-sync — Painel            ${R}"
echo -e "${M}══════════════════════════════════════${R}"
echo ""
echo -e "  ${A}Usuario:${R}    ${B}$_git_user${R} <$_git_email>"
echo -e "  ${A}Repositorio:${R} ${B}$_repo_name${R}"
echo -e "  ${A}Branch:${R}      ${B}$_branch${R}"
echo -e "  ${A}Token:${R}       $_token_status"
echo ""

# ══════════════════════════════════════════════════════════
#  ULTIMOS 5 COMMITS
# ══════════════════════════════════════════════════════════

echo -e "${A}Ultimos 5 commits:${R}"
git log --oneline -5 --color=always 2>/dev/null | while IFS= read -r _line; do
    echo -e "  $_line"
done
echo ""

# ══════════════════════════════════════════════════════════
#  ARQUIVOS MODIFICADOS
# ══════════════════════════════════════════════════════════

_changes=$(git status --porcelain)

if [ -z "$_changes" ]; then
    echo -e "${AM}Nada para sincronizar.${R}"
    echo ""
    echo -ne "${A}Fazer pull mesmo assim? [s/N]:${R} "
    read -r _do_pull
    if [ "${_do_pull,,}" = "s" ]; then
        echo -e "${A}git pull origin $_branch${R}"
        git pull origin "$_branch" 2>/dev/null && echo -e "${V}Pull concluido.${R}" || echo -e "${AM}Pull nao precisou ou houve conflito.${R}"
    fi
    exit 0
fi

echo -e "${A}Arquivos modificados:${R}"
echo "$_changes" | while IFS= read -r _line; do
    _status="${_line:0:2}"
    _file="${_line:3}"
    case "$_status" in
        "M ") echo -e "  ${V}M${R}  $_file";;
        " D") echo -e "  ${VM}D${R}  $_file";;
        "A ") echo -e "  ${AM}A${R}  $_file";;
        "??") echo -e "  ${M}?${R}  $_file";;
        *)    echo -e "  $_file";;
    esac
done
echo ""

# ══════════════════════════════════════════════════════════
#  CONTEUDO DA PASTA ATUAL
# ══════════════════════════════════════════════════════════

echo -e "${A}Conteudo da pasta atual:${R}"
ls -1 --color=never | while IFS= read -r _item; do
    if [ -d "$_item" ]; then
        echo -e "  ${A}$_item/${R}"
    else
        echo -e "  $_item"
    fi
done
echo ""

# ══════════════════════════════════════════════════════════
#  VERIFICACAO DE ALINHAMENTO
# ══════════════════════════════════════════════════════════

if ! _verificar_alinhamento; then
    echo -ne "${VM}Deseja abortar a sincronizacao? [S/n]:${R} "
    read -r _abort
    if [ "${_abort,,}" != "n" ]; then
        echo -e "${VM}Operacao abortada.${R}"
        exit 1
    fi
    echo -e "${AM}Continuando mesmo assim...${R}"
fi

# ══════════════════════════════════════════════════════════
#  ATUALIZAR REMOTE COM TOKEN
# ══════════════════════════════════════════════════════════

if [ -n "$_remote_url" ] && [ -n "$_token" ]; then
    _repo_path=$(echo "$_remote_url" | sed -E 's|https?://[^@]*@github.com/||;s|https?://github.com/||;s|\.git$||;s|\.git/||')
    _new_url="https://${_token}@github.com/${_repo_path}.git"
    git remote set-url origin "$_new_url"
fi

# ══════════════════════════════════════════════════════════
#  CONFIRMACAO E COMMIT
# ══════════════════════════════════════════════════════════

echo -ne "${A}Mensagem do commit${R} [Atualizacao]: "
read -r _msg
_msg="${_msg:-Atualizacao}"

echo ""
echo -e "${A}Resumo da operacao:${R}"
echo -e "  Usuario:    $_git_user <$_git_email>"
echo -e "  Repositorio: $_repo_name"
echo -e "  Branch:     $_branch"
echo -e "  Commit msg: $_msg"
echo ""
echo -ne "${AM}Confirmar e sincronizar? [s/N]:${R} "
read -r _confirm

if [ "${_confirm,,}" != "s" ]; then
    echo -e "${VM}Operacao cancelada.${R}"
    exit 0
fi

echo ""
echo -e "${A}git add -A${R}"
git add -A

echo -e "${A}git commit -m \"$_msg\"${R}"
git commit -m "$_msg"

echo ""
echo -e "${A}git pull origin $_branch --rebase${R}"
git pull origin "$_branch" --rebase 2>/dev/null || echo -e "${AM}Pull nao precisou ou houve conflito.${R}"

echo ""
echo -e "${A}git push origin $_branch${R}"
if git push origin "$_branch" 2>&1; then
    echo ""
    echo -e "${V}${B}Sincronizado com sucesso!${R}"
else
    echo ""
    echo -e "${VM}Falha no push.${R}"
    echo -e "${A}Verifique: https://github.com/settings/tokens${R}"
    exit 1
fi
