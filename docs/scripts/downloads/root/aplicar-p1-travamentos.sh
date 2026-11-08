#!/usr/bin/env bash
# =============================================================================
# aplicar-p1-travamentos.sh
# Ajustes P1 da auditoria de travamentos — Positivo DH8BT11TV / OL9 / UEK 6.12
#
# O que faz:
#   1. remove a reserva de crashkernel (somente se o kdump estiver desligado)
#   2. aumenta o zram de 1 GiB para 2 GiB
#   3. desativa o swap no HDD (opcional: --keep-hdd-swap)
#   4. troca o agendador de I/O do sda para BFQ
#   5. aplica sysctl de resposta (dirty_ratio, page-cluster, swappiness)
#   6. coloca Transparent Huge Pages em madvise
#   7. habilita o bool SELinux selinuxuser_execmod (elimina o AVC do llamafile)
#   8. opcional: mascara o setroubleshootd (--mask-setroubleshoot)
#
# Uso:
#   ./aplicar-p1-travamentos.sh                        # simulação (não altera nada)
#   sudo ./aplicar-p1-travamentos.sh --apply           # aplica
#   sudo ./aplicar-p1-travamentos.sh --apply --keep-hdd-swap
#   sudo ./aplicar-p1-travamentos.sh --apply --mask-setroubleshoot
#
# Segurança:
#   - idempotente: pode rodar de novo sem duplicar nada
#   - backup dos arquivos alterados em /var/backups/travamentos-<data>/
#   - não reinicia a máquina sozinho
#   - não remove crashkernel se o kdump estiver ativo
#   - não desativa o swap do HDD se ele estiver em uso (a menos que --force)
# =============================================================================

set -Eeuo pipefail

APPLY=0
KEEP_HDD_SWAP=0
MASK_SETROUBLESHOOT=0
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --apply)               APPLY=1 ;;
        --keep-hdd-swap)       KEEP_HDD_SWAP=1 ;;
        --mask-setroubleshoot) MASK_SETROUBLESHOOT=1 ;;
        --force)               FORCE=1 ;;
        -h|--help)             sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opção desconhecida: $arg (use --help)" >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '   \033[1;33mAVISO\033[0m  %s\n' "$*" >&2; }
skip() { printf '   \033[0;37m--  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

do_it() {
    printf '   + %s\n' "$*"
    [ "$APPLY" -eq 1 ] && "$@"
    return 0
}

TS="$(date +%Y%m%d-%H%M%S)"
BK="/var/backups/travamentos-$TS"

backup() {
    local f="$1"
    [ -f "$f" ] || return 0
    if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$BK"
        cp -a "$f" "$BK/$(basename "$f").$TS"
    fi
}

if [ "$APPLY" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Precisa de root; reexecutando com sudo..."
    exec sudo -E "$(readlink -f "$0")" "$@"
fi

[ -d /run/systemd/system ] || die "este script assume systemd."

if [ "$APPLY" -eq 0 ]; then
    printf '\033[1;33mMODO SIMULAÇÃO\033[0m — nada será alterado. Use --apply para valer.\n'
else
    printf '\033[1;32mMODO APLICAÇÃO\033[0m — backups em %s\n' "$BK"
fi

# -----------------------------------------------------------------------------
# 1. crashkernel (kdump desligado)
# -----------------------------------------------------------------------------
say "1/7 crashkernel"
if grep -q 'crashkernel=' /proc/cmdline; then
    if systemctl is-active --quiet kdump 2>/dev/null; then
        warn "kdump está ATIVO; não vou remover o crashkernel. Desative o kdump antes, se quiser o ganho."
    else
        CK="$(tr ' ' '\n' < /proc/cmdline | grep '^crashkernel=' | head -1)"
        ok "kdump desligado; removendo '$CK' (~448 MiB de RAM a recuperar)"
        backup /etc/default/grub
        backup /etc/kernel/cmdline
        # usa só a chave: o valor tem vírgula e o grubby trata --remove-args como lista
        do_it grubby --update-kernel=ALL --remove-args="crashkernel"
        if [ -f /etc/default/grub ]; then
            do_it sed -i -E 's/[[:space:]]*crashkernel=[^"[:space:]]*//g' /etc/default/grub
        fi
        if [ -f /etc/kernel/cmdline ]; then
            do_it sed -i -E 's/[[:space:]]*crashkernel=[^[:space:]]*//g' /etc/kernel/cmdline
        fi
        if [ "$APPLY" -eq 1 ]; then
            TMPG="$(mktemp)"
            if ! grubby --info=ALL >"$TMPG" 2>/dev/null || [ ! -s "$TMPG" ]; then
                warn "não consegui ler as entradas do grubby; confira manualmente após o reboot"
            elif grep -q 'crashkernel=' "$TMPG"; then
                warn "ainda há crashkernel em alguma entrada; confira: grubby --info=ALL | grep args"
            else
                ok "crashkernel removido das entradas de boot"
            fi
            rm -f "$TMPG"
        fi
    fi
else
    ok "já não há crashkernel na linha de comando"
fi

# -----------------------------------------------------------------------------
# 2. zram 1G -> 2G
# -----------------------------------------------------------------------------
say "2/7 zram"
UNIT=/etc/systemd/system/zram-swap.service
if [ ! -f "$UNIT" ]; then
    warn "$UNIT não existe; pulando (confira como o zram é criado nesta máquina)"
elif grep -q 'echo 1G > /sys/block/zram0/disksize' "$UNIT"; then
    backup "$UNIT"
    ok "zram: 1 GiB -> 2 GiB (efetivo no próximo boot)"
    do_it sed -i 's|echo 1G > /sys/block/zram0/disksize|echo 2G > /sys/block/zram0/disksize|' "$UNIT"
    do_it sed -i 's/ZRAM swap (1G/ZRAM swap (2G/' "$UNIT"
    do_it systemctl daemon-reload
else
    ok "zram já configurado para 2 GiB (ou tamanho diferente); nada a fazer"
fi

# -----------------------------------------------------------------------------
# 3. swap no HDD
# -----------------------------------------------------------------------------
say "3/7 swap do HDD (/dev/sda3)"
if [ "$KEEP_HDD_SWAP" -eq 1 ]; then
    skip "mantido por --keep-hdd-swap (swappiness ficará em 60)"
elif ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/dev/sda3'; then
    ok "swap do HDD já está desativado"
elif ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/dev/zram0'; then
    warn "o zram não está ativo; NÃO vou desativar o swap do HDD (evita OOM)"
else
    USED_BYTES="$(swapon --show=NAME,USED --noheadings --bytes --raw 2>/dev/null \
                  | awk '$1=="/dev/sda3"{print $2}' | tr -dc '0-9')"
    USED_BYTES="${USED_BYTES:-0}"
    if [ "$USED_BYTES" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
        warn "há $((USED_BYTES / 1048576)) MiB em uso no swap do HDD; não vou mexer (use --force para forçar)"
    else
        ok "desativando e mascarando o swap do HDD (zram fica como único swap)"
        do_it swapoff /dev/sda3
        do_it systemctl mask dev-sda3.swap
        if [ "$APPLY" -eq 1 ] && swapon --show=NAME --noheadings | grep -qx '/dev/sda3'; then
            warn "ainda ativo; mascare também a unit por UUID: systemctl list-units --type=swap"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 4. BFQ no sda
# -----------------------------------------------------------------------------
say "4/7 agendador de I/O (BFQ)"
if [ ! -e /sys/block/sda/queue/scheduler ]; then
    warn "/sys/block/sda não encontrado; pulando"
elif grep -qw bfq /sys/block/sda/queue/scheduler; then
    if [ "$(cat /sys/block/sda/queue/scheduler | sed 's/.*\[\(.*\)\].*/\1/')" = bfq ]; then
        ok "BFQ já está ativo"
    else
        ok "ativando BFQ agora"
        do_it sh -c 'echo bfq > /sys/block/sda/queue/scheduler'
    fi
    backup /etc/udev/rules.d/60-sda-bfq.rules
    do_it sh -c 'printf "%s\n" "ACTION==\"add|change\", KERNEL==\"sda\", ATTR{queue/scheduler}=\"bfq\"" > /etc/udev/rules.d/60-sda-bfq.rules'
    do_it udevadm control --reload-rules
    do_it udevadm trigger --name-match=sda
else
    warn "BFQ não disponível neste kernel; mantendo o agendador atual"
fi

# -----------------------------------------------------------------------------
# 5. sysctl
# -----------------------------------------------------------------------------
say "5/7 sysctl de resposta"
SWAPPINESS=100
[ "$KEEP_HDD_SWAP" -eq 1 ] && SWAPPINESS=60
SYSCTL_FILE=/etc/sysctl.d/99-resposta.conf
ok "escrevendo $SYSCTL_FILE (swappiness=$SWAPPINESS)"
backup "$SYSCTL_FILE"
if [ "$APPLY" -eq 1 ]; then
    cat > "$SYSCTL_FILE" <<EOF
# Auditoria de travamentos — 24/10/2026
# swappiness alto só vale com zram como único swap (swap no HDD desativado)
vm.swappiness=$SWAPPINESS
vm.dirty_ratio=10
vm.dirty_background_ratio=3
vm.page-cluster=0
vm.min_free_kbytes=98304
EOF
    sysctl --system >/dev/null
else
    printf '   + escrever %s\n' "$SYSCTL_FILE"
fi

# -----------------------------------------------------------------------------
# 6. Transparent Huge Pages
# -----------------------------------------------------------------------------
say "6/7 Transparent Huge Pages"
THP=/sys/kernel/mm/transparent_hugepage/enabled
if [ -f "$THP" ]; then
    if grep -q '\[madvise\]' "$THP"; then
        ok "THP já está em madvise"
    else
        ok "THP: always -> madvise"
        do_it sh -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled'
    fi
fi
if ! grep -q 'transparent_hugepage=' /proc/cmdline; then
    ok "persistindo via kernel cmdline (próximo boot)"
    do_it grubby --update-kernel=ALL --args="transparent_hugepage=madvise" >/dev/null
else
    skip "já há transparent_hugepage= na cmdline"
fi

# -----------------------------------------------------------------------------
# 7. SELinux execmod + setroubleshoot
# -----------------------------------------------------------------------------
say "7/7 SELinux"
if command -v getsebool >/dev/null 2>&1; then
    if getsebool selinuxuser_execmod 2>/dev/null | grep -q -- '--> on'; then
        ok "selinuxuser_execmod já está on"
    else
        ok "habilitando selinuxuser_execmod (elimina o AVC a cada start do llamafile)"
        do_it setsebool -P selinuxuser_execmod on
    fi
else
    warn "getsebool não encontrado; pulando"
fi
if [ "$MASK_SETROUBLESHOOT" -eq 1 ]; then
    ok "mascarando setroubleshootd (não abre o notificador a cada negação)"
    do_it systemctl mask --now setroubleshootd.service
fi

# -----------------------------------------------------------------------------
# resumo
# -----------------------------------------------------------------------------
say "resumo"
if [ "$APPLY" -eq 0 ]; then
    echo "   Simulação concluída. Para aplicar:  sudo $0 --apply"
else
    echo "   Aplicado. Backup em: $BK"
    echo
    echo "   REINICIE para valer:  sudo reboot"
    echo
    echo "   Depois do boot, confira:"
    echo "     free -m                      # MemTotal deve ter subido ~448 MB"
    echo "     swapon --show                # deve listar só /dev/zram0 (2G)"
    echo "     cat /sys/block/sda/queue/scheduler   # deve mostrar [bfq]"
    echo "     cat /sys/kernel/mm/transparent_hugepage/enabled  # [madvise]"
    echo "     cat /proc/pressure/io        # full deve ficar < 10%"
    echo
    echo "   Saúde do HDD (recomendado):"
    echo "     sudo dnf install -y smartmontools"
    echo "     sudo smartctl -a /dev/sda | grep -Ei 'Reallocated|Pending|Uncorrectable|Power_On|Temperature'"
fi
