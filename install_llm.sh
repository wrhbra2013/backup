#!/bin/sh
# ==============================================================
# install_sh — Instala SQLite + Integra com LLM (Llamafile)
# Purpose: Baixar dependências do SQLite, integrar banco de dados
# nas operações da LLM, melhorar desempenho e configurar pontes Python.
# Requer: Debian/Ubuntu, root.
# ==============================================================

set -eu

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_sh.sh"

# --- Detectar gerenciador de pacotes ---
_apt_update_done=0
_apt_update() {
  if [ "$_apt_update_done" -eq 0 ]; then
    info "Executando apt-get update..."
    apt-get update -qq || error "Falha ao executar apt-get update"
    _apt_update_done=1
  fi
}

# --- Verificar Debian/Ubuntu ---
if [ ! -f /etc/debian_version ]; then
  error "Este script requer Debian 11+ ou Ubuntu. /etc/debian_version nao encontrado."
fi
DEB_VER=$(cat /etc/debian_version 2>/dev/null || echo "desconhecido")
info "Sistema: Debian $DEB_VER"

# --- curl ---
if ! command -v curl >/dev/null 2>&1; then
  warn "curl nao encontrado — instalando..."
  _apt_update && apt-get install -y -qq curl
  command -v curl >/dev/null 2>&1 && info "curl instalado" || error "Falha ao instalar curl"
fi

# --- openssl ---
if ! command -v openssl >/dev/null 2>&1; then
  warn "openssl nao encontrado — instalando..."
  _apt_update && apt-get install -y -qq openssl
  command -v openssl >/dev/null 2>&1 && info "openssl instalado" || error "Falha ao instalar openssl"
fi

# --- sqlite3 ---
if ! command -v sqlite3 >/dev/null 2>&1; then
  warn "sqlite3 nao encontrado — instalando..."
  _apt_update && apt-get install -y -qq sqlite3
  command -v sqlite3 >/dev/null 2>&1 && info "sqlite3 instalado" || error "Falha ao instalar sqlite3"
fi

# --- python3-sqlite3 ---
if ! python3 -c "import sqlite3" >/dev/null 2>&1; then
  warn "python3-sqlite3 nao encontrado — instalando..."
  _apt_update && apt-get install -y -qq python3-sqlite3
  python3 -c "import sqlite3; print('python3-sqlite3 ok')" && info "python3-sqlite3 instalado" || error "Falha ao instalar python3-sqlite3"
fi

# --- Diretórios de instalação ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/var/www/llm"
SRC_DIR="$INSTALL_DIR/api/src"
DATA_DIR="$INSTALL_DIR/data"
mkdir -p "$SRC_DIR" "$DATA_DIR" && info "Diretórios criados: $SRC_DIR, $DATA_DIR"

# --- Banco de dados SQLite com performance optimizations ---
DB_PATH="$DATA_DIR/llm.db"

info "Inicializando banco de dados SQLite com optimizações de desempenho..."

sqlite3 "$DB_PATH" <<SQLEOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=-64000;         -- 64MB cache
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
SQLEOF

chmod 600 "$DB_PATH" && info "Banco de dados criado: $DB_PATH com WAL e indexes"

# Inserir configurações padrão se nao existirem
DEFAULT_CONTEXT_SIZE=1024
DEFAULT_THREADS=2
sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO configuracoes (chave, valor) VALUES ('CONTEXT_SIZE', '$DEFAULT_CONTEXT_SIZE');"
sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO configuracoes (chave, valor) VALUES ('THREADS', '$DEFAULT_THREADS');"
info "Tabelas SQLite criadas com indexes de performance"

# --- Ponteiro Python para SQLite ---
PY_BRIDGE_DST="$DATA_DIR/sqlite_llm_bridge.py"

if [ -f "$SCRIPT_DIR/api/src/sqlite_llm_bridge.py" ]; then
  cp "$SCRIPT_DIR/api/src/sqlite_llm_bridge.py" "$PY_BRIDGE_DST"
  chmod +x "$PY_BRIDGE_DST"
  info "Ponteiro Python copiado: $PY_BRIDGE_DST"
else
  warn "Arquivo ponteiro Python nao encontrado em $SCRIPT_DIR/api/src/sqlite_llm_bridge.py — criando versao minima"
  cat > "$PY_BRIDGE_DST" <<'PYEOF'
#!/usr/bin/env python3
import sqlite3, os, sys, datetime
DB=os.getenv("LLM_DB_PATH","/var/www/llm/data/llm.db")
c=sqlite3.connect(DB)
def log(p, t): c.execute("INSERT INTO conversa (papel,conteudo,timestamp) VALUES (?,?,?)",(p,t,datetime.now().isoformat())); c.commit()
def hist(n=10): c.execute("SELECT papel,conteudo,timestamp FROM conversa ORDER BY id DESC LIMIT %s"%(n,)); return c.fetchall()
def get(k,df=None): r=c.execute("SELECT valor FROM configuracoes WHERE chave=%s"%(k,)).fetchone(); return r[0] if r else df
def setk(k,v): c.execute("INSERT OR REPLACE INTO configuracoes (chave,valor) VALUES (%s,%s)"%(k,v)); c.commit()
c.close()
PYEOF
  chmod +x "$PY_BRIDGE_DST"
  info "Ponteiro Python minim criado: $PY_BRIDGE_DST"
fi

# --- .env ---
if [ ! -f "$INSTALL_DIR/.env" ]; then
  API_TOKEN=$(openssl rand -hex 16 2>/dev/null || echo "$(date +%s)$RANDOM" | md5sum | head -c 32)
  cat > "$INSTALL_DIR/.env" <<ENVEOF
# App
PORT=8080
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
  info "Arquivo .env ja existe: $INSTALL_DIR/.env"
fi

# --- Baixar modelo GGUF se nao existir ---
GGUF_SRC="$INSTALL_DIR/LFM2.5-230M-Q4_K_M.gguf"
if [ ! -f "$GGUF_SRC" ]; then
  info "Modelo GGUF nao encontrado. Baixando de HuggingFace..."
  wget -c --tries=5 --timeout=60 -O "$GGUF_SRC" \
    "https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf" || \
    error "Falha ao baixar o modelo GGUF de HuggingFace"
  info "Modelo baixado: $GGUF_FILE"
else
  info "Modelo GGUF ja existente: $GGUF_FILE"
fi

# --- Baixar runtime llamafile ---
LLAMAFILE_RUNTIME="llamafile-0.10.6"
LLAMAFILE_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/llamafile-0.10.6"
if [ -f "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" ] && [ -x "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" ]; then
  info "Usando runtime local: $LLAMAFILE_RUNTIME"
else
  warn "$LLAMAFILE_RUNTIME nao encontrado. Baixando..."
  wget -O "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" "$LLAMAFILE_URL" || error "Falha ao baixar $LLAMAFILE_URL"
  chmod +x "$SCRIPT_DIR/$LLAMAFILE_RUNTIME"
  info "Baixado: $LLAMAFILE_RUNTIME"
fi

# --- zipalign ---
ZIPALIGN="zipalign-0.10.6"
ZIPALIGN_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/zipalign-0.10.6"
if [ -f "$SCRIPT_DIR/$ZIPALIGN" ] && [ -x "$SCRIPT_DIR/$ZIPALIGN" ]; then
  info "Usando zipalign local: $ZIPALIGN"
else
  warn "$ZIPALIGN nao encontrado. Baixando..."
  wget -O "$SCRIPT_DIR/$ZIPALIGN" "$ZIPALIGN_URL" || error "Falha ao baixar $ZIPALIGN_URL"
  chmod +x "$SCRIPT_DIR/$ZIPALIGN"
  info "Baixado: $ZIPALIGN"
fi

# --- Gerar .llamafile executavel via zipalign -j0 ---
LLAMAFILE_OUT="LFM2.5-230M-Q4_K_M.llamafile"
if [ -f "$INSTALL_DIR/$LLAMAFILE_OUT" ]; then
  warn "${LLAMAFILE_OUT} ja existe. Serah recriado."
  rm -f "$INSTALL_DIR/$LLAMAFILE_OUT"
fi

info "Copiando runtime para ${LLAMAFILE_OUT}..."
cp "$SCRIPT_DIR/$LLAMAFILE_RUNTIME" "$INSTALL_DIR/$LLAMAFILE_OUT"
chmod +x "$INSTALL_DIR/$LLAMAFILE_OUT"

info "Empacotando GGUF + .args com zipalign (-j0)..."
cat > "$INSTALL_DIR/.args" <<ARGSEOF
-m /zip/${GGUF_FILE}
-c 1024
--nologo
-np 1
ARGSEOF

"$SCRIPT_DIR/$ZIPALIGN" -j0 "$INSTALL_DIR/$LLAMAFILE_OUT" "$GGUF_SRC" "$INSTALL_DIR/.args" || \
  error "Falha ao executar zipalign"
chmod +x "$INSTALL_DIR/$LLAMAFILE_OUT"
SIZE_LLAMA=$(du -h "$INSTALL_DIR/$LLAMAFILE_OUT" | awk '{print $1}')
info "Gerado com sucesso: ${LLAMAFILE_OUT} (${SIZE_LLAMA})"

# --- Systemd service (opcional) ---
SERVICE_FILE="/etc/systemd/system/lfm-llamafile.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=LFM2.5-230M Llamafile Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${LLAMAFILE_OUT} --ctx-size 1024 -t 2 -tb 2 -np 1 --server --host 127.0.0.1 --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || warn "Nao foi possivel recarregar systemd"
systemctl enable lfm-llamafile.service 2>/dev/null || warn "Nao foi possivel habilitar o service systemd"
info "Servico systemd criado: $SERVICE_FILE"

# --- Nginx: publicar o LLM em https://api.projetosdinamicos.com.br/llm/ ---
NGINX_SITE="/etc/nginx/sites-available/default"
NGINX_DIR="/etc/nginx/llm.d"
NGINX_LOCATIONS="$NGINX_DIR/llm.conf"
# O curinga e proposital: se o diretorio estiver vazio, o nginx ignora o
# include em vez de falhar. Assim o vhost pode ser recarregado antes do LLM.
NGINX_INCLUDE="include ${NGINX_DIR}/*.conf;"
info "Criando configuracao nginx..."

mkdir -p "$NGINX_DIR"
chmod 755 "$NGINX_DIR"

# Heredoc com o location. O `proxy_pass` com barra final remove /llm/ antes de
# entregar ao llamafile: /llm/v1/chat/completions -> /v1/chat/completions.
cat > "$NGINX_LOCATIONS" <<'NGINXEOF'
# /llm/ -> llamafile (127.0.0.1:8080). Gerado por install_llm.sh.
location /llm/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Streaming (SSE): sem buffer e sem timeout curto
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;

    # Prompts/contextos maiores que o default de 1M do nginx
    client_max_body_size 25M;

    # Rate limit por IP (zone definida em /etc/nginx/nginx.conf pelo instalador)
    limit_req zone=llm burst=5 nodelay;
    limit_req_status 429;

    # CORS para a pagina estatica OpenChat (GitHub Pages / projetosdinamicos)
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
    add_header Access-Control-Max-Age 86400 always;
    if ($request_method = OPTIONS) { return 204; }
}
NGINXEOF
info "Location do LLM criada: $NGINX_LOCATIONS"

# --- Rate limit: a zone precisa estar no contexto http do nginx.conf ---
NGINX_MAIN="/etc/nginx/nginx.conf"
NGINX_RATE_LINE='    limit_req_zone $binary_remote_addr zone=llm:10m rate=2r/s;'
NGINX_MAIN_BACKUP=""
if grep -q 'zone=llm:' "$NGINX_MAIN" 2>/dev/null; then
    info "Rate limit do LLM ja presente em $NGINX_MAIN"
else
    NGINX_MAIN_BACKUP="$NGINX_MAIN.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$NGINX_MAIN" "$NGINX_MAIN_BACKUP"
    TMP_MAIN=$(mktemp)
    awk -v line="$NGINX_RATE_LINE" '
        { print }
        !done && /^[[:space:]]*http[[:space:]]*\{/ { print line; done = 1 }
    ' "$NGINX_MAIN" > "$TMP_MAIN"

    if grep -q 'zone=llm:' "$TMP_MAIN"; then
        chmod --reference="$NGINX_MAIN" "$TMP_MAIN" 2>/dev/null || chmod 644 "$TMP_MAIN"
        mv "$TMP_MAIN" "$NGINX_MAIN"
        info "Rate limit adicionado em $NGINX_MAIN (2 req/s, burst 5)"
    else
        rm -f "$TMP_MAIN"
        NGINX_MAIN_BACKUP=""
        warn "Nao encontrei o bloco 'http {' em $NGINX_MAIN"
        warn "Adicione manualmente: $NGINX_RATE_LINE"
        # Sem a zone, 'limit_req' no location quebraria o nginx -t.
        sed -i '/limit_req zone=llm/d; /limit_req_status 429/d' "$NGINX_LOCATIONS" 2>/dev/null || true
        warn "Rate limit removido do location; o LLM sobe sem limite por IP"
    fi
fi

# Inclui o arquivo dentro do server 443 de api.projetosdinamicos.com.br.
# Insere logo apos o marcador do bloco amoranimal (que fica nesse server),
# de forma idempotente: se o include ja existe, nao duplica.
NGINX_BACKUP=""
if grep -qF "$NGINX_INCLUDE" "$NGINX_SITE" 2>/dev/null; then
    info "Include do LLM ja presente em $NGINX_SITE"
else
    NGINX_BACKUP="$NGINX_SITE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$NGINX_SITE" "$NGINX_BACKUP"
    TMP_CONF=$(mktemp)
    awk -v inc="    $NGINX_INCLUDE" '
        { print }
        /# LOCATION_END amoranimal/ { print inc }
    ' "$NGINX_SITE" > "$TMP_CONF"

    if grep -qF "$NGINX_INCLUDE" "$TMP_CONF"; then
        chmod --reference="$NGINX_SITE" "$TMP_CONF" 2>/dev/null || chmod 644 "$TMP_CONF"
        mv "$TMP_CONF" "$NGINX_SITE"
        info "Include do LLM adicionado em $NGINX_SITE"
    else
        rm -f "$TMP_CONF"
        warn "Marcador '# LOCATION_END amoranimal' nao encontrado em $NGINX_SITE"
        warn "Adicione manualmente esta linha dentro do server 443: $NGINX_INCLUDE"
    fi
fi

# Valida e recarrega; se falhar, restaura os backups para nao derrubar a 443
if nginx -t; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    info "Nginx recarregado"
else
    if [ -n "$NGINX_BACKUP" ]; then
        cp -a "$NGINX_BACKUP" "$NGINX_SITE"
        warn "Config restaurada de $NGINX_BACKUP"
    fi
    if [ -n "$NGINX_MAIN_BACKUP" ]; then
        cp -a "$NGINX_MAIN_BACKUP" "$NGINX_MAIN"
        warn "Config restaurada de $NGINX_MAIN_BACKUP"
    fi
    error "nginx -t falhou ao configurar /llm/"
fi

# --- Final ---
echo ""
info "===== Instalacao concluida! ====="
echo ""
echo "  Pasta:   $INSTALL_DIR"
echo "  Modelo:  $LLAMAFILE_OUT"
echo "  API:     http://127.0.0.1:8080/health"
echo "  Publico: https://api.projetosdinamicos.com.br/llm/health"
echo "  OpenChat: https://www.projetosdinamicos.com.br/openchat.html"
echo "  Banco:   $DB_PATH (SQLite com WAL e indexes)"
echo "  Bridge:  $PY_BRIDGE_DST"
echo ""
echo "  Comandos utilis:"
echo "    Logs:      $LLAMAFILE_OUT --ctx-size 1024 -t 2 -tb 2 -np 1 --server --host 127.0.0.1 --port 8080"
echo "    Service:   systemctl start/stop lfm-llamafile"
echo "    Stop:      pkill -f '$LLAMAFILE_OUT'"
echo ""
echo "  .env:    $INSTALL_DIR/.env"
echo ""

info "Testando API..."
resp=$(curl -s "http://127.0.0.1:8080/health" 2>/dev/null) || resp=""
echo "$resp" | grep -q '"status":"ok"' && info "Local:      ✓ http://127.0.0.1:8080/health" || warn "Local:      ✗ $resp"

code=$(curl -s -o /dev/null -w '%{http_code}' \
    "https://api.projetosdinamicos.com.br/llm/health" 2>/dev/null) || code=000
[ "$code" = "200" ] \
    && info "Publico:    ✓ https://api.projetosdinamicos.com.br/llm/health" \
    || warn "Publico:    ✗ HTTP $code (confira DNS, certificado e nginx)"

echo && info "Testes concluidos!"