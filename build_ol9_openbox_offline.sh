#!/bin/bash
#============================================================
# Script: build_ol9_openbox_offline.sh
# Objetivo: Corrigir OL9-Offline-Completa.iso instalando
#           Openbox como ambiente padrão (auto-login), com
#           pacotes para Wi-Fi automático. 100% offline.
#
# Pré-requisitos: dnf, sudo, createrepo_c, xorriso
# Uso: sudo bash build_ol9_openbox_offline.sh
#============================================================
set -euo pipefail

# ============================================================
# CONFIGURAÇÃO
# ============================================================
ISO_SRC="/mnt/iso_ol9"
ISO_ORIGEM="/home/wander/ISO/OL9-Offline-Completa.iso"
ISO_DESTINO="/home/wander/ISO/OL9-Offline-Completa.iso"
ISO_STAGING="/tmp/ol9_openbox_build/OL9-Openbox-Offline-Completa.iso"
WORK_DIR="/tmp/ol9_openbox_build"
INSTALLROOT="${WORK_DIR}/installroot"
PKGDIR="${WORK_DIR}/Packages"
VOLUME_ID="OL9_OFFLINE_OPENBOX"

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

[[ $EUID -ne 0 ]] && fatal "Execute como root: sudo bash $0"
[[ ! -d "$ISO_SRC" ]] && fatal "Monte a ISO fonte em $ISO_SRC (mount -o loop $ISO_ORIGEM $ISO_SRC)"

for cmd in dnf createrepo_c xorriso; do
    command -v "$cmd" &>/dev/null || fatal "Dependência '$cmd' não encontrada."
done
[[ -f /usr/share/syslinux/isohdpfx.bin ]] || fatal "Falta /usr/share/syslinux/isohdpfx.bin"

log "========================================="
log "  REBUILD OL9 OPENBOX OFFLINE"
log "========================================="
log "ISO fonte:   $ISO_ORIGEM"
log "Volume ID:   $VOLUME_ID"
log ""

# ============================================================
# ETAPA 1: Limpeza e preparação
# ============================================================
log "ETAPA 1/8: Limpeza e preparação..."
pkill -9 -f "dnf.*installroot" 2>/dev/null || true
sleep 1
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$PKGDIR"
ok "Ambiente preparado em $WORK_DIR"

# ============================================================
# ETAPA 2: Copiar estrutura base da ISO (exceto Packages antigo)
# ============================================================
log "ETAPA 2/8: Copiando estrutura base da ISO..."
for item in "$ISO_SRC"/*; do
    base=$(basename "$item")
    [[ "$base" == "Packages" ]] && continue
    cp -a "$item" "$WORK_DIR/"
done
mkdir -p "$WORK_DIR/Packages"
ok "Estrutura base copiada"

# ============================================================
# ETAPA 3: Copiar pacotes do ISO XFCE (reuso, base completa)
# ============================================================
# O ISO XFCE (OL9-XFCE-Offline-Completa.iso) já contém os RPMs
# dos grupos base (@core @base @base-x @hardware-support).
# Reutilizamos para evitar rebaixar ~1.5GB da internet.
XFCE_PKG="/mnt/iso_xfce/Packages"
if [ -d "$XFCE_PKG" ]; then
    log "ETAPA 3/8: Reutilizando pacotes base do ISO XFCE..."
    cp -a "$XFCE_PKG"/. "$PKGDIR/"
    # Remove repodata antigo (será regenerado)
    rm -rf "$PKGDIR/repodata"
    ok "Copiados $(ls "$PKGDIR"/*.rpm 2>/dev/null | wc -l) RPMs do ISO XFCE"
else
    log "ETAPA 3/8: ISO XFCE não montado; pacotes base virão via dnf."
fi

# ============================================================
# ETAPA 4: Baixar pacotes extras (openbox + wifi) via dnf
# ============================================================
log "ETAPA 4/8: Baixando pacotes extras via dnf download --resolve..."

dnf download \
    --destdir="$PKGDIR" \
    --resolve \
    --alldeps \
    --setopt=install_weak_deps=False \
    --disablerepo=ol9_UEKR7,ol9_codeready_builder \
    --exclude='kernel-uek*' \
    openbox tint2 xcompmgr polkit-gnome network-manager-applet \
    wmctrl xdotool xterm 2>&1 | grep -vE '^$|Falha ao carregar' || true

if ! ls "$PKGDIR"/openbox-*.rpm >/dev/null 2>&1; then
    fatal "openbox não disponível em Packages. Verifique os repositórios."
fi

TOTAL=$(ls "$PKGDIR"/*.rpm 2>/dev/null | wc -l)
SIZE=$(du -sh "$PKGDIR" | cut -f1)
ok "Total no Packages/: $TOTAL RPMs, $SIZE"

# ============================================================
# ETAPA 5: Gerar repodata (com grupos comps.xml)
# ============================================================
log "ETAPA 5/8: Gerando repodata (grupos comps.xml)..."

# Comps (grupos @core @base @base-x @hardware-support) vindos do cache do host
BASEOS_COMPS=$(ls /var/cache/dnf/ol9_baseos_latest-*/repodata/*-comps.xml.gz 2>/dev/null | head -1)
APPSTREAM_COMPS=$(ls /var/cache/dnf/ol9_appstream-*/repodata/*-comps.xml.gz 2>/dev/null | head -1)

if [[ -n "$BASEOS_COMPS" && -n "$APPSTREAM_COMPS" ]]; then
    zcat "$BASEOS_COMPS" > "$WORK_DIR/comps_baseos.xml"
    zcat "$APPSTREAM_COMPS" > "$WORK_DIR/comps_appstream.xml"
    python3 << 'PYEOF'
import re
import xml.etree.ElementTree as ET

def load(path):
    data = open(path).read()
    data = re.sub(r'<!DOCTYPE[^>]*>', '', data)
    return ET.fromstring(data)

def ids(root, tag):
    return [el.findtext('id') for el in root.findall(tag)]

comps = ET.Element('comps')
b = load('/tmp/ol9_openbox_build/comps_baseos.xml')
a = load('/tmp/ol9_openbox_build/comps_appstream.xml')

for tag in ('group', 'category', 'environment'):
    seen = set(ids(comps, tag))
    for src in (b, a):
        for el in src.findall(tag):
            ident = el.findtext('id')
            if ident not in seen:
                seen.add(ident)
                comps.append(el)
lp = b.find('langpacks')
if lp is not None:
    comps.append(lp)

tree = ET.ElementTree(comps)
tree.write('/tmp/ol9_openbox_build/comps_merged.xml', encoding='UTF-8', xml_declaration=True)
PYEOF
    createrepo_c --database --groupfile "$WORK_DIR/comps_merged.xml" "$PKGDIR"
else
    warn "comps.xml não encontrado no cache; grupos kickstart podem falhar"
    createrepo_c --database "$PKGDIR"
fi
ok "Repodata criada"

# ============================================================
# ETAPA 6: Atualizar ks.cfg (Openbox padrão, auto-login, wifi)
# ============================================================
log "ETAPA 6/8: Gravando ks.cfg..."

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

# --- Openbox (ambiente padrão, leve) ---
openbox
tint2
xcompmgr
polkit-gnome
wmctrl
xdotool
xorg-x11-xinit

# --- Aplicativos ---
xfce4-terminal
xterm
thunar
thunar-volman
gvfs

# --- Kernel e Boot ---
kernel-core
grub2-efi-x64
grub2-pc
shim-x64
syslinux
dracut-live

# --- Bluetooth ---
bluez

# --- Rede e Wireless (Wi-Fi automático) ---
NetworkManager-wifi
NetworkManager-tui
wpa_supplicant
iw

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

hostnamectl set-name oracle-openbox

systemctl enable sshd
systemctl enable chronyd
systemctl enable bluetooth
systemctl enable NetworkManager

useradd -m -s /bin/bash -G wheel oracle 2>/dev/null || true
echo "oracle:oracle" | chpasswd 2>/dev/null || true

# =============================================
# Auto-login do usuário oracle no tty1
# =============================================
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'TEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin oracle --noclear tty1 $TERM
TEOF
systemctl daemon-reload

# =============================================
# Sessão X: startx -> openbox-session (dbus)
# =============================================
cat > /etc/skel/.bash_profile << 'BEOF'
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-}" = "1" ]; then
    exec startx
fi
BEOF

cat > /etc/skel/.xinitrc << 'XEOF'
#!/bin/sh
if [ -x /usr/bin/dbus-launch ]; then
    exec dbus-launch --exit-with-session openbox-session
else
    exec openbox-session
fi
XEOF

# Aplica ao usuário oracle (já criado pelo kickstart)
cp -f /etc/skel/.bash_profile /home/oracle/.bash_profile
cp -f /etc/skel/.xinitrc /home/oracle/.xinitrc
chown oracle:oracle /home/oracle/.bash_profile /home/oracle/.xinitrc

# =============================================
# Openbox: autostart (painel, wifi, compositor, polkit)
# =============================================
cat > /etc/xdg/openbox/autostart << 'AEOF'
# Compositor leve
xcompmgr &
# Painel/taskbar (fornece a bandeja de sistema)
tint2 &
# Agente de autenticação (polkit)
if [ -x /usr/libexec/polkit-gnome-authentication-agent-1 ]; then
    /usr/libexec/polkit-gnome-authentication-agent-1 &
fi
# Applet de rede (Wi-Fi na bandeja)
if [ -x /usr/bin/nm-applet ]; then
    nm-applet &
fi
# Fundo de tela simples
if [ -x /usr/bin/xsetroot ]; then
    xsetroot -solid "#2E3440" &
fi
AEOF

# =============================================
# Menu do Openbox (estático e funcional)
# =============================================
cat > /etc/xdg/openbox/menu.xml << 'MEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Menu">
    <item label="Terminal">
      <action name="Execute"><command>xfce4-terminal</command></action>
    </item>
    <item label="Gerenciador de Arquivos">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="Navegador Chromium">
      <action name="Execute"><command>chromium</command></action>
    </item>
    <separator/>
    <item label="Configurar Wi-Fi (nmtui)">
      <action name="Execute"><command>xfce4-terminal -e nmtui</command></action>
    </item>
    <item label="Monitor do Sistema (htop)">
      <action name="Execute"><command>xfce4-terminal -e htop</command></action>
    </item>
    <separator/>
    <item label="Reiniciar Openbox">
      <action name="Restart"/>
    </item>
    <item label="Sair">
      <action name="Exit"/>
    </item>
  </menu>
</openbox_menu>
MEOF

# =============================================
# Wi-Fi automático: NetworkManager + powersave off
# =============================================
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf << 'NMEOF'
[connection]
wifi.powersave = 2
NMEOF

cat > /etc/NetworkManager/conf.d/autoconnect.conf << 'NMOF'
[connection]
autoconnect = true
[main]
autoconnect = true
NMOF

systemctl enable NetworkManager-wait-online.service 2>/dev/null || true

# =============================================
# Copiar scripts/conteúdo do disco instalador
# =============================================
mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if mountpoint -q /mnt/media; then
    for SCRIPT in update-appimages.sh create_rpm.sh fix-repos-ol9.sh; do
        if [ -f "/mnt/media/content/$SCRIPT" ]; then
            rsync -a "/mnt/media/content/$SCRIPT" /usr/local/bin/
            chmod +x "/usr/local/bin/$SCRIPT"
        fi
    done

    for DIR in system_scripts vm_scripts bluetooth; do
        if [ -d "/mnt/media/content/$DIR" ]; then
            rsync -av "/mnt/media/content/$DIR/" "/opt/$DIR/"
            chmod -R +x "/opt/$DIR/" 2>/dev/null || true
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

# Aliases úteis
cat > /etc/profile.d/openbox.sh << 'PEOF'
alias wifi='nmcli dev wifi list'
alias wifi-on='nmcli radio wifi on'
alias wifi-off='nmcli radio wifi off'
alias wifi-config='nmtui'
PEOF

ln -sf /opt/system_scripts/ol9-full-setup.sh /usr/local/bin/ol9-setup 2>/dev/null || true

echo "Instalacao offline Openbox concluida: $(date)" > /root/INSTALL_OK
%end
KSEOF

ok "ks.cfg gravado"

# ============================================================
# ETAPA 7: Atualizar isolinux.cfg e grub (novo label)
# ============================================================
log "ETAPA 7/8: Atualizando configurações de boot..."

OLD_LABEL="OL9_OFFLINE_XFCE"
NEW_LABEL="OL9_OFFLINE_OPENBOX"

# isolinux.cfg
sed -i "s/$OLD_LABEL/$NEW_LABEL/g" "$WORK_DIR/isolinux/isolinux.cfg"
sed -i 's/Instalar com Kickstart (auto, XFCE)/Instalar com Kickstart (auto, Openbox)/' "$WORK_DIR/isolinux/isolinux.cfg"

# EFI grub.cfg
sed -i "s/$OLD_LABEL/$NEW_LABEL/g" "$WORK_DIR/EFI/BOOT/grub.cfg"
sed -i 's/Instalar com Kickstart (auto, XFCE)/Instalar com Kickstart (auto, Openbox)/' "$WORK_DIR/EFI/BOOT/grub.cfg"

# efiboot.img (imagem FAT com próprio grub.cfg)
EFIBOOT="$WORK_DIR/images/efiboot.img"
EFI_MNT="$WORK_DIR/efiboot_mnt"
mkdir -p "$EFI_MNT"
mount -o loop "$EFIBOOT" "$EFI_MNT"
sed -i "s/$OLD_LABEL/$NEW_LABEL/g" "$EFI_MNT/EFI/BOOT/grub.cfg"
sed -i 's/Instalar com Kickstart (auto, XFCE)/Instalar com Kickstart (auto, Openbox)/' "$EFI_MNT/EFI/BOOT/grub.cfg"
umount "$EFI_MNT"
rmdir "$EFI_MNT"
ok "Boot configs atualizados para $NEW_LABEL"

# ============================================================
# ETAPA 8: Gerar nova ISO com xorriso
# ============================================================
log "ETAPA 8/8: Gerando nova ISO com xorriso..."

ISO_SIZE=$(du -sb "$WORK_DIR" | cut -f1)
ISO_SIZE_GB=$(echo "scale=2; $ISO_SIZE / 1073741824" | bc)
log "  Tamanho estimado da ISO: ${ISO_SIZE_GB}GB"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "$VOLUME_ID" \
    -output "$ISO_STAGING" \
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

ok "ISO gerada em $ISO_STAGING"

# ============================================================
# LIMPEZA E RELATÓRIO FINAL
# ============================================================
FINAL_SIZE=$(du -h "$ISO_STAGING" | cut -f1)
FINAL_RPMS=$(ls "$PKGDIR"/*.rpm 2>/dev/null | wc -l)

echo ""
log "========================================="
log "  CONSTRUÇÃO CONCLUÍDA (staging)"
log "========================================="
log "ISO:          $ISO_STAGING"
log "Tamanho:      $FINAL_SIZE"
log "Pacotes:      $FINAL_RPMS RPMs"
log "Volume ID:    $VOLUME_ID"
log "========================================="
log "Agora substitua a ISO original com:"
log "  mv $ISO_STAGING $ISO_DESTINO"
log "========================================="
