#!/bin/bash

# --- Configurações ---
APP_NAME="amoranimal"
REPO_DIR="amoranimalmarilia"

echo "=============================================="
echo "   SCRIPT DE MANUTENÇÃO: $APP_NAME"
echo "=============================================="

# 1. Entrada do Usuário
read -p "Deseja iniciar a manutenção completa (NPM + PM2 + Nginx)? (s/n): " inic>

if [[ "$iniciar" != "s" && "$iniciar" != "S" ]]; then
    echo "Operação cancelada."
    exit 0
fi

# 2. Atualização de Dependências
echo -e "\n[1/4] Verificando dependências (npm install)..."
cd ~/$REPO_DIR || { echo "Erro: Pasta $REPO_DIR não encontrada."; exit 1; }

if npm install; then
    echo "✔ Dependências atualizadas com sucesso."
else
    echo "✖ Erro ao instalar módulos. Verifique o arquivo package.json."
    exit 1
fi

# 3. Reinicialização do PM2
echo -e "\n[2/4] Reiniciando instância no PM2..."
pm2 restart $APP_NAME || pm2 start index.js --name $APP_NAME

# 4. Verificação do Nginx
echo -e "\n[3/4] Analisando status do Nginx..."
if sudo nginx -t; then
    echo "✔ Configuração do Nginx está íntegra."
    sudo systemctl reload nginx
    echo "✔ Nginx recarregado."
else
    echo "✖ Erro na configuração do Nginx! Verifique /etc/nginx/sites-available/"
fi

# 5. Análise de Logs
echo -e "\n[4/4] Abrindo logs do PM2 para análise (Pressione Ctrl+C para sair)..>
echo "Aguardando 3 segundos antes de exibir logs..."
sleep 3
pm2 logs $APP_NAME --lines 20

