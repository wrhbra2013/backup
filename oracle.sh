 #!/bin/bash
# ==============================================================================
# Gerador de ISO Customizada Oracle Linux 9.5 (Modo Portátil)
# ==============================================================================

set -e

# --- Configuração de Caminhos Relativos ---
# Define a pasta base onde o script está localizado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Cria uma pasta de trabalho específica para não poluir o diretório atual
BUILD_ROOT="$SCRIPT_DIR/build_oracle_lxde"
OUT_DIR="$BUILD_ROOT/output_iso"
KS_FILE="$BUILD_ROOT/ks_automated.cfg"
LOG_FILE="$BUILD_ROOT/build.log"

# Subpastas para injeção de arquivos
SOFTWARE_DIR="$BUILD_ROOT/software_rpm"
FAVORITOS_DIR="$BUILD_ROOT/favoritos"

echo "### Iniciando ambiente em: $BUILD_ROOT"

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   echo "ERRO: Execute este script como root ou com sudo"
   exit 1
fi

# Criar estrutura de pastas
mkdir -p "$OUT_DIR" "$SOFTWARE_DIR" "$FAVORITOS_DIR"

# --- [1/7] Verificando dependências ---
echo "### [1/7] Verificando dependências..."
DEPS=(anaconda lorax livemedia-creator xorriso rsync createrepo_c grub2-efi-x64 shim-x64)
for cmd in "${DEPS[@]}"; do
    if ! rpm -q "$cmd" &> /dev/null; then
        echo "Instalando $cmd..."
        dnf install -y "$cmd" >> "$LOG_FILE" 2>&1
    fi
done

# --- [2/7] Criando Kickstart ---
echo "### [2/7] Criando arquivo Kickstart..."

# Lógica para pacotes locais
LOCAL_RPM_LINE="# Nenhum RPM local"
if [ -n "$(ls -A "$SOFTWARE_DIR" 2>/dev/null)" ]; then
    LOCAL_RPM_LINE="rpm -i /mnt/media/software_rpm/*.rpm"
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
mount /dev/cdrom /mnt/media || mount /dev/sr0 /mnt/media

if [ -d /mnt/media/software_rpm ]; then
    $LOCAL_RPM_LINE
fi

if [ -d /mnt/media/favoritos ]; then
    rsync -av /mnt/media/favoritos/ /etc/skel/favoritos/
fi
umount /mnt/media || true
%end
EOFKS

# --- [3/7] Construindo ISO ---
echo "### [3/7] Executando livemedia-creator..."
# Limpeza prévia de builds falhas
rm -rf "$OUT_DIR"/*

livemedia-creator \
    --make-iso \
    --ks="$KS_FILE" \
    --no-virt \
    --resultdir="$OUT_DIR" \
    --project="Oracle Linux 9.5 Custom" \
    --releasever=9.5 \
    --repo=https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/ \
    --repo=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/latest/x86_64/ \
    --repo=https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/ \
    --iso-name=OracleLinux-9.5-Custom.iso

# --- [4/7 a 6/7] Injeção e Pós-Processamento ---
# (O processo de injeção de arquivos e checksums permanece o mesmo, 
# mas agora usando as variáveis $OUT_DIR e $BUILD_ROOT)

echo "### [5/7] Injetando arquivos extras na ISO gerada..."
cp -r "$SOFTWARE_DIR" "$OUT_DIR/"
cp -r "$FAVORITOS_DIR" "$OUT_DIR/"
cp "$KS_FILE" "$OUT_DIR/ks.cfg"

echo "### [6/7] Gerando Checksums..."
cd "$OUT_DIR"
find . -type f ! -name "checksums.txt" -exec sha256sum {} + > checksums.txt
cd "$SCRIPT_DIR"

# --- [7/7] Finalização ---
echo "### SUCESSO!"
echo "Sua ISO e arquivos de build estão em: $BUILD_ROOT"

