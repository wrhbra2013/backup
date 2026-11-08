 #!/bin/bash
# ==============================================================================
# Gerador de ISO Customizada Oracle Linux 9.5 (XFCE + Chromium + Local Apps)
# Usando livemedia-creator apenas com repositórios oficiais
# Inclui configuração automática do GRUB para UEFI
# Suporte: UEFI e MBR (BIOS)
# ==============================================================================

set -e

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/output_iso"
KS_FILE="$WORKDIR/ks_automated.cfg"
LOG_FILE="$WORKDIR/build.log"

# Verificar se está rodando como root ou com sudo
if [[ $EUID -ne 0 ]]; then
   echo "ERRO: Execute este script como root ou com sudo"
   exit 1
fi

# Verificar dependências necessárias
echo "### [1/7] Verificando dependências..."
MISSING_DEPS=()
for cmd in anaconda lorax livemedia-creator xorriso rsync createrepo_c grub2-efi-x64 shim-x64; do
    if ! command -v $cmd &> /dev/null && ! rpm -q ${cmd} &> /dev/null 2>&1; then
        MISSING_DEPS+=($cmd)
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "Instalando dependências faltantes: ${MISSING_DEPS[@]}"
    dnf install -y "${MISSING_DEPS[@]}" | tee -a "$LOG_FILE" || {
        echo "ERRO: Falha ao instalar dependências"
        exit 1
    }
fi

# Verificar diretórios necessários
for dir in software_rpm favoritos; do
    if [ ! -d "$WORKDIR/$dir" ]; then
        echo "AVISO: Diretório '$dir' não encontrado. Criando..."
        mkdir -p "$WORKDIR/$dir"
    fi
done

# --- Criação do Kickstart ---
echo "### [2/7] Criando arquivo Kickstart..."

# Verificar se há pacotes RPM locais
if [ -d "$WORKDIR/software_rpm" ] && [ -n "$(ls -A $WORKDIR/software_rpm/*.rpm 2>/dev/null)" ]; then
    LOCAL_RPM_LINE="rpm -i /mnt/media/software_rpm/*.rpm"
else
    LOCAL_RPM_LINE="# Nenhum RPM local encontrado"
fi

cat <<EOFKS > "$KS_FILE"
text
keyboard --vckeymap=br --layout=br
lang pt_BR.UTF-8
timezone America/Sao_Paulo
zerombr
clearpart --all --initlabel
autopart --type=plain
reboot

%packages
@xfce
chromium
rsync
kernel
grub2-efi-x64
grub2-pc
shim-x64
%end

%post --log=/root/post-install.log
mkdir -p /mnt/media
for dev in /dev/cdrom /dev/sr0 /dev/sr1; do
    if mount "\$dev" /mnt/media 2>/dev/null; then
        break
    fi
done

if [ ! -f /mnt/media/.discinfo ]; then
    echo "AVISO: Não foi possível montar a mídia de instalação"
    umount /mnt/media 2>/dev/null || true
    exit 0
fi

cd /mnt/media

if [ -f checksums.txt ]; then
    sha256sum -c checksums.txt || echo "AVISO: Checksum não confere, continuando..."
fi

$LOCAL_RPM_LINE

if [ -d /mnt/media/favoritos ]; then
    rsync -av /mnt/media/favoritos/ /etc/skel/favoritos/
fi

umount /mnt/media 2>/dev/null || true
%end
EOFKS

# --- Construção da ISO com livemedia-creator ---
echo "### [3/7] Construindo ISO customizada a partir dos repositórios..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if ! livemedia-creator \
    --make-iso \
    --ks="$KS_FILE" \
    --no-virt \
    --resultdir="$OUT_DIR" \
    --project="Oracle Linux 9.5 XFCE" \
    --releasever=9.5 \
    --repo=https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/ \
    --repo=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/latest/x86_64/ \
    --repo=https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/ \
    --iso-name=OracleLinux-9.5-XFCE-Custom.iso; then
    echo "ERRO: livemedia-creator falhou. Verifique os logs em $LOG_FILE"
    exit 1
fi

# --- Configuração do GRUB para UEFI ---
echo "### [4/7] Criando configuração do GRUB para UEFI..."
GRUB_DIR="$OUT_DIR/EFI/BOOT"
mkdir -p "$GRUB_DIR"

cat <<'EOF' > "$GRUB_DIR/grub.cfg"
set default=0
set timeout=5

menuentry "Instalar Oracle Linux 9.5 XFCE" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL-9-5-XFCE quiet
    initrdefi /images/pxeboot/initrd.img
}

menuentry "Rescue Mode" {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL-9-5-XFCE rescue
    initrdefi /images/pxeboot/initrd.img
}
EOF

# --- Injeção de Arquivos Locais ---
echo "### [5/7] Injetando pacotes e favoritos..."

if [ -d "$WORKDIR/software_rpm" ] && [ "$(ls -A $WORKDIR/software_rpm/ 2>/dev/null)" ]; then
    rsync -a "$WORKDIR/software_rpm" "$OUT_DIR/"
else
    mkdir -p "$OUT_DIR/software_rpm"
    echo "AVISO: Nenhum arquivo em software_rpm para copiar"
fi

if [ -d "$WORKDIR/favoritos" ] && [ -n "$(ls -A $WORKDIR/favoritos/ 2>/dev/null)" ]; then
    rsync -a "$WORKDIR/favoritos" "$OUT_DIR/"
else
    mkdir -p "$OUT_DIR/favoritos"
    echo "AVISO: Nenhum arquivo em favoritos para copiar"
fi

cp "$KS_FILE" "$OUT_DIR/ks.cfg"

# --- Checksums ---
echo "### [6/7] Gerando checksums..."
cd "$OUT_DIR"

FILE_COUNT=$(find software_rpm/ favoritos/ -type f 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -gt 0 ]; then
    find software_rpm/ favoritos/ -type f -exec sha256sum {} + > checksums.txt
else
    touch checksums.txt
    echo "AVISO: Nenhum arquivo para gerar checksums"
fi

cd "$WORKDIR"

# --- Finalização ---
echo "### [7/7] SUCESSO!"

ISO_FILE=$(find "$OUT_DIR" -name "*.iso" -type f 2>/dev/null | head -1)
if [ -n "$ISO_FILE" ]; then
    echo "ISO gerada em: $ISO_FILE"
    ls -lh "$ISO_FILE"
else
    echo "ERRO: Nenhum arquivo ISO encontrado em $OUT_DIR"
    exit 1
fi

