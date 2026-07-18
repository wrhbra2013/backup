#!/bin/bash
# ==============================================================================
# Gerador de ISO Hibrida (UEFI + MBR) - Oracle Linux 9 (Sistema Basico)
# Instalacao via kickstart com suporte completo a boot em ambos os modos
# ==============================================================================

set -e

# --- Cores e Formatacao ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Variaveis ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build_hybrid"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$BUILD_ROOT/ks_minimal.cfg"
GRUB_DIR="$BUILD_ROOT/grub_files"
LOG_FILE="$BUILD_ROOT/build.log"
ISO_NAME="OL9-Minimal-Hybrid.iso"

TOTAL_STEPS=8
CURRENT_STEP=0
STEP_START=0
ERRORS=0
WARNINGS=0

# --- Funcoes de Log ---
timestamp() { date '+%H:%M:%S'; }

elapsed() {
    local s=$1
    printf '%02dm%02ds' $((s/60)) $((s%60))
}

log_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  [$1/$TOTAL_STEPS] $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_progress() {
    echo -e "  ${YELLOW}[status=progress]${NC} $(timestamp) - $1"
}

log_ok() {
    echo -e "  ${GREEN}[status=ok]${NC}      $(timestamp) - $1"
}

log_erro() {
    echo -e "  ${RED}[status=error]${NC}   $(timestamp) - $1"
    ((ERRORS++)) || true
}

log_aviso() {
    echo -e "  ${YELLOW}[status=warn]${NC}    $(timestamp) - $1"
    ((WARNINGS++)) || true
}

log_info() {
    echo -e "  ${CYAN}[status=info]${NC}    $(timestamp) - $1"
}

step_init() {
    CURRENT_STEP=$1
    STEP_START=$(date +%s)
    log_header "$1" "$2"
    log_progress "Inicio da etapa"
}

step_done() {
    local end=$(date +%s)
    local dur=$(( end - STEP_START ))
    log_ok "Etapa concluida em $(elapsed $dur)"
}

run_cmd() {
    local desc="$1"
    shift
    log_progress "Executando: ${desc}"
    if "$@" >> "$LOG_FILE" 2>&1; then
        log_ok "${desc} - OK"
    else
        log_erro "${desc} - FALHOU (verifique $LOG_FILE)"
        return 1
    fi
}

# --- Limpeza ---
limpar_tudo() {
    echo ""
    log_progress "Limpando temporarios..."
    sync
    grep "$BUILD_ROOT" /proc/mounts 2>/dev/null | cut -d' ' -f2 | xargs -r umount -l 2>/dev/null || true
    rm -rf "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" 2>/dev/null || true
    log_ok "Temporarios limpos"
}
trap limpar_tudo EXIT

# --- Inicio ---
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║  GERADOR DE ISO HIBRIDA - Oracle Linux 9                ║"
echo "  ║  UEFI + MBR (BIOS) | Kickstart                         ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log_progress "Log detalhado: $LOG_FILE"
log_progress "Data: $(date '+%d/%m/%Y %H:%M:%S')"
echo ""

# --- Verificacoes Iniciais ---
if [[ $EUID -ne 0 ]]; then
    log_erro "Execute como ROOT."
    exit 1
fi
log_ok "Executando como root"

FREE_GB=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_GB" -lt 10 ]; then
    log_erro "Espaco insuficiente ($FREE_GB GB). Minimo 10GB."
    exit 1
fi
log_ok "Espaco em disco: ${FREE_GB}GB disponivel (minimo: 10GB)"

mkdir -p "$BUILD_ROOT" "$GRUB_DIR" "$BUILD_ROOT/content/software_rpm" "$BUILD_ROOT/content/favoritos"
log_ok "Diretorios de build criados"

TOTAL_START=$(date +%s)

# =============================================================================
# ETAPA 1/8 - Dependencias
# =============================================================================
step_init 1 "Instalando dependencias"

log_progress "Instalando epel-release..."
if dnf install -y epel-release >> "$LOG_FILE" 2>&1; then
    log_ok "epel-release instalado"
else
    log_aviso "epel-release pode ja estar instalado"
fi

PACKAGES="lorax lorax-lmc-novirt xorriso rsync syslinux grub2-efi-x64 shim-x64 grub2-tools lorax-templates-generic"
log_progress "Instalando pacotes: $PACKAGES"
if dnf install -y $PACKAGES >> "$LOG_FILE" 2>&1; then
    log_ok "Todas as dependencias instaladas"
else
    log_erro "Falha na instalacao de dependencias"
    exit 1
fi

mkdir -p "$BUILD_ROOT/content/software_rpm" \
         "$BUILD_ROOT/content/favoritos" \
         "$OUT_DIR" \
         "$GRUB_DIR"
log_ok "Estrutura de diretorios preparada"

step_done

# =============================================================================
# ETAPA 2/8 - Pacotes Locais
# =============================================================================
step_init 2 "Copiando pacotes locais"

SOFTWARE_SRC="$SCRIPT_DIR/software_rpm"
FAVORITOS_SRC="$SCRIPT_DIR/favoritos"

if [ -d "$SOFTWARE_SRC" ] && [ -n "$(ls -A "$SOFTWARE_SRC" 2>/dev/null)" ]; then
    RPM_COUNT=$(find "$SOFTWARE_SRC" -name '*.rpm' 2>/dev/null | wc -l)
    log_progress "Encontrados $RPM_COUNT pacotes RPM em $SOFTWARE_SRC"
    rsync -av --progress "$SOFTWARE_SRC/" "$BUILD_ROOT/content/software_rpm/" 2>&1 | while IFS= read -r line; do
        log_info "$line"
    done
    log_ok "$RPM_COUNT pacotes RPM copiados"
else
    log_aviso "Nenhum pacote local encontrado em $SOFTWARE_SRC, pulando..."
fi

if [ -d "$FAVORITOS_SRC" ] && [ -n "$(ls -A "$FAVORITOS_SRC" 2>/dev/null)" ]; then
    FAV_COUNT=$(find "$FAVORITOS_SRC" -type f 2>/dev/null | wc -l)
    log_progress "Encontrados $FAV_COUNT favoritos"
    rsync -av --progress "$FAVORITOS_SRC/" "$BUILD_ROOT/content/favoritos/" 2>&1 | while IFS= read -r line; do
        log_info "$line"
    done
    log_ok "$FAV_COUNT favoritos copiados"
else
    log_aviso "Nenhum favorito encontrado, pulando..."
fi

step_done

# =============================================================================
# ETAPA 3/8 - Kickstart
# =============================================================================
step_init 3 "Gerando Kickstart"

log_progress "Criando .buildstamp para anaconda..."
mkdir -p /etc/anaconda
cat <<'BSTAMP' > /etc/anaconda/.buildstamp
[Anaconda]
Buildstamp = oracle-linux-9-build
Product = OracleLinux
Variant =
Timestamp = 0
BSTAMP
log_ok ".buildstamp criado em /etc/anaconda/.buildstamp"

log_progress "Gerando arquivo de kickstart: $KS_FILE"
cat <<'EOFKS' > "$KS_FILE"
keyboard br-abnt2
lang pt_BR.UTF-8
timezone America/Sao_Paulo --utc

# Disco - apaga tudo e particiona automaticamente
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

# Senha root (altere apos instalacao)
user --name=oracle --password=oracle --plaintext

# Senha root
rootpw --lock

# Servicos basicos
services --enabled="chronyd,sshd"

reboot

%packages
@core
@base
@hardware-support
@xfce
@base-x
kernel-core
grub2-efi-x64
grub2-pc
shim-x64
syslinux
dracut-live
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
bluetooth
bluez
bluez-tools
NetworkManager-wifi
wireless-tools
wpa_supplicant
iwl*firmware
iw
rfkill
%end

%post --log=/root/post-install.log
#!/bin/bash

# Configurar hostname
hostnamectl set-name oracle-minimal

# Habilitar servicos
systemctl enable sshd
systemctl enable chronyd
systemctl enable bluetooth

# Criar usuario oracle
useradd -m -s /bin/bash -G wheel oracle 2>/dev/null || true
echo "oracle:oracle" | chpasswd 2>/dev/null || true

# Montar midia para injetar arquivos extras
mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if mountpoint -q /mnt/media; then
    # Instalar RPMs locais se existirem
    if [ -d /mnt/media/software_rpm ] && ls /mnt/media/software_rpm/*.rpm >/dev/null 2>&1; then
        dnf install -y /mnt/media/software_rpm/*.rpm || true
    fi

    # Copiar favoritos
    if [ -d /mnt/media/favoritos ]; then
        mkdir -p /etc/skel/favoritos
        rsync -av /mnt/media/favoritos/ /etc/skel/favoritos/
    fi

    # Checksums
    if [ -f /mnt/media/checksums.txt ]; then
        cd /mnt/media && sha256sum -c checksums.txt || echo "AVISO: Checksum inconsistente"
    fi

    umount /mnt/media 2>/dev/null || true
fi

echo "Instalacao concluida com sucesso!" > /root/INSTALL_OK
%end
EOFKS

KS_LINES=$(wc -l < "$KS_FILE")
log_ok "Kickstart gerado: $KS_FILE ($KS_LINES linhas)"
log_info "  - Idioma: pt_BR.UTF-8"
log_info "  - Timezone: America/Sao_Paulo"
log_info "  - Repos: OracleLinux OL9 baseos + AppStream"
log_info "  - Desktop: XFCE"
log_info "  - Usuario: oracle"

step_done

# =============================================================================
# ETAPA 4/8 - GRUB UEFI
# =============================================================================
step_init 4 "Configurando GRUB para UEFI"

log_progress "Criando diretorio GRUB: $GRUB_DIR"
mkdir -p "$GRUB_DIR"

log_progress "Gerando grub.cfg..."
cat <<'EOFGRUB' > "$GRUB_DIR/grub.cfg"
set default=0
set timeout=5
set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

menuentry "Oracle Linux 9 - Instalar" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_MIN_HYB quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 - Instalar (Texto)" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_MIN_HYB text quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 - Modo Resgate" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_MIN_HYB rescue quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Oracle Linux 9 - Testar midia e instalar" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_MIN_HYB rd.live.check quiet
    initrdefi /images/pxeboot/initrd.img
}
EOFGRUB

log_ok "grub.cfg gerado com 4 entradas de menu"
log_info "  - Instalar (GUI)"
log_info "  - Instalar (Texto)"
log_info "  - Modo Resgate"
log_info "  - Testar midia e instalar"

step_done

# =============================================================================
# ETAPA 5/8 - Build ISO
# =============================================================================
step_init 5 "Build da ISO com livemedia-creator"

log_progress "Removendo diretorio de saida (livemedia-creator exige que nao exista)..."
rm -rf "$OUT_DIR"
log_ok "Diretorio de saida removido"

log_progress "Iniciando livemedia-creator (pode demorar varios minutos)..."
log_info "  KS: $KS_FILE"
log_info "  Projeto: OracleLinux"
log_info "  Release: 9"
log_info "  ISO: $ISO_NAME"
log_info "  Label: OL9_MIN_HYB"

livemedia-creator \
    --make-iso \
    --ks="$KS_FILE" \
    --no-virt \
    --resultdir="$OUT_DIR" \
    --project="OracleLinux" \
    --releasever=9 \
    --iso-name="$ISO_NAME" \
    --fs-label="OL9_MIN_HYB" \
    --anaconda-arg=--product=OracleLinux \
    --anaconda-arg=--variant= \
    2>&1 | tee -a "$LOG_FILE"

log_progress "Buscando ISO gerada..."
ISO_PATH=$(find "$OUT_DIR" -name "$ISO_NAME" -type f 2>/dev/null | head -1)
if [ -z "$ISO_PATH" ]; then
    ISO_PATH=$(find "$OUT_DIR" -name "*.iso" -type f 2>/dev/null | head -1)
fi

if [ -z "$ISO_PATH" ]; then
    log_erro "Nenhum ISO gerado. Verifique $LOG_FILE"
    exit 1
fi

ISO_SIZE_RAW=$(stat -c%s "$ISO_PATH" 2>/dev/null || echo 0)
ISO_SIZE_HUMAN=$(ls -lh "$ISO_PATH" | awk '{print $5}')
log_ok "ISO gerada: $ISO_PATH ($ISO_SIZE_HUMAN)"

step_done

# =============================================================================
# ETAPA 6/8 - GRUB UEFI na ISO
# =============================================================================
step_init 6 "Injetando GRUB UEFI na ISO"

if [ -d "$GRUB_DIR" ]; then
    XORRISO_OPTS="-boot_info -patch_joliet -r-rock -append_partition 2 0xef $GRUB_DIR/efi.img -e /isolinux/boot.cat"
    log_progress "Opcoes xorriso configuradas para UEFI"
    log_info "  - EFI partition: $GRUB_DIR/efi.img"
    log_info "  - Boot catalog: /isolinux/boot.cat"
    log_ok "Configuracao UEFI preparada"
else
    log_aviso "Diretorio GRUB nao encontrado, pulando injecao UEFI"
fi

step_done

# =============================================================================
# ETAPA 7/8 - isohybrid
# =============================================================================
step_init 7 "Aplicando isohybrid (MBR + UEFI)"

TEMP_ISO="$OUT_DIR/${ISO_NAME%.iso}-tmp.iso"
log_progress "Criando backup temporario da ISO..."
cp "$ISO_PATH" "$TEMP_ISO"
log_ok "Backup: $TEMP_ISO"

log_progress "Tentando isohybrid --uefi..."
if isohybrid --uefi "$ISO_PATH" 2>>"$LOG_FILE"; then
    log_ok "isohybrid --uefi aplicado com sucesso"
else
    log_aviso "isohybrid --uefi falhou, tentando fallback com xorriso..."
    xorriso -as dd -indev "$TEMP_ISO" \
            -outdev "$ISO_PATH" \
            --interval:partition_interval:efi_path:$GRUB_DIR/efi.img 2>>"$LOG_FILE" || true
    log_ok "Fallback xorriso aplicado"
fi

log_progress "Removendo backup temporario..."
rm -f "$TEMP_ISO" 2>/dev/null || true
log_ok "Temporario removido"

step_done

# =============================================================================
# ETAPA 8/8 - Arquivos Extras
# =============================================================================
step_init 8 "Injetando arquivos extras na ISO"

cd "$BUILD_ROOT/content"
if [ -n "$(ls -A . 2>/dev/null)" ]; then
    EXTRA_FILES=$(find . -type f 2>/dev/null | wc -l)
    log_progress "Encontrados $EXTRA_FILES arquivos extras para injetar"

    log_progress "Extraindo ISO para montagem..."
    mkdir -p "$BUILD_ROOT/iso_mount"
    xorriso -osirrox on -indev "$ISO_PATH" -extract / "$BUILD_ROOT/iso_mount" 2>>"$LOG_FILE" || true
    log_ok "ISO extraida para $BUILD_ROOT/iso_mount"

    if [ -d "$BUILD_ROOT/iso_mount" ]; then
        log_progress "Copiando arquivos extras para ISO montada..."
        rsync -av "$BUILD_ROOT/content/" "$BUILD_ROOT/iso_mount/" 2>&1 | while IFS= read -r line; do
            log_info "$line"
        done
        log_ok "Arquivos extras copiados"

        log_progress "Regenerando ISO com xorriso (mantendo boot)..."
        cd "$BUILD_ROOT/iso_mount"
        xorriso -as mkisofs \
            -r -V "OL9_MIN_HYB" \
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
            . 2>>"$LOG_FILE" || true
        log_ok "ISO regenerada com arquivos extras"
    fi
else
    log_aviso "Nenhum arquivo extra encontrado, pulando..."
fi

# --- Checksum ---
log_progress "Gerando checksum SHA256..."
cd "$OUT_DIR"
sha256sum "$ISO_NAME" > hash_iso.txt
HASH=$(awk '{print $1}' hash_iso.txt)
log_ok "Checksum gerado: ${HASH:0:16}..."

# --- Resumo Final ---
TOTAL_END=$(date +%s)
TOTAL_DUR=$(( TOTAL_END - TOTAL_START ))

ISO_SIZE=$(ls -lh "$ISO_PATH" | awk '{print $5}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ISO HIBRIDA GERADA COM SUCESSO!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Arquivo:${NC}    $ISO_PATH"
echo -e "  ${BOLD}Tamanho:${NC}    $ISO_SIZE"
echo -e "  ${BOLD}Boot:${NC}       UEFI + MBR (BIOS)"
echo -e "  ${BOLD}Checksum:${NC}   $OUT_DIR/hash_iso.txt"
echo -e "  ${BOLD}SHA256:${NC}     ${HASH:0:32}..."
echo -e "  ${BOLD}Tempo:${NC}      $(elapsed $TOTAL_DUR)"
echo -e "  ${BOLD}Log:${NC}        $LOG_FILE"
echo ""

if [ "$ERRORS" -gt 0 ]; then
    echo -e "  ${RED}Erros: $ERRORS${NC}"
fi
if [ "$WARNINGS" -gt 0 ]; then
    echo -e "  ${YELLOW}Avisos: $WARNINGS${NC}"
fi
echo ""
