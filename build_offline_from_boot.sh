#!/bin/bash
# ==============================================================================
# ISO OFFLINE a partir da ISO Boot Minimal (Oracle Linux 9)
# Usa OracleLinux-R9-U8-x86_64-boot.iso como base
# Adiciona Packages/ offline + kickstart + XFCE + update-appimages.sh
# Boot: UEFI + MBR (BIOS)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_ISO="$SCRIPT_DIR/OracleLinux-R9-U8-x86_64-boot.iso"
BUILD_ROOT="$SCRIPT_DIR/build_offline_boot"
WORK_DIR="$BUILD_ROOT/iso_tree"
LOCAL_REPO="$WORK_DIR/Packages"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$WORK_DIR/ks.cfg"
CONTENT_DIR="$WORK_DIR/content"
LOG_DIR="$BUILD_ROOT/logs"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"
ISO_NAME="OL9-Offline-Completa.iso"
FS_LABEL="OL9_OFFLINE_XFCE"

TOTAL_STEPS=8
CURRENT_STEP=0
STEP_START=0
BUILD_START=$(date +%s)
ERRORS=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_ok()  { echo -e "  ${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn(){ echo -e "  ${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_err() { echo -e "  ${RED}[ERRO]${NC}  $*" | tee -a "$LOG_FILE"; ((ERRORS++)) || true; }
log_info(){ echo -e "  ${CYAN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }

step_init() {
    CURRENT_STEP=$1
    STEP_START=$(date +%s)
    local elapsed_total=$((STEP_START - BUILD_START))
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    printf "${BOLD}  ETAPA %2d/%d${NC}  " "$CURRENT_STEP" "$TOTAL_STEPS"
    echo -e "${BOLD}$2${NC}"
    echo -e "${DIM}  Inicio: $(date '+%H:%M:%S') | Acumulado: ${elapsed_total}s${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

step_done() {
    local elapsed=$(( $(date +%s) - STEP_START ))
    local total_elapsed=$(( $(date +%s) - BUILD_START ))
    echo ""
    echo -e "  ${GREEN}✔ Etapa $CURRENT_STEP concluida em ${elapsed}s${NC} (total: ${total_elapsed}s)"
    echo "" >> "$LOG_FILE"
}

limpar_tudo() {
    echo ""
    log "Limpando temporarios..."
    sync
    grep "$BUILD_ROOT" /proc/mounts 2>/dev/null | cut -d' ' -f2 | xargs -r umount -l 2>/dev/null || true
    rm -rf "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" 2>/dev/null || true
}
trap limpar_tudo EXIT

# ==================================================================
# INICIO
# ==================================================================
echo -e "${BOLD}${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ISO OFFLINE a partir da ISO Boot — Oracle Linux 9           ║"
echo "║  Boot ISO → Baixa RPMs → Repo local → ISO instalavel offline║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
log "Log: $LOG_FILE"
echo ""

# --- Verificacoes ---
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

mkdir -p "$LOG_DIR" "$BUILD_ROOT" "$OUT_DIR" "$LOCAL_REPO" \
         "$CONTENT_DIR/software_rpm" "$CONTENT_DIR/favoritos" \
         "$CONTENT_DIR/system_scripts" "$CONTENT_DIR/vm_scripts" "$CONTENT_DIR/bluetooth"

# ==================================================================
# ETAPA 1/8 - Dependencias
# ==================================================================
step_init 1 "Instalando dependencias"

DEPS=(createrepo_c xorriso rsync isohybrid)

for dep in "${DEPS[@]}"; do
    printf "    %-30s" "$dep"
    if command -v "$dep" &>/dev/null || rpm -q "$dep" &>/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        printf "instalando... "
        if dnf install -y "$dep" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}skip${NC}"
        fi
    fi
done

step_done

# ==================================================================
# ETAPA 2/8 - Extrair ISO boot
# ==================================================================
step_init 2 "Extraindo ISO boot minimal"

log_info "ISO: $BOOT_ISO"
log_info "Destino: $WORK_DIR"

xorriso -osirrox on \
    -indev "$BOOT_ISO" \
    -extract / "$WORK_DIR" \
    2>&1 | tee -a "$LOG_FILE"

EXTRACTED=$(find "$WORK_DIR" -type f | wc -l)
log_ok "$EXTRACTED arquivos extraidos"

# Listar arquivos importantes
log_info "Arquivos de boot:"
for f in images/pxeboot/vmlinuz images/pxeboot/initrd.img images/install.img images/efiboot.img; do
    if [ -f "$WORK_DIR/$f" ]; then
        log_info "  $f ($(du -h "$WORK_DIR/$f" | cut -f1))"
    fi
done

step_done

# ==================================================================
# ETAPA 3/8 - Baixar RPMs offline
# ==================================================================
step_init 3 "Baixando RPMs para instalacao offline"

PACKAGES=(
    @xfce @base-x @base @core @hardware-support
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

log_info "Total de itens: ${#PACKAGES[@]}"

GROUPS=()
INDIVIDUAL=()
for pkg in "${PACKAGES[@]}"; do
    if [[ "$pkg" == @* ]]; then
        GROUPS+=("$pkg")
    else
        INDIVIDUAL+=("$pkg")
    fi
done

FAILED_LIST=()

# Baixar grupos
if [[ ${#GROUPS[@]} -gt 0 ]]; then
    log_info "Baixando grupos..."
    for grp in "${GROUPS[@]}"; do
        printf "    %-25s" "$grp"
        if dnf download --repo=ol9_baseos_latest --repo=ol9_appstream \
            --destdir="$LOCAL_REPO" "$grp" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}fallo${NC}"
            FAILED_LIST+=("$grp")
        fi
    done
fi

# Baixar pacotes individuais
if [[ ${#INDIVIDUAL[@]} -gt 0 ]]; then
    log_info "Baixando pacotes individuais..."
    dnf download --repo=ol9_baseos_latest --repo=ol9_appstream \
        --destdir="$LOCAL_REPO" \
        "${INDIVIDUAL[@]}" 2>&1 | while IFS= read -r line; do
            echo "$line" >> "$LOG_FILE"
        done || true
fi

RPM_COUNT=$(find "$LOCAL_REPO" -name '*.rpm' -type f 2>/dev/null | wc -l)
log_info "RPMs baixados: $RPM_COUNT"

if [[ $RPM_COUNT -eq 0 ]]; then
    log_err "Nenhum RPM baixado!"
    exit 1
fi

if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    log_warn "Falharam: ${FAILED_LIST[*]}"
fi

# Calcular tamanho
REPO_SIZE=$(du -sh "$LOCAL_REPO" | cut -f1)
log_ok "$RPM_COUNT RPMs ($REPO_SIZE) salvos em $LOCAL_REPO"
step_done

# ==================================================================
# ETAPA 4/8 - Criar repodata
# ==================================================================
step_init 4 "Criando repodata (createrepo_c)"

createrepo_c "$LOCAL_REPO" >> "$LOG_FILE" 2>&1
log_ok "repodata criada em $LOCAL_REPO"

REPODATA_SIZE=$(du -sh "$LOCAL_REPO/repodata" 2>/dev/null | cut -f1)
log_info "Tamanho repodata: $REPODATA_SIZE"
step_done

# ==================================================================
# ETAPA 5/8 - Copiar scripts + criar conteudo
# ==================================================================
step_init 5 "Copiando scripts e criando conteudo"

for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
    SRC="$SCRIPT_DIR/$SCRIPT"
    printf "    %-35s" "$SCRIPT"
    if [ -f "$SRC" ]; then
        rsync -a "$SRC" "$CONTENT_DIR/"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}skip${NC}"
    fi
done

for DIR in system_scripts vm_scripts bluetooth; do
    SRC="$SCRIPT_DIR/$DIR"
    printf "    %-35s" "$DIR/"
    if [ -d "$SRC" ]; then
        COUNT=$(find "$SRC" -type f | wc -l)
        rsync -a "$SRC/" "$CONTENT_DIR/$DIR/" >> "$LOG_FILE" 2>&1
        echo -e "${GREEN}OK${NC} ($COUNT)"
    else
        echo -e "${YELLOW}skip${NC}"
    fi
done

printf "    %-35s" "software_rpm/"
if [ -d "$SCRIPT_DIR/software_rpm" ] && [ -n "$(ls -A "$SCRIPT_DIR/software_rpm"/*.rpm 2>/dev/null)" ]; then
    C=$(ls "$SCRIPT_DIR/software_rpm"/*.rpm | wc -l)
    rsync -a "$SCRIPT_DIR/software_rpm/" "$CONTENT_DIR/software_rpm/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}OK${NC} ($C RPMs)"
else
    echo -e "${DIM}vazio${NC}"
fi

printf "    %-35s" "favoritos/"
if [ -d "$SCRIPT_DIR/favoritos" ] && [ -n "$(ls -A "$SCRIPT_DIR/favoritos" 2>/dev/null)" ]; then
    C=$(find "$SCRIPT_DIR/favoritos" -type f | wc -l)
    rsync -a "$SCRIPT_DIR/favoritos/" "$CONTENT_DIR/favoritos/" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}OK${NC} ($C)"
else
    echo -e "${DIM}vazio${NC}"
fi

TOTAL_CONTENT=$(find "$CONTENT_DIR" -type f 2>/dev/null | wc -l)
log_ok "Total: ${TOTAL_CONTENT} arquivos"
step_done

# ==================================================================
# ETAPA 6/8 - Kickstart + Boot configs
# ==================================================================
step_init 6 "Criando kickstart e configurando boot"

# --- Kickstart ---
cat > "$KS_FILE" << 'EOFKS'
keyboard br-abnt2
lang pt_BR.UTF-8
timezone America/Sao_Paulo --utc

zerombr
clearpart --all --initlabel
autopart --type=plain

bootloader --location=mbr --driveorder=sda

# Repos offline via cdrom ( Packages/ na raiz da ISO )
repo --name="Packages" --baseurl=file:///run/install/repo/Packages --noverifyssl

# Backup online (se precisar)
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

# Montar midia
mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "\$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if mountpoint -q /mnt/media; then
    # Scripts para /usr/local/bin
    for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
        if [ -f "/mnt/media/content/\$SCRIPT" ]; then
            rsync -a "/mnt/media/content/\$SCRIPT" /usr/local/bin/
            chmod +x "/usr/local/bin/\$SCRIPT"
        fi
    done

    # Diretorios para /opt
    for DIR in system_scripts vm_scripts bluetooth; do
        if [ -d "/mnt/media/content/\$DIR" ]; then
            rsync -av "/mnt/media/content/\$DIR/" "/opt/\$DIR/"
            chmod -R +x "/opt/\$DIR/" 2>/dev/null || true
        fi
    done

    # Repo local offline
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

    # Favoritos
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

log_ok "Kickstart: $KS_FILE"

# --- GRUB UEFI (modificar o extraido) ---
# Label original: OL-9-8-0-BaseOS-x86_64 -> novo: OL9_OFFLINE_XFCE
GRUB_CFG="$WORK_DIR/EFI/BOOT/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$GRUB_CFG"
    sed -i "s|set timeout=60|set timeout=5|g" "$GRUB_CFG"
    log_ok "grub.cfg UEFI atualizado (label: $FS_LABEL)"
fi

# Adicionar entrada com kickstart automatico
if [ -f "$GRUB_CFG" ]; then
    cat >> "$GRUB_CFG" << 'GRUBKS'

menuentry 'Instalar com Kickstart (auto, XFCE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_XFCE inst.ks=hd:LABEL=OL9_OFFLINE_XFCE:/ks.cfg quiet
    initrdefi /images/pxeboot/initrd.img
}
GRUBKS
    log_ok "Entrada kickstart adicionada ao grub.cfg"
fi

# --- isolinux BIOS (modificar o extraido) ---
ISOLINUX_CFG="$WORK_DIR/isolinux/isolinux.cfg"
if [ -f "$ISOLINUX_CFG" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$ISOLINUX_CFG"
    log_ok "isolinux.cfg atualizado (label: $FS_LABEL)"

    # Adicionar entrada kickstart
    cat >> "$ISOLINUX_CFG" << 'ISOLINUXKS'

label kickstart
  menu label ^Instalar com Kickstart (auto, XFCE)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_XFCE inst.ks=hd:LABEL=OL9_OFFLINE_XFCE:/ks.cfg quiet
ISOLINUXKS
    log_ok "Entrada kickstart adicionada ao isolinux.cfg"
fi

# --- .discinfo ---
DISCINFO="$WORK_DIR/.discinfo"
if [ -f "$DISCINFO" ]; then
    sed -i "s|OL-9-8-0-BaseOS-x86_64|${FS_LABEL}|g" "$DISCINFO"
    log_ok ".discinfo atualizado"
fi

# --- Atualizar grub.cfg DENTRO do efiboot.img ---
EFIIMG="$WORK_DIR/images/efiboot.img"
EFIIMG_MOUNT="$BUILD_ROOT/efiboot_mount"
if [ -f "$EFIIMG" ]; then
    log_info "Atualizando grub.cfg dentro do efiboot.img..."
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

step_done

# ==================================================================
# ETAPA 7/8 - Gerar ISO
# ==================================================================
step_init 7 "Gerando ISO offline com xorriso"

# Calcular tamanho total
TOTAL_ISO_SIZE=$(du -sh "$WORK_DIR" | cut -f1)
log_info "Tamanho total da arvore ISO: $TOTAL_ISO_SIZE"
log_info "RPMs: $RPM_COUNT | Scripts: $TOTAL_CONTENT"

ISO_PATH="$OUT_DIR/$ISO_NAME"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

log_info "Gerando ISO hibrida (UEFI + BIOS)..."

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
    "$WORK_DIR" 2>&1 | tee -a "$LOG_FILE"

if [ ! -f "$ISO_PATH" ]; then
    log_err "ISO nao gerada!"
    exit 1
fi

ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
log_ok "ISO gerada: $ISO_PATH ($ISO_SIZE)"
step_done

# ==================================================================
# ETAPA 8/8 - isohybrid + checksum + resumo
# ==================================================================
step_init 8 "Aplicando isohybrid + checksum + resumo"

printf "    isohybrid --uefi... "
if isohybrid --uefi "$ISO_PATH" 2>>"$LOG_FILE"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}skip (ja hibrida)${NC}"
fi

cd "$OUT_DIR"
sha256sum "$ISO_NAME" > hash_iso.txt 2>/dev/null
log_ok "SHA256 gerado"

ISO_SIZE_FINAL=$(ls -lh "$ISO_NAME" | awk '{print $5}')
ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME" 2>/dev/null || echo 0)
BUILD_TOTAL=$(($(date +%s) - BUILD_START))
BUILD_MIN=$((BUILD_TOTAL / 60))
BUILD_SEC=$((BUILD_TOTAL % 60))

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║    ISO OFFLINE GERADA COM SUCESSO (a partir da ISO boot)!  ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Arquivo:${NC}  $OUT_DIR/$ISO_NAME"
echo -e "  ${BOLD}Tamanho:${NC}  $ISO_SIZE_FINAL"
echo -e "  ${BOLD}Checksum:${NC} $OUT_DIR/hash_iso.txt"
echo ""
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
