 #!/bin/bash

# ==============================================================================
# CONFIGURAÇÕES GERAIS
# ==============================================================================
DATA=$(date +%F)
ISO_BASE="OracleLinux-R9-U4-x86_64-dvd.iso" # <<< ARQUIVO ISO BASE DO ORACLE LINUX 9
ISO_NAME="ol9-custom-install-${DATA}.iso"
WORKDIR="/tmp/custom-iso"
ROOTFS="$WORKDIR/rootfs" # RootFS para o ambiente Live CD
RPM_EXTRA="./software_rpm"
FAVORITOS="./favoritos"
KICKSTART_FILE="kickstart.cfg"

MNT_BASE="$WORKDIR/mnt_base"
KERNEL_FILE="vmlinuz"
INITRD_FILE="initrd.img"

# REPOSITÓRIOS OFICIAIS (Oracle Linux 9)
REPO_BASE="https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/"
REPO_APPSTREAM="https://yum.oracle.com/repo/OracleLinux/OL9/appstream/latest/x86_64/"
REPO_EPEL="https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/"
REPO_RPMFUSION_FREE="https://download1.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm"
RPMFUSION_RELEASE_PKG="$WORKDIR/rpmfusion-release-pkg.rpm"

# ==============================================================================
# 🧹 LIMPEZA E DEPENDÊNCIAS
# ==============================================================================
echo "🧹 Limpando e preparando diretórios..."
rm -f ol9-custom-install-*.iso
rm -rf "$WORKDIR"
mkdir -p "$ROOTFS" "$MNT_BASE" "$WORKDIR/LiveOS" "$WORKDIR/rpms-extra"

echo "📦 Instalando dependências essenciais..."
sudo dnf install -y rsync xorriso squashfs-tools syslinux isomd5sum pykickstart createrepo_c wget curl dnf-utils

if [ ! -f "$ISO_BASE" ]; then
    echo "❌ Erro: O arquivo ISO base ($ISO_BASE) não foi encontrado."
    exit 1
fi

# ==============================================================================
# 1. PREPARAÇÃO: DOWNLOADS E CÓPIA DA ESTRUTURA BASE
# ==============================================================================
echo "⬇️ Baixando pacote de release do RPM Fusion e montando ISO base..."
wget -O "$RPMFUSION_RELEASE_PKG" "$REPO_RPMFUSION_FREE"

sudo mount -o loop "$ISO_BASE" "$MNT_BASE"

# Copiar arquivos de boot e estrutura do instalador (EFI, ISOLINUX, images)
cp "$MNT_BASE/isolinux/$KERNEL_FILE" "$WORKDIR/"
cp "$MNT_BASE/isolinux/$INITRD_FILE" "$WORKDIR/"
rsync -aAXv "$MNT_BASE/EFI" "$WORKDIR/"
rsync -aAXv "$MNT_BASE/images" "$WORKDIR/"
rsync -aAXv "$MNT_BASE/isolinux" "$WORKDIR/"
mkdir -p "$WORKDIR/BaseOS" "$WORKDIR/AppStream"
rsync -aAXv "$MNT_BASE/BaseOS/repodata" "$WORKDIR/BaseOS/"
rsync -aAXv "$MNT_BASE/AppStream/repodata" "$WORKDIR/AppStream/"

sudo umount "$MNT_BASE"

# ==============================================================================
# 2. CRIAÇÃO DO ROOTFS (LIVE CD) DO ZERO
# ==============================================================================
echo "🛠️ Criando um RootFS MÍNIMO para o Live CD com dnf..."

# 2.1 Instalar pacotes base no RootFS (usando dnf --installroot)
sudo dnf install -y --installroot="$ROOTFS" \
  kernel-core \
  dracut \
  systemd \
  yum \
  dnf \
  passwd \
  bash \
  coreutils \
  procps \
  iproute \
  openssh-clients \
  @core --exclude=dracut-config-generic

# 2.2 Configurar repositórios e instalar pacotes extras no Live CD
echo "⚙️ Configurando DNF, EPEL e RPM Fusion no Live CD RootFS..."

# Copiar arquivos necessários para o chroot
cp /etc/resolv.conf "$ROOTFS/etc/"
cp "$RPMFUSION_RELEASE_PKG" "$ROOTFS/tmp/"

# Adicionar repositórios básicos para o chroot
sudo chroot "$ROOTFS" /bin/bash <<EOF_CHROOT
  # Habilitar EPEL (se não foi instalado com dnf --installroot)
  dnf install -y $REPO_EPEL
  
  # Instalar RPM Fusion
  dnf install -y /tmp/$(basename "$RPMFUSION_RELEASE_PKG")
  
  # Instalar ambiente gráfico mínimo para o Live CD
  dnf groupinstall -y "Minimal Install"
  dnf install -y xterm
  
  # Instalar favoritos e pacotes extras (se forem necessários no Live CD)
  mkdir -p /home/usuario/Favoritos
  
  dnf clean all
  rm -f /tmp/$(basename "$RPMFUSION_RELEASE_PKG")
EOF_CHROOT

# 2.3 Incluir arquivos de personalização e pacotes RPM extras
echo "📁 Incluindo favoritos e pacotes RPM extras..."
cp -r "$FAVORITOS"/* "$ROOTFS/home/usuario/Favoritos"
cp "$RPM_EXTRA"/*.rpm "$WORKDIR/rpms-extra/"
cp "$RPMFUSION_RELEASE_PKG" "$WORKDIR/" # Copiar também para a raiz da ISO

# ==============================================================================
# 3. CRIAÇÃO DO SQUASHFS CUSTOMIZADO (LIVE CD)
# ==============================================================================
echo "🗜️ Compactando rootfs customizado (Live CD)..."
# Garantir que /boot e /dev não estão no squashfs
rm -rf "$ROOTFS/boot" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys"
mksquashfs "$ROOTFS" "$WORKDIR/LiveOS/custom.squashfs" -comp xz -Xbc

# ==============================================================================
# 4. GERAR ARQUIVO KICKSTART (INSTALAÇÃO)
# ==============================================================================
echo "📝 Gerando arquivo Kickstart com repositórios externos..."
cat <<EOF > "$WORKDIR/$KICKSTART_FILE"
#version=RHEL9
install
lang pt_BR.UTF-8
keyboard br-abnt2
timezone America/Sao_Paulo
network --bootproto=dhcp
rootpw --plaintext senha123
firewall --enabled
selinux --enforcing
reboot

# DEFINIÇÃO DOS REPOSITÓRIOS ONLINE PARA O ANACONDA 
repo --name="ol9_baseos" --baseurl=$REPO_BASE
repo --name="ol9_appstream" --baseurl=$REPO_APPSTREAM
repo --name="epel" --baseurl=$REPO_EPEL
url --url=$REPO_BASE

%packages
@^graphical-server-environment
gnome-terminal
firefox
# Adicionar outros pacotes, ex: vlc, htop
%end

%post
# 1. Instalar o pacote de release do RPM Fusion
echo "Instalando RPM Fusion no sistema instalado..."
cp /run/install/repo/$(basename "$RPMFUSION_RELEASE_PKG") /mnt/sysimage/tmp/
chroot /mnt/sysimage dnf install -y /tmp/$(basename "$RPMFUSION_RELEASE_PKG")
chroot /mnt/sysimage rm -f /tmp/$(basename "$RPMFUSION_RELEASE_PKG")

# 2. Instalar pacotes RPM Extras
echo "Instalando pacotes extras..."
cp -r /run/install/repo/rpms-extra/*.rpm /mnt/sysimage/root/
chroot /mnt/sysimage dnf install -y /root/*.rpm
chroot /mnt/sysimage rm -f /root/*.rpm
%end
EOF

# ==============================================================================
# 5. CONFIGURAÇÃO DE BOOT E GERAÇÃO DA ISO
# ==============================================================================
echo "⚙️ Ajustando isolinux.cfg para opções Live/Install..."
ISOCONF="$WORKDIR/isolinux/isolinux.cfg"
# O kernel/initrd copiado da ISO base será usado para todos os boots

# Adiciona as opções de boot customizadas ao arquivo isolinux.cfg
cat <<EOF >> "$ISOCONF"

label customlive
  menu label ^Custom OL9 Live Environment (Minimal)
  kernel /$KERNEL_FILE
  append initrd=/$INITRD_FILE root=live:LABEL=OracleLinux rd.live.image quiet

label custominstall
  menu label ^Custom OL9 Installation (Kickstart)
  kernel /$KERNEL_FILE
  append initrd=/$INITRD_FILE inst.stage2=hd:LABEL=OracleLinux inst.ks=hd:LABEL=OracleLinux:/$KICKSTART_FILE quiet

label livegui
  menu label ^Live CD com Instalador GUI (OL Padrão)
  kernel /$KERNEL_FILE
  append initrd=/$INITRD_FILE inst.stage2=hd:LABEL=OracleLinux inst.repo=hd:LABEL=OracleLinux quiet
EOF

# Geração da ISO
echo "🔥 Gerando imagem ISO híbrida..."
xorriso -as mkisofs \
  -isohybrid-mbr "$WORKDIR/isolinux/isohdpfx.bin" \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e EFI/BOOT/BOOTX64.EFI \
  -no-emul-boot \
  -V "OracleLinux" \
  -J -R -T -D \
  -r -T "$WORKDIR" \
  -o "$ISO_NAME"

isohybrid "$ISO_NAME"

echo "✅ ISO híbrida de Instalação/Live criada com sucesso: $ISO_NAME"
