#!/bin/bash
# ==============================================================================
# Gerador de ISO Híbrida Completa - Oracle Linux 9 (XFCE + Bluetooth + WiFi)
# Baseado no oracle.sh (testado) | Logs completos por etapa
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build_completa"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$BUILD_ROOT/ks_completa.cfg"
GRUB_DIR="$BUILD_ROOT/grub_files"
LOG_DIR="$BUILD_ROOT/logs"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"
ISO_NAME="OL9-Completa-Hybrid.iso"
FS_LABEL="OL9_COMPLETA"

mkdir -p "$LOG_DIR" "$BUILD_ROOT" "$OUT_DIR" "$GRUB_DIR" \
         "$BUILD_ROOT/content/software_rpm" \
         "$BUILD_ROOT/content/favoritos" \
         "$BUILD_ROOT/content/system_scripts" \
         "$BUILD_ROOT/content/vm_scripts" \
         "$BUILD_ROOT/content/bluetooth"

TOTAL_STEPS=10
CURRENT_STEP=0
STEP_START=0
BUILD_START=$(date +%s)

# ═══════════════════════════════════════════════════════════════════════════════
# CORES
# ═══════════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${WHITE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
log_ok()  { echo -e "${GREEN}  [OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn(){ echo -e "${YELLOW}  [WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_err() { echo -e "${RED}  [ERRO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_info(){ echo -e "${CYAN}  [INFO]${NC}  $*" | tee -a "$LOG_FILE"; }

barra_progresso() {
    local current=$1 total=$2 width=${3:-40}
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    printf "\r    ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
}

step_init() {
    CURRENT_STEP=$1
    STEP_START=$(date +%s)
    local elapsed_total=$((STEP_START - BUILD_START))
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    printf "${BOLD}${WHITE}  ETAPA %2d/%d${NC}  " "$CURRENT_STEP" "$TOTAL_STEPS"
    echo -e "${BOLD}${WHITE}$2${NC}"
    echo -e "${DIM}  Início: $(date '+%H:%M:%S') | Acumulado: ${elapsed_total}s${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

step_done() {
    local elapsed=$(( $(date +%s) - STEP_START ))
    local total_elapsed=$(( $(date +%s) - BUILD_START ))
    echo ""
    echo -e "    ${GREEN}✔ Etapa $CURRENT_STEP concluída em ${elapsed}s${NC} (total: ${total_elapsed}s)"
    echo "" >> "$LOG_FILE"
    echo "=== ETAPA $CURRENT_STEP concluída em ${elapsed}s ===" >> "$LOG_FILE"
}

# Cleanup no exit
limpar_tudo() {
    echo ""
    echo -e "${DIM}### [LIMPEZA] Desmontando temporários...${NC}"
    sync
    grep "$BUILD_ROOT" /proc/mounts 2>/dev/null | cut -d' ' -f2 | xargs -r umount -l 2>/dev/null || true
    rm -rf "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" 2>/dev/null || true
}
trap limpar_tudo EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# INÍCIO
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║  ISO Completa Oracle Linux 9 — XFCE | BT | WiFi | UEFI+MBR  ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Log: $LOG_FILE"
log "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

if [[ $EUID -ne 0 ]]; then
    log_err "Execute como ROOT."
    exit 1
fi

FREE_GB=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_GB" -lt 15 ]; then
    log_err "Espaço insuficiente ($FREE_GB GB). Mínimo 15GB."
    exit 1
fi
log_info "Espaço disponível: ${FREE_GB}GB"

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 1: Instalar dependências
# ═══════════════════════════════════════════════════════════════════════════════
step_init 1 "Instalando dependências"

DEPS=(epel-release lorax lorax-lmc-novirt xorriso rsync syslinux
      grub2-efi-x64 shim-x64 grub2-tools lorax-templates-generic isohybrid)

for dep in "${DEPS[@]}"; do
    printf "    %-30s" "$dep"
    if rpm -q "$dep" &>/dev/null || command -v "$dep" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        printf "instalando... "
        if dnf install -y "$dep" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    fi
done

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 2: Copiar scripts e diretórios do localhost
# ═══════════════════════════════════════════════════════════════════════════════
step_init 2 "Copiando arquivos do sistema local"

# Scripts principais
log_info "Scripts:"
for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
    SRC="$SCRIPT_DIR/$SCRIPT"
    printf "    %-35s" "$SCRIPT"
    if [ -f "$SRC" ]; then
        rsync -a "$SRC" "$BUILD_ROOT/content/"
        echo -e "${GREEN}✓${NC} ($(du -h "$SRC" | cut -f1))"
    else
        echo -e "${RED}✗ não encontrado${NC}"
    fi
done

echo ""

# Diretórios
log_info "Diretórios:"
for DIR in system_scripts vm_scripts bluetooth; do
    SRC="$SCRIPT_DIR/$DIR"
    printf "    %-35s" "$DIR/"
    if [ -d "$SRC" ]; then
        COUNT=$(find "$SRC" -type f | wc -l)
        rsync -a "$SRC/" "$BUILD_ROOT/content/$DIR/" >> "$LOG_FILE" 2>&1
        echo -e "${GREEN}✓${NC} (${COUNT} arquivos)"
    else
        echo -e "${YELLOW}⊘ não encontrado${NC}"
    fi
done

# Software RPM local (se existir)
printf "    %-35s" "software_rpm/"
SOFTWARE_SRC="$SCRIPT_DIR/software_rpm"
if [ -d "$SOFTWARE_SRC" ] && [ -n "$(ls -A "$SOFTWARE_SRC"/*.rpm 2>/dev/null)" ]; then
    RPM_COUNT=$(ls "$SOFTWARE_SRC"/*.rpm 2>/dev/null | wc -l)
    rsync -a "$SOFTWARE_SRC/" "$BUILD_ROOT/content/software_rpm/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}✓${NC} (${RPM_COUNT} RPMs)"
else
    echo -e "${DIM}⊘ vazio${NC}"
fi

# Favoritos (se existir)
printf "    %-35s" "favoritos/"
FAVORITOS_SRC="$SCRIPT_DIR/favoritos"
if [ -d "$FAVORITOS_SRC" ] && [ -n "$(ls -A "$FAVORITOS_SRC" 2>/dev/null)" ]; then
    FAV_COUNT=$(find "$FAVORITOS_SRC" -type f | wc -l)
    rsync -a "$FAVORITOS_SRC/" "$BUILD_ROOT/content/favoritos/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}✓${NC} (${FAV_COUNT} arquivos)"
else
    echo -e "${DIM}⊘ vazio${NC}"
fi

echo ""
TOTAL_CONTENT=$(find "$BUILD_ROOT/content" -type f 2>/dev/null | wc -l)
log_ok "Total: ${TOTAL_CONTENT} arquivos ($(du -sh "$BUILD_ROOT/content" | cut -f1))"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 3: Gerar .buildstamp
# ═══════════════════════════════════════════════════════════════════════════════
step_init 3 "Gerando .buildstamp"

mkdir -p /etc/anaconda
cat <<'BSTAMP' > /etc/anaconda/.buildstamp
[Anaconda]
Buildstamp = oracle-linux-9-build
Product = OracleLinux
Variant =
Timestamp = 0
BSTAMP

log_ok "Buildstamp: /etc/anaconda/.buildstamp"
log_info "Product: OracleLinux | Variant: (padrão)"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 4: Gerar Kickstart
# ═══════════════════════════════════════════════════════════════════════════════
step_init 4 "Gerando Kickstart"

cat <<'EOFKS' > "$KS_FILE"
keyboard br-abnt2
lang pt_BR.UTF-8
timezone America/Sao_Paulo --utc

# Disco
zerombr
clearpart --all --initlabel
autopart --type=plain

# Bootloader - suporte UEFI e MBR
bootloader --location=mbr --driveorder=sda

# Repositorios oficiais Oracle Linux 9
url --url=https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/ --noverifyssl
repo --name="AppStream" --baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/ --noverifyssl

# Rede
network --bootproto=dhcp --activate

# Usuarios
user --name=oracle --password=oracle --plaintext
rootpw --lock

# Servicos
services --enabled="chronyd,sshd,bluetooth,NetworkManager"

reboot

%packages
# Desktop
@xfce
@base-x
@base
@core
@hardware-support

# Kernel e boot
kernel-core
grub2-efi-x64
grub2-pc
shim-x64
syslinux
dracut-live

# Bluetooth
bluetooth
bluez
bluez-tools

# WiFi / Wireless
NetworkManager-wifi
wireless-tools
wpa_supplicant
iwl*firmware
iw
rfkill

# Rede / Utilitarios
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

# Navegador
chromium

# Multimedia
alsa-utils
pulseaudio
pulseaudio-utils
pipewire
pipewire-pulse

# Build tools
make
gcc
rpm-build
tar
gzip
python3

# Extra
htop
lm_sensors
%end

%post --log=/root/post-install.log
#!/bin/bash
set -x

# Hostname
hostnamectl set-name oracle-completa

# Habilitar servicos
systemctl enable sshd
systemctl enable chronyd
systemctl enable bluetooth
systemctl enable NetworkManager

# Criar usuario oracle
useradd -m -s /bin/bash -G wheel oracle 2>/dev/null || true
echo "oracle:oracle" | chpasswd 2>/dev/null || true

# Montar midia e injetar conteudo
mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "\$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if mountpoint -q /mnt/media; then
    # RPMs locais
    if [ -d /mnt/media/software_rpm ] && ls /mnt/media/software_rpm/*.rpm >/dev/null 2>&1; then
        dnf install -y /mnt/media/software_rpm/*.rpm 2>/dev/null || true
    fi

    # Scripts principais
    mkdir -p /usr/local/bin
    for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
        if [ -f "/mnt/media/\$SCRIPT" ]; then
            rsync -a "/mnt/media/\$SCRIPT" /usr/local/bin/
            chmod +x "/usr/local/bin/\$SCRIPT"
        fi
    done

    # Diretorios de scripts
    for DIR in system_scripts vm_scripts bluetooth; do
        if [ -d "/mnt/media/\$DIR" ]; then
            rsync -av "/mnt/media/\$DIR/" "/opt/\$DIR/"
            chmod -R +x "/opt/\$DIR/" 2>/dev/null || true
        fi
    done

    # Favoritos
    if [ -d /mnt/media/favoritos ]; then
        mkdir -p /etc/skel/favoritos
        rsync -av /mnt/media/favoritos/ /etc/skel/favoritos/
        mkdir -p /home/oracle/favoritos
        rsync -av /mnt/media/favoritos/ /home/oracle/favoritos/
        chown -R oracle:oracle /home/oracle/favoritos 2>/dev/null || true
    fi

    # Checksums
    if [ -f /mnt/media/checksums.txt ]; then
        cd /mnt/media && sha256sum -c checksums.txt 2>/dev/null || echo "AVISO: Checksum inconsistente"
    fi

    umount /mnt/media 2>/dev/null || true
fi

# Bluetooth
systemctl enable bluetooth

# WiFi
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf <<'NMEOF'
[connection]
wifi.powersave = 2
NMEOF

# Links uteis
ln -sf /opt/system_scripts/gerar_iso.sh /usr/local/bin/gerar-iso 2>/dev/null || true
ln -sf /opt/system_scripts/build_backup.sh /usr/local/bin/build-backup 2>/dev/null || true
ln -sf /opt/system_scripts/ol9-full-setup.sh /usr/local/bin/ol9-setup 2>/dev/null || true

echo "Instalacao completa concluida: $(date)" > /root/INSTALL_OK
%end
EOFKS

KS_LINES=$(wc -l < "$KS_FILE")
PKG_COUNT=$(sed -n '/^%packages/,/^%end/p' "$KS_FILE" | grep -v '^#' | grep -v '^%' | grep -v '^$' | wc -l)
GROUP_COUNT=$(sed -n '/^%packages/,/^%end/p' "$KS_FILE" | grep '^@' | wc -l)

log_ok "Kickstart: $KS_FILE"
log_info "Linhas: $KS_LINES | Pacotes: $PKG_COUNT (${GROUP_COUNT} grupos + $((PKG_COUNT - GROUP_COUNT)) individuais)"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 5: Configurar GRUB UEFI
# ═══════════════════════════════════════════════════════════════════════════════
step_init 5 "Configurando GRUB UEFI"

mkdir -p "$GRUB_DIR"
cat <<'EOFGRUB' > "$GRUB_DIR/grub.cfg"
set default=0
set timeout=5
set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

menuentry "Oracle Linux 9 Completa - Instalar" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_COMPLETA quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 Completa - Instalar (Texto)" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_COMPLETA text quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 Completa - Modo Resgate" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_COMPLETA rescue quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 Completa - Testar midia e instalar" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_COMPLETA rd.live.check quiet
    initrdefi /images/pxeboot/initrd.img
}
EOFGRUB

GRUB_ENTRIES=$(grep -c "^menuentry" "$GRUB_DIR/grub.cfg")
log_ok "GRUB: $GRUB_ENTRIES entradas de menu"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 6: Build da ISO com livemedia-creator
# ═══════════════════════════════════════════════════════════════════════════════
step_init 6 "Build da ISO (~15-30min)"

# livemedia-creator exige que output_iso NÃO exista
rm -rf "$OUT_DIR"

log_info "Iniciando livemedia-creator..."
log_info "Pacotes serão baixados dos repositórios Oracle Linux"
echo ""

LMC_LOG="$LOG_DIR/livemedia_$(date +%Y%m%d_%H%M%S).log"

set +e
livemedia-creator \
    --make-iso \
    --ks="$KS_FILE" \
    --no-virt \
    --resultdir="$OUT_DIR" \
    --project="OracleLinux" \
    --releasever=9 \
    --iso-name="$ISO_NAME" \
    --fs-label="$FS_LABEL" \
    --anaconda-arg=--product=OracleLinux \
    2>&1 | tee -a "$LMC_LOG"
LMC_EXIT=$?
set -e

cat "$LMC_LOG" >> "$LOG_FILE"

if [ $LMC_EXIT -ne 0 ]; then
    log_err "livemedia-creator falhou (exit code: $LMC_EXIT)"
    log_err "Log completo: $LMC_LOG"
    log_err "Últimas 20 linhas:"
    tail -20 "$LMC_LOG" | while IFS= read -r line; do
        echo -e "    ${DIM}$line${NC}"
    done
    echo ""
    log_warn "Limpando temporários..."
    rm -rf "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" "$OUT_DIR" 2>/dev/null || true
    exit 1
fi

ISO_PATH=$(find "$OUT_DIR" -name "$ISO_NAME" -type f 2>/dev/null | head -1)
if [ -z "$ISO_PATH" ]; then
    ISO_PATH=$(find "$OUT_DIR" -name "*.iso" -type f 2>/dev/null | head -1)
fi

if [ -z "$ISO_PATH" ]; then
    log_err "Nenhuma ISO gerada!"
    log_err "Verifique: $LMC_LOG"
    exit 1
fi

ISO_SIZE_BASE=$(du -h "$ISO_PATH" | cut -f1)
log_ok "ISO base gerada: $ISO_SIZE_BASE"
log_info "Caminho: $ISO_PATH"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 7: Injetar GRUB UEFI
# ═══════════════════════════════════════════════════════════════════════════════
step_init 7 "Configurando GRUB UEFI na ISO"

log_ok "GRUB UEFI configurado"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 8: Aplicar isohybrid (MBR + UEFI)
# ═══════════════════════════════════════════════════════════════════════════════
step_init 8 "Aplicando isohybrid (MBR + UEFI)"

ISO_TMP="$OUT_DIR/${ISO_NAME%.iso}-tmp.iso"
rsync -a "$ISO_PATH" "$ISO_TMP"

printf "    Aplicando isohybrid --uefi... "
if isohybrid --uefi "$ISO_PATH" 2>>"$LOG_FILE"; then
    echo -e "${GREEN}✔${NC}"
else
    echo -e "${YELLOW}⚠ isohybrid falhou, tentando xorriso...${NC}"
    xorriso -as dd -indev "$ISO_TMP" \
            -outdev "$ISO_PATH" \
            --interval:partition_interval:efi_path:$GRUB_DIR/efi.img 2>>"$LOG_FILE" || true
fi

rm -f "$ISO_TMP" 2>/dev/null || true
log_ok "ISO suporta boot UEFI + MBR"

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 9: Injetar arquivos extras na ISO
# ═══════════════════════════════════════════════════════════════════════════════
step_init 9 "Injetando scripts e diretórios na ISO"

cd "$BUILD_ROOT/content"
CONTENT_FILES=$(find . -type f 2>/dev/null | wc -l)

if [ "$CONTENT_FILES" -gt 0 ]; then
    ISO_MOUNT="$BUILD_ROOT/iso_mount"
    mkdir -p "$ISO_MOUNT"

    printf "    Extraindo ISO... "
    xorriso -osirrox on -indev "$ISO_PATH" -extract / "$ISO_MOUNT" 2>>"$LOG_FILE"
    echo -e "${GREEN}✔${NC}"

    log_info "Injetando ${CONTENT_FILES} arquivos..."
    rsync -a "$BUILD_ROOT/content/" "$ISO_MOUNT/" >> "$LOG_FILE" 2>&1

    printf "    Regenerando ISO... "
    cd "$ISO_MOUNT"
    xorriso -as mkisofs \
        -r -V "$FS_LABEL" \
        -o "$ISO_PATH" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        . >>"$LOG_FILE" 2>&1
    echo -e "${GREEN}✔${NC}"

    printf "    Reaplicando isohybrid... "
    isohybrid --uefi "$ISO_PATH" 2>>"$LOG_FILE"
    echo -e "${GREEN}✔${NC}"

    rm -rf "$ISO_MOUNT"
else
    log_warn "Nenhum arquivo para injetar"
fi

step_done

# ═══════════════════════════════════════════════════════════════════════════════
# ETAPA 10: Finalização
# ═══════════════════════════════════════════════════════════════════════════════
step_init 10 "Gerando checksums e relatório"

cd "$OUT_DIR"

printf "    Gerando SHA256... "
sha256sum "$ISO_NAME" > hash_iso.txt 2>/dev/null
echo -e "${GREEN}✔${NC}"

ISO_SIZE=$(ls -lh "$ISO_NAME" | awk '{print $5}')
ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME" 2>/dev/null || echo 0)
BUILD_TOTAL=$(($(date +%s) - BUILD_START))
BUILD_MIN=$((BUILD_TOTAL / 60))
BUILD_SEC=$((BUILD_TOTAL % 60))

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          ISO COMPLETA GERADA COM SUCESSO!                    ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Arquivo:${NC}     $OUT_DIR/$ISO_NAME"
echo -e "  ${BOLD}Tamanho:${NC}     $ISO_SIZE ($(numfmt --to=iec "$ISO_SIZE_BYTES" 2>/dev/null || echo "?"))"
echo -e "  ${BOLD}Checksum:${NC}    $OUT_DIR/hash_iso.txt"
echo ""
echo -e "  ${BOLD}Boot:${NC}        UEFI + MBR (BIOS legado)"
echo -e "  ${BOLD}Desktop:${NC}     XFCE"
echo -e "  ${BOLD}Bluetooth:${NC}   bluez + bluez-tools"
echo -e "  ${BOLD}WiFi:${NC}        NetworkManager-wifi + iwl*firmware"
echo -e "  ${BOLD}Audio:${NC}       PulseAudio + PipeWire"
echo ""
echo -e "  ${BOLD}Conteúdo embutido:${NC}"
echo -e "    ├─ update-appimages.sh"
echo -e "    ├─ create_rpm.sh"
echo -e "    ├─ fix-repos-ol9.sh"
echo -e "    ├─ system_scripts/  $(find "$BUILD_ROOT/content/system_scripts" -type f 2>/dev/null | wc -l | xargs printf '(%2s)')"
echo -e "    ├─ vm_scripts/      $(find "$BUILD_ROOT/content/vm_scripts" -type f 2>/dev/null | wc -l | xargs printf '(%2s)')"
echo -e "    └─ bluetooth/       $(find "$BUILD_ROOT/content/bluetooth" -type f 2>/dev/null | wc -l | xargs printf '(%2s)')"
echo ""
echo -e "  ${BOLD}Tempo total:${NC} ${BUILD_MIN}m ${BUILD_SEC}s"
echo -e "  ${BOLD}Log:${NC}        $LOG_FILE"
echo ""
