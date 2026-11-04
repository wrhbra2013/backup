 #!/bin/sh
set -eu

# ==============================================================
# install_llm.sh — Instalação completa (Llamafile + Fastify API + SQLite + Nginx)
# Requer: Debian 11+, root.
# ==============================================================

INSTALL_DIR="/var/www/llm"
SRC_DIR="$INSTALL_DIR/api/src"
DATA_DIR="$INSTALL_DIR/data"
NGINX_CONF="/etc/nginx/sites-available/llm-main"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

# Verificar root
[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_llm.sh"

# Função de desinstalação
uninstall() {
    info "===== Iniciando desinstalação do LLM API ====="
    systemctl stop lfm-llamafile.service 2>/dev/null || true
    systemctl disable lfm-llamafile.service 2>/dev/null || true
    rm -f /etc/systemd/system/lfm-llamafile.service
    systemctl daemon-reload

    systemctl stop llm-api.service 2>/dev/null || true
    systemctl disable llm-api.service 2>/dev/null || true
    rm -f /etc/systemd/system/llm-api.service
    systemctl daemon-reload

    rm -f "/etc/nginx/sites-enabled/llm-main"
    rm -f "$NGINX_CONF"
    systemctl reload nginx 2>/dev/null || true

    rm -rf "$INSTALL_DIR"
    info "Desinstalação concluída com sucesso!"
}

if [ "${1:-}" = "uninstall" ]; then
    uninstall
    exit 0
fi

info "===== Iniciando instalação da API LLM + SQLite + Llamafile ====="

# Checar dependências
apt-get update -qq
apt-get install -y -qq curl openssl sqlite3 nginx nodejs npm wget iproute2

# --------------------------------------------------------------
# 0. Configuração de Portas
# --------------------------------------------------------------
APP_PORT=3004
LLM_PORT=3005

info "Porta selecionada para a API Fastify: $APP_PORT"
info "Porta reservada para o Llamafile: $LLM_PORT"

# Criar diretórios
mkdir -p "$SRC_DIR" "$DATA_DIR"

# Gerar Token de API seguro
API_TOKEN=$(openssl rand -hex 16)

# --------------------------------------------------------------
# 1. Criar arquivo .env
# --------------------------------------------------------------
info "Criando arquivo .env..."
cat > "$INSTALL_DIR/.env" <<ENVEOF
PORT=$APP_PORT
LLM_PORT=$LLM_PORT
API_TOKEN=$API_TOKEN
DB_PATH=$DATA_DIR/llm.db
MODEL_FILE=LFM2.5-230M-Q4_K_M.llamafile
GGUF_FILE=LFM2.5-230M-Q4_K_M.gguf
ENVEOF
chmod 600 "$INSTALL_DIR/.env"

# --------------------------------------------------------------
# 2. Baixar e preparar o Llamafile
# --------------------------------------------------------------
cd "$INSTALL_DIR"

if [ ! -f "LFM2.5-230M-Q4_K_M.gguf" ]; then
    info "Baixando modelo GGUF..."
    wget -q --show-progress -O "LFM2.5-230M-Q4_K_M.gguf" "https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf"
fi

info "Baixando e configurando o runtime Llamafile..."
rm -f llamafile-0.10.6 zipalign-0.10.6 LFM2.5-230M-Q4_K_M.llamafile

wget -q --show-progress -O "llamafile-0.10.6" "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/llamafile-0.10.6"
wget -q --show-progress -O "zipalign-0.10.6" "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.6/zipalign-0.10.6"
chmod +x llamafile-0.10.6 zipalign-0.10.6

cp llamafile-0.10.6 LFM2.5-230M-Q4_K_M.llamafile
chmod +x LFM2.5-230M-Q4_K_M.llamafile
./zipalign-0.10.6 -j0 LFM2.5-230M-Q4_K_M.gguf LFM2.5-230M-Q4_K_M.llamafile
chmod +x LFM2.5-230M-Q4_K_M.llamafile

# Systemd para o Llamafile (usando /bin/sh -c para evitar erro 203/EXEC)
cat > /etc/systemd/system/lfm-llamafile.service <<SVCEOF
[Unit]
Description=LFM2.5-230M Llamafile Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/bin/sh -c '${INSTALL_DIR}/LFM2.5-230M-Q4_K_M.llamafile -m LFM2.5-230M-Q4_K_M.gguf --ctx-size 1024 -t 2 --server --host 127.0.0.1 --port ${LLM_PORT}'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now lfm-llamafile.service

# --------------------------------------------------------------
# 3. Configurar API Node.js / Fastify + SQLite
# --------------------------------------------------------------
cd "$INSTALL_DIR/api"
cat > package.json <<JSONEOF
{
  "name": "llm-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "fastify": "^4.28.0",
    "dotenv": "^16.4.0",
    "undici": "^5.28.4",
    "sqlite3": "^5.1.7"
  }
}
JSONEOF

npm install --production

# Criar src/server.js comunicando via HTTP com a porta 3005
cat > "$SRC_DIR/server.js" <<'SVREOF'
import Fastify from 'fastify';
import 'dotenv/config';
import { request } from 'undici';
import sqlite3 from 'sqlite3';

const fastify = Fastify({ logger: true });
const PORT = process.env.PORT || 3004;
const LLM_PORT = process.env.LLM_PORT || 3005;
const DB_PATH = process.env.DB_PATH || '/var/www/llm/data/llm.db';

const db = new sqlite3.Database(DB_PATH, (err) => {
  if (err) {
    console.error('Erro ao conectar ao SQLite:', err.message);
  } else {
    console.log('Conectado ao banco SQLite em:', DB_PATH);
    db.run(`CREATE TABLE IF NOT EXISTS chat_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request TEXT,
      response TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
  }
});

const authMiddleware = async (req, reply) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  const activeToken = process.env.API_TOKEN;

  if (!token || token !== activeToken) {
    reply.code(401).send({ success: false, error: 'Unauthorized - Token inválido ou ausente' });
  }
};

fastify.get('/ping', async () => ({ pong: true, token_configurado: !!process.env.API_TOKEN, db: 'ativo' }));

fastify.post('/v1/chat/completions', { preHandler: authMiddleware }, async (req, reply) => {
  try {
    const llmResponse = await request(`http://127.0.0.1:${LLM_PORT}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });
    
    const data = await llmResponse.body.json();

    const reqBodyStr = JSON.stringify(req.body);
    const resBodyStr = JSON.stringify(data);
    db.run(`INSERT INTO chat_logs (request, response) VALUES (?, ?)`, [reqBodyStr, resBodyStr], (err) => {
      if (err) req.log.error('Erro ao salvar no SQLite: ' + err.message);
    });

    return reply.code(llmResponse.statusCode).send(data);
  } catch (error) {
    req.log.error(error);
    return reply.code(500).send({ success: false, error: 'Erro ao comunicar com o motor LLM' });
  }
});

await fastify.listen({ port: PORT, host: '127.0.0.1' });
console.log(`API rodando na porta ${PORT}`);
SVREOF

# Systemd para a API Fastify
cat > /etc/systemd/system/llm-api.service <<SVCEOF
[Unit]
Description=LLM Fastify API
After=network.target lfm-llamafile.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/api
ExecStart=/usr/bin/node src/server.js
Restart=on-failure
RestartSec=5
EnvironmentFile=${INSTALL_DIR}/.env

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now llm-api.service

# --------------------------------------------------------------
# 4. Configurar Nginx
# --------------------------------------------------------------
cat > "$NGINX_CONF" <<NGXEOF
server {
    listen 80;
    server_name api.projetosdinamicos.com.br;

    location /llm/ {
        proxy_pass http://127.0.0.1:${APP_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/llm-main
nginx -t && systemctl reload nginx

info "===== Instalação concluída com sucesso! ====="
info "Seu token de acesso gerado está em: $INSTALL_DIR/.env"
