#!/bin/bash

# Script para Git: commit, pull, push e listar commits
# Uso: 
#   ./git-sync.sh -m "mensagem do commit"  (commit + sync)
#   ./git-sync.sh -l [n]                   (listar últimos n commits)
#   ./git-sync.sh                          (modo interativo)

VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
RESET='\033[0m'

_TOKEN_FILE="$HOME/.git-sync-token"

# Funcao para configurar token no remote
configurar_token() {
    _remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$_remote_url" ]; then
        echo -e "${VERMELHO}Nenhum remote configurado.${RESET}"
        return 1
    fi

    # Se ja tem token no remote, ok
    if [[ "$_remote_url" == *"@"* ]] || [[ "$_remote_url" == *"ghp_"* ]]; then
        return 0
    fi

    # Carregar token salvo
    local token=""
    if [ -f "$_TOKEN_FILE" ]; then
        token=$(cat "$_TOKEN_FILE" 2>/dev/null || echo "")
    fi

    # Se nao tem token, pedir
    if [ -z "$token" ]; then
        echo ""
        echo -e "${AM}  GitHub exige token (nao aceita mais senha).${RESET}"
        echo -e "${AZUL}  Abrindo navegador para gerar token...${RESET}"
        echo -e "${AZUL}  Permissoes: repo, read:org, workflow${RESET}"
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

        echo -ne "${AZUL}  Token GitHub:${RESET} "
        read -rs token
        echo ""

        if [ -z "$token" ]; then
            echo -e "${VERMELHO}  Token vazio. Abortado.${RESET}"
            return 1
        fi

        # Salvar
        echo "$token" > "$_TOKEN_FILE"
        chmod 600 "$_TOKEN_FILE"
        echo -e "${VERDE}  Token salvo.${RESET}"
    fi

    # Atualizar remote com token
    _repo_path=$(echo "$_remote_url" | sed -E 's|https?://github.com/||;s|\.git$||;s|\.git/||')
    _new_url="https://${token}@github.com/${_repo_path}.git"
    git remote set-url origin "$_new_url"
    echo -e "${VERDE}  Remote atualizado com token.${RESET}"
    return 0
}

# Função para mostrar commits
mostrar_commits() {
    local n="${1:-5}"
    echo -e "${AZUL}=== Últimos $n commits ===${RESET}"
    git log --format="%h - %s (%ad)" --date=short -n "$n"
}

# Função para sync (commit + pull + push)
sync_git() {
    local mensagem="$1"
    
    echo -e "${AZUL}=== Git Sync ===${RESET}\n"
    
    # Configurar token antes de tudo
    if ! configurar_token; then
        exit 1
    fi
    
    local _branch
    _branch=$(git branch --show-current 2>/dev/null || echo "main")
    
    # Verificar se há mudanças
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${AMARELO}Não há mudanças para commitar.${RESET}"
        
        echo -ne "\n${AZUL}Fazer pull mesmo assim? [s/N]:${RESET} "
        read -r _do_pull
        if [ "${_do_pull,,}" = "s" ]; then
            echo -e "${AZUL}Pulling...${RESET}"
            git pull origin "$_branch" 2>/dev/null && echo -e "${VERDE}✔ Pull concluido.${RESET}" || echo -e "${AMARELO}Pull nao precisou.${RESET}"
        fi
        exit 0
    fi
    
    # Mostrar status
    echo -e "${AZUL}Status:${RESET}"
    git status --short
    
    # Adicionar todas as mudanças
    echo -e "\n${AZUL}Adicionando arquivos...${RESET}"
    git add -A
    
    # Commit
    echo -e "\n${AZUL}Criando commit: '$mensagem'${RESET}"
    git commit -m "$mensagem"
    
    # Pull
    echo -e "\n${AZUL}Pulling...${RESET}"
    git pull origin "$_branch" --rebase 2>/dev/null || echo -e "${AMARELO}Pull não foi necessário ou houve conflitos.${RESET}"
    
    # Push
    echo -e "\n${AZUL}Pushing...${RESET}"
    if git push origin "$_branch" 2>&1; then
        echo -e "\n${VERDE}Concluído!${RESET}"
    else
        echo -e "\n${VERMELHO}Falha no push. Verifique o token.${RESET}"
        exit 1
    fi
}

# Função interativa
modo_interativo() {
    echo -e "${AZUL}=== Git Interativo ===${RESET}\n"
    
    # Mostrar status
    echo -e "${AZUL}Status atual:${RESET}"
    git status --short
    
    # Mostrar últimos 3 commits
    echo -e "\n${AZUL}Últimos 3 commits:${RESET}"
    git log --oneline -3
    
    # Pedir mensagem
    echo -ne "\n${AZUL}Mensagem do commit${RESET} (Enter para padrão 'Atualização'): "
    read -r mensagem
    
    if [ -z "$mensagem" ]; then
        mensagem="Atualização"
    fi
    
    sync_git "$mensagem"
}

# Parsear argumentos
case "${1:-}" in
    -l|--log)
        mostrar_commits "${2:-5}"
        ;;
    -m|--message)
        if [ -z "${2:-}" ]; then
            echo -e "${VERMELHO}Erro: Informe a mensagem do commit${RESET}"
            echo "Uso: ./git-sync.sh -m \"mensagem\""
            exit 1
        fi
        sync_git "$2"
        ;;
    -h|--help)
        echo "Uso:"
        echo "  ./git-sync.sh              - Modo interativo"
        echo "  ./git-sync.sh -m \"msg\"   - Commit com mensagem e sincroniza"
        echo "  ./git-sync.sh -l [n]       - Listar últimos n commits (padrão: 5)"
        echo "  ./git-sync.sh -h           - Mostrar ajuda"
        ;;
    "")
        modo_interativo
        ;;
    *)
        echo -e "${VERMELHO}Opção inválida: $1${RESET}"
        echo "Use ./git-sync.sh -h para ajuda"
        exit 1
        ;;
esac
