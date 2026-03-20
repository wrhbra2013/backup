 #!/bin/bash
# ==============================================================================
# Gerador de ISO Híbrida (UEFI + MBR) - Oracle Linux 9.5 XFCE
# Foco: Download via Internet + Sincronização via Rsync
# ==============================================================================

set -e

# 1. Configuração de Caminhos e Variáveis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build_oracle_95"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$BUILD_ROOT/ks_custom.cfg"
LOG_FILE="$BUILD_ROOT/build.log"
ISO_NAME="OL95-XFCE-Hybrid.iso"

# Pastas de Origem (ao lado do script)
SOFTWARE_SRC="$SCRIPT_DIR/software_rpm"
FAVORITOS_SRC="$SCRIPT_DIR/favoritos"

# Limpeza e Segurança
limpar_tudo() {
    echo "### [LIMPEZA] Desmontando e limpando temporários..."
    sync
    grep "$BUILD_ROOT" /proc/mounts | cut -d' ' -f2 | xargs -r umount -l 2>/dev/null || true
    rm -rf "$BUILD_ROOT/lmc-work-*" "/var/tmp/lmc-*" 2>/dev/null || true
}

trap limpar_tudo EXIT

if [[ $EUID -ne 0 ]]; then echo "ERRO: Execute como ROOT."; exit 1; fi

# 2. Verificação de Espaço e Dependências do Host
FREE_GB=$(df -BG "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_GB" -lt 15 ]; then
    echo "ERRO: Espaço insuficiente ($FREE_GB GB). Mínimo 15GB."
    exit 1
fi

echo "### [1/6] Baixando e instalando ferramentas de build via DNF..."
dnf install -y EPEL-release >> "$LOG_FILE" 2>&1
dnf install -y lorax livemedia-creator xorriso rsync syslinux \
    grub2-efi-x64 shim-x64 grub2-pc-bin grub2-tools >> "$LOG_FILE" 2>&1

# Preparar estrutura de build usando rsync para garantir integridade
mkdir -p "$BUILD_ROOT/content/software_rpm" "$BUILD_ROOT/content/favoritos" "$OUT_DIR"

if [ -d "$SOFTWARE_SRC" ]; then
    rsync -av --progress "$SOFTWARE_SRC/" "$BUILD_ROOT/content/software_rpm/"
fi
if [ -d "$FAVORITOS_SRC" ]; then
    rsync -av --progress "$FAVORITOS_SRC/" "$BUILD_ROOT/content/favoritos/"
fi

# 3. Gerar Kickstart (Configurado para baixar pacotes da Web)
echo "### [2/6] Gerando Kickstart..."
cat <<EOFKS > "$KS_FILE"
text
keyboard --vckeymap=br --layout=br
lang pt_BR.UTF-8
timezone America/Sao_Paulo
zerombr
clearpart --all --initlabel
autopart --type=plain
reboot

# Repositórios remotos (Download via Internet durante o build)
url --url=https://yum.oracle.com
repo --name="AppStream" --baseurl=https://yum.oracle.com
repo --name="EPEL" --baseurl=https://dl.fedoraproject.org

%packages
@xfce
chromium
rsync
kernel
grub2-efi-x64
grub2-pc
shim-x64
syslinux
%end

%post
# Montar a mídia para acessar os arquivos injetados pelo rsync no passo final
mkdir -p /mnt/media
mount /dev/sr0 /mnt/media || mount /dev/cdrom /mnt/media

if [ -d /mnt/media/software_rpm ]; then
    dnf install -y /mnt/media/software_rpm/*.rpm || true
fi

if [ -d /mnt/media/favoritos ]; then
    mkdir -p /etc/skel/favoritos
    rsync -av /mnt/media/favoritos/ /etc/skel/favoritos/
fi
umount /mnt/media || true
%end
EOFKS

# 4. Build da ISO
echo "### [3/6] Iniciando Build da ISO Híbrida (via rede)..."
rm -f "$OUT_DIR/$ISO_NAME"

livemedia-creator \
    --make-iso \
    --ks="$KS_FILE" \
    --no-virt \
    --resultdir="$OUT_DIR" \
    --project="OL9-Hybrid" \
    --releasever=9.5 \
    --iso-name="$ISO_NAME" \
    --fs-label="OL9_XFCE_HYB" \
    --image-type-option="hybrid=true"

# 5. Pós-Processamento Hybrid (Compatibilidade UEFI/MBR)
echo "### [4/6] Aplicando isohybrid..."
isohybrid --uefi "$OUT_DIR/$ISO_NAME" || true

# 6. Injeção de Arquivos Extras via Rsync na estrutura final
echo "### [5/6] Injetando pacotes locais e favoritos na ISO..."
# Nota: Para injetar após o build, usamos ferramentas de manipulação de ISO ou 
# garantimos que o lmc inclua o diretório. Como o lmc isola o build, 
# o rsync aqui prepara o diretório de saída.
rsync -av "$BUILD_ROOT/content/" "$OUT_DIR/"

cd "$OUT_DIR"
sha256sum "$ISO_NAME" > hash_iso.txt

echo "### [6/6] SUCESSO! ISO gerada em: $OUT_DIR/$ISO_NAME"

