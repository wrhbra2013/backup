#!/usr/bin/env bash
# =============================================================================
# manutencao-api.sh — Diagnóstico de manutenção da API (somente leitura)
#
# Cobre os quatro pontos pedidos:
#   1. Docker       — daemon, containers, saúde, restarts, portas, compose
#   2. Descoberta   — quem escuta, qual processo/arquivo, systemd, containers
#   3. server.js    — existência, sintaxe, permissões, módulos, versão em uso
#   4. nginx        — nginx -t, vhost carregado, locations duplicadas,
#                     upstreams, certificados, CORS e probe público
#
# Uso:
#   sudo bash manutencao-api.sh
#   sudo API_FILE=/var/www/projeto/api/sc/server.js bash manutencao-api.sh
#   bash manutencao-api.sh --help
#
# Variáveis de ambiente:
#   API_FILE      arquivo da API        (default: /var/www/projeto/api/sc/server.js)
#   NGINX_SITE    vhost                 (default: /etc/nginx/sites-available/default)
#   DOMINIO       host público          (default: api.projetosdinamicos.com.br)
#   API_PREFIX    prefixo da API        (default: amoranimal)
#   LLM_PREFIX    prefixo do LLM        (default: llm)
#   PORTA_LOCAL   porta esperada        (default: 3002)
#   API_HEALTH    rota de health        (default: /health)
#   CONTAINER_RE  nomes de containers   (default: amoranimal|crebortoli|llamafile|api|node)
#
# Saída:
#   0 = tudo ok | 1 = avisos | 2 = falhas
#
# O script NÃO altera nada (sem restart, sem reload, sem escrita de config).
# =============================================================================

set -u

API_FILE="${API_FILE:-/var/www/projeto/api/sc/server.js}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/default}"
DOMINIO="${DOMINIO:-api.projetosdinamicos.com.br}"
API_PREFIX="${API_PREFIX:-amoranimal}"
LLM_PREFIX="${LLM_PREFIX:-llm}"
PORTA_LOCAL="${PORTA_LOCAL:-3002}"
API_HEALTH="${API_HEALTH:-/health}"
ORIGEM="${ORIGEM:-https://www.${DOMINIO#api.}}"
CONTAINER_RE="${CONTAINER_RE:-amoranimal|crebortoli|llamafile|api|node}"

_c_ok=0
_c_warn=0
_c_fail=0

if [ -t 1 ]; then
    R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'
    B=$'\033[0;34m'; C=$'\033[0;36m'; N=$'\033[0m'
else
    R=''; G=''; Y=''; B=''; C=''; N=''
fi

ok()    { _c_ok=$((_c_ok + 1));    printf '  %s[ OK ]%s %s\n'  "$G" "$N" "$*"; }
aviso() { _c_warn=$((_c_warn + 1)); printf '  %s[AVISO]%s %s\n' "$Y" "$N" "$*"; }
falha() { _c_fail=$((_c_fail + 1)); printf '  %s[FALHA]%s %s\n' "$R" "$N" "$*"; }
info()  {                           printf '  %s[info]%s %s\n'  "$B" "$N" "$*"; }
secao() {                           printf '\n%s== %s ==%s\n'    "$C" "$*" "$N"; }

uso() {
    sed -n '3,/^# ====/p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=*$'
    exit 0
}

case "${1:-}" in
    -h|--help) uso ;;
    '') ;;
    *) echo "Opção desconhecida: $1 (use --help)" >&2; exit 64 ;;
esac

# Privilégio: usa sudo -n se já não for root; se não der, segue sem e avisa.
SUDO=""
SEM_PRIV=0
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO="sudo"
else
    SEM_PRIV=1
fi

existe() { [ -e "$1" ]; }
tem_cmd() { command -v "$1" >/dev/null 2>&1; }
porta_aberta() {
    local p="$1"
    tem_cmd ss || return 1
    ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
}

# =============================================================================
# 0. AMBIENTE
# =============================================================================
secao "0. Ambiente"

info "$(hostname) • $(date '+%Y-%m-%d %H:%M:%S %Z') • kernel $(uname -r)"
info "uptime:$(uptime -p 2>/dev/null | sed 's/^up/ up/')"
[ "$SUDO" = "sudo" ] && info "executando com sudo -n"
[ "$SEM_PRIV" -eq 1 ] && aviso "sem root/sudo: algumas checagens (ss -p, docker, nginx -T, logs) ficam limitadas"

if tem_cmd df; then
    while read -r uso_pct ponto; do
        uso_num=${uso_pct%\%}
        if [ "${uso_num:-0}" -ge 90 ] 2>/dev/null; then
            aviso "disco ${ponto} em ${uso_pct}"
        else
            info "disco ${ponto} em ${uso_pct}"
        fi
    done < <(df -P / /var 2>/dev/null | awk 'NR>1 {print $5, $6}' | sort -u)
fi

# =============================================================================
# 1. DOCKER
# =============================================================================
secao "1. Docker"

CONTAINERS_RELACIONADOS=()

if ! tem_cmd docker; then
    aviso "docker não instalado (se a API não usa containers, ignore)"
else
    if ! $SUDO docker info >/dev/null 2>&1; then
        falha "docker instalado, mas o daemon não responde (systemctl status docker)"
    else
        ok "daemon docker ativo — versão $($SUDO docker version --format '{{.Server.Version}}' 2>/dev/null)"

        if $SUDO docker compose version >/dev/null 2>&1; then
            info "docker compose: $($SUDO docker compose version --short 2>/dev/null)"
        elif tem_cmd docker-compose; then
            info "docker-compose (v1): $(docker-compose version --short 2>/dev/null)"
        else
            aviso "nem 'docker compose' nem 'docker-compose' disponíveis"
        fi

        mapa=$($SUDO docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null)
        if [ -z "$mapa" ]; then
            info "nenhum container criado"
        else
            while IFS=$'\t' read -r nome imagem status; do
                [ -n "$nome" ] || continue
                if echo "$nome" | grep -Eqi "$CONTAINER_RE"; then
                    CONTAINERS_RELACIONADOS+=("$nome")
                    if echo "$status" | grep -q '^Up'; then
                        ok "container ${nome} — ${status} (${imagem})"
                    else
                        falha "container ${nome} — ${status} (${imagem})"
                    fi

                    health=$($SUDO docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$nome" 2>/dev/null)
                    restarts=$($SUDO docker inspect -f '{{.RestartCount}}' "$nome" 2>/dev/null)
                    portas=$($SUDO docker port "$nome" 2>/dev/null | tr '\n' ' ')

                    [ -n "${restarts:-}" ] && [ "${restarts:-0}" -gt 5 ] 2>/dev/null \
                        && aviso "container ${nome} reiniciou ${restarts}x (crash loop?)"
                    case "${health:-}" in
                        healthy)   info "${nome}: health healthy" ;;
                        unhealthy) falha "${nome}: health unhealthy" ;;
                        starting)  aviso "${nome}: health starting (ainda subindo)" ;;
                    esac
                    [ -n "${portas:-}" ] && info "${nome}: ${portas}"
                fi
            done <<< "$mapa"

            outros=$(printf '%s\n' "$mapa" | cut -f1 | grep -Evi "$CONTAINER_RE" | wc -l)
            [ "$outros" -gt 0 ] && info "${outros} container(s) fora do filtro de nome"
        fi

        # Projetos compose em execução
        if $SUDO docker compose ls -a >/dev/null 2>&1; then
            projetos=$($SUDO docker compose ls -a 2>/dev/null | tail -n +2)
            if [ -n "$projetos" ]; then
                info "projetos compose:"
                printf '%s\n' "$projetos" | sed 's/^/         /'
            fi
        fi

        if $SUDO docker system df >/dev/null 2>&1; then
            info "uso do docker:"
            $SUDO docker system df 2>/dev/null | sed 's/^/         /'
        fi
    fi
fi

# =============================================================================
# 2. DESCOBERTA DA API
# =============================================================================
secao "2. Descoberta da API"

# Escolhe o arquivo: variável > candidatos conhecidos
API_FILE_ORIGEM="variável API_FILE"
if ! existe "$API_FILE"; then
    encontrado=""
    for cand in \
        /var/www/projeto/api/sc/server.js \
        /var/www/projeto/api/server.js \
        /home/*/scripts/server.js \
        /opt/*/server.js \
        /srv/*/server.js
    do
        if [ -f "$cand" ]; then encontrado="$cand"; break; fi
    done
    if [ -n "$encontrado" ]; then
        aviso "$API_FILE não existe; usando candidato $encontrado"
        API_FILE="$encontrado"
        API_FILE_ORIGEM="descoberta automática"
    else
        falha "$API_FILE não existe e nenhum candidato foi encontrado"
        API_FILE_ORIGEM=""
    fi
fi
[ -n "$API_FILE_ORIGEM" ] && [ -f "$API_FILE" ] && info "arquivo da API: $API_FILE ($API_FILE_ORIGEM)"

# Portas escutando
PORTA_PIDS=()      # "porta:pid"
PORTAS_API=()
if tem_cmd ss; then
    linhas_ss=$($SUDO ss -tlnp 2>/dev/null | awk 'NR>1')
    if [ -z "$linhas_ss" ]; then
        falha "nenhum socket TCP escutando (ss vazio)"
    else
        while IFS= read -r linha; do
            [ -n "$linha" ] || continue
            endereco=$(awk '{print $4}' <<< "$linha")
            porta=${endereco##*:}
            case "$porta" in ''|'*'|*[!0-9]*) continue ;; esac
            pid=$(sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' <<< "$linha" | head -1)
            prog=$(sed -n 's/.*users:(("\([^"]*\)".*/\1/p' <<< "$linha" | head -1)
            [ -n "$pid" ] && PORTA_PIDS+=("${porta}:${pid}")

            case "$porta" in
                80|443|3001|3002|8080) info "porta ${porta} — ${prog:-?}${pid:+ (pid $pid)}" ;;
            esac

            if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ]; then
                cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
                if echo "$cmd" | grep -Eq 'node|llamafile|gunicorn|uvicorn'; then
                    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
                    alvo=""
                    for arg in $cmd; do
                        case "$arg" in *.js|*.mjs|*.cjs) alvo="$arg" ;; esac
                    done
                    case "$alvo" in
                        /*) arquivo_proc="$alvo" ;;
                        '') arquivo_proc="" ;;
                        *)  arquivo_proc="${cwd%/}/${alvo}" ;;
                    esac
                    PORTAS_API+=("$porta")
                    info "porta ${porta}: pid ${pid} — ${arquivo_proc:-$cmd}"
                    if [ -n "$arquivo_proc" ] && [ -f "$API_FILE" ] \
                        && [ "$(readlink -f "$arquivo_proc" 2>/dev/null)" = "$(readlink -f "$API_FILE" 2>/dev/null)" ]; then
                        ok "processo pid ${pid} está executando $API_FILE"
                        API_PID="$pid"
                    fi
                fi
            fi
        done <<< "$linhas_ss"
    fi

    # Fallback: pgrep em processos node
    if tem_cmd pgrep; then
        while read -r pid; do
            [ -n "$pid" ] || continue
            cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
            cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
            [ -n "$cmd" ] && info "processo node pid ${pid}: ${cmd} (cwd: ${cwd:-?})"
        done < <(pgrep -f '[n]ode .*\.js' 2>/dev/null)
    fi
else
    aviso "ss não disponível — descoberta de portas limitada"
fi

# Unidades systemd relacionadas
if tem_cmd systemctl; then
    unidades=$(systemctl list-units --type=service --no-legend --no-pager 2>/dev/null \
        | awk '{print $1, $3, $4}' | grep -Ei 'amoranimal|crebortoli|llama|(^|[^a-z])api([^a-z]|$)|(^|[^a-z])node([^a-z]|$)' || true)
    if [ -n "$unidades" ]; then
        info "serviços systemd relacionados:"
        printf '%s\n' "$unidades" | sed 's/^/         /'
        while read -r u; do
            [ -n "$u" ] && falha "serviço ${u} não está ativo"
        done < <(printf '%s\n' "$unidades" | awk '$2!="active" {print $1}')
    else
        info "nenhum serviço systemd com nome de API/node"
    fi
fi

# Sondas locais de health (portas do processo + esperadas)
portas_probe=$(printf '%s\n' "${PORTAS_API[@]:-}" "$PORTA_LOCAL" 3001 3002 8080 \
    | grep -E '^[0-9]+$' | sort -un)
for p in $portas_probe; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${p}${API_HEALTH}" 2>/dev/null)
    case "$code" in
        200) ok "GET 127.0.0.1:${p}${API_HEALTH} -> 200" ;;
        000|'') info "127.0.0.1:${p} sem resposta (porta fechada)" ;;
        *)   aviso "GET 127.0.0.1:${p}${API_HEALTH} -> ${code}" ;;
    esac
done

# Sonda pública: pela 443 local (se esta máquina for o edge) ou por DNS real
if tem_cmd curl; then
    if porta_aberta 443; then
        code=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 \
            --resolve "${DOMINIO}:443:127.0.0.1" \
            "https://${DOMINIO}/${API_PREFIX}${API_HEALTH}" 2>/dev/null)
        case "$code" in
            200) ok "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} -> 200 (via localhost)" ;;
            000|'') falha "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} sem resposta (nginx parado?)" ;;
            *)   aviso "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} -> ${code}" ;;
        esac
    else
        info "esta máquina não escuta 443 — testando o domínio pela internet"
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
            "https://${DOMINIO}/${API_PREFIX}${API_HEALTH}" 2>/dev/null)
        case "$code" in
            200) ok "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} -> 200 (via DNS)" ;;
            000|'') falha "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} inacessível (DNS/firewall/edge)" ;;
            *)   aviso "público ${DOMINIO}/${API_PREFIX}${API_HEALTH} -> ${code} (via DNS)" ;;
        esac
    fi
fi

# =============================================================================
# 3. ARQUIVO DA API (server.js)
# =============================================================================
secao "3. Arquivo da API"

if [ -z "${API_FILE_ORIGEM:-}" ] || [ ! -f "$API_FILE" ]; then
    falha "arquivo da API não encontrado — pulando testes de server.js"
else
    dono=$(stat -c '%U:%G' "$API_FILE" 2>/dev/null)
    perm=$(stat -c '%a' "$API_FILE" 2>/dev/null)
    tam=$(stat -c '%s' "$API_FILE" 2>/dev/null)
    mtime=$(stat -c '%y' "$API_FILE" 2>/dev/null)
    sha=$(sha256sum "$API_FILE" 2>/dev/null | awk '{print $1}')
    info "${API_FILE}"
    info "dono ${dono} • perms ${perm} • ${tam} bytes • mtime ${mtime}"
    info "sha256 ${sha}"

    case "$perm" in
        6[0-7][0-7]|7[0-7][0-7]) : ;;
        *) aviso "permissões ${perm}: o servidor web/container pode não conseguir ler" ;;
    esac
    echo "$dono" | grep -q '^root:' && aviso "arquivo pertence a root — confirme se o processo roda como root (evite)"

    # Sintaxe: node no host ou dentro de um container
    if tem_cmd node; then
        if node --check "$API_FILE" >/tmp/manut_node_check.$$ 2>&1; then
            ok "node --check (host): sintaxe válida"
        else
            falha "node --check (host): $(tr '\n' ' ' < /tmp/manut_node_check.$$ | cut -c1-220)"
        fi
        rm -f /tmp/manut_node_check.$$
    else
        checado=0
        for c in "${CONTAINERS_RELACIONADOS[@]:-}"; do
            [ -n "$c" ] || continue
            if $SUDO docker exec "$c" test -f "$API_FILE" 2>/dev/null; then
                if $SUDO docker exec "$c" node --check "$API_FILE" >/tmp/manut_node_check.$$ 2>&1; then
                    ok "node --check (container ${c}): sintaxe válida"
                else
                    falha "node --check (container ${c}): $(tr '\n' ' ' < /tmp/manut_node_check.$$ | cut -c1-220)"
                fi
                rm -f /tmp/manut_node_check.$$
                checado=1
                break
            fi
        done
        [ "$checado" -eq 0 ] && aviso "node não disponível no host nem com o arquivo exposto em container — sintaxe não validada"
    fi

    # Módulos relativos que não existem (erro clássico após mover/renomear arquivos)
    faltando=0
    if tem_cmd grep; then
        while read -r req; do
            [ -n "$req" ] || continue
            base="${API_FILE%/*}"
            alvo="${base}/${req}"
            if ! existe "$alvo" && ! existe "${alvo}.js" && ! existe "${alvo}.json" \
                && ! existe "${alvo}/index.js" && ! existe "${alvo}/index.json"; then
                falha "require('${req}') não resolve (procurado em ${base})"
                faltando=$((faltando + 1))
            fi
        done < <(grep -oE "require\\(['\"]\\./[^'\"]+" "$API_FILE" 2>/dev/null \
            | sed -E "s/.*require\\(['\"]//" | sort -u)
        [ "$faltando" -eq 0 ] && ok "todos os require('./...') resolvem"
    fi

    # Listen/porta e .env
    if grep -qE '\.listen\(' "$API_FILE"; then
        linhas_listen=$(grep -nE '\.listen\(' "$API_FILE" | head -3 | sed 's/^/         /')
        info "listen():"
        printf '%s\n' "$linhas_listen"
    else
        aviso "não encontrei .listen( no arquivo — confirme como a API é servida"
    fi

    env_file="${API_FILE%/*}/.env"
    if [ -f "$env_file" ]; then
        porta_env=$(grep -E '^[[:space:]]*PORT[[:space:]]*=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]')
        info ".env encontrado • PORT=${porta_env:-não definido}"
        if [ -n "${porta_env:-}" ] && [ -n "${PORTAS_API[0]:-}" ] && [ "$porta_env" != "${PORTAS_API[0]}" ]; then
            aviso ".env PORT=${porta_env} difere da porta escutada ${PORTAS_API[0]}"
        fi
    else
        info "sem .env em ${API_FILE%/*} (variáveis vêm do systemd/compose?)"
    fi

    # Arquivo mais novo que o processo em execução => precisa reiniciar
    if [ -n "${API_PID:-}" ] && [ -r "/proc/${API_PID}" ]; then
        inicio_proc=$(stat -c '%Y' "/proc/${API_PID}" 2>/dev/null)
        mtime_epoch=$(stat -c '%Y' "$API_FILE" 2>/dev/null)
        if [ -n "${inicio_proc:-}" ] && [ -n "${mtime_epoch:-}" ] && [ "$mtime_epoch" -gt "$inicio_proc" ]; then
            aviso "server.js foi alterado DEPOIS do start do pid ${API_PID} — reinicie o serviço para aplicar"
        else
            ok "processo em execução (pid ${API_PID}) iniciou depois da última alteração do arquivo"
        fi
    fi

    # Versão do arquivo dentro do container vs host
    for c in "${CONTAINERS_RELACIONADOS[@]:-}"; do
        [ -n "$c" ] || continue
        if $SUDO docker exec "$c" test -f "$API_FILE" 2>/dev/null; then
            sha_ct=$($SUDO docker exec "$c" sha256sum "$API_FILE" 2>/dev/null | awk '{print $1}')
            if [ -n "${sha_ct:-}" ] && [ "$sha_ct" = "$sha" ]; then
                ok "cópia dentro de ${c} idêntica ao host"
            else
                aviso "cópia dentro de ${c} DIFERENTE do host (container precisa de rebuild/copy)"
            fi
        fi
    done

    # Backups e diferenças
    backups=$(ls -1t "${API_FILE}".bak* "${API_FILE%.js}"*.bak* 2>/dev/null | head -5 || true)
    if [ -n "$backups" ]; then
        info "backups recentes:"
        printf '%s\n' "$backups" | sed 's/^/         /'
        ultimo=$(printf '%s\n' "$backups" | head -1)
        cmp -s "$API_FILE" "$ultimo" && info "último backup é idêntico ao arquivo atual" \
            || info "arquivo atual difere do último backup ($(basename "$ultimo"))"
    else
        info "nenhum backup .bak encontrado ao lado do arquivo"
    fi

    # Logs recentes com erro
    if [ -n "${API_PID:-}" ]; then
        unidade=$(sed -n 's#.*/\([^/]*\.service\).*#\1#p' "/proc/${API_PID}/cgroup" 2>/dev/null | head -1)
        if [ -n "${unidade:-}" ] && tem_cmd journalctl; then
            erros=$($SUDO journalctl -u "$unidade" -n 120 --no-pager 2>/dev/null | grep -iE 'error|exception|unhandled|ECONN|EADDRINUSE' | tail -5)
            if [ -n "$erros" ]; then
                aviso "últimos erros em ${unidade}:"
                printf '%s\n' "$erros" | sed 's/^/         /'
            else
                ok "journalctl -u ${unidade}: sem erros nas últimas 120 linhas"
            fi
        fi
    fi
    for c in "${CONTAINERS_RELACIONADOS[@]:-}"; do
        [ -n "$c" ] || continue
        erros=$($SUDO docker logs --tail 120 "$c" 2>&1 | grep -iE 'error|exception|unhandled|ECONN|EADDRINUSE' | tail -5)
        if [ -n "$erros" ]; then
            aviso "últimos erros no container ${c}:"
            printf '%s\n' "$erros" | sed 's/^/         /'
        fi
    done
fi

# =============================================================================
# 4. NGINX
# =============================================================================
secao "4. Nginx"

if ! tem_cmd nginx; then
    falha "nginx não instalado"
else
    info "nginx $(nginx -v 2>&1 | sed 's#nginx version: nginx/##')"

    # nginx -t
    if saida_t=$($SUDO nginx -t 2>&1); then
        ok "nginx -t: configuração válida"
        printf '%s\n' "$saida_t" | grep -Ei 'warn|emerg' | sed 's/^/         /'
    else
        falha "nginx -t FALHOU — $(printf '%s' "$saida_t" | tr '\n' ' ' | cut -c1-240)"
        printf '%s\n' "$saida_t" | sed 's/^/         /'
    fi

    # Serviço ativo
    if tem_cmd systemctl; then
        estado=$(systemctl is-active nginx 2>/dev/null)
        [ "$estado" = "active" ] && ok "systemd: nginx active" || falha "systemd: nginx ${estado:-desconhecido}"
    fi

    # Escuta 80/443 — o sintoma que derrubou a API antes
    if tem_cmd ss; then
        for p in 80 443; do
            if porta_aberta "$p"; then
                ok "escutando na porta ${p}"
            else
                falha "nada escutando na porta ${p} (nginx carregou algum server block?)"
            fi
        done
    else
        aviso "ss não disponível — não foi possível verificar 80/443"
    fi

    # Arquivo do vhost e symlink
    if [ -f "$NGINX_SITE" ]; then
        ok "vhost existe: $NGINX_SITE"
        alvo=$(readlink -f "$NGINX_SITE" 2>/dev/null)
        for en in /etc/nginx/sites-enabled/*; do
            [ -e "$en" ] || continue
            if [ "$(readlink -f "$en" 2>/dev/null)" = "$alvo" ]; then
                ok "habilitado via $(basename "$en")"
                HABILITADO=1
            fi
        done
        [ "${HABILITADO:-0}" -eq 1 ] || falha "vhost não está em sites-enabled — o nginx não carrega esse arquivo"

        # O arquivo testado é o que o nginx realmente carrega?
        if $SUDO nginx -T >/dev/null 2>&1; then
            if $SUDO nginx -T 2>/dev/null | grep -q "configuration file ${alvo}"; then
                ok "nginx -T confirma que ${alvo} está carregado"
            else
                falha "nginx -T NÃO mostra ${alvo} — você está editando o arquivo errado"
            fi
        else
            aviso "nginx -T indisponível (sem permissão?) — não foi possível confirmar o arquivo carregado"
        fi

        # server_name e locations esperadas
        dominios_cfg=$(grep -hoE 'server_name[[:space:]]+[^;]+' "$NGINX_SITE" 2>/dev/null | sed 's/server_name[[:space:]]*//' | tr ' ' '\n' | sort -u | tr '\n' ' ')
        info "server_name: ${dominios_cfg:-nenhum}"
        echo " $dominios_cfg " | grep -q " ${DOMINIO} " \
            && ok "server_name contém ${DOMINIO}" \
            || aviso "server_name não contém ${DOMINIO}"

        grep -qE "location[[:space:]]+/${API_PREFIX}/" "$NGINX_SITE" \
            && ok "location /${API_PREFIX}/ presente" \
            || falha "location /${API_PREFIX}/ ausente"

        grep -qE "location[[:space:]]+/${LLM_PREFIX}/" "$NGINX_SITE" 2>/dev/null \
            && ok "location /${LLM_PREFIX}/ presente no vhost" \
            || info "location /${LLM_PREFIX}/ não está no vhost (pode estar em include)"

        # Include do LLM (arquivo separado)
        if $SUDO nginx -T 2>/dev/null | grep -q "llm.d/.*\.conf"; then
            ok "include /etc/nginx/llm.d/*.conf carregado"
        else
            info "include de /etc/nginx/llm.d não detectado"
        fi

        # Locations duplicadas no mesmo server (causa do outage anterior)
        dup=$(
            $SUDO awk '
                function limpar(s) {
                    gsub(/^[[:space:]]+/, "", s)
                    gsub(/[[:space:]]+$/, "", s)
                    sub(/[[:space:]]*\{.*$/, "", s)
                    gsub(/[[:space:]]+/, " ", s)
                    return s
                }
                {
                    bruto = $0
                    sub(/#.*/, "", bruto)
                    abre = gsub(/\{/, "{", bruto)
                    fecha = gsub(/\}/, "}", bruto)
                    if (dentro && prof == 1 && bruto ~ /^[[:space:]]*location[[:space:]]/) {
                        chave = limpar(bruto)
                        if (chave in visto) {
                            printf "server %d: %s (linha %d) repete a linha %d\n", srv, chave, FNR, visto[chave]
                            achou = 1
                        } else {
                            visto[chave] = FNR
                        }
                    }
                    if (!dentro) {
                        if (bruto ~ /^[[:space:]]*server[[:space:]]*\{/) {
                            dentro = 1; srv++; prof = abre - fecha; delete visto
                        }
                        next
                    }
                    prof += abre - fecha
                    if (prof <= 0) dentro = 0
                }
                END { if (!achou) print "" }
            ' "$NGINX_SITE" 2>/dev/null
        )
        if [ -n "$dup" ]; then
            falha "location duplicada no mesmo server:"
            printf '%s\n' "$dup" | sed 's/^/         /'
        else
            ok "nenhuma location duplicada no mesmo server"
        fi

        # Upstreams: extrai proxy_pass e testa connectividade
        while read -r up; do
            [ -n "$up" ] || continue
            hostporta=$(printf '%s' "$up" | sed -E 's#^https?://##; s#/.*$##')
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://${hostporta}${API_HEALTH}" 2>/dev/null)
            case "$code" in
                000|'') aviso "upstream ${up} sem resposta em ${API_HEALTH}" ;;
                *)      ok "upstream ${up} respondeu ${code} em ${API_HEALTH}" ;;
            esac
        done < <(grep -oE 'proxy_pass[[:space:]]+https?://[^;]+' "$NGINX_SITE" 2>/dev/null \
            | sed -E 's#proxy_pass[[:space:]]+##' | sort -u)

        # Certificados: existência e validade
        certs=$(grep -hoE 'ssl_certificate[[:space:]]+[^;]+' "$NGINX_SITE" 2>/dev/null | sed -E 's/ssl_certificate[[:space:]]+//' | sort -u)
        if [ -n "$certs" ] && tem_cmd openssl; then
            while read -r cert; do
                [ -n "$cert" ] || continue
                if [ -r "$cert" ]; then
                    fim=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
                    if [ -n "$fim" ]; then
                        fim_epoch=$(date -d "$fim" +%s 2>/dev/null || echo 0)
                        agora=$(date +%s)
                        dias=$(( (fim_epoch - agora) / 86400 ))
                        if [ "$dias" -lt 0 ]; then
                            falha "certificado EXPIRADO: $cert ($fim)"
                        elif [ "$dias" -lt 21 ]; then
                            aviso "certificado expira em ${dias} dias: $cert"
                        else
                            ok "certificado válido por ${dias} dias ($cert)"
                        fi
                    fi
                else
                    aviso "certificado referenciado mas ilegível: $cert"
                fi
            done <<< "$certs"
        fi
    else
        falha "vhost não existe: $NGINX_SITE"
    fi

    # CORS e preflight pela 443 local
    if ! tem_cmd curl; then
        aviso "curl não instalado — CORS/preflight não testados"
    elif ! porta_aberta 443; then
        info "esta máquina não escuta 443 — CORS/preflight locais não se aplicam"
    else
        cors=$(curl -k -s -o /dev/null -D - --max-time 8 \
            --resolve "${DOMINIO}:443:127.0.0.1" \
            -H "Origin: ${origem}" \
            "https://${DOMINIO}/${API_PREFIX}${API_HEALTH}" 2>/dev/null \
            | grep -i '^access-control-allow-origin' | tr -d '\r' | head -1)
        [ -n "$cors" ] && ok "CORS: ${cors}" || aviso "sem header CORS para Origin ${origem}"

        preflight=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 \
            --resolve "${DOMINIO}:443:127.0.0.1" -X OPTIONS \
            -H "Origin: ${origem}" \
            -H 'Access-Control-Request-Method: POST' \
            -H 'Access-Control-Request-Headers: content-type' \
            "https://${DOMINIO}/${API_PREFIX}/voluntario" 2>/dev/null)
        case "$preflight" in
            2*) ok "preflight OPTIONS -> ${preflight}" ;;
            *)  aviso "preflight OPTIONS -> ${preflight} (esperado 2xx)" ;;
        esac
    fi

    # Logs de erro do nginx
    for log in /var/log/nginx/error.log; do
        if [ -r "$log" ] && tem_cmd tail; then
            recentes=$(tail -n 40 "$log" 2>/dev/null | grep -iE '\[(crit|alert|emerg)\]|duplicate location|no live upstreams' | tail -5)
            if [ -n "$recentes" ]; then
                aviso "eventos recentes em ${log}:"
                printf '%s\n' "$recentes" | sed 's/^/         /'
            else
                ok "${log}: sem crit/alert/emerg nas últimas 40 linhas"
            fi
        fi
    done
fi

# =============================================================================
# RESUMO
# =============================================================================
secao "Resumo"
printf '  %sOK%s: %d   %savisos%s: %d   %sfalhas%s: %d\n' \
    "$G" "$N" "$_c_ok" "$Y" "$N" "$_c_warn" "$R" "$N" "$_c_fail"

if [ "$_c_fail" -gt 0 ]; then
    printf '  %sResultado: FALHAS encontradas — corrija antes de reiniciar serviços.%s\n' "$R" "$N"
    exit 2
elif [ "$_c_warn" -gt 0 ]; then
    printf '  %sResultado: operacional, com avisos.%s\n' "$Y" "$N"
    exit 1
else
    printf '  %sResultado: tudo certo.%s\n' "$G" "$N"
    exit 0
fi
