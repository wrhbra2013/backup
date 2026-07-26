#!/bin/bash
#============================================================
# Script: rebuild_ol9_xfce_offline.sh
# Objetivo: Reconstruir a ISO OL9-Offline-Completa.iso com
#           instalação 100% offline do XFCE4
#
# Pré-requisitos: dnf, sudo, createrepo_c, xorriso
# Uso: sudo bash rebuild_ol9_xfce_offline.sh
#============================================================
set -euo pipefail

# ============================================================
# CONFIGURAÇÃO
# ============================================================
ISO_ORIGEM="/home/wander/ISO/OL9-Offline-Completa.iso"
ISO_DESTINO="/home/wander/ISO/OL9-XFCE-Offline-Completa.iso"
MOUNT_POINT="/tmp/iso_mount"
WORK_DIR="/tmp/iso_build"
INSTALLROOT="${WORK_DIR}/installroot"
PKGDIR="${WORK_DIR}/Packages"
VOLUME_ID="OL9_OFFLINE_XFCE"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()    { echo -e "${GREEN}[$(date +%H:%M:%S)] OK:${NC} $1"; }
warn()  { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $1"; }
err()   { echo -e "${RED}[$(date +%H:%M:%S)] ERRO:${NC} $1"; }
fatal() { err "$1"; exit 1; }

# ============================================================
# VERIFICAÇÕES INICIAIS
# ============================================================
[[ $EUID -ne 0 ]] && fatal "Execute como root: sudo bash $0"
[[ ! -f "$ISO_ORIGEM" ]] && fatal "ISO original não encontrada: $ISO_ORIGEM"

for cmd in dnf createrepo_c xorriso; do
    command -v "$cmd" &>/dev/null || fatal "Dependência '$cmd' não encontrada. Instale com: dnf install $cmd"
done

log "========================================="
log "  REBUILD OL9 XFCE OFFLINE"
log "========================================="
log "ISO origem:    $ISO_ORIGEM"
log "ISO destino:   $ISO_DESTINO"
log "Volume ID:     $VOLUME_ID"
log ""

# ============================================================
# ETAPA 1: Limpeza e preparação
# ============================================================
log "ETAPA 1/7: Limpeza e preparação do ambiente..."

# Mata processos dnf anteriores
pkill -9 -f "dnf.*installroot" 2>/dev/null || true
sleep 1

# Desmonta ISO anterior se montada
umount "$MOUNT_POINT" 2>/dev/null || true

# Limpa diretórios de trabalho
rm -rf "$WORK_DIR"
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT" "$WORK_DIR" "$PKGDIR"

ok "Ambiente preparado"

# ============================================================
# ETAPA 2: Montar ISO original
# ============================================================
log "ETAPA 2/7: Montando ISO original..."
mount -o loop "$ISO_ORIGEM" "$MOUNT_POINT"
ok "ISO montada em $MOUNT_POINT"

# ============================================================
# ETAPA 3: Copiar estrutura base da ISO
# ============================================================
log "ETAPA 3/7: Copiando estrutura base da ISO..."

# Copia tudo exceto Packages/ antigo
for item in "$MOUNT_POINT"/*; do
    basename=$(basename "$item")
    if [[ "$basename" == "Packages" ]]; then
        continue
    fi
    cp -a "$item" "$WORK_DIR/"
done

# Mantém a estrutura
mkdir -p "$WORK_DIR/Packages"
ok "Estrutura base copiada"

# ============================================================
# ETAPA 4: Baixar pacotes para instalação offline completa
# ============================================================
log "ETAPA 4/7: Baixando pacotes via dnf (resolve dependências)... [status=progress]"
log "  Isso pode demorar 10-30 minutos dependendo da conexão... [status=progress]"

# Cria installroot limpo
rm -rf "$INSTALLROOT"
mkdir -p "$INSTALLROOT"

dnf --releasever=9 \
    --installroot="$INSTALLROOT" \
    --setopt=keepcache=True \
    --setopt=install_weak_deps=False \
    -y install \
    @core @base @base-x @hardware-support \
    xfce4-session xfce4-panel xfwm4 xfdesktop thunar thunar-volman \
    xfce4-terminal xfce4-settings xfce4-power-manager xfce4-notifyd \
    xfce4-screenshooter xfce4-taskmanager xfce4-whiskermenu-plugin \
    xfce4-appfinder xfconf garcon mousepad parole ristretto \
    gdm \
    kernel-core grub2-efi-x64 grub2-pc shim-x64 syslinux dracut-live \
    bluez bluez-obexd NetworkManager-wifi \
    wpa_supplicant iw rfkill rsync chrony openssh-server bash-completion \
    vim-minimal nano wget curl net-tools iproute NetworkManager chromium \
    alsa-utils pipewire pipewire-pulseaudio \
    make gcc rpm-build tar gzip python3 htop lm_sensors \
    --exclude='kernel-uek*' \
    --exclude='dnf-plugin-spacewalk' \
    --exclude='rhn-client-tools' \
    --exclude='rhn-setup' \
    --exclude='rhnlib' \
    --exclude='rhnsd' 2>&1 | while IFS= read -r line; do
        [ -z "$line" ] && continue
        log "  $line [status=progress]"
    done

ok "Pacotes baixados pelo dnf [status=completed]"

# Copia RPMs do cache para Packages/
log "  Copiando RPMs do cache para Packages/..."
find "$INSTALLROOT/var/cache/dnf" -name "*.rpm" -exec cp -u {} "$PKGDIR/" \;

TOTAL=$(ls "$PKGDIR"/*.rpm 2>/dev/null | wc -l)
SIZE=$(du -sh "$PKGDIR" | cut -f1)

if [[ "$TOTAL" -lt 100 ]]; then
    fatal "Poucos pacotes baixados ($TOTAL). Verifique a conexão ou erros do dnf."
fi

ok "Pacotes: $TOTAL arquivos, tamanho $SIZE"

# ============================================================
# ETAPA 5: Gerar repodata
# ============================================================
log "ETAPA 5/7: Gerando repodata para o repo local..."

createrepo_c --database "$PKGDIR"
ok "Repodata criada em $PKGDIR/repodata/"

# ============================================================
# ETAPA 6: Atualizar ks.cfg para 100% offline
# ============================================================
log "ETAPA 6/7: Atualizando ks.cfg para instalação 100% offline..."

cat > "$WORK_DIR/ks.cfg" << 'KSEOF'
keyboard br-abnt2
lang pt_BR.UTF-8
timezone America/Sao_Paulo --utc

zerombr
clearpart --all --initlabel
autopart --type=plain

bootloader --location=mbr --driveorder=sda

repo --name="Packages" --baseurl=file:///run/install/repo/Packages --noverifyssl

network --bootproto=dhcp --activate

user --name=oracle --password=oracle --plaintext
rootpw --lock

services --enabled="chronyd,sshd,bluetooth,NetworkManager"

reboot

%packages
@core
@base
@base-x
@hardware-support

# --- XFCE4 Desktop (ambiente completo) ---
xfce4-session
xfce4-panel
xfce4-settings
xfce4-appfinder
xfce4-power-manager
xfce4-notifyd
xfce4-screenshooter
xfce4-taskmanager
xfce4-whiskermenu-plugin
xfwm4
xfdesktop
xfconf
garcon
thunar
thunar-volman
mousepad
parole
ristretto

# --- Display Manager ---
gdm

# --- Kernel e Boot ---
kernel-core
grub2-efi-x64
grub2-pc
shim-x64
syslinux
dracut-live

# --- Bluetooth ---
bluez
bluez-obexd

# --- Rede e Wireless ---
NetworkManager-wifi
wpa_supplicant
iw
rfkill

# --- Sistema e Utilitários ---
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

# --- Áudio ---
alsa-utils
pipewire
pipewire-pulseaudio

# --- Desenvolvimento ---
make
gcc
rpm-build
tar
gzip
python3

# --- Monitoramento ---
htop
lm_sensors

# --- Navegador ---
chromium

# --- Excluir pacotes indesejados ---
-dnf-plugin-spacewalk
-rhn-client-tools
-rhn-setup
-rhnlib
-rhnsd
%end

%post --log=/root/post-install.log
#!/bin/bash
set -x

hostnamectl set-name oracle-offline

systemctl enable sshd
systemctl enable chronyd
systemctl enable bluetooth
systemctl enable NetworkManager
systemctl enable gdm

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

cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'NMEOF'
[connection]
wifi.powersave = 2
NMEOF

ln -sf /opt/system_scripts/ol9-full-setup.sh /usr/local/bin/ol9-setup 2>/dev/null || true
ln -sf /opt/system_scripts/otimizar-xfce.sh /usr/local/bin/otimizar-xfce 2>/dev/null || true

echo "Instalacao offline XFCE concluida: $(date)" > /root/INSTALL_OK
%end
KSEOF

ok "ks.cfg atualizado (100% offline, XFCE4 como padrão)"

# ============================================================
# ETAPA 7: Gerar nova ISO
# ============================================================
log "ETAPA 7/7: Gerando nova ISO com xorriso..."

ISO_SIZE=$(du -sb "$WORK_DIR" | cut -f1)
ISO_SIZE_GB=$(echo "scale=2; $ISO_SIZE / 1073741824" | bc)
log "  Tamanho da ISO estimado: ${ISO_SIZE_GB}GB"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "$VOLUME_ID" \
    -output "$ISO_DESTINO" \
    -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/boot.cat \
    -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    "$WORK_DIR"

ok "ISO gerada: $ISO_DESTINO"

# ============================================================
# LIMPEZA E RELATÓRIO FINAL
# ============================================================
umount "$MOUNT_POINT" 2>/dev/null || true

FINAL_SIZE=$(du -h "$ISO_DESTINO" | cut -f1)
FINAL_RPMS=$(ls "$PKGDIR"/*.rpm 2>/dev/null | wc -l)

echo ""
log "========================================="
log "  CONSTRUÇÃO CONCLUÍDA"
log "========================================="
log "ISO destino:  $ISO_DESTINO"
log "Tamanho:      $FINAL_SIZE"
log "Pacotes:      $FINAL_RPMS RPMs"
log "Volume ID:    $VOLUME_ID"
log ""
log "Modos de boot disponíveis:"
log "  BIOS:  Instalar / Kickstart auto (XFCE)"
log "  UEFI:  Instalar / Kickstart auto (XFCE)"
log ""
log "Kickstart (auto): selecionar 'Instalar com Kickstart' no menu"
log "  - Instala XFCE4 como ambiente padrão"
log "  - 100% offline (sem dependência de internet)"
log "  - Usuário: oracle/oracle"
log "========================================="
