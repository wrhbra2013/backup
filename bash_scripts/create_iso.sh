 #!/bin/bash
set -e

# ==============================================================================
# CONFIGURAÇÕES DA ISO E DIRETÓRIOS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

# Definindo o limite de tamanho da ISO em bytes (5 GiB)
MAX_ISO_SIZE_BYTES=$(( 5 * 1024 * 1024 * 1024 ))
MAX_ISO_SIZE_HUMAN="5 GiB"
SAFETY_MARGIN=$(( 150 * 1024 * 1024 )) # Margem de segurança de 150 MB

DATA=$(date +%Y-%m-%d)
ISO_BASE="OracleLinux-R9-U4-x86_64-dvd.iso"
OUTPUT_ISO="OracleLinux-9.6-GUI-Offline-5G-${DATA}.iso"
SOFTWARE_DIR="software_rpm"
FAVORITOS_DIR="favoritos"
REQUIRED_RPMS_DIR="required_rpms" # Pacotes de EPEL/RPM Fusion para inclusão offline
KS_FILE="ks.cfg"
COMPRESSED_REPO_NAME="repo.tar.xz"

# Diretórios temporários
MOUNT_DIR=$(mktemp -d -t ol9-mnt-XXXXXXXXXX)
EXTRACT_DIR=$(mktemp -d -t ol9-extract-XXXXXXXXXX)
TEMP_REPO_DIR=$(mktemp -d -t ol9-repo-XXXXXXXXXX)
EFI_DIR="$EXTRACT_DIR/EFI/BOOT"
ISOLINUX_DIR="$EXTRACT_DIR/isolinux"

# Dependências necessárias no HOST (Adicionado 'syslinux' e 'dnf-utils' para MBR/downloads)
REQUIRED_PACKAGES=("rsync" "createrepo_c" "xorriso" "xz" "syslinux" "dnf-utils")

# Caminho interno do binário MBR após a cópia ou fallback
INTERNAL_ISOHDPFX_BIN="$ISOLINUX_DIR/isohdpfx.bin" 

# ==============================================================================
# FUNÇÕES DE LOG (Mantidas)
# ==============================================================================
STEP=0
TOTAL_STEPS=9 # Aumentamos para 9

log_step() { STEP=$((STEP+1)); echo -e "\n[\e[1;34m${STEP}/${TOTAL_STEPS}\e[0m] 🚀 $1"; }
log_info() { echo -e "    ➜ $1"; }
log_done() { echo -e "    ✅ $1"; }
log_error() { echo -e "    ❌ \e[1;31mERRO: $1\e[0m" >&2; exit 1; }
log_warn() { echo -e "    ⚠️ \e[1;33mAVISO: $1\e[0m"; }

# ==============================================================================
# FUNÇÕES PRINCIPAIS DO PROCESSO
# ==============================================================================

# Novo passo: Baixar RPMs de dependências para o repositório
download_required_rpms() {
    log_step "Baixando RPMs de repositórios externos para inclusão offline..."
    
    mkdir -p "$REQUIRED_RPMS_DIR"

    # Pacotes necessários para configurar repositórios no %post
    # Usamos dnf download --resolve para garantir que dependências essenciais sejam baixadas
    
    # Adicionando EPEL release (URL estável)
    log_info "Baixando EPEL release e dependências..."
    sudo dnf download -y --resolve --destdir="$REQUIRED_RPMS_DIR" "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm" || log_warn "Falha ao baixar EPEL. O Kickstart continuará tentando baixar online."

    # Adicionando RPM Fusion (URLs estáveis)
    log_info "Baixando RPM Fusion release (Free e Nonfree) e dependências..."
    sudo dnf download -y --resolve --destdir="$REQUIRED_RPMS_DIR" \
        "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm" || log_warn "Falha ao baixar RPM Fusion. O Kickstart continuará tentando baixar online."
        
    log_done "Downloads de dependências de repositório concluídos em $REQUIRED_RPMS_DIR."
}

setup() {
    log_step "Preparando ambiente e verificando dependências..."
    
    if [ ! -f "$ISO_BASE" ]; then
        log_error "Arquivo de ISO base não encontrado: $ISO_BASE."
    fi

    log_info "Verificando e instalando dependências: ${REQUIRED_PACKAGES[*]}..."
    local missing=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Instalando dependências faltantes: ${missing[*]}"
        sudo dnf install -y "${missing[@]}" || log_error "Falha crítica na instalação de dependências."
    fi
    
    # 2. Copia o binário MBR para o diretório de extração, usando fallback do host
    if [ ! -f "$INTERNAL_ISOHDPFX_BIN" ]; then
        log_warn "Binário MBR (isohdpfx.bin) não encontrado no diretório de extração local. Tentando copiar do host..."
        if [ -f "/usr/share/syslinux/isohdpfx.bin" ]; then
            mkdir -p "$ISOLINUX_DIR"
            cp "/usr/share/syslinux/isohdpfx.bin" "$INTERNAL_ISOHDPFX_BIN"
            log_info "Binário MBR copiado do HOST para $INTERNAL_ISOHDPFX_BIN (Fallback OK)."
        else
            log_error "O binário MBR isohdpfx.bin não foi encontrado na ISO base. Instale o pacote 'syslinux' ou verifique o caminho da ISO."
        fi
    fi

    log_done "Ambiente e dependências OK."
}

cleanup() {
    log_info "Limpando arquivos temporários..."
    if mountpoint -q "$MOUNT_DIR" &>/dev/null; then
        sudo umount "$MOUNT_DIR"
    fi
    rm -rf "$MOUNT_DIR" "$TEMP_REPO_DIR" "$EXTRACT_DIR" "$KS_FILE"
    log_done "Limpeza concluída."
}

# 1. GERAÇÃO DO KICKSTART: Configurado para iniciar em modo gráfico (GUI)
generate_kickstart() {
    log_step "Gerando arquivo Kickstart customizado (Instalação GUI)..."
    cat > "$KS_FILE" <<EOF
#version=RHEL9
install
cdrom
lang pt_BR.UTF-8
keyboard br-abnt2
timezone America/Sao_Paulo --isUtc
rootpw --plaintext oracle
user --name=customuser --password=oracle --plaintext --groups=wheel
firewall --enabled
selinux --enforcing
network --bootproto=dhcp --device=link --activate
bootloader --location=all
autopart --type=lvm
reboot

# Inicia o instalador em modo gráfico (GUI)
# text 
graphical

# Repositório local (descompactado)
repo --name="local-repo" --baseurl=file:///mnt/repo --gpgcheck=0 --enabled=1

%packages
@core
# Adicione um ambiente de desktop básico para um sistema mais usável pós-instalação
@server-product-environment
%end

# =================================================================
# FASE PRE: Descompacta o repositório
# =================================================================
%pre
log_info() { echo -e "-> \$1"; }
log_info "Iniciando descompactação do repositório..."
REPO_ARCHIVE="/mnt/install/$COMPRESSED_REPO_NAME"
REPO_TARGET="/mnt/repo"
mkdir -p \$REPO_TARGET
# Usamos 'tar -xJf' para descompactar o arquivo .tar.xz
tar -xJf \$REPO_ARCHIVE -C \$REPO_TARGET
log_info "Repositório descompactado em \$REPO_TARGET."
%end

# =================================================================
# FASE POST: Configura repos e copia arquivos
# =================================================================
%post --log=/root/post-install.log
log_info() { echo -e "-> \$1"; }
log_info "Iniciando scripts de pós-instalação..."

# Os RPMs do EPEL/RPM Fusion já estão no repositório local (/mnt/repo)

# 1. Configura Repositórios Externos (Offline)
log_info "Configurando repositórios EPEL e RPM Fusion (Offline)..."
# Busca e instala os pacotes de release do EPEL/RPM Fusion diretamente do repositório local
# O 'dnf install' deve ser capaz de encontrá-los no /mnt/repo
dnf install -y \
    /mnt/repo/epel-release-latest-9.noarch.rpm \
    /mnt/repo/rpmfusion-free-release-9.noarch.rpm \
    /mnt/repo/rpmfusion-nonfree-release-9.noarch.rpm || log_warn "Falha ao instalar pacotes de release do repositório local. Tentando dnf install -y (online)."

# Instala oraclelinux-release-epl (se necessário)
dnf install -y oraclelinux-release-epl > /dev/null 2>&1
log_info "Repositórios EPEL e RPM Fusion configurados (parcialmente ou totalmente offline)."

# 2. Copia Arquivos Customizados (Favoritos e Software)
CUSTOM_USER="customuser"
HOME_DIR="/home/\$CUSTOM_USER"
log_info "Copiando arquivos customizados para \$HOME_DIR..."
# Arquivos customizados estão na raiz da ISO (agora /mnt/install)
for dir_name in "favoritos" "software_rpm"; do
    if [ -d "/mnt/install/\$dir_name" ]; then
        mkdir -p "\$HOME_DIR/\$dir_name"
        cp -r /mnt/install/\$dir_name/* "\$HOME_DIR/\$dir_name/" || true
        chown -R \$CUSTOM_USER:\$CUSTOM_USER "\$HOME_DIR/\$dir_name"
        log_info "Arquivos de \$dir_name copiados."
    fi
done

# 3. Limpeza
rm -f /root/anaconda-ks.cfg
log_info "Pós-instalação concluída."

%end
EOF
    log_done "Kickstart criado em $KS_FILE. (Início da instalação: GUI)"
}

# 2. MONTAGEM E EXTRAÇÃO
mount_and_extract_iso() {
    log_step "Montando e extraindo ISO base..."
    sudo mount -o loop "$ISO_BASE" "$MOUNT_DIR" || log_error "Falha ao montar ISO base."

    log_info "Copiando arquivos essenciais da ISO (excluindo pacotes)..."
    rsync -a --exclude="Packages" "$MOUNT_DIR"/ "$EXTRACT_DIR"/

    log_info "Copiando pacotes da ISO para o repositório temporário..."
    rsync -a "$MOUNT_DIR/BaseOS/Packages/" "$TEMP_REPO_DIR/"

    log_done "Arquivos base copiados."
    sudo umount "$MOUNT_DIR" # Desmonta a ISO base imediatamente após copiar
}

# 3. CRIAÇÃO E COMPACTAÇÃO DO REPOSITÓRIO OFFLINE
create_offline_repo() {
    log_step "Criando e compactando repositório offline (Limite: ${MAX_ISO_SIZE_HUMAN})..."
    
    # 1. Adicionar pacotes customizados e de repositórios (software_rpm + required_rpms)
    for dir in "$SOFTWARE_DIR" "$REQUIRED_RPMS_DIR"; do
        if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
            log_info "Adicionando pacotes de $dir ao repositório..."
            cp "$dir"/*.rpm "$TEMP_REPO_DIR/" || log_warn "Não foi possível copiar RPMs de $dir."
        fi
    done

    # 2. Gerar metadados
    log_info "Gerando metadados do repositório temporário..."
    createrepo_c "$TEMP_REPO_DIR"

    # 3. Compactar
    log_info "Compactando repositório para ${COMPRESSED_REPO_NAME} (usando xz)..."
    tar -cJpf "$EXTRACT_DIR/$COMPRESSED_REPO_NAME" -C "$(dirname "$TEMP_REPO_DIR")" "$(basename "$TEMP_REPO_DIR")"
    
    rm -rf "$TEMP_REPO_DIR"

    # 4. Checagem de limite (Mantida)
    COMPRESSED_REPO_SIZE=$(du -sb "$EXTRACT_DIR/$COMPRESSED_REPO_NAME" | awk '{print $1}')
    log_info "Tamanho do repositório compactado: $(numfmt --to=iec --format="%.1f" "$COMPRESSED_REPO_SIZE")"
    
    CURRENT_ISO_CONTENT_SIZE=$(sudo du -sb "$EXTRACT_DIR" | awk '{print $1}')
    
    if [ "$CURRENT_ISO_CONTENT_SIZE" -gt "$(( MAX_ISO_SIZE_BYTES - SAFETY_MARGIN ))" ]; then
        log_error "O conteúdo da ISO excede o limite de ${MAX_ISO_SIZE_HUMAN}."
    else
        log_info "Tamanho total do conteúdo (~$(numfmt --to=iec --format="%.1f" "$CURRENT_ISO_CONTENT_SIZE")) está dentro do limite."
    fi
    
    log_done "Repositório compactado e verificado."
}

# 4. ADIÇÃO DE ARQUIVOS CUSTOMIZADOS (Mantido)
add_custom_files() {
    log_step "Adicionando arquivos personalizados..."
    
    for dir_name in "$FAVORITOS_DIR" "$SOFTWARE_DIR"; do
        if [ -d "$dir_name" ] && [ "$(ls -A $dir_name)" ]; then
            mkdir -p "$EXTRACT_DIR/$dir_name"
            cp -r "$dir_name"/* "$EXTRACT_DIR/$dir_name/"
            log_done "Arquivos de $dir_name adicionados."
        fi
    done
    
    # O kickstart é copiado aqui para a raiz da extração
    cp "$KS_FILE" "$EXTRACT_DIR/"
}

# 5. CONFIGURAÇÃO DE BOOT (Inclui 'inst.ks')
configure_bootloaders() {
    log_step "Configurando arquivos de boot GRUB2 e ISOLINUX..."
    
    # Arquivos de configuração de boot (apontando para o Kickstart na raiz)
    
    # Parâmetros de boot: inst.stage2=hd:LABEL=OL9 inst.ks=cdrom:/ks.cfg
    BOOT_PARAMS="inst.stage2=hd:LABEL=OL9 inst.ks=cdrom:/ks.cfg"
    
    # BIOS grub.cfg
    mkdir -p "$EXTRACT_DIR/boot/grub"
    cat > "$EXTRACT_DIR/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

menuentry "Instalar Oracle Linux 9.6 Compacto (GUI)" {
    linux /images/pxeboot/vmlinuz $BOOT_PARAMS
    initrd /images/pxeboot/initrd.img
}
EOF

    # UEFI grub.cfg
    cat > "$EFI_DIR/grub.cfg" <<EOF
set timeout=5
set default=0

menuentry "Instalar Oracle Linux 9.6 Compacto (GUI)" {
    linux /images/pxeboot/vmlinuz $BOOT_PARAMS
    initrd /images/pxeboot/initrd.img
}
EOF

    log_done "Configuração de boot finalizada."
}

# 6. GERAÇÃO FINAL DA IMAGEM ISO (HYBRID)
generate_iso() {
    log_step "Gerando ISO híbrida..."
    
    # Agora confiamos que $INTERNAL_ISOHDPFX_BIN foi criado pelo setup (fallback)
    xorriso -as mkisofs \
        -o "$OUTPUT_ISO" \
        -volid OL9 \
        -isohybrid-mbr "$INTERNAL_ISOHDPFX_BIN" \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e EFI/BOOT/BOOTX64.EFI \
        -no-emul-boot \
        "$EXTRACT_DIR" || log_error "Falha ao gerar a ISO. O binário MBR pode estar faltando."
    log_done "ISO criada com sucesso: $OUTPUT_ISO"
}

finalize() {
    log_step "Processo concluído."
    ISO_SIZE=$(du -h "$OUTPUT_ISO" | awk '{print $1}')
    
    FINAL_SIZE_BYTES=$(du -s "$OUTPUT_ISO" | awk '{print $1 * 1024}')

    if [ "$FINAL_SIZE_BYTES" -gt "$MAX_ISO_SIZE_BYTES" ]; then
        log_warn "A ISO final ($ISO_SIZE) EXCEDEU o limite de ${MAX_ISO_SIZE_HUMAN}. Reduza o conteúdo de $SOFTWARE_DIR e $REQUIRED_RPMS_DIR."
    fi

    log_done "ISO personalizada pronta: $OUTPUT_ISO"
    log_done "Tamanho da imagem: $ISO_SIZE"
}

# ==============================================================================
# FLUXO PRINCIPAL
# ==============================================================================
trap cleanup EXIT

# Novo passo de download antes do setup para garantir que os RPMs de repo estejam prontos
download_required_rpms 

setup
generate_kickstart
mount_and_extract_iso
create_offline_repo   # Inclui RPMs da ISO + software + releases de repo
add_custom_files      # Adiciona favoritos e software_rpm para cópia pós-instalação
configure_bootloaders # Configura GRUB para iniciar a GUI do Anaconda
generate_iso
finalize
