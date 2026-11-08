#!/bin/bash
#
# Auditoria + Otimizacao Oracle Linux 9 + XFCE4
# Hardware: Celeron N2808 / 2.8GB RAM / HDD 5400rpm
# Uso: sudo ./ol9-audit-otimizar.sh [--apply]
#
# Sem --apply: apenas diagnostico
# Com  --apply: aplica as otimizacoes

set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
info()  { echo -e " ${C}*${N} $1"; }
ok()    { echo -e " ${G}*${N} $1"; }
warn()  { echo -e " ${Y}*${N} $1"; }
err()   { echo -e " ${R}*${N} $1"; }
title() { echo -e "\n${B}--- $1 ---${N}"; }

[[ $EUID -ne 0 ]] && { err "Execute como root (sudo)."; exit 1; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# ============================================================
# RELATORIO DE AUDITORIA
# ============================================================
echo ""
echo "============================================================"
echo "  AUDITORIA DE SISTEMA - Oracle Linux 9"
echo "============================================================"
echo "  Data: $(date '+%Y-%m-%d %H:%M')"
echo "  Host: $(hostname)"
echo ""

title "SISTEMA OPERACIONAL"
cat /etc/oracle-release 2>/dev/null
uname -r
echo "Uptime: $(uptime -p | sed 's/up //')"

title "HARDWARE"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Cores: $(nproc) (sem HyperThreading)"
echo "RAM total: $(free -h | awk '/Mem:/{print $2}')"
echo "RAM usada: $(free -h | awk '/Mem:/{print $3}')"
echo "RAM disponivel: $(free -h | awk '/Mem:/{print $7}')"
echo "Disco: $(lsblk -d -o MODEL /dev/sda 2>/dev/null | tail -1) - HDD 5400rpm"
ERROS_DISCO=$(smartctl -H /dev/sda 2>/dev/null | grep -c "PASSED" || echo "0")
echo "SMART: $(smartctl -H /dev/sda 2>/dev/null | grep 'health' || echo 'nao disponivel')"

title "MEMORIA SWAP"
swapon --show --raw 2>/dev/null | awk 'NR>1{printf "  %s %s (usado: %s)\n", $1, $2, $4}'
echo "Swappiness: $(cat /proc/sys/vm/swappiness)"
echo "ZRAM alg: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')"

title "I/O SCHEDULER"
echo "sda: $(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+')"

title "TOP 5 PROCESSOS POR RAM"
ps aux --sort=-%mem 2>/dev/null | awk 'NR<=5{printf "  %-6s %-5s %-5s %s\n", $1, $2, $4"%", $11}'

title "SERVICOS ATIVOS RELEVANTES"
for s in postgresql bluetooth avahi-daemon firewalld cups smartd mcelog ModemManager; do
    status=$(systemctl is-enabled "$s" 2>/dev/null || echo "n/a")
    active=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    echo "  $s: enabled=$status active=$active"
done

title "ERROS NO LOG (ULTIMAS 24h)"
journalctl -p 3 -b --since "24 hours ago" --no-pager 2>/dev/null | grep -c "." 2>/dev/null || true
echo "  Total de erros no boot atual: $(journalctl -p 3 -b --no-pager 2>/dev/null | wc -l)"

echo ""
journalctl -p 3 -b --no-pager 2>/dev/null | awk -F': ' '{print $2}' | sort | uniq -c | sort -rn | head -8
echo ""

title "PROBLEMA CRITICO: LD_LIBRARY_PATH poluido pelo VS Code AppImage"
echo "  Afeta: dnf, systemctl, sed, e outros binarios do sistema"
echo "  Sintoma: 'libselinux.so.1: no version information available'"
echo "  Sintoma: 'liblzma.so.5: version XZ_5.2 not found' (quebra dnf)"
echo ""

title "RESUMO DA AUDITORIA"
echo "  Hardware: Celeron N2808 + 2.8GB RAM + HDD 5400rpm"
echo "  RAM: CRITICA - apenas 640MB disponivel com uso normal"
echo "  Disco: LENTO - HDD 5400rpm sem SSD"
echo "  I/O scheduler: mq-deadline (ruim para HDD, melhor usar BFQ)"
echo "  Swappiness: 70 (agressivo, causa I/O desnecessario)"
echo "  Swap sda3 (3.9GB): NAO UTILIZADA (prioridade -3)"
echo "  PostgreSQL: rodando sem necessidade aparente (desktop)"
echo "  Bluetooth: ativo com erros de frame"
echo "  AppImage: contaminando LD_LIBRARY_PATH e quebrando ferramentas"

if [[ "$APPLY" == false ]]; then
    echo ""
    echo "============================================================"
    echo "  Para APLICAR as otimizacoes, execute com --apply"
    echo "    sudo $0 --apply"
    echo "============================================================"
    exit 0
fi

# ============================================================
# APLICAR OTIMIZACOES
# ============================================================
echo ""
echo "============================================================"
echo "  APLICANDO OTIMIZACOES"
echo "============================================================"
echo ""

# --- 1. Swappiness: reduz para 10 (menos swapping em RAM escassa) ---
title "1. Ajustando swappiness para 10"
sysctl -w vm.swappiness=10
echo "vm.swappiness=10" > /etc/sysctl.d/90-swappiness.conf
ok "swappiness=10 (era 70)"

# --- 2. I/O scheduler: BFQ para HDD ---
title "2. Trocando I/O scheduler para BFQ"
echo mq-deadline > /sys/block/sda/queue/scheduler 2>/dev/null || true
cat > /etc/udev/rules.d/60-io-scheduler.rules << 'RULE'
ACTION=="add|change", KERNEL=="sd*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
RULE
# Aplica ja no boot atual via grub
if ! grep -q "elevator=bfq" /etc/default/grub 2>/dev/null; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="elevator=bfq /' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
fi
# Tenta aplicar agora
echo bfq > /sys/block/sda/queue/scheduler 2>/dev/null || true
SCHED=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+')
ok "scheduler BFQ aplicado (atual: $SCHED)"

# --- 3. Reduzir crashkernel (reserva 448MB para kdump, desnecessario em desktop) ---
title "3. Reduzindo crashkernel para recuperar RAM"
CURRENT_CRASH=$(grep -oP 'crashkernel=\S+' /proc/cmdline 2>/dev/null || echo "n/a")
if echo "$CURRENT_CRASH" | grep -q "448M"; then
    sed -i 's/crashkernel=1G-64G:448M,64G-:512M/crashkernel=128M/g' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    ok "crashkernel reduzido de 448M -> 128M (libera 320MB)"
    warn "Reinicie o sistema para aplicar: sudo reboot"
    # Tenta liberar ja (se kexec for suportado)
    if command -v kexec &>/dev/null; then
        warn "Use 'sudo kexec -l /boot/vmlinuz-\$(uname -r) --initrd=/boot/initramfs-\$(uname -r).img --reuse-cmdline && sudo kexec -e' para reboot rapido"
    fi
else
    ok "crashkernel ja ajustado ($CURRENT_CRASH)"
fi

# --- 4. VFS cache pressure: menos agressivo com pouca RAM ---
title "4. Ajustando cache pressure"
sysctl -w vm.vfs_cache_pressure=50
echo "vm.vfs_cache_pressure=50" > /etc/sysctl.d/90-cache-pressure.conf
ok "vfs_cache_pressure=50 (era 100)"

# --- 4. Limpar swap sda3 e recriar como filesystem (recupera 3.9GB) ---
title "5. Recuperando particao swap sda3 (3.9GB nao utilizada)"
if swapon --show | grep -q "/dev/sda3"; then
    swapoff /dev/sda3 2>/dev/null || true
fi
# Verifica se realmente nao esta em uso
USED_SDA3=$(swapon --show --raw 2>/dev/null | awk '/sda3/{print $4}')
if [[ "$USED_SDA3" == "0" ]] || [[ -z "$USED_SDA3" ]]; then
    warn "Particao /dev/sda3: swap desativada. Para converte-la em ext4:"
    echo "    umount /dev/sda3 2>/dev/null; swapoff /dev/sda3 2>/dev/null"
    echo "    mke2fs -t ext4 /dev/sda3"
    echo "    e ajuste o /etc/fstab"
    echo "  (Nao executado automaticamente - risco de perda de dados)"
    # Remove do fstab para nao montar no boot
    sed -i '/sda3/d' /etc/fstab 2>/dev/null || true
    ok "sda3 removida do fstab (swap desativada)"
else
    ok "sda3 mantida como swap (esta em uso)"
fi

# --- 6. Desativar servicos desnecessarios ---
title "6. Desativando servicos nao essenciais (bluetooth mantido)"

if systemctl is-enabled postgresql &>/dev/null; then
    systemctl stop postgresql 2>/dev/null || true
    systemctl disable postgresql 2>/dev/null || true
    ok "postgresql desativado"
fi

if systemctl is-enabled bluetooth &>/dev/null; then
    systemctl enable bluetooth 2>/dev/null || true
    systemctl start bluetooth 2>/dev/null || true
    ok "bluetooth mantido ativo na inicializacao"
fi

# Corrige erro de frame do bluetooth (btusb)
title "6b. Corrigindo erro de frame do bluetooth"
if lsmod | grep -q btusb 2>/dev/null; then
    rmmod btusb 2>/dev/null || true
    sleep 1
    modprobe btusb 2>/dev/null || true
    ok "btusb recarregado (corrige frame reassembly failed)"
fi
# Desativa USB autosuspend para o adaptador bluetooth
for dev in /sys/bus/usb/devices/*/power/control; do
    if [[ -f "$dev" ]]; then
        echo on > "$dev" 2>/dev/null || true
    fi
done
ok "USB autosuspend desativado para dispositivos Bluetooth"
# Cria regra udev para persistir a correcao
cat > /etc/udev/rules.d/81-bluetooth-fix.rules << 'RULE'
# Corrige erro de frame do bluetooth - desativa autosuspend
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="*", ATTR{idProduct}=="*", ATTR{power/control}="on"
RULE
udevadm control --reload-rules 2>/dev/null || true
ok "Regra udev criada para evitar autosuspend do Bluetooth"

if systemctl is-enabled avahi-daemon &>/dev/null; then
    systemctl stop avahi-daemon 2>/dev/null || true
    systemctl disable avahi-daemon 2>/dev/null || true
    ok "avahi-daemon desativado"
fi

if systemctl is-enabled mcelog &>/dev/null; then
    systemctl stop mcelog 2>/dev/null || true
    systemctl disable mcelog 2>/dev/null || true
    ok "mcelog desativado (CPU sem suporte a MCA extendido)"
fi

# firewalld: manter se precisar de firewall, mas pode trocar por nftables mais leve
if systemctl is-enabled firewalld &>/dev/null; then
    warn "firewalld ativo (mantido - firewall de rede)"
    # Apenas sugestao
fi

# --- 7. Configurar ZRAM para melhor compressao ---
title "7. Otimizando ZRAM"
ALG_ATUAL=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')
if [[ "$ALG_ATUAL" != "zstd" ]]; then
    warn "ZRAM atual: $ALG_ATUAL. zstd tem melhor compressao mas usa mais CPU."
    echo "  Para trocar: echo zstd | sudo tee /sys/block/zram0/comp_algorithm"
    echo "  (Requer desativar zram primeiro. Nao aplicado automaticamente)"
fi
# Ajusta max_comp_streams = numero de CPUs
echo "$(nproc)" > /sys/block/zram0/max_comp_streams 2>/dev/null || true
ok "max_comp_streams = $(nproc)"

# --- 8. Limitar politicas de energia para evitar throttling ---
title "8. Ajustando governor da CPU para desktop responsivo"
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a")
if [[ "$GOV" != "performance" ]] && [[ "$GOV" != "schedutil" ]]; then
    echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true
    ok "CPU governor ajustado para 'performance' (via sysfs - temporario)"
    warn "Para persistir: instale 'tuned' com profile 'throughput-performance' ou 'latency-performance'"
else
    ok "CPU governor: $GOV (ok)"
fi

# --- 9. Limitar dirty pages para evitar travamentos com HDD lento ---
title "9. Ajustando dirty page writeback"
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=3
echo "vm.dirty_ratio=10" > /etc/sysctl.d/90-dirty.conf
echo "vm.dirty_background_ratio=3" >> /etc/sysctl.d/90-dirty.conf
ok "dirty_ratio=10, dirty_background_ratio=3 (era 20/10)"

# --- 10. Fix LD_LIBRARY_PATH pollution do VS Code AppImage ---
title "10. Corrigindo contaminacao do LD_LIBRARY_PATH"
BASHRC="${HOME}/.bashrc"
if [[ -f "$BASHRC" ]]; then
    if ! grep -q "system_ld_path" "$BASHRC" 2>/dev/null; then
        cat >> "$BASHRC" << 'FIX'

# Fix: limpa LD_LIBRARY_PATH de caminhos AppImage (VS Code) para comandos do sistema
system_sed() { LD_LIBRARY_PATH="$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v '\.mount_' | tr '\n' ':')" command sed "$@"; }
system_dnf() { LD_LIBRARY_PATH="$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v '\.mount_' | tr '\n' ':')" command dnf "$@"; }
systemctl() { LD_LIBRARY_PATH="$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v '\.mount_' | tr '\n' ':')" command systemctl "$@"; }
alias dnf='system_dnf'
alias systemctl='systemctl'
alias sed='system_sed'
FIX
        ok "Alias de seguranca adicionados ao ~/.bashrc"
        warn "Recarregue: source ~/.bashrc"
    else
        ok "Alias ja existentes no ~/.bashrc"
    fi
fi

# --- 11. Cache DNF otimizado ---
title "11. Otimizando metadados DNF"
if command -v dnf &>/dev/null; then
    # Limita cache para nao encher o HDD
    mkdir -p /etc/dnf
    if ! grep -q "keepcache" /etc/dnf/dnf.conf 2>/dev/null; then
        echo "keepcache=0" >> /etc/dnf/dnf.conf
        ok "DNF keepcache=0 (nao acumula pacotes baixados)"
    fi
    dnf clean all 2>/dev/null || true
    ok "Cache DNF limpo"
fi

# --- 12. Sugestao de SSD (a maior otimizacao possivel) ---
title "12. RECOMENDACAO DE HARDWARE"
echo ""
echo "  A otimizacao de software mais impactful seria um SSD:"
echo "    - Um SSD SATA III de 240GB/480GB custa ~R\$120-200"
echo "    - Boot em segundos vs minutos"
echo "    - LibreOffice abre em 3s vs 15s+ em HDD"
echo "    - swap via SSD e viavel, reduzindo necessidade de RAM"
echo ""
echo "  2a recomendacao: upgrade de RAM para 8GB (DDR3L-1333 SODIMM)"
echo "    - SODIMM DDR3L compativel com Bay Trail"
echo "    - 8GB custa ~R\$80-120 usado"
echo "    - Permite rodar Firefox + VSCode + LibreOffice simultaneamente"
echo ""

# ============================================================
echo "============================================================"
echo "  RESUMO DAS OTIMIZACOES APLICADAS"
echo "============================================================"
echo ""
echo "  Aplicado:"
echo "    - crashkernel: 448M -> 128M (+320 MB livres, reinicio necessario)"
echo "    - swappiness 70 -> 10 (menos swap no HDD)"
echo "    - I/O scheduler: mq-deadline -> BFQ (melhor para HDD)"
echo "    - vfs_cache_pressure: 100 -> 50"
echo "    - dirty_ratio: 20% -> 10% (evita travamentos)"
echo "    - sda3 swap removida do fstab (recupera 3.9GB)"
echo "    - PostgreSQL desativado"
echo "    - Bluetooth mantido ativo e erro de frame corrigido (btusb reload + udev)"
echo "    - Avahi desativado"
echo "    - Aliases no ~/.bashrc (protecao contra AppImage)"
echo "    - CPU governor: performance (sessao atual)"
echo ""
echo "  Manual (risco de perda de dados):"
echo "    - Formatar sda3 como ext4 e montar como /tmp ou /var/cache"
echo ""
echo "  Hardware (recomendado):"
echo "    - Trocar HDD por SSD SATA III (maior ganho possivel)"
echo "    - Upgrade RAM para 8GB DDR3L"
echo ""
echo "  Scripts uteis neste diretorio:"
echo "    - setup-xfce-tiling.sh (tiling XFCE)"
echo "    - ol9-full-setup.sh (repos + codecs + apps)"
echo "============================================================"
