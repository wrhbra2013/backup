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
    
    # Verificar se há mudanças
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${AMARELO}Não há mudanças para commitar.${RESET}"
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
    git pull origin main 2>/dev/null || echo -e "${AMARELO}Pull não foi necessário ou houve conflitos.${RESET}"
    
    # Push
    echo -e "\n${AZUL}Pushing...${RESET}"
    git push origin main
    
    echo -e "\n${VERDE}Concluído!${RESET}"
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
    read mensagem
    
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
