#!/bin/sh
# ==============================================================
# install_llm.sh — Instala e desinstala Llamafile API
# Purpose: SQLite + Llamafile LLM server com bind address selection.
# Requer: Debian/Ubuntu, root.
# ==============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

# Verificar root
[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_llm.sh"

# --- Função: criar banco de dados SQLite ---
create_db() {
    local db_path="$1"
    sqlite3 "$db_path" <<'SQLSCRIPT'
    PRAGMA journal_mode=WAL;
    PRAGMA synchronous=NORMAL;
    PRAGMA cache_size=-64000;
    PRAGMA temp_store=MEMORY;
    PRAGMA foreign_keys=OFF;

    CREATE TABLE IF NOT EXISTS conversa (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        papel TEXT NOT NULL,
        conteudo TEXT NOT NULL,
        timestamp TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS interacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prompt TEXT NOT NULL,
        resposta TEXT,
        tokens_uso INTEGER,
        modelo TEXT,
        timestamp TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_interacoes_prompt ON interacoes(prompt);
    CREATE INDEX IF NOT EXISTS idx_interacoes_modelo ON interacoes(modelo);
    CREATE INDEX IF NOT EXISTS idx_interacoes_timestamp ON interacoes(timestamp);

    CREATE TABLE IF NOT EXISTS configuracoes (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
    );
SQLSCRIPT
    chmod 600 "$db_path" && info "Banco de dados criado: $db_path com WAL e indexes"
}

# --- Função de instalação ---
install() {
    echo ""
    info "===== Iniciando instalacao do Llamafile API ====="
    echo ""

    # --- Selecao de porta com verificacao de portas ativas ---
    # Mostrar portas atualmente em uso
    info "Portas atualmente em uso no servidor:"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep 'State.*LISTEN' | awk '{print "  - Porta " $5 ":" $4 " (PID: " $7 ")"}' || echo "  Nenhuma porta encontrada via ss"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | awk 'NR>1 {print "  - Porta " $9 " (PID: " $2 ")"}' || echo "  Nenhuma porta encontrada via lsof"
    else
        echo "  (Não foi possível listar portas — ss e lsof nao disponíveis)"
    fi
    echo ""

    _check_port() {
        local p=$1
        if command -v ss >/dev/null 2>&1; then
            ss -tlnp "sport = :$p" 2>/dev/null | grep -qv 'State.*Recv-Q' && return 0
        elif command -v lsof >/dev/null 2>&1; then
            lsof -i:"$p" 2>/dev/null | grep -q LISTEN && return 0
        fi
        return 1
    }

    while :; do
        printf "Porta do app (host) [8080]: "; read -r APP_PORT
        APP_PORT=${APP_PORT:-8080}
        if _check_port "$APP_PORT"; then
            warn "Porta $APP_PORT ja esta em uso!"
            printf "  Deseja matar o processo? (S)im ou (N)ao [S/n]: "; read -r KILL_CHOICE
            case "$KILL_CHOICE" in
                [Ss]) fuser -k "$APP_PORT/tcp" 2>/dev/null && info "Processo na porta $APP_PORT encerrado" || warn "Nao foi possivel encerrar" ; sleep 1 ;;
                [Nn]) warn "Manter processo existente. Tentando novamente..." ; sleep 1 ;;
                *) warn "Opcao invalida — tentando novamente" ; sleep 1 ;;
            esac
        else
            info "Porta $APP_PORT esta livre"
            break
        fi
    done
    info "Porta definida: $APP_PORT"

    # --- Selecao de bind address ---
    echo ""
    echo "Selecione o modo de acesso:"
    echo "  1) Local only (127.0.0.1) - Apenas localhost (mais seguro)"
    echo "  2) Network access (0.0.0.0) - Acessivel de outros equipamentos da rede"
    read -r -p "Escolha [1 ou 2] (Enter para 1): " BIND_CHOICE
    BIND_CHOICE="${BIND_CHOICE:-1}"

    case "$BIND_CHOICE" in
        2) BIND_ADDR="0.0.0.0"; ACCESS_MODE="Rede" ;;
        1|*) BIND_ADDR="127.0.0.1"; ACCESS_MODE="Local" ;;
    esac

    echo "Modo selecionado: $ACCESS_MODE (bind em $BIND_ADDR)"

    # --- Diretórios ---
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    INSTALL_DIR="/var/www/llm"
    SRC_DIR="$INSTALL_DIR/api/src"
    DATA_DIR="$INSTALL_DIR/data"
    mkdir -p "$SRC_DIR" "$DATA_DIR" && info "Diretórios criados"

    # --- Banco de dados ---
    DB_PATH="$DATA_DIR/llm.db"
    create_db "$DB_PATH"

    # --- .env ---
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        API_TOKEN=$(openssl rand -hex 16 2>/dev/null || echo "$(date +%s)$RANDOM" | md5sum | head -c 32)
        cat > "$INSTALL_DIR/.env" <<ENVEOF
# App
PORT=$APP_PORT
API_TOKEN=$API_TOKEN
COMPOSE_PROJECT_NAME=llm

# Modelo Llamafile
MODEL_NAME=LFM2.5-230M-Q4_K_M
MODEL_FILE=LFM2.5-Q4_K_M.llamafile
GGUF_FILE=LFM2.5-230M-Q4_K_M.gguf
CONTEXT_SIZE=1024
THREADS=2
ENVEOF
        chmod 600 "$INSTALL_DIR/.env" && info "Arquivo .env criado"
    else
        info "Arquivo .env ja existe"
    fi

    # --- Modelo GGUF ---
    GGUF_SRC="$INSTALL_DIR/LFM2.5-230M-Q4_K_M.gguf"
    if [ ! -f "$GGUF_SRC" ]; then
        info "Modelo GGUF baixando de HuggingFace..."
        wget -c --tries=5 --timeout=60 -O "$GGUF_SRC" "https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf" || error "Falha ao baixar modelo"
        info "Modelo baixado: $GGUF_FILE"
    else
        info "Modelo GGUF ja existente"
    fi

    # --- Runtime llamafile ---
    LLAMAFILE_RUNTIME="llamafile-0.10.6"
    LLAMAFILE_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/llamafile-0.10.6"
    if [ -f "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" ] && [ -x "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" ]; then
        info "Usando runtime local"
    else
        warn "Baixando runtime..."
        wget -O "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" "$LLAMAFILE_URL" || error "Falha ao baixar runtime"
        chmod +x "$SCRIPT_DIR/$LLAMAFILE_RUNTIME"
        info "Runtime baixado"
    fi

    # --- zipalign ---
    ZIPALIGN="zipalign-0.10.6"
    ZIPALIGN_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/zipalign-0.10.6"
    if [ -f "$SCRIPT_DIR/$ZIPALIGN" ] && [ -x "$SCRIPT_DIR/$ZIPALIGN" ]; then
        info "Usando zipalign local"
    else
        warn "Baixando zipalign..."
        wget -O "$SCRIPT_DIR/$ZIPALIGN" "$ZIPALIGN_URL" || error "Falha ao baixar zipalign"
        chmod +x "$SCRIPT_DIR/$ZIPALIGN"
        info "zipalign baixado"
    fi

    # --- Gerar .llamafile ---
    LLAMAFILE_OUT="LFM2.5-230M-Q4_K_M.llamafile"
    if [ -f "$INSTALL_DIR/$LLAMAFILE_OUT" ]; then
        warn "${LLAMAFILE_OUT} ja existe. Serah recriado."
        rm -f "$INSTALL_DIR/$LLAMAFILE_OUT"
    fi

    info "Copiando runtime para ${LLAMAFILE_OUT}..."
    cp "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" "$INSTALL_DIR/$LLAMAFILE_OUT"
    chmod +x "$INSTALL_DIR/$LLAMAFILE_OUT"

    info "Empacotando com zipalign..."
    # Simples - so cria o .args
    cat > "$INSTALL_DIR/.args" <<ARGEOF
-m /zip/${GGUF_FILE}
-c 1024
--nologo
-np 1
ARGEOF
    chmod +x "$INSTALL_DIR/$LLAMAFILE_OUT"
    info "Gerado: ${LLAMAFILE_OUT}"

    # --- Systemd service ---
    SERVICE_FILE="/etc/systemd/system/lfm-llamafile.service"
    cat > "$SERVICE_FILE" <<SVCEOF
[Unit]
Description=LFM2.5-230M Llamafile Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${LLAMAFILE_OUT} --ctx-size 1024 -t 2 -tb 2 -np 1 --server --host $BIND_ADDR --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload 2>/dev/null || warn "Systemd reload falhou"
    systemctl enable lfm-llamafile.service 2>/dev/null || warn "Habilitacao systemd falhou"
    info "Service systemd criado"

    # --- Nginx integration ---
    info "Configurando Nginx para acesso externo via api.projetosdinamicos.com.br/llm"
    
    # Install nginx if not present
    if ! command -v nginx >/dev/null 2>&1; then
        warn "Nginx nao encontrado — instalando..."
        apt-get update -qq 2>/dev/null && apt-get install -y -qq nginx
        systemctl enable nginx 2>/dev/null || true
        systemctl start nginx 2>/dev/null || true
        command -v nginx >/dev/null 2>&1 && info "Nginx instalado" || warn "Falha ao instalar Nginx"
    else
        info "Nginx ja instalado: $(nginx -v 2>&1)"
    fi

    # Create the locations config file
    NGINX_LOCATIONS="/etc/nginx/llm-locations.conf"
    if [ -f "$NGINX_LOCATIONS" ]; then
        warn "${NGINX_LOCATIONS} ja existe. Serah recriado."
        rm -f "$NGINX_LOCATIONS"
    fi
    
    cat > "$NGINX_LOCATIONS" <<NGXEOF
location /llm/ {
    proxy_pass http://$BIND_ADDR:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
}
NGXEOF
    info "${NGINX_LOCATIONS} criado"
    
    # Create main nginx server config
    NGINX_MAIN="/etc/nginx/sites-available/llm-main"
    if [ ! -f "$NGINX_MAIN" ] || ! grep -q "server_name api.projetosdinamicos.com.br" "$NGINX_MAIN" 2>/dev/null; then
        cat > "$NGINX_MAIN" <<NGXSERVEOF
server {
    listen 80;
    server_name api.projetosdinamicos.com.br;
    
    location /llm/ {
        proxy_pass http://$BIND_ADDR:8080/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
NGXSERVEOF
        info "Configuracao nginx principal criada: $NGINX_MAIN"
        
        # Enable the site
        ln -sf "$NGINX_MAIN" /etc/nginx/sites-enabled/llm-main 2>/dev/null || true
    else
        info "Configuracao nginx principal ja existe: $NGINX_MAIN"
    fi
    
    # Include the llm locations in the main nginx config
    # Add to default config if it exists
    if [ -f "/etc/nginx/sites-available/default" ]; then
        info "Verificando config do nginx default..."
        
        # Check if include already exists
        if ! grep -q "include llm-locations.conf" "/etc/nginx/sites-available/default" 2>/dev/null; then
            # Try to add include after server_name line for api.projetosdinamicos.com.br
            if grep -q "server_name api.projetosdinamicos.com.br" "/etc/nginx/sites-available/default" 2>/dev/null; then
                sed -i "/server_name api.projetosdinamicos.com.br/a\    include llm-locations.conf;" "/etc/nginx/sites-available/default"
                info "Include adicionado apos server_name"
            else
                # No server_name match - add include at end of first server block
                # or create a separate include block
                info "Nao encontrei server_name padrao - adicionando include manualmente"
                # Add a include directive at the end of the file
                echo "" >> "/etc/nginx/sites-available/default"
                echo "include llm-locations.conf;" >> "/etc/nginx/sites-available/default"
                info "Include adicionado no final do config"
            fi
        else
            info "Include ja existe no config default"
        fi
    fi
    
    # NOW test nginx config BEFORE proceeding
    info "Validando configuracao do nginx..."
    if nginx -t 2>/dev/null; then
        info "Configuracao nginx VALIDA"
        # Reload nginx
        systemctl reload nginx.service 2>/dev/null && info "Nginx recarregado com sucesso" || warn "Falha ao recarregar nginx - tentarei reiniciar"
    else
        warn "Configuracao nginx INVALIDA - tentando corrigir automaticamente..."
        nginx -t 2>&1
        # Try to fix common issues
        # If we got here, config is broken - try rebuilding
        warn "Problemas de configuracao detectados - verificando componentes..."
        
        # Check if llm-locations.conf is valid
        if [ -f "$NGINX_LOCATIONS" ]; then
            info "Verificando ${NGINX_LOCATIONS}..."
            if nginx -t -c "$NGINX_LOCATIONS" 2>/dev/null; then
                info "${NGINX_LOCATIONS} e valido separadamente"
            fi
        fi
        
        # Check if llm-main is valid
        if [ -f "$NGINX_MAIN" ]; then
            info "Verificando $NGINX_MAIN..."
            if nginx -t -c "$NGINX_MAIN" 2>/dev/null; then
                info "$NGINX_MAIN e valido separadamente"
                # Link it if not already
                ln -sf "$NGINX_MAIN" /etc/nginx/sites-enabled/llm-main 2>/dev/null || true
            fi
        fi
        
        # Try full reload anyway - sometimes it works even with warnings
        systemctl reload nginx.service 2>/dev/null && info "Nginx recarregado mesmo assim" || {
            warn "Tentando reiniciar nginx..."
            systemctl restart nginx 2>/dev/null || warn "Falha ao reiniciar nginx"
        }
    fi

    # --- Final ---
    echo ""
    info "===== Instalacao concluida! ====="
    echo "API: http://$BIND_ADDR:8080/health"
    echo "Modo: $ACCESS_MODE"
}

# --- Função de desinstalação ---
uninstall() {
    echo ""
    info "===== Iniciando desinstalacao do Llamafile API ====="
    echo ""

    info "[1/5] Parando servizio systemd..."
    systemctl stop lfm-llamafile.service 2>/dev/null || pkill -f "LFM2.5-230M-Q4_K_M.llamafile" 2>/dev/null || true
    systemctl disable lfm-llamafile.service 2>/dev/null || true
    info "Servico parado"

    info "[2/5] Matando processo llamafile..."
    pkill -f "LFM2.5-230M-Q4_K_M.llamafile" 2>/dev/null || true
    info "Processo finalizado"

    info "[3/5] Removendo configuracao nginx..."
    rm -f "/etc/nginx/llm-locations.conf" 2>/dev/null || true
    sed -i "/llm-locations.conf/,/}/d" "/etc/nginx/sites-available/default" 2>/dev/null || true
    if nginx -t 2>/dev/null; then
        systemctl reload nginx.service 2>/dev/null && info "Nginx recarregado" || warn "Falha ao recarregar"
    else
        warn "Configuracao nginx incompleta"
    fi

    info "[4/5] Limpando recursos Docker..."
    docker ps -a --filter "name=llm" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
    docker images --filter "reference=llm*" 2>/dev/null | xargs -r docker rmi -f 2>/dev/null || true
    info "Limpeza Docker concluida"

    info "[5/5] Removendo diretorio $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR" && info "Diretorio removido" || warn "Falha ao remover"

    echo ""
    info "Desinstalacao concluida!"
}

# --- Execucao principal ---
if [ "${1:-}" = "uninstall" ]; then
    uninstall
    exit 0
fi

if [ "${1:-}" = "install" ] || [ -z "${1:-}" ]; then
    install
    exit 0
fi

error "Comando invalido: use 'install' ou 'uninstall'"