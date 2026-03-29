 #!/bin/bash
set -e

# ==============================
# CONFIGURAÇÕES
# ==============================
DATA=$(date +%Y-%m-%d)
ISO_BASE="OracleLinux-R9-U6-x86_64-dvd.iso"
OUTPUT_ISO="OracleLinux-9.6-compacta-${DATA}.iso"
SOFTWARE_DIR="software_rpm"
FAVORITOS_DIR="favoritos"
KS_FILE="ks.cfg"
TEMP_REPO_DIR="compact_repo"
MOUNT_DIR="mnt"
EXTRACT_DIR="iso_extract"
EFI_DIR="$EXTRACT_DIR/EFI/BOOT"

# URLs dos repositórios para Oracle Linux 9
ORACLE_BASE_URL="https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/"
EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm"
RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm"

REQUIRED_PACKAGES=("rsync" "createrepo_c" "xorriso" "syslinux" "grub2-tools" "grub2-efi-x64" "shim-x64" "mtools" "dnf-plugins-core")

# ==============================
# FUNÇÕES DE LOG
# ==============================
STEP=0
TOTAL_STEPS=7

log_step() { STEP=$((STEP+1)); echo -e "\n[\e[1;34m${STEP}/${TOTAL_STEPS}\e[0m] 🚀 $1"; }
log_info() { echo -e "    ➜ $1"; }
log_done() { echo -e "    ✅ $1"; }
log_error() { echo -e "    ❌ \e[1;31mERRO: $1\e[0m" >&2; exit 1; }

# ==============================
# FUNÇÃO DE LIMPEZA
# ==============================
cleanup() {
    log_info "Limpando arquivos temporários..."
    mountpoint -q "$MOUNT_DIR" &>/dev/null && sudo umount "$MOUNT_DIR"
    rm -rf "$MOUNT_DIR" "$TEMP_REPO_DIR" "$EXTRACT_DIR" "$KS_FILE"
    log_done "Limpeza concluída."
}
trap cleanup EXIT

# ==============================
# VERIFICA DEPENDÊNCIAS
# ==============================
check_dependencies() {
    log_step "Verificando dependências..."
    local missing=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Instalando: ${missing[*]}"
        sudo dnf install -y "${missing[@]}" || log_error "Falha na instalação de dependências."
    fi
    log_done "Dependências OK."
}

# ==============================
# INÍCIO DO SCRIPT
# ==============================
check_dependencies

# 1️⃣ GERA ARQUIVO KICKSTART
log_step "Gerando Kickstart..."
cat > "$KS_FILE" <<'EOF'
#version=RHEL9
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

# Repositório local com pacotes essenciais
repo --name="local-repo" --baseurl=file:///mnt/repo --gpgcheck=0 --enabled=1

%packages
@^minimal-environment
@core
# Pacotes adicionais de repositórios externos
epel-release
rpmfusion-free-release
rpmfusion-nonfree-release
%end

%post --log=/root/post-install.log
# Ativação dos repositórios
dnf install -y oraclelinux-release-epl
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf install -y https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm

# Copia arquivos favoritos
mkdir -p /home/user/favoritos
cp -r /mnt/favoritos/* /home/user/favoritos/ || true
chown -R user:user /home/user/favoritos

# Copia software RPM
mkdir -p /home/user/software_rpm
cp -r /mnt/software_rpm/* /home/user/software_rpm/ || true
chown -R user:user /home/user/software_rpm
%end
EOF
log_done "Kickstart criado."

# 2️⃣ MONTA E EXTRAI ISO BASE
log_step "Montando e extraindo ISO base..."
mkdir -p "$MOUNT_DIR" "$EXTRACT_DIR"
sudo mount -o loop "$ISO_BASE" "$MOUNT_DIR" || log_error "Falha ao montar ISO base."
rsync -a --exclude="Packages" "$MOUNT_DIR"/ "$EXTRACT_DIR"/
log_done "ISO extraída (sem pacotes)."
sudo umount "$MOUNT_DIR"

# 3️⃣ CRIA REPOSITÓRIO COMPACTO A PARTIR DA ISO BASE
log_step "Criando repositório de pacotes compacto a partir da ISO base..."
mkdir -p "$TEMP_REPO_DIR"

log_info "Identificando pacotes essenciais dos grupos @core e @minimal-environment..."
declare -a ESSENTIAL_PACKAGES

# Monta a ISO base para copiar metadados
log_info "Montando ISO para copiar metadados..."
sudo mount -o loop "$ISO_BASE" "$MOUNT_DIR" || log_error "Falha ao montar ISO base."

# Copia os metadados do repositório da ISO para um diretório temporário
mkdir -p "$TEMP_REPO_DIR/BaseOS/repodata"
log_info "Copiando metadados da ISO para diretório temporário..."
sudo rsync -a "$MOUNT_DIR/BaseOS/repodata/" "$TEMP_REPO_DIR/BaseOS/repodata/" || log_error "Falha ao copiar metadados do repositório."
sudo umount "$MOUNT_DIR"

# Garante que os arquivos temporários tenham as permissões corretas
sudo chown -R $USER:$USER "$TEMP_REPO_DIR"

for GROUP in "core" "minimal-environment"; do
    log_info "Obtendo pacotes do grupo: $GROUP"
    
    # Usa o dnf para ler o grupo do repositório temporário
    sudo dnf -c /dev/null --repofrompath=temp_repo,"file://$TEMP_REPO_DIR/BaseOS" group info "$GROUP" &> group_info.txt

    # Extrai a lista de pacotes a partir da saída do dnf
    PACKAGES=$(grep -A 1000 'Mandatory Packages:' group_info.txt | sed '/^Default Packages/q' | awk '{print $1}')
    
    if [ -z "$PACKAGES" ]; then
        PACKAGES=$(grep -A 1000 'Mandatory Packages:' group_info.txt | sed '1,/^$/d' | sed 's/ (.*)//g' | grep -v '^\s*$' | awk '{print $1}')
    fi

    if [ -n "$PACKAGES" ]; then
        ESSENTIAL_PACKAGES+=($PACKAGES)
    fi
done

if [ ${#ESSENTIAL_PACKAGES[@]} -gt 0 ]; then
    ESSENTIAL_PACKAGES=($(printf "%s\n" "${ESSENTIAL_PACKAGES[@]}" | sort -u))
fi

if [ ${#ESSENTIAL_PACKAGES[@]} -eq 0 ]; then
    log_error "Não foi possível obter a lista de pacotes essenciais da ISO base."
fi

log_info "Copiando pacotes da ISO base..."
sudo mount -o loop "$ISO_BASE" "$MOUNT_DIR"
for PKG in "${ESSENTIAL_PACKAGES[@]}"; do
    find "$MOUNT_DIR/BaseOS/Packages" -type f -name "$PKG-*.rpm" -exec cp -t "$TEMP_REPO_DIR" {} + || true
done
sudo umount "$MOUNT_DIR"
log_done "Pacotes essenciais copiados."

# Adiciona pacotes personalizados, se houver
if [ -d "$SOFTWARE_DIR" ] && ls "$SOFTWARE_DIR"/*.rpm &>/dev/null; then
    log_info "Adicionando pacotes personalizados..."
    cp "$SOFTWARE_DIR"/*.rpm "$TEMP_REPO_DIR/"
    log_done "Pacotes personalizados adicionados."
else
    log_info "Nenhum pacote personalizado encontrado."
fi

# Move o repositório para o diretório de extração da ISO e gera os metadados
mkdir -p "$EXTRACT_DIR/repo"
cp -r "$TEMP_REPO_DIR"/* "$EXTRACT_DIR/repo/"
createrepo_c "$EXTRACT_DIR/repo"
log_done "Repositório compacto criado e movido."

# 4️⃣ ADICIONA FAVORITOS E SOFTWARE RPM
log_step "Adicionando arquivos favoritos e software RPM..."
if [ -d "$FAVORITOS_DIR" ] && [ "$(ls -A $FAVORITOS_DIR)" ]; then
    mkdir -p "$EXTRACT_DIR/$FAVORITOS_DIR"
    cp -r "$FAVORITOS_DIR"/* "$EXTRACT_DIR/$FAVORITOS_DIR/"
    log_done "Favoritos adicionados."
else
    log_info "Nenhum favorito encontrado."
fi

if [ -d "$SOFTWARE_DIR" ] && [ "$(ls -A $SOFTWARE_DIR)" ]; then
    mkdir -p "$EXTRACT_DIR/$SOFTWARE_DIR"
    cp -r "$SOFTWARE_DIR"/* "$EXTRACT_DIR/$SOFTWARE_DIR/"
    log_done "Software RPM adicionado."
else
    log_info "Nenhum software RPM encontrado."
fi

# 5️⃣ ADICIONA KICKSTART E CONFIGURA GRUB
log_step "Configurando GRUB2 para BIOS e UEFI..."
mkdir -p "$EXTRACT_DIR/boot/grub" "$EFI_DIR"

# grub.cfg para BIOS
cat > "$EXTRACT_DIR/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

menuentry "Instalar Oracle Linux 9.6" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL96 inst.ks=cdrom:/ks.cfg
    initrd /images/pxeboot/initrd.img
}
EOF

# grub.cfg para UEFI
cat > "$EFI_DIR/grub.cfg" <<'EOF'
set timeout=5
set default=0

menuentry "Instalar Oracle Linux 9.6" {
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL96 inst.ks=cdrom:/ks.cfg
    initrd /images/pxeboot/initrd.img
}
EOF

# Detecta GRUB EFI e shim
GRUB_PATHS=(
    "/usr/lib64/efi/grubx64.efi"
    "/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi"
    "/boot/efi/EFI/BOOT/grubx64.efi"
)
SHIM_PATHS=(
    "/usr/lib64/efi/shimx64.efi"
    "/boot/efi/EFI/BOOT/BOOTX64.EFI"
)

FOUND_GRUB=""
for path in "${GRUB_PATHS[@]}"; do
    [ -f "$path" ] && FOUND_GRUB="$path" && break
done

FOUND_SHIM=""
for path in "${SHIM_PATHS[@]}"; do
    [ -f "$path" ] && FOUND_SHIM="$path" && break
done

if [ -n "$FOUND_SHIM" ]; then
    log_info "Usando shim como BOOTX64.EFI: $FOUND_SHIM"
    cp "$FOUND_SHIM" "$EFI_DIR/BOOTX64.EFI"
    if [ -n "$FOUND_GRUB" ]; then
        cp "$FOUND_GRUB" "$EFI_DIR/grubx64.efi"
    else
        log_error "shim encontrado, mas grubx64.efi ausente."
    fi
elif [ -n "$FOUND_GRUB" ]; then
    log_info "Usando grubx64.efi diretamente como BOOTX64.EFI: $FOUND_GRUB"
    cp "$FOUND_GRUB" "$EFI_DIR/BOOTX64.EFI"
else
    log_error "Nenhum arquivo EFI encontrado. Instale 'grub2-efi-x64'."
fi

cp "$KS_FILE" "$EXTRACT_DIR/"
log_done "GRUB2 configurado."

# 6️⃣ GERA ISO HÍBRIDA
log_step "Gerando ISO híbrida com suporte BIOS e UEFI..."
xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
    -volid OL96 \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e EFI/BOOT/BOOTX64.EFI \
    -no-emul-boot \
    "$EXTRACT_DIR"
log_done "ISO criada com sucesso: $OUTPUT_ISO"

# 7️⃣ FINALIZAÇÃO
log_step "Processo concluído."
log_done "ISO personalizada e compacta pronta: $OUTPUT_ISO"
