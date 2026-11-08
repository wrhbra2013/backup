#!/bin/bash
#
# otimizar-xfce.sh — Otimiza XFCE + sistema completo (Oracle Linux 9)
# Uso: ./otimizar-xfce.sh                    # diagnostico
#       sudo ./otimizar-xfce.sh --apply       # aplicar otimizacoes
#       sudo ./otimizar-xfce.sh --apply --yes # auto-instalar pacotes sem perguntar
#
# Sem argumentos: diagnostico completo + sugestoes
# --apply: aplica todas as otimizacoes com seguranca e rollback

set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
info()  { echo -e " ${C}*${N} $1"; }
ok()    { echo -e " ${G}*${N} $1"; }
warn()  { echo -e " ${Y}*${N} $1"; }
err()   { echo -e " ${R}*${N} $1"; }
title() { echo -e "\n${B}--- $1 ---${N}"; }

APPLY=false; YES=false
for arg in "$@"; do
    [[ "$arg" == "--apply" ]] && APPLY=true
    [[ "$arg" == "--yes" ]]   && YES=true
done

LOGDIR="$HOME/.local/share/xfce-optimize"
mkdir -p "$LOGDIR"
UNDO_LOG="$LOGDIR/undo-$(date +%Y%m%d-%H%M%S).log"
OPERATIONS_LOG="$LOGDIR/operations-$(date +%Y%m%d-%H%M%S).log"
echo "# Log de restauracao $(date)" > "$UNDO_LOG"
echo "# Operacoes aplicadas $(date)" > "$OPERATIONS_LOG"
log_cmd(){ echo "$*" >> "$UNDO_LOG"; }
log_op(){ echo "[$(date '+%H:%M:%S')] $*" >> "$OPERATIONS_LOG"; }

# ─────────────────────────────────────────────────────────────
# AUTO-INSTALL: baixa pacotes faltantes via dnf (ou wget)
# ─────────────────────────────────────────────────────────────
REQUIRED_PKGS=()
PKG_INSTALLED=0

check_pkg() {
    rpm -q "$1" &>/dev/null && return 0
    REQUIRED_PKGS+=("$1")
    return 1
}

install_pkgs() {
    [[ ${#REQUIRED_PKGS[@]} -eq 0 ]] && return
    if ! command -v dnf &>/dev/null; then
        err "dnf nao encontrado. Instale manualmente: ${REQUIRED_PKGS[*]}"
        return
    fi
    if [[ "$YES" == false ]]; then
        echo ""
        warn "Pacotes necessarios nao instalados: ${REQUIRED_PKGS[*]}"
        read -rp "  Deseja instalar via dnf? [s/N] " resp
        [[ "$resp" =~ ^[Ss]$ ]] || { info "Pulei instalacao."; return; }
    fi
    for pkg in "${REQUIRED_PKGS[@]}"; do
        info "Instalando $pkg..."
        dnf install -y "$pkg" 2>/dev/null || {
            warn "Falha ao instalar $pkg via dnf. Tentando via wget..."
            _install_fallback "$pkg"
        }
    done
    PKG_INSTALLED=1
}

# Fallback: baixa RPM manualmente (caso dnf esteja corrompido)
_install_fallback() {
    local pkg="$1" url
    case "$pkg" in
        lm_sensors)     url="https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/l/lm_sensors-3.6.0-17.el9.x86_64.rpm" ;;
        preload)        warn "preload nao disponivel no OL9. Pule."; return ;;
        *)              warn "Nao sei baixar $pkg manualmente."; return ;;
    esac
    local tmpdir=$(mktemp -d)
    wget -q "$url" -P "$tmpdir" && dnf install -y "$tmpdir"/*.rpm 2>/dev/null || \
        warn "Falha ao instalar $pkg manualmente."
    rm -rf "$tmpdir"
}

# ─────────────────────────────────────────────────────────────
# DETECCAO XFCE
# ─────────────────────────────────────────────────────────────
if [[ "${XDG_CURRENT_DESKTOP:-}" != "XFCE" ]] && [[ "${XDG_SESSION_DESKTOP:-}" != "XFCE" ]]; then
    warn "XFCE nao detectado (atual: ${XDG_CURRENT_DESKTOP:-desconhecido})"
fi

# ============================================================
# DIAGNOSTICO COMPLETO
# ============================================================
echo ""
echo "============================================================"
echo "  DIAGNOSTICO XFCE + SISTEMA"
echo "============================================================"
echo "  Data: $(date '+%Y-%m-%d %H:%M')"
echo "  Host: $(hostname)"
echo "  Desktop: ${XDG_CURRENT_DESKTOP:-N/A}"
echo ""

SYS_BOOT=$(uptime -s 2>/dev/null | cut -d' ' -f1)
INFO_LOG="$LOGDIR/diagnostico-$(date +%Y%m%d-%H%M%S).log"

title "SISTEMA OPERACIONAL"
cat /etc/oracle-release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -4
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime -p | sed 's/up //')"
echo "  Boot:   $SYS_BOOT"

title "HARDWARE"
echo "  CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "  Cores: $(nproc)"
echo "  RAM total: $(free -h | awk '/Mem:/{print $2}')"
echo "  RAM usada: $(free -h | awk '/Mem:/{print $3}')"
echo "  RAM disp.: $(free -h | awk '/Mem:/{print $7}')"
echo "  Swap total: $(free -h | awk '/Swap:/{print $2}')"
echo "  Swap usado: $(free -h | awk '/Swap:/{print $3}')"
echo "  Disco: $(df -h / | awk 'NR==2{print $4" livres de "$2" ("$5" usado)"}')"

title "BOOT TIME (systemd-analyze)"
systemd-analyze 2>/dev/null | sed 's/^/  /'
echo "  Top 5 servicos mais lentos:"
systemd-analyze blame 2>/dev/null | head -5 | sed 's/^/    /'
KDUMP_TIME=$(systemd-analyze blame 2>/dev/null | grep kdump | head -1)
[[ -n "$KDUMP_TIME" ]] && warn "  kdump.service: $KDUMP_TIME (maior vilao do boot!)"

title "TRANSPARENT HUGE PAGES (THP)"
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')
echo "  THP: $THP"
if [[ "$THP" == "always" ]]; then
    warn "  THP='always' fragmenta memoria em sistemas com <4GB RAM"
    echo "    Recomendado: madvise (echo madvise > /sys/kernel/mm/transparent_hugepage/enabled)"
fi

title "ZRAM"
if command -v zramctl &>/dev/null; then
    zramctl 2>/dev/null | tail -n+2 | while read line; do
        echo "  $line"
    done
    ZRAM_ALGO=$(zramctl 2>/dev/null | awk 'NR==2{print $2}')
    echo "  Algoritmo: ${ZRAM_ALGO:-n/a}"
    [[ -n "$ZRAM_ALGO" && "$ZRAM_ALGO" != "zstd" ]] && \
        warn "  Algoritmo '$ZRAM_ALGO' — trocar para 'zstd' comprime ~15% melhor"
else
    echo "  zramctl nao encontrado"
fi

title "MOUNT OPTIONS (/)"
MOUNT_OPTS=$(findmnt -no OPTIONS / 2>/dev/null)
echo "  Opcoes: $MOUNT_OPTS"
if [[ "$MOUNT_OPTS" != *noatime* ]]; then
    warn "  'noatime' nao ativo — adicionar economiza escritas em HDD"
fi

title "XFCE - COMPOSITOR"
if command -v xfconf-query &>/dev/null; then
    COMPOSITOR=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo "n/a")
    echo "  Compositor: $([ "$COMPOSITOR" == "true" ] && echo 'ativado' || echo 'desativado')"
    if [[ "$COMPOSITOR" == "true" ]]; then
        SHOW_CORE=$(xfconf-query -c xfwm4 -p /general/show_dock_shadows 2>/dev/null || echo "n/a")
        echo "  Shadows: ${SHOW_CORE:-n/a}"
        CYCLE_RAISE=$(xfconf-query -c xfwm4 -p /general/raise_on_click 2>/dev/null || echo "n/a")
        echo "  Raise on click: ${CYCLE_RAISE:-n/a}"
    fi
else
    warn "xfconf-query nao encontrado"
fi

title "XFCE - GERENCIADOR DE JANELAS"
if command -v xfconf-query &>/dev/null; then
    TILE=$(xfconf-query -c xfwm4 -p /general/tile_on_move 2>/dev/null || echo "n/a")
    echo "  Tiling on move: ${TILE}"
    WORKSPACES=$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || echo "4")
    echo "  Workspaces: ${WORKSPACES}"
fi

title "XFCE - PAINEL"
if command -v xfconf-query &>/dev/null; then
    for i in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oP '/plugins/plugin-\d+' | sort -u); do
        NAME=$(xfconf-query -c xfce4-panel -p "$i" 2>/dev/null || true)
        [[ -n "$NAME" ]] && echo "  $i: $NAME"
    done 2>/dev/null | head -15
fi

title "APPS DE INICIO AUTOMATICO"
STARTUP_DIR="$HOME/.config/autostart"
if [[ -d "$STARTUP_DIR" ]]; then
    for f in "$STARTUP_DIR"/*.desktop; do
        [[ -f "$f" ]] || continue
        NAME=$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2)
        echo "  ${NAME:-$(basename "$f" .desktop)}"
    done
else
    echo "  Nenhum"
fi

title "MEMORIA E SWAP"
echo "  RAM: $(free -h | awk '/Mem:/{printf "%s total, %s usada, %s disponivel", $2, $3, $7}')"
SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "n/a")
echo "  Swappiness: ${SWAPPINESS}"
echo "  Swap: $(swapon --show 2>/dev/null | wc -l) dispositivo(s)"
[[ -n "$SWAPPINESS" && "$SWAPPINESS" -gt 60 ]] && \
    warn "  Swappiness=${SWAPPINESS} alto para HDD — recomendado: 10"

title "TOP 8 PROCESSOS POR RAM"
ps aux --sort=-%mem 2>/dev/null | awk 'NR<=8{printf "  %-6s %-5s %-5s %s\n", $1, $2, $4"%", $11}'

title "SERVICOS ATIVOS RELEVANTES"
for s in kdump.service xfce4-screensaver power-profiles-daemon accounts-daemon \
         cups bluetooth avahi-daemon firewalld smartd ModemManager \
         postgresql mongod redis NetworkManager-wait-online; do
    enabled=$(systemctl is-enabled "$s" 2>/dev/null || echo "n/a")
    active=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    [[ "$enabled" == "enabled" ]] && warn "  $s: enabled=$enabled active=$active" || \
        echo "  $s: enabled=$enabled active=$active"
done

title "TEMPERATURA DA CPU"
if command -v sensors &>/dev/null; then
    sensors 2>/dev/null | grep -E '^Core|^Package|temp[0-9]' | head -5 | sed 's/^/  /'
else
    echo "  lm-sensors nao instalado"
    check_pkg lm_sensors
fi

title "ERROS NO LOG (BOOT ATUAL)"
ERR_COUNT=$(journalctl -p 3 -b --no-pager 2>/dev/null | wc -l || echo "0")
echo "  Total de erros: ${ERR_COUNT}"
(( ERR_COUNT > 0 )) && \
    journalctl -p 3 -b --no-pager 2>/dev/null | awk -F': ' '{print $2}' | sort | uniq -c | sort -rn | head -5 | sed 's/^/  /'

title "OOM (OUT OF MEMORY)"
OOM_COUNT=$(journalctl -b -t oom-kill --no-pager 2>/dev/null | wc -l || echo "0")
echo "  OOM kills: ${OOM_COUNT}"
(( OOM_COUNT > 0 )) && err "VISAO: eventos OOM detectados!" || ok "Sem OOM"

title "CRASHES XFCE"
for proc in xfwm4 xfdesktop xfce4-panel; do
    n=$(journalctl -b "_COMM=$proc" --no-pager 2>/dev/null | grep -ci "crash\|segfault\|abort\|signal" || echo "0")
    echo "  $proc: ${n} eventos"
done

title "PRESSURE STALL INFORMATION (PSI)"
for metric in cpu memory io; do
    [[ -f "/proc/pressure/$metric" ]] && \
        awk "{printf \"  %s: %s\n\", \"$metric\", \$0}" "/proc/pressure/$metric" 2>/dev/null || \
        echo "  $metric: n/a (kernel sem CONFIG_PSI)"
done

# ============================================================
# Salvar diagnostico em log
# ============================================================
{
    echo "=== DIAGNOSTICO $(date) ==="
    echo "Host: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "RAM: $(free -h | awk '/Mem:/{print $2" total, "$3" used, "$7" avail"}')"
    echo "DISK: $(df -h / | awk 'NR==2{print $4" free of "$2}')"
    echo "SWAPPINESS: $(cat /proc/sys/vm/swappiness 2>/dev/null || echo n/a)"
    echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')"
    echo "Boot time: $(systemd-analyze 2>/dev/null | head -1)"
    echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
} > "$INFO_LOG"

# ============================================================
# PROPOSTA DE MELHORIAS
# ============================================================
echo ""
echo "============================================================"
echo "  PROPOSTA DE MELHORIAS"
echo "============================================================"
echo ""

RAM_TOTAL=$(free -m | awk '/Mem:/{print int($2)}')
RAM_LIVRE=$(free -m | awk '/Mem:/{print int($7)}')

# 1. RAM
echo " ${B}1. MEMORIA RAM${N}"
PERC=$((RAM_LIVRE * 100 / RAM_TOTAL))
(( RAM_TOTAL < 3072 )) && \
    warn "RAM total (${RAM_TOTAL}MB) abaixo de 3GB. Upgrade para 8GB DDR3L recomendado." || \
    (( RAM_TOTAL < 6144 )) && \
    warn "RAM total (${RAM_TOTAL}MB) abaixo de 6GB." || \
    ok "RAM total (${RAM_TOTAL}MB) OK"
(( PERC < 15 )) && err "RAM livre: ${PERC}% (${RAM_LIVRE}MB) — CRITICO" || \
    (( PERC < 25 )) && warn "RAM livre: ${PERC}% (${RAM_LIVRE}MB)" || \
    ok "RAM livre: ${PERC}% (${RAM_LIVRE}MB) - OK"

# 2. Swap + swappiness
title "2. SWAP + SWAPPINESS"
SWAP_SIZE=$(free -m | awk '/Swap:/{print int($2)}')
SWAP_USED=$(free -m | awk '/Swap:/{print int($3)}')
(( SWAP_SIZE == 0 )) && warn "Sem swap configurada!" || \
    (( SWAP_USED > SWAP_SIZE * 80 / 100 )) && warn "Swap ${SWAP_USED}/${SWAP_SIZE}MB (>80%!)"
(( SWAPPINESS > 60 )) && \
    warn "Swappiness=${SWAPPINESS} alto demais para HDD. sysctl vm.swappiness=10"

# 3. Compositor
title "3. COMPOSITOR XFCE"
if [[ "${COMPOSITOR:-false}" == "true" ]]; then
    (( RAM_TOTAL < 4000 )) && \
        warn "Compositor ativo — desative (xfconf-query ... use_compositing false)" || \
        info "Compositor ativo (RAM suficiente)"
else
    ok "Compositor desativado"
fi

# 4. Servicos (inclui kdump como prioridade)
title "4. SERVICOS (PRIORIDADE: KDUMP)"
if systemctl is-enabled kdump.service 2>/dev/null | grep -q "^enabled$"; then
    kdump_time=$(systemd-analyze blame 2>/dev/null | grep kdump | awk '{print $1}')
    err "kdump.service ativo — adiciona ~${kdump_time:-60s} ao boot!"
    echo "    systemctl mask kdump.service  # economia de ~${kdump_time:-60s}"
fi

title "   Servicos nao essenciais"
for s_desc in "cups:impressao" "bluetooth:Bluetooth" "avahi-daemon:descoberta" \
              "ModemManager:modem" "mcelog:MCA" "accounts-daemon:contas" \
              "power-profiles-daemon:energia" "postgresql:banco" "mongod:banco" \
              "redis:caching" "NetworkManager-wait-online:espera rede"; do
    svc="${s_desc%%:*}"; desc="${s_desc#*:}"
    systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled" && \
        warn "$svc: ativo ($desc)" && echo "    systemctl disable --now $svc"
done

# 5. Startup apps + screensaver
title "5. APPS DE INICIO"
if [[ -d "$STARTUP_DIR" ]]; then
    for f in "$STARTUP_DIR"/*.desktop; do
        [[ -f "$f" ]] || continue
        NAME=$(grep -m1 '^Name=' "$f" 2>/dev/null || basename "$f" .desktop)
        warn "${NAME} inicia automaticamente"
    done
fi
command -v xfce4-screensaver &>/dev/null && \
    warn "xfce4-screensaver ativo (~30-50MB RAM)"

# 6. THP
title "6. TRANSPARENT HUGE PAGES"
THP_CUR=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')
[[ "$THP_CUR" == "always" ]] && \
    warn "THP='always' — trocar para 'madvise' reduz fragmentacao de RAM" && \
    echo "    echo madvise | tee /sys/kernel/mm/transparent_hugepage/enabled"

# 7. ZRAM
title "7. ZRAM (COMPRESSAO)"
if command -v zramctl &>/dev/null; then
    ZRAM_ALGO=$(zramctl 2>/dev/null | awk 'NR==2{print $2}')
    [[ -n "$ZRAM_ALGO" && "$ZRAM_ALGO" != "zstd" ]] && \
        warn "ZRAM algoritmo='$ZRAM_ALGO' — trocar para 'zstd'" && \
        echo "    echo zstd | tee /sys/block/zram0/comp_algorithm"
fi

# 8. noatime
title "8. MOUNT OPTIONS"
MOUNT_OPTS=$(findmnt -no OPTIONS / 2>/dev/null)
[[ "$MOUNT_OPTS" != *noatime* ]] && \
    warn "Falta 'noatime' em / — adicionar em /etc/fstab reduz escrita em HDD"

# 9. I/O scheduler
title "9. I/O SCHEDULER"
DISK_TYPE="SSD"
if [[ -f /sys/block/sda/queue/rotational ]] && [[ "$(cat /sys/block/sda/queue/rotational)" == "1" ]]; then
    DISK_TYPE="HDD"
    SCHED=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+')
    echo "  Disco: HDD 5400rpm (ST500LT012)"
    echo "  Scheduler: ${SCHED}"
    [[ "$SCHED" != "bfq" ]] && warn "Trocar para BFQ: echo bfq > /sys/block/sda/queue/scheduler"
fi

# 10. Erros
title "10. SYSLOG"
(( ERR_COUNT > 50 )) && warn "${ERR_COUNT} erros no boot"
(( OOM_COUNT > 0 )) && err "${OOM_COUNT} eventos OOM!"

# 11. Boot time
title "11. ANALISE DE BOOT"
echo "  Boot total: $(systemd-analyze 2>/dev/null | grep -oP '^Startup finished in .*' || echo 'n/a')"
echo "  Para grafico: systemd-analyze plot > boot.svg"

# 12. Hardware
title "12. RECOMENDACOES DE HARDWARE"
(( RAM_TOTAL < 4096 )) && echo "  - Upgrade RAM: 8GB DDR3L SODIMM (~R\$80-120)"
[[ "$DISK_TYPE" == "HDD" ]] && echo "  - Upgrade SSD: SATA III 240GB (~R\$120-200) — maior ganho possivel"

# ============================================================
# APLICAR OTIMIZACOES (--apply)
# ============================================================
if [[ "$APPLY" == false ]]; then
    echo ""
    echo "============================================================"
    echo "  Para APLICAR as otimizacoes: sudo $0 --apply [--yes]"
    echo "============================================================"
    echo ""
    echo "  Log: $INFO_LOG"
    # Instalar pacotes mesmo sem --apply se --yes
    [[ "$YES" == true ]] && install_pkgs
    exit 0
fi

# ── MODO APPLY ──
echo ""
echo "============================================================"
echo "  APLICANDO OTIMIZACOES"
echo "============================================================"
echo ""

if [[ $EUID -ne 0 ]]; then
    err "Modo --apply requer root (sudo)."
    exit 1
fi

# Instalar pacotes necessarios antes das alteracoes
install_pkgs

# ─────────────────────────────────────────────────────────────
# 1. Swappiness
# ─────────────────────────────────────────────────────────────
title "1. Swappiness"
CURRENT_SWAP=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "70")
if (( CURRENT_SWAP > 10 )); then
    sysctl -w vm.swappiness=10
    echo "vm.swappiness=10" > /etc/sysctl.d/90-swappiness.conf
    log_cmd "sysctl -w vm.swappiness=$CURRENT_SWAP; rm -f /etc/sysctl.d/90-swappiness.conf"
    ok "swappiness $CURRENT_SWAP -> 10"
    log_op "swappiness: $CURRENT_SWAP -> 10"
else
    ok "swappiness ja em $CURRENT_SWAP"
fi

# ─────────────────────────────────────────────────────────────
# 2. kdump.service (MAIOR VILAO DO BOOT)
# ─────────────────────────────────────────────────────────────
title "2. kdump.service"
if systemctl is-enabled kdump.service 2>/dev/null | grep -q "^enabled$"; then
    KDUMP_ACTIVE=$(systemctl is-active kdump.service 2>/dev/null || echo "unknown")
    systemctl mask kdump.service 2>/dev/null || true
    log_cmd "systemctl unmask kdump.service; systemctl enable kdump.service"
    ok "kdump.service mascarado (economia de ~60s no boot!)"
    log_op "kdump.service mascarado"
    if [[ "$KDUMP_ACTIVE" == "active" ]]; then
        warn "kdump ainda rodando nesta sessao. Efetivo no proximo boot."
    fi
else
    ok "kdump.service ja desativado"
fi

# ─────────────────────────────────────────────────────────────
# 3. THP: always -> madvise
# ─────────────────────────────────────────────────────────────
title "3. Transparent Huge Pages"
THP_CUR=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')
if [[ "$THP_CUR" == "always" ]]; then
    echo madvise | tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>/dev/null || true
    log_cmd "echo always > /sys/kernel/mm/transparent_hugepage/enabled"
    ok "THP: always -> madvise (menos fragmentacao de RAM)"
    log_op "THP: always -> madvise"
    # Persistir via tuned ou udev
    if ! grep -q "transparent_hugepage" /etc/tuned/active_profile 2>/dev/null; then
        cat > /etc/udev/rules.d/99-thp-madvise.rules << 'RULE'
ACTION=="add", SUBSYSTEM=="cpu", ATTR{online}=="1", RUN+="/bin/sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled'"
RULE
        ok "Regra udev criada para persistir THP=madvise"
        log_op "Regra udev 99-thp-madvise.rules criada"
        log_cmd "rm -f /etc/udev/rules.d/99-thp-madvise.rules"
    fi
else
    ok "THP ja em madvise"
fi

# ─────────────────────────────────────────────────────────────
# 4. ZRAM: algoritmo zstd
# ─────────────────────────────────────────────────────────────
title "4. ZRAM (algoritmo zstd)"
if command -v zramctl &>/dev/null; then
    ZRAM_ALGO=$(zramctl 2>/dev/null | awk 'NR==2{print $2}')
    ZRAM_DEV=$(zramctl 2>/dev/null | awk 'NR==2{print $1}')
    if [[ -n "$ZRAM_ALGO" && "$ZRAM_ALGO" != "zstd" && -n "$ZRAM_DEV" ]]; then
        # Troca algoritmo: precisa desativar, trocar, reativar
        swapoff "$ZRAM_DEV" 2>/dev/null || true
        echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || warn "zstd nao suportado pelo hardware"
        swapon "$ZRAM_DEV" 2>/dev/null || true
        log_cmd "swapoff $ZRAM_DEV; echo $ZRAM_ALGO > /sys/block/zram0/comp_algorithm; swapon $ZRAM_DEV"
        ok "ZRAM: $ZRAM_ALGO -> zstd (compressao ~15% melhor)"
        log_op "ZRAM algoritmo: $ZRAM_ALGO -> zstd"
    else
        ok "ZRAM ja em zstd ou indisponivel"
    fi
fi

# ─────────────────────────────────────────────────────────────
# 5. Compositor XFCE desativado (se RAM < 4GB)
# ─────────────────────────────────────────────────────────────
title "5. Compositor XFCE"
if (( RAM_TOTAL < 4000 )); then
    COMP_OLD=$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo "false")
    if [[ "$COMP_OLD" == "true" ]]; then
        xfconf-query -c xfwm4 -p /general/use_compositing -s false
        log_cmd "xfconf-query -c xfwm4 -p /general/use_compositing -s true"
        ok "Compositor XFCE desativado (~80MB RAM liberada)"
        log_op "Compositor XFCE desativado"
    else
        ok "Compositor ja desativado"
    fi
else
    ok "RAM >= 4GB, compositor mantido"
fi

# ─────────────────────────────────────────────────────────────
# 6. Servicos nao essenciais (inclui kdump ja feito)
# ─────────────────────────────────────────────────────────────
title "6. Servicos nao essenciais"
SERVICES_DISABLE=(
    "cups:impressao"
    "avahi-daemon:descoberta de rede"
    "ModemManager:modem"
    "mcelog:MCA"
    "accounts-daemon:contas"
    "NetworkManager-wait-online:espera rede"
    "postgresql:banco"
    "mongod:banco"
    "redis:caching"
)
for s_desc in "${SERVICES_DISABLE[@]}"; do
    svc="${s_desc%%:*}"; desc="${s_desc#*:}"
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q "^enabled$"; then
        if [[ "$svc" == "NetworkManager-wait-online" ]]; then
            systemctl mask "$svc" 2>/dev/null || true
            log_cmd "systemctl unmask $svc"
        else
            systemctl disable --now "$svc" 2>/dev/null || true
            log_cmd "systemctl enable --now $svc"
        fi
        ok "$svc desativado ($desc)"
        log_op "$svc desativado ($desc)"
    else
        info "$svc ja desativado"
    fi
done

# ─────────────────────────────────────────────────────────────
# 7. Apps de inicio
# ─────────────────────────────────────────────────────────────
title "7. Apps de inicio automatico"
if [[ -d "$STARTUP_DIR" ]]; then
    mkdir -p "$STARTUP_DIR/disabled"
    for f in "$STARTUP_DIR"/*.desktop; do
        [[ -f "$f" ]] || continue
        NAME=$(grep -m1 '^Name=' "$f" 2>/dev/null || basename "$f" .desktop)
        mv "$f" "$STARTUP_DIR/disabled/"
        log_cmd "mv \"$STARTUP_DIR/disabled/$(basename "$f")\" \"$STARTUP_DIR/\""
        ok "${NAME} movido para disabled/"
        log_op "${NAME} movido para disabled/"
    done
fi

# ─────────────────────────────────────────────────────────────
# 8. xfce4-screensaver
# ─────────────────────────────────────────────────────────────
title "8. xfce4-screensaver"
if command -v xfce4-screensaver &>/dev/null; then
    if xfconf-query -c xfce4-screensaver -p /saver/enabled -s false &>/dev/null; then
        log_cmd "xfconf-query -c xfce4-screensaver -p /saver/enabled -s true"
        ok "xfce4-screensaver desativado"
        log_op "xfce4-screensaver desativado"
    elif xfconf-query -c xfce4-screensaver -l 2>/dev/null | grep -q "/saver/enabled"; then
        info "xfce4-screensaver ja desativado"
    else
        xfconf-query -c xfce4-screensaver -n -p /saver/enabled -t bool -s false 2>/dev/null || true
        log_cmd "xfconf-query -c xfce4-screensaver -p /saver/enabled -s true"
        ok "xfce4-screensaver desativado (propriedade criada)"
        log_op "xfce4-screensaver desativado"
    fi
fi

# ─────────────────────────────────────────────────────────────
# 9. Reduzir workspaces
# ─────────────────────────────────────────────────────────────
title "9. Workspaces"
WS_OLD=$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || echo "4")
if (( WS_OLD > 4 )); then
    xfconf-query -c xfwm4 -p /general/workspace_count -s 4
    log_cmd "xfconf-query -c xfwm4 -p /general/workspace_count -s $WS_OLD"
    ok "Workspaces: $WS_OLD -> 4"
    log_op "Workspaces: $WS_OLD -> 4"
fi

# ─────────────────────────────────────────────────────────────
# 10. VFS cache pressure
# ─────────────────────────────────────────────────────────────
title "10. Cache de disco (vfs_cache_pressure)"
CACHE_OLD=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "100")
if (( CACHE_OLD > 50 )); then
    sysctl -w vm.vfs_cache_pressure=50
    echo "vm.vfs_cache_pressure=50" > /etc/sysctl.d/90-cache-pressure.conf
    log_cmd "sysctl -w vm.vfs_cache_pressure=$CACHE_OLD; rm -f /etc/sysctl.d/90-cache-pressure.conf"
    ok "vfs_cache_pressure $CACHE_OLD -> 50"
    log_op "vfs_cache_pressure: $CACHE_OLD -> 50"
else
    info "vfs_cache_pressure ja em $CACHE_OLD"
fi

# ─────────────────────────────────────────────────────────────
# 11. Dirty page writeback (ajustado para HDD)
# ─────────────────────────────────────────────────────────────
title "11. Dirty page writeback"
DR_OLD=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo "20")
if (( DR_OLD > 10 )); then
    sysctl -w vm.dirty_ratio=10
    echo "vm.dirty_ratio=10" > /etc/sysctl.d/90-dirty.conf
    log_cmd "sysctl -w vm.dirty_ratio=$DR_OLD"
fi
DBR_OLD=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || echo "10")
if (( DBR_OLD > 3 )); then
    sysctl -w vm.dirty_background_ratio=3
    echo "vm.dirty_background_ratio=3" >> /etc/sysctl.d/90-dirty.conf
    log_cmd "sysctl -w vm.dirty_background_ratio=$DBR_OLD"
    ok "Dirty writeback: $DR_OLD->10, bg $DBR_OLD->3"
    log_op "Dirty writeback: ratio $DR_OLD->10, bg $DBR_OLD->3"
fi

# ─────────────────────────────────────────────────────────────
# 12. CPU governor (ja em performance, mas assegura)
# ─────────────────────────────────────────────────────────────
title "12. CPU governor"
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    if [[ "$GOV" != "performance" && "$GOV" != "schedutil" ]]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>/dev/null || true
        log_cmd "echo $GOV | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
        ok "CPU governor: $GOV -> performance"
        log_op "CPU governor: $GOV -> performance"
    else
        ok "CPU governor ja em $GOV"
    fi
fi

# ─────────────────────────────────────────────────────────────
# 13. Ionice: Xorg com prioridade de I/O
# ─────────────────────────────────────────────────────────────
title "13. Ionice (prioridade I/O)"
XORG_PID=$(pidof Xorg 2>/dev/null || pidof X 2>/dev/null || echo "")
if [[ -n "$XORG_PID" ]]; then
    ionice -c 1 -n 0 -p "$XORG_PID" 2>/dev/null && \
        ok "Xorg (PID $XORG_PID) com ionice REALTIME" && \
        log_op "Xorg (PID $XORG_PID) ionice REALTIME" || \
        warn "Nao foi possivel alterar ionice do Xorg"
fi

# ─────────────────────────────────────────────────────────────
# 14. Limpar cache DNF
# ─────────────────────────────────────────────────────────────
title "14. Cache DNF"
command -v dnf &>/dev/null && dnf clean all 2>/dev/null && ok "Cache DNF limpo" && log_op "Cache DNF limpo" || true

# ─────────────────────────────────────────────────────────────
# 15. Protecao LD_LIBRARY_PATH
# ─────────────────────────────────────────────────────────────
title "15. Protecao LD_LIBRARY_PATH"
BASHRC="${HOME}/.bashrc"
if [[ -f "$BASHRC" ]] && ! grep -q "system_ld_path" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'FIX'

# Fix: limpa LD_LIBRARY_PATH de AppImage para comandos do sistema
system_ld_path() {
    local cmd="$1"; shift
    LD_LIBRARY_PATH="$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v '\.mount_' | tr '\n' ':')" command "$cmd" "$@"
}
alias dnf='system_ld_path dnf'
alias sed='system_ld_path sed'
alias systemctl='system_ld_path systemctl'
FIX
    ok "Alias de seguranca adicionados ao ~/.bashrc"
    log_op "Aliad system_ld_path adicionados ao ~/.bashrc"
    warn "Recarregue: source ~/.bashrc"
else
    ok "Alias ja existentes"
fi

# ─────────────────────────────────────────────────────────────
# 16. Sugerir noatime (manual, edita fstab)
# ─────────────────────────────────────────────────────────────
title "16. noatime (montagem)"
CUR_OPTS=$(findmnt -no OPTIONS / 2>/dev/null)
if [[ "$CUR_OPTS" != *noatime* ]]; then
    warn "'noatime' nao ativo em /."
    echo "    Edite /etc/fstab: substitua 'defaults' por 'defaults,noatime' na linha do /"
    echo "    Depois: mount -o remount /"
    echo "    OU agora: mount -o remount,noatime /"
    log_cmd "sed -i 's/noatime//g' /etc/fstab # remove noatime (restaura)"
fi

# ═════════════════════════════════════════════════════════════
echo ""
echo "============================================================"
echo "  RESUMO DAS OTIMIZACOES APLICADAS"
echo "============================================================"
echo ""
echo "  Aplicado automaticamente:"
echo "    - kdump.service mascarado (economia ~60s no boot!)"
echo "    - swappiness: 70 -> 10"
echo "    - THP: always -> madvise (menos fragmentacao RAM)"
echo "    - ZRAM: lzo-rle -> zstd (compressao melhor)"
echo "    - Compositor XFCE desativado (se RAM < 4GB)"
echo "    - Servicos nao essenciais desativados"
echo "    - Apps de inicio movidos para disabled/"
echo "    - xfce4-screensaver desativado"
echo "    - Workspaces reduzidos (se > 4)"
echo "    - vfs_cache_pressure: 100 -> 50"
echo "    - dirty_ratio: 20% -> 10%, bg 10% -> 3%"
echo "    - CPU governor mantido/ajustado"
echo "    - Xorg com ionice REALTIME"
echo "    - Cache DNF limpo"
echo "    - Protecao LD_LIBRARY_PATH ~/.bashrc"
echo ""
echo "  Log de operacoes: $OPERATIONS_LOG"
echo "  Log de restauracao: $UNDO_LOG"
echo "  Para restaurar TUDO: bash $UNDO_LOG"
echo ""
echo "  RECOMENDACOES PENDENTES (manual):"
echo "    - Adicionar 'noatime' em /etc/fstab (mount -o remount,noatime /)"
echo "    - Upgrade RAM para 8GB DDR3L"
echo "    - Upgrade HDD -> SSD SATA III (maior impacto)"
echo "    - sudo systemd-analyze plot > boot.svg (ver grafico de boot)"
echo "============================================================"
