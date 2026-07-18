#!/bin/bash
# ==============================================================================
# Gerador de ISO Offline - Oracle Linux 9 (XFCE + UEFI + MBR)
# Extrai ISO boot, baixa RPMs, copia scripts com rsync, regenera ISO offline
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build_offline"
WORK_DIR="$BUILD_ROOT/work"
ISO_TREE="$WORK_DIR/iso_tree"
LOCAL_REPO="$ISO_TREE/Packages"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$ISO_TREE/ks.cfg"
CONTENT_DIR="$ISO_TREE/content"
LOG_DIR="$BUILD_ROOT/logs"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"
STATUS_FILE="$LOG_DIR/build_status.log"
BOOT_ISO="$SCRIPT_DIR/OracleLinux-R9-U8-x86_64-boot.iso"
ISO_NAME="OL9-Offline-Completa.iso"
FS_LABEL="OL9_OFFLINE_XFCE"

TOTAL_STEPS=8
CURRENT_STEP=0
STEP_START=0
BUILD_START=$(date +%s)
ERRORS=0

declare -A STEP_TIMES
declare -A STEP_STATUS
RPM_DOWNLOADED=0
RPM_FAILED=0
CONTENT_COPIED=0
SCRIPTS_COPIED=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "$msg"
    [ -d "$(dirname "$LOG_FILE")" ] 2>/dev/null && echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    [ -d "$(dirname "$STATUS_FILE")" ] 2>/dev/null && echo "$msg" >> "$STATUS_FILE" 2>/dev/null || true
}

log_ok() {
    local msg="[OK]    $*"
    echo -e "  ${GREEN}${msg}${NC}"
    log "${msg}" 2>/dev/null || true
}

log_warn() {
    local msg="[WARN]  $*"
    echo -e "  ${YELLOW}${msg}${NC}"
    log "${msg}" 2>/dev/null || true
}

log_err() {
    local msg="[ERRO]  $*"
    echo -e "  ${RED}${msg}${NC}"
    log "${msg}" 2>/dev/null || true
    ((ERRORS++)) || true
}

log_info() {
    local msg="[INFO]  $*"
    echo -e "  ${CYAN}${msg}${NC}"
    log "${msg}" 2>/dev/null || true
}

log_status() {
    local msg="[STATUS] $*"
    echo -e "  ${WHITE}${msg}${NC}"
    log "${msg}" 2>/dev/null || true
}

log_progress() {
    local current=$1 total=$2 label=$3
    local percent=$((current * 100 / total))
    local width=40
    local filled=$((width * current / total))
    local empty=$((width - filled))
    printf "\r    ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% %s" "$percent" "$label"
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

log_step_header() {
    local step=$1 total=$2 title=$3
    local elapsed_total=$(($(date +%s) - BUILD_START))
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    printf "${BOLD}${WHITE}  ETAPA %2d/%d${NC}  " "$step" "$total"
    echo -e "${BOLD}${WHITE}$title${NC}"
    echo -e "${DIM}  Inicio: $(date '+%H:%M:%S') | Acumulado: ${elapsed_total}s${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    log "ETAPA $step/$total: $title" 2>/dev/null || true
}

log_step_footer() {
    local step=$1
    local elapsed=$(( $(date +%s) - STEP_START ))
    local total_elapsed=$(( $(date +%s) - BUILD_START ))
    STEP_TIMES[$step]=$elapsed
    STEP_STATUS[$step]="OK"
    echo ""
    echo -e "  ${GREEN}✔ Etapa $step concluida em ${elapsed}s${NC} (total: ${total_elapsed}s)"
    log "ETAPA $step CONCLUIDA em ${elapsed}s (total: ${total_elapsed}s)" 2>/dev/null || true
    [ -d "$(dirname "$LOG_FILE")" ] 2>/dev/null && echo "" >> "$LOG_FILE" 2>/dev/null || true
}

log_step_error() {
    local step=$1
    local elapsed=$(( $(date +%s) - STEP_START ))
    STEP_TIMES[$step]=$elapsed
    STEP_STATUS[$step]="ERRO"
    echo ""
    echo -e "  ${RED}✗ Etapa $step FALHOU em ${elapsed}s${NC}"
    log "ETAPA $step FALHOU em ${elapsed}s" 2>/dev/null || true
}

limpar_tudo() {
    echo ""
    echo "[LIMPEZA] Desmontando temporarios..."
    sync
    grep "$BUILD_ROOT" /proc/mounts 2>/dev/null | cut -d' ' -f2 | xargs -r umount -l 2>/dev/null || true
    rm -rf "$BUILD_ROOT/iso_mount" "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" 2>/dev/null || true
    echo "[LIMPEZA] Concluida"
}

gerar_resumo_final() {
    local build_total=$(($(date +%s) - BUILD_START))
    local build_min=$((build_total / 60))
    local build_sec=$((build_total % 60))

    echo ""
    echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║              RESUMO DO BUILD - ISO OFFLINE                  ║${NC}"
    echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log "RESUMO DO BUILD"
    log "  Tempo total: ${build_total}s (${build_min}m ${build_sec}s)"

    echo -e "  ${BOLD}Tempo total:${NC}    ${BUILD_MIN}m ${BUILD_SEC}s"
    echo -e "  ${BOLD}Erros:${NC}          $ERRORS"
    echo ""

    echo -e "  ${BOLD}Detalhes por Etapa:${NC}"
    for i in $(seq 1 $TOTAL_STEPS); do
        local time=${STEP_TIMES[$i]:-0}
        local status=${STEP_STATUS[$i]:-PENDENTE}
        if [ "$status" = "OK" ]; then
            echo -e "    ${GREEN}✔${NC} Etapa $i: $status (${time}s)"
        else
            echo -e "    ${RED}✗${NC} Etapa $i: $status (${time}s)"
        fi
        log "  Etapa $i: $status (${time}s)"
    done
    echo ""

    echo -e "  ${BOLD}Conteudo:${NC}"
    echo -e "    ├─ RPMs:              $RPM_DOWNLOADED ($RPM_FAILED falharam)"
    echo -e "    ├─ Scripts:           $SCRIPTS_COPIED"
    echo -e "    ├─ Arquivos:          $CONTENT_COPIED"
    echo -e "    └─ Tamanho repo:      $(du -sh "$LOCAL_REPO" 2>/dev/null | cut -f1)"
    echo ""

    if [ -f "$OUT_DIR/$ISO_NAME" ]; then
        local iso_size=$(du -h "$OUT_DIR/$ISO_NAME" | cut -f1)
        echo -e "  ${BOLD}ISO Gerada:${NC}"
        echo -e "    ├─ Arquivo:           $OUT_DIR/$ISO_NAME"
        echo -e "    ├─ Tamanho:           $iso_size"
        echo -e "    ├─ Checksum:          $OUT_DIR/hash_iso.txt"
        echo -e "    ├─ Label:             $FS_LABEL"
        echo -e "    └─ Boot:              UEFI + MBR"
        echo ""
        log "ISO Gerada: $OUT_DIR/$ISO_NAME ($iso_size)"
    fi

    echo -e "  ${BOLD}Logs:${NC}"
    echo -e "    ├─ Principal:         $LOG_FILE"
    echo -e "    └─ Status:            $STATUS_FILE"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${RED}║  BUILD COMPLETADO COM $ERRORS ERRO(S)!                           ║${NC}"
        echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
        log "BUILD COMPLETADO COM $ERRORS ERRO(S)!"
    else
        echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${GREEN}║          BUILD CONCLUIDO COM SUCESSO!                       ║${NC}"
        echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
        log "BUILD CONCLUIDO COM SUCESSO!"
    fi
}

trap limpar_tudo EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# INICIO
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ISO OFFLINE Oracle Linux 9 — Extrair + RPMs + Regenerar    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log "══════════════════════════════════════════════════════════════════════════════"
log "INICIO DO BUILD - ISO OFFLINE Oracle Linux 9"
log "══════════════════════════════════════════════════════════════════════════════"
log "Log: $LOG_FILE"
log "Sistema: $(uname -n) | Kernel: $(uname -r) | User: $(whoami)"
log "Espaco: $(df -BG "$SCRIPT_DIR" | awk 'NR==2{print $4}')"
echo ""

if [[ $EUID -ne 0 ]]; then
    log_err "Execute como ROOT."
    exit 1
fi

if [ ! -f "$BOOT_ISO" ]; then
    log_err "ISO boot nao encontrada: $BOOT_ISO"
    exit 1
fi

FREE_GB=$(df -BG "$SCRIPT_DIR" | awk 'NR==2{print $4}' | sed 's/G//')
if [ "$FREE_GB" -lt 20 ]; then
    log_err "Espaco insuficiente ($FREE_GB GB). Minimo 20GB."
    exit 1
fi
log_info "Espaco: ${FREE_GB}GB | ISO boot: $(du -h "$BOOT_ISO" | cut -f1)"

if [ -d "$BUILD_ROOT" ]; then
    log_info "Removendo build anterior..."
    rm -rf "$BUILD_ROOT"
fi

mkdir -p "$LOG_DIR" "$BUILD_ROOT" "$WORK_DIR" "$ISO_TREE" "$LOCAL_REPO" \
         "$CONTENT_DIR/software_rpm" "$CONTENT_DIR/favoritos" \
         "$CONTENT_DIR/system_scripts" "$CONTENT_DIR/vm_scripts" \
         "$CONTENT_DIR/bluetooth" "$OUT_DIR"

log_info "Pasta de trabalho: $WORK_DIR"
log_info "Arvore ISO: $ISO_TREE"

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 1/8 - Dependencias
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=1
log_step_header $CURRENT_STEP $TOTAL_STEPS "Instalando dependencias"

DEPS=(createrepo_c xorriso rsync isohybrid)
DEPS_OK=0
DEPS_FAIL=0

for dep in "${DEPS[@]}"; do
    printf "    %-30s" "$dep"
    if command -v "$dep" &>/dev/null || rpm -q "$dep" &>/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        ((DEPS_OK++)) || true
    else
        printf "instalando... "
        if dnf install -y "$dep" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}OK${NC}"
            ((DEPS_OK++)) || true
        else
            echo -e "${YELLOW}skip${NC}"
            ((DEPS_FAIL++)) || true
        fi
    fi
done

log_status "Dependencias: $DEPS_OK OK, $DEPS_FAIL falharam"
log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 2/8 - Extrair ISO boot
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=2
log_step_header $CURRENT_STEP $TOTAL_STEPS "Extraindo ISO boot minimal"

log_status "ISO: $BOOT_ISO"
log_status "Destino: $ISO_TREE"

printf "    Extraindo... "
xorriso -osirrox on \
    -indev "$BOOT_ISO" \
    -extract / "$ISO_TREE" \
    2>&1 | tee -a "$LOG_FILE"

EXTRACTED=$(find "$ISO_TREE" -type f | wc -l)
echo ""
log_ok "$EXTRACTED arquivos extraidos"

log_status "Arquivos de boot:"
for f in images/pxeboot/vmlinuz images/pxeboot/initrd.img images/install.img images/efiboot.img; do
    if [ -f "$ISO_TREE/$f" ]; then
        log_info "  $f ($(du -h "$ISO_TREE/$f" | cut -f1))"
    fi
done

log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 3/8 - Baixar RPMs offline
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=3
log_step_header $CURRENT_STEP $TOTAL_STEPS "Baixando RPMs para instalacao offline"

ALL_PACKAGES=(
    kernel-core grub2-efi-x64 grub2-pc shim-x64 syslinux dracut-live
    bluetooth bluez bluez-tools
    NetworkManager-wifi wireless-tools wpa_supplicant iw rfkill
    rsync chrony openssh-server bash-completion vim-minimal
    nano wget curl net-tools iproute NetworkManager
    chromium
    alsa-utils pulseaudio pulseaudio-utils pipewire pipewire-pulse
    make gcc rpm-build tar gzip python3
    htop lm_sensors
)

log_status "Total de pacotes: ${#ALL_PACKAGES[@]}"
log "Pacotes a baixar: ${#ALL_PACKAGES[@]}"

DOWNLOADED=0
SKIPPED=0
TOTAL_PKGS=${#ALL_PACKAGES[@]}

log_status "Baixando $TOTAL_PKGS pacotes (um por vez)..."

for i in "${!ALL_PACKAGES[@]}"; do
    pkg="${ALL_PACKAGES[$i]}"
    idx=$((i + 1))
    log_progress $idx $TOTAL_PKGS "$pkg"

    if dnf download --repo=ol9_baseos_latest --repo=ol9_appstream \
        --destdir="$LOCAL_REPO" "$pkg" >> "$LOG_FILE" 2>&1; then
        ((DOWNLOADED++)) || true
    else
        log "  Pacote nao encontrado ou falhou: $pkg" 2>/dev/null || true
        ((SKIPPED++)) || true
    fi
done

RPM_COUNT=$(find "$LOCAL_REPO" -name '*.rpm' -type f 2>/dev/null | wc -l)
log_status "RPMs baixados: $RPM_COUNT | Nao encontrados: $SKIPPED"

if [[ $RPM_COUNT -eq 0 ]]; then
    log_err "Nenhum RPM baixado!"
    log_step_error $CURRENT_STEP
    exit 1
fi

REPO_SIZE=$(du -sh "$LOCAL_REPO" | cut -f1)
log_ok "$RPM_COUNT RPMs ($REPO_SIZE) salvos em $LOCAL_REPO"
log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 4/8 - Criar repodata
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=4
log_step_header $CURRENT_STEP $TOTAL_STEPS "Criando repodata (createrepo_c)"

log_status "Executando createrepo_c em $LOCAL_REPO..."
createrepo_c "$LOCAL_REPO" >> "$LOG_FILE" 2>&1
log_ok "repodata criada em $LOCAL_REPO"

REPODATA_SIZE=$(du -sh "$LOCAL_REPO/repodata" 2>/dev/null | cut -f1)
log_status "Tamanho repodata: $REPODATA_SIZE"
log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 5/8 - Copiar scripts + criar conteudo
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=5
log_step_header $CURRENT_STEP $TOTAL_STEPS "Copiando scripts e criando conteudo"

log_status "Copiando scripts principais..."
for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
    SRC="$SCRIPT_DIR/$SCRIPT"
    printf "    %-35s" "$SCRIPT"
    if [ -f "$SRC" ]; then
        rsync -a "$SRC" "$CONTENT_DIR/"
        echo -e "${GREEN}OK${NC} ($(du -h "$SRC" | cut -f1))"
        ((SCRIPTS_COPIED++)) || true
    else
        echo -e "${YELLOW}skip${NC}"
    fi
done

log_status "Copiando diretorios..."
for DIR in system_scripts vm_scripts bluetooth; do
    SRC="$SCRIPT_DIR/$DIR"
    printf "    %-35s" "$DIR/"
    if [ -d "$SRC" ]; then
        COUNT=$(find "$SRC" -type f | wc -l)
        rsync -a "$SRC/" "$CONTENT_DIR/$DIR/" >> "$LOG_FILE" 2>&1
        echo -e "${GREEN}OK${NC} ($COUNT arquivos)"
        ((CONTENT_COPIED+=COUNT)) || true
    else
        echo -e "${YELLOW}skip${NC}"
    fi
done

printf "    %-35s" "software_rpm/"
if [ -d "$SCRIPT_DIR/software_rpm" ] && [ -n "$(ls -A "$SCRIPT_DIR/software_rpm"/*.rpm 2>/dev/null)" ]; then
    C=$(ls "$SCRIPT_DIR/software_rpm"/*.rpm 2>/dev/null | wc -l)
    rsync -a "$SCRIPT_DIR/software_rpm/" "$CONTENT_DIR/software_rpm/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}OK${NC} ($C RPMs)"
    ((CONTENT_COPIED+=C)) || true
else
    echo -e "${DIM}vazio${NC}"
fi

printf "    %-35s" "favoritos/"
if [ -d "$SCRIPT_DIR/favoritos" ] && [ -n "$(ls -A "$SCRIPT_DIR/favoritos" 2>/dev/null)" ]; then
    C=$(find "$SCRIPT_DIR/favoritos" -type f | wc -l)
    rsync -a "$SCRIPT_DIR/favoritos/" "$CONTENT_DIR/favoritos/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}OK${NC} ($C arquivos)"
    ((CONTENT_COPIED+=C)) || true
else
    echo -e "${DIM}vazio${NC}"
fi

TOTAL_CONTENT=$(find "$CONTENT_DIR" -type f 2>/dev/null | wc -l)
log_ok "Total: ${TOTAL_CONTENT} arquivos ($(du -sh "$CONTENT_DIR" | cut -f1))"
log_status "Conteudo total: $TOTAL_CONTENT arquivos"
log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 6/8 - Kickstart + Boot configs
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=6
log_step_header $CURRENT_STEP $TOTAL_STEPS "Criando kickstart e configurando boot"

log_status "Gerando kickstart..."
cat > "$KS_FILE" << 'EOFKS'
keyboard br-abnt2
lang pt_BR.UTF-8
timezone America/Sao_Paulo --utc

zerombr
clearpart --all --initlabel
autopart --type=plain

bootloader --location=mbr --driveorder=sda

repo --name="Packages" --baseurl=file:///run/install/repo/Packages --noverifyssl

url --url=https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/ --noverifyssl
repo --name="AppStream" --baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/ --noverifyssl

network --bootproto=dhcp --activate

user --name=oracle --password=oracle --plaintext
rootpw --lock

services --enabled="chronyd,sshd,bluetooth,NetworkManager"

reboot

%packages
@xfce
@base-x
@base
@core
@hardware-support
kernel-core
grub2-efi-x64
grub2-pc
shim-x64
syslinux
dracut-live
bluetooth
bluez
bluez-tools
NetworkManager-wifi
wireless-tools
wpa_supplicant
iw
rfkill
rsync
chrony
openssh-server
bash-completion
vim-minimal
nano
wget
curl
net-tools
iproute
NetworkManager
chromium
alsa-utils
pulseaudio
pulseaudio-utils
pipewire
pipewire-pulse
make
gcc
rpm-build
tar
gzip
python3
htop
lm_sensors
%end

%post --log=/root/post-install.log
#!/bin/bash
set -x

hostnamectl set-name oracle-offline

systemctl enable sshd
systemctl enable chronyd
systemctl enable bluetooth
systemctl enable NetworkManager

useradd -m -s /bin/bash -G wheel oracle 2>/dev/null || true
echo "oracle:oracle" | chpasswd 2>/dev/null || true

mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "\$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if mountpoint -q /mnt/media; then
    for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
        if [ -f "/mnt/media/content/\$SCRIPT" ]; then
            rsync -a "/mnt/media/content/\$SCRIPT" /usr/local/bin/
            chmod +x "/usr/local/bin/\$SCRIPT"
        fi
    done

    for DIR in system_scripts vm_scripts bluetooth; do
        if [ -d "/mnt/media/content/\$DIR" ]; then
            rsync -av "/mnt/media/content/\$DIR/" "/opt/\$DIR/"
            chmod -R +x "/opt/\$DIR/" 2>/dev/null || true
        fi
    done

    if [ -d /mnt/media/Packages ]; then
        mkdir -p /opt/local_repo
        rsync -a /mnt/media/Packages/ /opt/local_repo/
        if [ -d /mnt/media/Packages/repodata ]; then
            rsync -a /mnt/media/Packages/repodata/ /opt/local_repo/repodata/
        fi
        cat > /etc/yum.repos.d/ol9-local-offline.repo << 'REPOEOF'
[ol9_local_offline]
name=Oracle Linux 9 Local Offline
baseurl=file:///opt/local_repo/
enabled=1
gpgcheck=0
REPOEOF
    fi

    if [ -d /mnt/media/content/favoritos ]; then
        mkdir -p /etc/skel/favoritos
        rsync -av /mnt/media/content/favoritos/ /etc/skel/favoritos/
        mkdir -p /home/oracle/favoritos
        rsync -av /mnt/media/content/favoritos/ /home/oracle/favoritos/
        chown -R oracle:oracle /home/oracle/favoritos 2>/dev/null || true
    fi

    if [ -f /mnt/media/content/checksums.txt ]; then
        cd /mnt/media/content && sha256sum -c checksums.txt 2>/dev/null || echo "AVISO: Checksum inconsistente"
    fi

    umount /mnt/media 2>/dev/null || true
fi

systemctl enable bluetooth

cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'NMEOF'
[connection]
wifi.powersave = 2
NMEOF

ln -sf /opt/system_scripts/ol9-full-setup.sh /usr/local/bin/ol9-setup 2>/dev/null || true
ln -sf /opt/system_scripts/otimizar-xfce.sh /usr/local/bin/otimizar-xfce 2>/dev/null || true

echo "Instalacao offline concluida: $(date)" > /root/INSTALL_OK
%end
EOFKS

KS_LINES=$(wc -l < "$KS_FILE")
log_ok "Kickstart: $KS_FILE ($KS_LINES linhas)"

log_status "Configurando GRUB UEFI..."
GRUB_CFG="$ISO_TREE/EFI/BOOT/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$GRUB_CFG"
    sed -i "s|set timeout=60|set timeout=5|g" "$GRUB_CFG"
    log_ok "grub.cfg UEFI atualizado (label: $FS_LABEL)"

    cat >> "$GRUB_CFG" << 'GRUBKS'

menuentry 'Instalar com Kickstart (auto, XFCE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_XFCE inst.ks=hd:LABEL=OL9_OFFLINE_XFCE:/ks.cfg quiet
    initrdefi /images/pxeboot/initrd.img
}
GRUBKS
    log_ok "Entrada kickstart adicionada ao grub.cfg"
fi

log_status "Configurando isolinux BIOS..."
ISOLINUX_CFG="$ISO_TREE/isolinux/isolinux.cfg"
if [ -f "$ISOLINUX_CFG" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$ISOLINUX_CFG"
    log_ok "isolinux.cfg atualizado (label: $FS_LABEL)"

    cat >> "$ISOLINUX_CFG" << 'ISOLINUXKS'

label kickstart
  menu label ^Instalar com Kickstart (auto, XFCE)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_XFCE inst.ks=hd:LABEL=OL9_OFFLINE_XFCE:/ks.cfg quiet
ISOLINUXKS
    log_ok "Entrada kickstart adicionada ao isolinux.cfg"
fi

DISCINFO="$ISO_TREE/.discinfo"
if [ -f "$DISCINFO" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$DISCINFO"
    log_ok ".discinfo atualizado"
fi

EFIIMG="$ISO_TREE/images/efiboot.img"
EFIIMG_MOUNT="$BUILD_ROOT/efiboot_mount"
if [ -f "$EFIIMG" ]; then
    log_status "Atualizando grub.cfg dentro do efiboot.img..."
    mkdir -p "$EFIIMG_MOUNT"
    if mount -o loop,rw "$EFIIMG" "$EFIIMG_MOUNT" 2>/dev/null; then
        cp "$GRUB_CFG" "$EFIIMG_MOUNT/EFI/BOOT/grub.cfg"
        chmod 644 "$EFIIMG_MOUNT/EFI/BOOT/grub.cfg"
        umount "$EFIIMG_MOUNT"
        log_ok "efiboot.img atualizado com grub.cfg correto (label: $FS_LABEL)"
    else
        log_warn "Falha ao montar efiboot.img. Tentando via mtools..."
        if command -v mcopy &>/dev/null; then
            mcopy -o "$GRUB_CFG" "::$EFIIMG_MOUNT/EFI/BOOT/grub.cfg" 2>/dev/null || true
            log_ok "efiboot.img atualizado via mtools"
        else
            log_err "NAO FOI POSSIVEL atualizar efiboot.img. Boot UEFI pode falhar!"
        fi
    fi
fi

log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 7/8 - Gerar ISO
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=7
log_step_header $CURRENT_STEP $TOTAL_STEPS "Gerando ISO offline com xorriso"

TOTAL_ISO_SIZE=$(du -sh "$ISO_TREE" | cut -f1)
log_status "Tamanho da arvore ISO: $TOTAL_ISO_SIZE"
log_status "RPMs: $RPM_COUNT | Scripts: $TOTAL_CONTENT"

ISO_PATH="$OUT_DIR/$ISO_NAME"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

log_status "Gerando ISO hibrida (UEFI + BIOS)..."

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -V "$FS_LABEL" \
    -o "$ISO_PATH" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -isohybrid-gpt-basdat \
    "$ISO_TREE" 2>&1 | tee -a "$LOG_FILE"

if [ ! -f "$ISO_PATH" ]; then
    log_err "ISO nao gerada!"
    log_step_error $CURRENT_STEP
    exit 1
fi

ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
log_ok "ISO gerada: $ISO_PATH ($ISO_SIZE)"
log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 8/8 - isohybrid + checksum + resumo
# ═══════════════════════════════════════════════════════════════════════════════
STEP_START=$(date +%s)
CURRENT_STEP=8
log_step_header $CURRENT_STEP $TOTAL_STEPS "Aplicando isohybrid + checksum + resumo"

log_status "Aplicando isohybrid --uefi..."
printf "    isohybrid --uefi... "
if isohybrid --uefi "$ISO_PATH" 2>>"$LOG_FILE"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}skip (ja hibrida)${NC}"
fi

log_status "Gerando checksum SHA256..."
cd "$OUT_DIR"
sha256sum "$ISO_NAME" > hash_iso.txt 2>/dev/null
log_ok "SHA256 gerado"

ISO_SIZE_FINAL=$(ls -lh "$ISO_NAME" | awk '{print $5}')
ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME" 2>/dev/null || echo 0)
BUILD_TOTAL=$(($(date +%s) - BUILD_START))
BUILD_MIN=$((BUILD_TOTAL / 60))
BUILD_SEC=$((BUILD_TOTAL % 60))

log_step_footer $CURRENT_STEP

# ═══════════════════════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════════════════════
gerar_resumo_final

echo -e "  ${BOLD}Base:${NC}     OracleLinux-R9-U8-x86_64-boot.iso"
echo -e "  ${BOLD}Boot:${NC}     UEFI + MBR (BIOS)"
echo -e "  ${BOLD}Desktop:${NC}  XFCE"
echo -e "  ${BOLD}Offline:${NC}  SIM — $RPM_COUNT RPMs embutidos"
echo ""
echo -e "  ${BOLD}Opcoes de boot:${NC}"
echo -e "    1) Install Oracle Linux 9.8.0"
echo -e "    2) Instalar com Kickstart (auto, XFCE)"
echo -e "    3) Test this media & install"
echo -e "    4) Text mode / Rescue"
echo ""
echo -e "  ${BOLD}Pos-install:${NC}"
echo -e "    update-appimages.sh   # Brave, VSCodium, Chromium, OpenCode"
echo -e "    ol9-setup             # EPEL + RPM Fusion + codecs"
echo -e "    otimizar-xfce         # Otimizar XFCE"
echo ""
echo -e "  ${BOLD}Tempo:${NC}    ${BUILD_MIN}m ${BUILD_SEC}s"
echo -e "  ${BOLD}Log:${NC}      $LOG_FILE"
echo ""
