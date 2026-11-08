#!/bin/bash

# --- Configurações ---
APP_NAME="amoranimal"
REPO_URL="https://github.com/wrhbra2013/amoranimalmarilia.git"
REPO_DIR="amoranimalmarilia"
DOMAIN="amoranimal.ong.br"   # ajuste para o domínio configurado no Certbot

# Cores
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# --- Funções ---

gerenciar_repositorio() {
    if [ -d "$REPO_DIR" ]; then
        echo -e "${AMARELO}A pasta '$REPO_DIR' já existe.${NC}"
        echo "1) Atualizar via Git Pull"
        echo "2) Apagar e clonar do zero"
        echo "3) Pular"
        read -p "Escolha: " opcao_repo

        case $opcao_repo in
            1) cd "$REPO_DIR" && git pull && cd .. ;;
            2) sudo rm -rf "$REPO_DIR" && git clone "$REPO_URL" ;;
            *) echo "Etapa pulada." ;;
        esac
    else
        echo -e "${AMARELO}Clonando repositório pela primeira vez...${NC}"
        git clone "$REPO_URL"
    fi
}

verificar_git() {
    echo -e "\n${AMARELO}[Git] Verificando atualizações...${NC}"
    cd "$REPO_DIR" || { echo -e "${VERMELHO}Erro: Pasta não encontrada.${NC}"; return 1; }
    git fetch
    LOCAL=$(git rev-parse HEAD)
    REMOTO=$(git rev-parse @{u})
    if [ "$LOCAL" = "$REMOTO" ]; then
        echo -e "${VERDE}✔ Código atualizado.${NC}"
    else
        echo -e "${AMARELO}Atualizações encontradas. Baixando...${NC}"
        git pull
    fi
    cd ..
}

instalar_dependencias() {
    echo -e "\n${AMARELO}[NPM] Instalando dependências...${NC}"
    cd "$REPO_DIR" && npm install && cd ..
    echo -e "${VERDE}✔ Dependências OK.${NC}"
}

reiniciar_pm2() {
    echo -e "\n${AMARELO}[PM2] Reiniciando aplicação...${NC}"
    pm2 restart $APP_NAME || pm2 start index.js --name $APP_NAME
    echo -e "${VERDE}✔ PM2 OK.${NC}"
}

validar_nginx() {
    echo -e "\n${AMARELO}[Nginx] Validando configuração...${NC}"
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo -e "${VERDE}✔ Nginx recarregado.${NC}"
    else
        echo -e "${VERMELHO}✖ Erro no Nginx.${NC}"
    fi
}

mostrar_logs() {
    echo -e "\n${AMARELO}[Logs] Exibindo logs...${NC}"
    pm2 logs $APP_NAME --lines 15
}

verificar_certbot() {
    echo -e "\n${AMARELO}[Certbot] Verificando certificado...${NC}"
    if sudo certbot certificates | grep -q "$DOMAIN"; then
        EXPIRACAO=$(sudo certbot certificates | grep "Expiry Date" | head -n1 | cut -d: -f2)
        echo "Data de expiração: $EXPIRACAO"
        echo -e "${AMARELO}Se faltar menos de 30 dias, será renovado automaticamente.${NC}"
    else
        echo -e "${VERMELHO}✖ Nenhum certificado encontrado para $DOMAIN.${NC}"
    fi
}

renovar_certbot() {
    echo -e "\n${AMARELO}[Certbot] Renovando certificado...${NC}"
    if sudo certbot renew --quiet; then
        echo -e "${VERDE}✔ Certificado renovado.${NC}"
        sudo systemctl reload nginx
        echo -e "${VERDE}✔ Nginx recarregado com novo certificado.${NC}"
    else
        echo -e "${VERMELHO}✖ Erro ao renovar certificado.${NC}"
    fi
}

# --- Menu Principal ---
clear
echo -e "${VERDE}=============================================="
echo -e "      SISTEMA DE MANUTENÇÃO AMOR ANIMAL"
echo -e "==============================================${NC}"
echo "1) Fluxo Completo (Repo -> NPM -> PM2 -> Nginx -> Certificado -> Logs)"
echo "2) Gerenciar Repositório"
echo "3) Atualizar Código (Git Pull)"
echo "4) Instalar Dependências (NPM)"
echo "5) Reiniciar App (PM2)"
echo "6) Validar Webserver (Nginx)"
echo "7) Verificar Certificado (Certbot)"
echo "8) Renovar Certificado (Certbot)"
echo "9) Ver Logs"
echo "0) Sair"
echo "----------------------------------------------"
read -p "Selecione uma opção: " opcao

case $opcao in
    1) gerenciar_repositorio && instalar_dependencias && reiniciar_pm2 && validar_nginx && verificar_certbot && renovar_certbot && mostrar_logs ;;
    2) gerenciar_repositorio ;;
    3) verificar_git ;;
    4) instalar_dependencias ;;
    5) reiniciar_pm2 ;;
    6) validar_nginx ;;
    7) verificar_certbot ;;
    8) renovar_certbot ;;
    9) mostrar_logs ;;
    0) exit 0 ;;
    *) echo "Opção inválida." ;;
esac
