 #!/bin/bash

# =====================================================================
# SCRIPT DE PROVISIONAMENTO: Git, Node.js, PostgreSQL, Nginx e PM2
# Ambiente: Ubuntu/Debian
# =====================================================================

# --- Variáveis de Configuração Padrão ---
NODE_VERSION="20"               # Versão LTS do Node.js
APP_USER="deploy_user"          # Usuário não-root para rodar a aplicação
APP_DIR="/home/$APP_USER/app"   # Diretório onde a aplicação será clonada

# --- Funções de Utilidade ---

# Função para exibir mensagem de erro e sair
die() {
    echo -e "\n\033[1;31mERRO: $1\033[0m" >&2
    exit 1
}

# Função para exibir mensagem de sucesso
ok() {
    echo -e "\033[1;32mSUCESSO: $1\033[0m"
}

# Função para verificar o código de saída do último comando
check_error() {
    if [ $? -ne 0 ]; then
        die "Falha na etapa anterior. Saindo."
    fi
}

# --- ETAPA 0: Coletar Entradas do Usuário ---
echo "--------------------------------------------------------"
echo "--- Configuração de Deploy para Node.js ---"
echo "--------------------------------------------------------"

# 1. URL do Repositório Git
read -p "1/5. URL do Repositório GIT (Ex: https://github.com/user/repo.git): " GIT_REPO_URL
[ -z "$GIT_REPO_URL" ] && die "A URL do repositório Git é obrigatória."

# 2. Nome do Arquivo de Entrada
read -p "2/5. Nome do arquivo principal da aplicação Node.js (Ex: index.js ou server.js): " NODE_ENTRY_FILE
[ -z "$NODE_ENTRY_FILE" ] && die "O nome do arquivo de entrada é obrigatório."

# 3. Domínio/IP Público
read -p "3/5. Seu Domínio ou IP Público (Ex: meuapp.com): " DOMAIN
[ -z "$DOMAIN" ] && die "O Domínio ou IP não pode ser vazio."

# 4. Porta do Backend
read -p "4/5. PORTA local da sua aplicação Node.js (Ex: 3000): " APP_PORT
APP_PORT=${APP_PORT:-3000} # Padrão para 3000

# 5. Senha do Banco de Dados
read -sp "5/5. Defina a senha para o usuário 'app_user' do PostgreSQL: " DB_PASSWORD
echo ""
[ -z "$DB_PASSWORD" ] && die "A senha do banco de dados não pode ser vazia."

# Nome do Banco de Dados/Usuário (Padrões)
DB_USER="app_user"
DB_NAME="app_db"
APP_NAME=$(basename "$GIT_REPO_URL" .git) # Usa o nome do repositório como nome do processo PM2


# --- ETAPA 1: Configuração Inicial do Sistema ---
echo -e "\n## 1. Configurando o sistema..."
sudo apt update
sudo apt install -y curl wget git nginx postgresql postgresql-contrib
check_error
ok "Pacotes básicos (Git, Nginx, PostgreSQL) instalados."

# Cria um usuário não-root se não existir (melhor prática de segurança)
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    sudo adduser --disabled-password --gecos "" "$APP_USER"
    ok "Usuário '$APP_USER' criado."
fi

# Cria o diretório de aplicação
sudo mkdir -p "$APP_DIR"
sudo chown -R "$APP_USER:$APP_USER" "/home/$APP_USER"


# --- ETAPA 2: Instalação do Node.js e PM2 ---
echo -e "\n## 2. Instalando Node.js (LTS v$NODE_VERSION) e PM2..."
curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs
check_error
sudo npm install pm2 -g
check_error
ok "Node.js e PM2 instalados."


# --- ETAPA 3: Clonagem do Projeto e Instalação de Dependências ---
echo -e "\n## 3. Clonando projeto Git e instalando dependências..."

# Executa as ações como o usuário não-root
sudo -u "$APP_USER" bash << EOF
    # Vai para o diretório
    cd $APP_DIR

    # Clona o repositório
    git clone $GIT_REPO_URL .
    
    # Instala as dependências
    npm install
EOF
check_error
ok "Projeto clonado e dependências instaladas em $APP_DIR."


# --- ETAPA 4: Configuração do PostgreSQL ---
echo -e "\n## 4. Configurando Usuário e Banco de Dados no PostgreSQL..."

# Cria o usuário e o banco de dados
sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
check_error
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
check_error

ok "Usuário '$DB_USER' e Banco de Dados '$DB_NAME' criados. **Lembre-se de configurar as variáveis de ambiente PG no seu app.**"


# --- ETAPA 5: Configuração e Início do PM2 ---
echo -e "\n## 5. Configurando e iniciando o PM2..."

# Inicia a aplicação Node.js com PM2 (executado como o usuário de aplicação)
sudo -u "$APP_USER" pm2 start "$APP_DIR/$NODE_ENTRY_FILE" --name "$APP_NAME" --interpreter node -- start
check_error

# Configura o PM2 para iniciar automaticamente após o reboot
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $APP_USER --hp /home/$APP_USER
sudo pm2 save
ok "Aplicação '$APP_NAME' iniciada com PM2 e configurada para auto-inicialização."


# --- ETAPA 6: Configuração do Nginx (Proxy Reverso) ---
echo -e "\n## 6. Configurando Nginx para $DOMAIN na porta $APP_PORT..."

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# Cria o arquivo de configuração do Virtual Host
sudo cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        # Proxy Reverso para a porta onde o PM2 está rodando (a porta do seu Node.js)
        proxy_pass http://localhost:$APP_PORT;
        
        # Headers essenciais
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Habilitar e Testar o Nginx
sudo rm -f "$NGINX_SITES_ENABLED/default" 2>/dev/null
sudo ln -s "$NGINX_CONF" "$NGINX_SITES_ENABLED/"
check_error "Falha ao criar o link simbólico do Nginx."

sudo nginx -t
check_error "Sintaxe do Nginx falhou. Verifique $NGINX_CONF."

sudo systemctl restart nginx
check_error "Falha ao reiniciar Nginx."
ok "Nginx configurado e ativo, expondo $DOMAIN na porta 80."


# --- ETAPA 7: Configuração do Firewall (UFW) ---
echo -e "\n## 7. Configurando Firewall (UFW)..."
sudo ufw allow 'Nginx HTTP'
sudo ufw enable
ok "Porta 80 (HTTP) liberada no UFW."


# --- Instruções Finais ---
echo -e "\n============================================================="
echo -e "--- DEPLOY CONCLUÍDO! ---"
echo -e "============================================================="
echo -e "Sua aplicação Node.js está rodando em $APP_DIR, gerenciada pelo PM2."
echo -e "O Nginx a está expondo publicamente em \033[1;34mhttp://$DOMAIN\033[0m"
echo ""

echo -e "\033[1;33mPRÓXIMOS PASSOS CRÍTICOS:\033[0m"
echo "1. **Variáveis de Ambiente**: Verifique se seu aplicativo está lendo as variáveis de ambiente necessárias (como a porta '$APP_PORT' e as credenciais do PostgreSQL) e ajuste-as dentro do seu projeto, se necessário."
echo "   - Usuário PG: $DB_USER"
echo "   - Senha PG: $DB_PASSWORD"
echo "   - Banco PG: $DB_NAME"
echo ""
echo "2. **PM2 Logs**: Monitore sua aplicação para garantir que iniciou corretamente:"
echo "   \033[1m$ pm2 logs $APP_NAME\033[0m"
echo "-------------------------------------------------------------"
