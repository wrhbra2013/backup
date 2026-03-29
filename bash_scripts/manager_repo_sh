#!/bin/bash

REPO_DIR="/etc/yum.repos.d"

function listar_repos() {
    echo "🔍 Repositórios habilitados:"
    dnf repolist
    echo ""
    echo "📁 Arquivos .repo disponíveis em $REPO_DIR:"
    ls $REPO_DIR
}

function desativar_repo() {
    read -p "Digite o ID do repositório que deseja desativar (ex: ol9_baseos_latest): " REPO_ID
    sudo dnf config-manager --set-disabled "$REPO_ID"
    echo "✅ Repositório '$REPO_ID' desativado."
}

function excluir_repo() {
    read -p "Digite o nome do arquivo .repo que deseja excluir (ex: oracle-linux.repo): " REPO_FILE
    if [ -f "$REPO_DIR/$REPO_FILE" ]; then
        read -p "⚠️ Tem certeza que deseja excluir '$REPO_FILE'? [s/N]: " CONFIRMA
        if [[ "$CONFIRMA" =~ ^[Ss]$ ]]; then
            sudo rm "$REPO_DIR/$REPO_FILE"
            echo "🗑️ Arquivo '$REPO_FILE' excluído com sucesso."
        else
            echo "❌ Exclusão cancelada."
        fi
    else
        echo "🚫 Arquivo não encontrado: $REPO_FILE"
    fi
}

while true; do
    echo ""
    echo "========= MENU DE GERENCIAMENTO DE REPOSITÓRIOS ========="
    echo "1️⃣ Listar repositórios"
    echo "2️⃣ Desativar repositório"
    echo "3️⃣ Excluir arquivo .repo"
    echo "4️⃣ Sair"
    echo "=========================================================="
    read -p "Escolha uma opção [1-4]: " OPCAO

    case $OPCAO in
        1) listar_repos ;;
        2) desativar_repo ;;
        3) excluir_repo ;;
        4) echo "👋 Saindo..."; break ;;
        *) echo "❌ Opção inválida. Tente novamente." ;;
    esac
done

