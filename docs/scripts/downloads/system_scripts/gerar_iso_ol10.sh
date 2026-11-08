 #!/bin/bash
set -e

# ==============================================================================
# CONFIGURAÇÕES GLOBAIS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

DATA=$(date +%Y-%m-%d)
ISO_BASE="OracleLinux-R10-U0-x86_64-dvd.iso" 
OUTPUT_ISO="OracleLinux-10.1-hibrido-custom-${DATA}.iso" 
SOFTWARE_DIR="software_rpm"
FAVORITOS_DIR="favoritos"
KS_FILE="ks.cfg"
VOL_ID="OL10CUSTOM" 

# Diretórios temporários
MOUNT_DIR=$(mktemp -d -t ol-mnt-XXXXXXXXXX)
EXTRACT_DIR=$(mktemp -d -t ol-extract-XXXXXXXXXX)
# ... (Resto dos diretórios)

# Dependências necessárias para a máquina host
REQUIRED_PACKAGES=("rsync" "createrepo_c" "xorriso" "syslinux" "grub2-tools" "mtools")

# ==============================================================================
# FUNÇÕES DE LOG
# ==============================================================================
STEP=0
TOTAL_STEPS=9 # Reintroduzimos o passo de verificação/download

log_step() { STEP=$((STEP+1)); echo -e "\n[\e[1;34m${STEP}/${TOTAL_STEPS}\e[0m] 🚀 $1"; }
log_info() { echo -e "    ➜ $1"; }
log_done() { echo -e "    ✅ $1"; }
log_error() { echo -e "    ❌ \e[1;31mERRO: $1\e[0m" >&2; exit 1; }

# ==============================================================================
# FUNÇÕES DE AMBIENTE E LIMPEZA
# ==============================================================================

setup() {
    log_step "Preparando ambiente e verificando dependências..."
    
    if [ ! -f "$ISO_BASE" ]; then
        log_error "Arquivo de ISO base não encontrado: $ISO_BASE. Baixe a ISO e coloque-a no mesmo diretório do script."
    fi

    local missing=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Instalando dependências: ${missing[*]}"
        sudo dnf install -y "${missing[@]}" || log_error "Falha na instalação de dependências."
    fi
    log_done "Ambiente e dependências OK."
}

cleanup() {
    log_info "Limpando arquivos temporários..."
    if mountpoint -q "$MOUNT_DIR" &>/dev/null; then
        sudo umount "$MOUNT_DIR"
    fi
    rm -rf "$MOUNT_DIR" "$EXTRACT_DIR"
    log_done "Limpeza concluída."
}

# ==============================================================================
# KICKSTART (KS.CFG)
# ==============================================================================

generate_kickstart() {
    log_step "Gerando arquivo Kickstart (ks.cfg)..."
    cat > "$KS_FILE" <<'EOF'
#version=RHEL10
install
cdrom
lang pt_BR.UTF-8
keyboard br-abnt2
timezone America/Sao_Paulo --isUtc
rootpw --plaintext oracle
user --name=user --password=oracle --plaintext --groups=wheel
firewall --enabled
selinux --enforcing
network --bootproto=dhcp --device=link --activate
bootloader --location=mbr
autopart --type=lvm
reboot

%packages
@^minimal-environment
@core
# Adicione outros grupos ou pacotes se o download condicional nao for suficiente.
%end

%post --log=/root/post-install.log
echo "--- Iniciando script post-install customizado ---"

# Repositorios extras (requerem internet na maquina alvo)
echo "Instalando repositórios extras (EPEL, RPM Fusion) - REQUER INTERNET..."
dnf install -y oraclelinux-release-epl
dnf install -y https://download.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
dnf install -y https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-10.noarch.rpm https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-10.noarch.rpm

# Copia arquivos favoritos
echo "Copiando arquivos de favoritos..."
mkdir -p /home/user/favoritos
cp -r /mnt/favoritos/* /home/user/favoritos/ || true
chown -R user:user /home/user/favoritos

# Copia software RPM (localizado fora do repo principal)
echo "Copiando software RPM personalizado..."
mkdir -p /home/user/software_rpm
cp -r /mnt/software_rpm/* /home/user/software_rpm/ || true
chown -R user:user /home/user/software_rpm
echo "--- Script post-install concluído ---"
%end
EOF
    log_done "Kickstart criado em $KS_FILE."
}

# ==============================================================================
# PREPARAÇÃO DO REPOSITÓRIO E ARQUIVOS
# ==============================================================================

mount_and_extract_iso() {
    log_step "Montando e extraindo ISO base..."
    sudo mount -o loop "$ISO_BASE" "$MOUNT_DIR" || log_error "Falha ao montar ISO base."

    log_info "Copiando **todos** os arquivos da ISO base para extração em $EXTRACT_DIR..."
    rsync -a "$MOUNT_DIR"/ "$EXTRACT_DIR"/
    
    log_info "Movendo pacotes BaseOS/Packages para o diretório de repositório customizado (/repo/Packages)..."
    local TARGET_PACKAGES_DIR="$EXTRACT_DIR/repo/Packages"
    mkdir -p "$TARGET_PACKAGES_DIR"
    
    # Move todos os RPMs da BaseOS/Packages para o novo local
    rsync -a "$EXTRACT_DIR/BaseOS/Packages/" "$TARGET_PACKAGES_DIR/"
    
    # Remove BaseOS/AppStream/Packages originais para evitar conflito
    rm -rf "$EXTRACT_DIR/BaseOS" "$EXTRACT_DIR/AppStream"

    # Desmonta a ISO, a partir de agora todos os passos usam $EXTRACT_DIR
    sudo umount "$MOUNT_DIR"
    log_done "Arquivos da ISO base copiados e ISO desmontada com sucesso."
}

ensure_essential_packages() {
    log_step "Verificando e baixando dependências essenciais (se faltarem na ISO)..."
    
    local TARGET_PACKAGES_DIR="$EXTRACT_DIR/repo/Packages"
    
    # Os pacotes que devem ser garantidos para evitar falhas no kickstart minimal
    local ESSENTIAL_PACKAGES=("@minimal-environment" "@core" "kernel-uek" "dracut-config-generic") 

    log_info "Tentando baixar pacotes essenciais (e dependências) para: ${ESSENTIAL_PACKAGES[*]}"
    log_info "Se o pacote já existir, ele será ignorado."

    # O DNF tenta baixar pacotes (e suas dependências) que NÃO ESTÃO instalados no --installroot.
    # Como o --installroot é um diretório de disco real, o erro de 'rpmdb open failed' é evitado.
    # O --installroot usa os pacotes de $TARGET_PACKAGES_DIR como base para resolver dependências.
    sudo dnf download \
        --installroot="$TARGET_PACKAGES_DIR" \
        --downloaddir="$TARGET_PACKAGES_DIR" \
        --resolve \
        --allowerasing \
        --nobest \
        "${ESSENTIAL_PACKAGES[@]}" || log_error "Falha ao baixar pacotes essenciais. Verifique a conectividade e os repositórios da sua máquina host."

    log_done "Verificação de pacotes concluída. Arquivos adicionais baixados (se necessário)."
}

create_offline_repo() {
    log_step "Criando metadados (repodata) para o repositório customizado..."
    
    local TARGET_PACKAGES_DIR="$EXTRACT_DIR/repo/Packages"
    
    if [ -d "$SOFTWARE_DIR" ] && [ "$(ls -A $SOFTWARE_DIR)" ]; then
        log_info "Adicionando pacotes RPM personalizados de $SOFTWARE_DIR..."
        cp "$SOFTWARE_DIR"/*.rpm "$TARGET_PACKAGES_DIR/" || true
    else
        log_info "Nenhum pacote RPM personalizado encontrado para adicionar."
    fi

    log_info "Gerando metadados do repositório (repodata) em $EXTRACT_DIR/repo..."
    createrepo_c "$EXTRACT_DIR/repo"
    log_done "Repositório offline criado e atualizado."
}

add_custom_files() {
    log_step "Adicionando arquivos personalizados (Favoritos e RPMs) para a mídia..."
    
    if [ -d "$FAVORITOS_DIR" ] && [ "$(ls -A $FAVORITOS_DIR)" ]; then
        mkdir -p "$EXTRACT_DIR/$FAVORITOS_DIR"
        cp -r "$FAVORITOS_DIR"/* "$EXTRACT_DIR/$FAVORITOS_DIR/"
        log_info "Arquivos de favoritos adicionados."
    else
        log_info "Nenhum arquivo de favoritos encontrado."
    fi

    if [ -d "$SOFTWARE_DIR" ] && [ "$(ls -A $SOFTWARE_DIR)" ]; then
        mkdir -p "$EXTRACT_DIR/$SOFTWARE_DIR"
        log_info "Diretório de software RPM adicionado (para acesso fácil pós-instalação)."
    else
        log_info "Nenhum diretório de software RPM encontrado."
    fi
}

# ==============================================================================
# CONFIGURAÇÃO DE BOOT (UEFI/MBR e MENU GRUB)
# ==============================================================================

configure_bootloaders() {
    log_step "Configurando GRUB2 para BIOS e UEFI..."
    
    log_info "Criando estrutura de diretórios para boot..."

    # Configura arquivos UEFI/EFI
    mkdir -p "$EFI_DIR"
    
    # Configura arquivos BIOS/ISOLINUX
    mkdir -p "$ISOLINUX_DIR"
    
    # ----------------------------------------------------------------------
    # grub.cfg para BIOS
    # ----------------------------------------------------------------------
    mkdir -p "$EXTRACT_DIR/boot/grub"
    cat > "$EXTRACT_DIR/boot/grub/grub.cfg" <<EOF
set timeout=10
set default=0

menuentry "1. Instalar Oracle Linux 10 (Modo Grafico/Manual)" {
    # Inicia o instalador grafico (Anaconda).
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID
    initrd /images/pxeboot/initrd.img
}

menuentry "2. Instalacao Automatizada (Kickstart)" {
    # Inicia a instalacao automatica usando o ks.cfg.
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID inst.ks=cdrom:/ks.cfg
    initrd /images/pxeboot/initrd.img
}

menuentry "3. Troubleshooting" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID inst.expert
    initrd /images/pxeboot/initrd.img
}
EOF

    # ----------------------------------------------------------------------
    # grub.cfg para UEFI
    # ----------------------------------------------------------------------
    cat > "$EFI_DIR/grub.cfg" <<EOF
set timeout=10
set default=0

menuentry "1. Instalar Oracle Linux 10 (Modo Grafico/Manual)" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID
    initrd /images/pxeboot/initrd.img
}

menuentry "2. Instalacao Automatizada (Kickstart)" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID inst.ks=cdrom:/ks.cfg
    initrd /images/pxeboot/initrd.img
}

menuentry "3. Troubleshooting" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$VOL_ID inst.expert
    initrd /images/pxeboot/initrd.img
}
EOF

    cp "$KS_FILE" "$EXTRACT_DIR/"
    log_done "Bootloaders configurados. Volume ID: $VOL_ID"
}

# ==============================================================================
# GERAÇÃO DA ISO
# ==============================================================================

generate_iso() {
    log_step "Gerando ISO híbrida..."
    # xorriso -volid usa o rótulo necessário para o bootloader (OL10CUSTOM)
    # Assumimos que o isohdpfx.bin padrão do syslinux é suficiente.
    xorriso -as mkisofs \
        -o "$OUTPUT_ISO" \
        -volid "$VOL_ID" \
        -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e EFI/BOOT/BOOTX64.EFI \
        -no-emul-boot \
        "$EXTRACT_DIR" || log_error "Falha ao gerar a ISO."
    log_done "ISO criada com sucesso: $OUTPUT_ISO"
}

finalize() {
    log_step "Processo concluído."
    ISO_SIZE=$(du -h "$OUTPUT_ISO" | awk '{print $1}')
    log_done "ISO personalizada pronta: $OUTPUT_ISO"
    log_done "Tamanho da imagem: $ISO_SIZE"
    echo "--------------------------------------------------------"
    echo "A ISO é robusta: pacotes essenciais foram verificados/baixados."
    echo "A configuracao de repositorios extras (EPEL/Fusion)"
    echo "no Kickstart requer conexao de internet durante a instalacao."
    echo "--------------------------------------------------------"
}

# ==============================================================================
# FLUXO PRINCIPAL
# ==============================================================================
trap cleanup EXIT

setup
generate_kickstart
mount_and_extract_iso # Monta, copia TUDO e desmonta
ensure_essential_packages # Baixa pacotes faltantes do Oracle Linux 10
create_offline_repo
add_custom_files
configure_bootloaders # Trabalha apenas com arquivos extraídos
generate_iso
finalize
