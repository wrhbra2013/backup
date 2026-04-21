 #!/bin/bash
# ----------------------------------------------------
# SCRIPT DE CRIAÇÃO DE ISO HÍBRIDA OL 9.6: CLONE COM SQUASHFS E REPOSITÓRIOS
# OBJETIVO: Criar uma ISO Live/Restore a partir do sistema atual (SquashFS)
#            incluindo pacotes e repositórios extras em um Tarball de Dados.
# ----------------------------------------------------

# Define a cor verde para mensagens de sucesso e informativo
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ====================================================
# 1. CONFIGURAÇÃO GLOBAL (AJUSTE AQUI)
# ====================================================
ISO_WORK_DIR="/tmp/custom_ol_iso"
LIVE_ROOT_DIR="${ISO_WORK_DIR}/LiveOS"
DATA_ROOT_DIR="${ISO_WORK_DIR}/install_data"
VOLUME_ID="OL9_CUSTOM_LIVE"

# --- Nomes de Arquivos ---
SQUASHFS_FILE="squashfs.img"
DATA_TARBALL="ol_data.tar.gz"

# --- Caminhos de Origem/Destino ---
CUSTOM_RPM_SOURCE="software_rpm" 
CUSTOM_FILES_SOURCE="favoritos" 
CUSTOM_RPM_DEST="/opt/custom_data/software_rpm"
CUSTOM_FILES_DEST="/opt/custom_data/files"

# --- Caminhos de Ferramentas e Boot ---
ISOHYBRID_MBR_FILE="/usr/share/syslinux/isohdpfx.bin"
GRUB_EFI_BOOTLOADER="/boot/efi/EFI/ol/grubx64.efi"

# --- Saída Final ---
DATE_TAG=$(date +%Y%m%d_%H%M)
OUTPUT_ISO_NAME="Oracle_Linux_9.6_Custom_Live_${DATE_TAG}.iso"

# Lista de diretórios/arquivos a excluir do backup do sistema raiz (SquashFS)
# O '*' é crucial para excluir todos os subdiretórios de /home
EXCLUDES=(
    /proc/* /sys/* /dev/* /run/* /proc/kcore /proc/iomem
    /mnt/* /tmp/* /media/* /lost+found
    /boot/* /var/cache/*
    /home/* # <--- INCLUSÃO DA EXCLUSÃO DA PASTA /HOME
    ${ISO_WORK_DIR}/* )

# ====================================================
# 2. FUNÇÕES DE VERIFICAÇÃO E LIMPEZA (CORRIGIDO AQUI)
# ====================================================

check_dependencies() {
    echo -e "${GREEN}Verificando dependências essenciais: xorriso, mksquashfs, dracut...${NC}"
    local dependencies="xorriso mksquashfs dracut tar cp date ls bash grub2-install"
    local missing=0

    for dep in $dependencies; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${RED}ERRO: Dependência '$dep' não encontrada. Instale-a via DNF.${NC}"
            missing=1
        fi
    done

    # === NOVO CHECK E INSTALAÇÃO DE MÓDULO LIVE DO DRACUT ===
    echo -e "\n${GREEN}Verificando módulo 'live' do dracut (pacote dracut-live)...${NC}"
    if ! dnf list installed dracut-live &> /dev/null; then
        echo -e "${RED}PACOTE AUSENTE: 'dracut-live' é necessário para o boot Live. (Causa do erro anterior).${NC}"
        echo -e "Tentando instalar 'dracut-live' via DNF..."
        # Tenta instalar o pacote. 'sudo' é necessário, assumindo que o usuário tem permissão.
        sudo dnf install -y dracut-live
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}ERRO FATAL: Falha ao instalar 'dracut-live'. Verifique os repositórios ou permissões sudo.${NC}"
            missing=1
        else
            echo -e "${GREEN}Pacote 'dracut-live' instalado com sucesso.${NC}"
        fi
    else
        echo -e "${GREEN}Pacote 'dracut-live' já instalado. OK.${NC}"
    fi
    # =========================================================
    
    if [ ! -f "$ISOHYBRID_MBR_FILE" ]; then
        echo -e "${RED}ERRO: Arquivo MBR (${ISOHYBRID_MBR_FILE}) não encontrado. Instale 'syslinux-nonboot'.${NC}"
        missing=1
    fi
    
    if [ $missing -ne 0 ]; then
        echo -e "\n${RED}Existem dependências ausentes ou falha na instalação. Por favor, corrija o problema e execute novamente.${NC}"
        exit 1
    fi
    echo -e "\n${GREEN}Todas as dependências (incluindo 'dracut-live') OK.${NC}"
}

prepare_environment() {
    echo -e "\n--- 1/6. PREPARAÇÃO E LIMPEZA DE AMBIENTE ---"
    if [ -d "${ISO_WORK_DIR}" ]; then
        echo "Limpando diretório de trabalho antigo: ${ISO_WORK_DIR}"
        rm -rf "${ISO_WORK_DIR}"
    fi
    echo "Criando nova estrutura de trabalho básica..."
    mkdir -p "${LIVE_ROOT_DIR}"
    mkdir -p "${DATA_ROOT_DIR}"
    mkdir -p "${ISO_WORK_DIR}/boot/grub"
    mkdir -p "${ISO_WORK_DIR}/EFI/BOOT"
    mkdir -p "${ISO_WORK_DIR}/etc"
    echo -e "${GREEN}Estrutura de diretórios criada com sucesso.${NC}"
}

# ====================================================
# 3. FASE DE CLONAGEM (SQUASHFS)
# ====================================================

create_squashfs() {
    echo -e "\n--- 2/6. CLONAGEM DO SISTEMA EM SQUASHFS ---"
    echo "Iniciando compactação do sistema raiz (/) em ${SQUASHFS_FILE}..."
    echo "Usando compressão XZ e excluindo diretórios virtuais, caches e A PASTA HOME."

    # Comando corrigido: o argumento de exclusão (-e) é posicional
    mksquashfs / "${LIVE_ROOT_DIR}/${SQUASHFS_FILE}" -comp xz -e "${EXCLUDES[@]}"

    if [ $? -ne 0 ]; then
        echo -e "${RED}ERRO: Falha ao criar a imagem SquashFS. Verifique os logs do mksquashfs.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Imagem SquashFS (${SQUASHFS_FILE}) criada com sucesso.${NC}"
}

# ====================================================
# 4. FASE DE DADOS E REPOSITÓRIOS
# ====================================================

create_data_tarball() {
    echo -e "\n--- 3/6. CONFIGURAÇÃO DE REPOSITÓRIOS E TARBALL DE DADOS ---"

    # 4.1. Criar Arquivo de Repositório (OL 9.x)
    local REPO_FILE="${ISO_WORK_DIR}/etc/ol_custom_repos.repo"
    echo "-> Criando arquivo de repositório '$REPO_FILE' com URLs do OL/EL 9."
    
    cat << EOF_REPO > "$REPO_FILE"
# Repositórios para o Ambiente Live/Instalação (Oracle Linux 9.x)
[ol_custom_rpms]
name=Custom RPMs (Local)
baseurl=file://${CUSTOM_RPM_DEST}
enabled=1
gpgcheck=0

[ol_appstream]
name=Oracle Linux 9 AppStream
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle

[epel]
name=Extra Packages for Enterprise Linux 9 - \$basearch
baseurl=https://download.fedoraproject.org/pub/epel/9/Everything/\$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9

[rpmfusion-free]
name=RPM Fusion for EL 9 - Free - \$basearch
baseurl=http://download1.rpmfusion.org/free/el/9/Everything/\$basearch/os/
enabled=1
gpgcheck=0
EOF_REPO

    # Copiar o arquivo de repositório e chaves GPG (assumindo que existam no host)
    mkdir -p "${DATA_ROOT_DIR}/etc/yum.repos.d"
    cp "$REPO_FILE" "${DATA_ROOT_DIR}/etc/yum.repos.d/ol_custom_repos.repo"
    
    # 4.2. Preparar Conteúdo
    echo "-> Copiando pacotes RPMs de '$CUSTOM_RPM_SOURCE' para inclusão..."
    mkdir -p "${DATA_ROOT_DIR}${CUSTOM_RPM_DEST}"
    if [ -d "$CUSTOM_RPM_SOURCE" ]; then
        cp -rv "$CUSTOM_RPM_SOURCE"/* "${DATA_ROOT_DIR}${CUSTOM_RPM_DEST}/"
    else
        echo "    AVISO: Diretório de RPMs (${CUSTOM_RPM_SOURCE}) não encontrado."
    fi

    echo "-> Copiando arquivos de pós-instalação de '$CUSTOM_FILES_SOURCE'..."
    mkdir -p "${DATA_ROOT_DIR}${CUSTOM_FILES_DEST}"
    if [ -d "$CUSTOM_FILES_SOURCE" ]; then
        cp -rv "$CUSTOM_FILES_SOURCE"/* "${DATA_ROOT_DIR}${CUSTOM_FILES_DEST}/"
    else
        echo "    AVISO: Diretório de arquivos extras (${CUSTOM_FILES_SOURCE}) não encontrado."
    fi

    # 4.3. Criar o Tarball de Dados
    echo "-> Criando tarball de dados ${DATA_TARBALL} na raiz da ISO."
    tar -czvf "${ISO_WORK_DIR}/${DATA_TARBALL}" -C "${DATA_ROOT_DIR}" .
    echo -e "${GREEN}Tarball de dados criado com sucesso: ${ISO_WORK_DIR}/${DATA_TARBALL}${NC}"
}

# ====================================================
# 5. FASE DE BOOT E DRACUT
# ====================================================

configure_boot() {
    echo -e "\n--- 4/6. CONFIGURAÇÃO DE BOOT (Kernel, Initramfs e GRUB) ---"
    CURRENT_KERNEL_VERSION=$(uname -r)
    KERNEL="/boot/vmlinuz-${CURRENT_KERNEL_VERSION}"

    # 5.1. Copiar Kernel e Initramfs (do sistema atual)
    echo "-> Kernel do sistema (v. ${CURRENT_KERNEL_VERSION}) será usado para o boot Live."
    if [ ! -f "$KERNEL" ]; then
        echo -e "${RED}ERRO: Kernel (${KERNEL}) não encontrado. Abortando.${NC}"
        exit 1
    fi
    cp "$KERNEL" "${ISO_WORK_DIR}/boot/vmlinuz"

    # 5.2. Gerar Initramfs Customizado com Suporte a Live/SquashFS
    CUSTOM_INITRAMFS="${ISO_WORK_DIR}/boot/initrd.img"
    echo "-> Gerando novo Initramfs customizado com módulo 'live' via dracut..."
    
    # Esta linha agora deve funcionar, pois 'dracut-live' foi verificado/instalado.
    dracut --force --no-host-only --add "live" "$CUSTOM_INITRAMFS" "$CURRENT_KERNEL_VERSION"

    if [ $? -ne 0 ]; then
        echo -e "${RED}ERRO: Falha ao gerar o initramfs com dracut. O boot Live falhará.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Initramfs com suporte Live gerado com sucesso.${NC}"

    # 5.3. Configuração do GRUB e Bootloader EFI
    echo "-> Copiando bootloader EFI e configurando GRUB..."
    if [ -f "$GRUB_EFI_BOOTLOADER" ]; then
        cp "$GRUB_EFI_BOOTLOADER" "${ISO_WORK_DIR}/EFI/BOOT/grubx64.efi"
    else
        echo "    AVISO: Bootloader EFI (${GRUB_EFI_BOOTLOADER}) não encontrado. Boot UEFI pode falhar."
    fi

    # Criar o Arquivo de Configuração do GRUB
    local BOOT_DIR="${ISO_WORK_DIR}/boot"
    cat << EOF_GRUB_LIVE > "$BOOT_DIR/grub/grub.cfg"
set default="0"
set timeout=10

menuentry "Oracle Linux 9.6 Live & Restore (Live) [Volume ID: ${VOLUME_ID}]" {
    linux /boot/vmlinuz rd.live.image root=live:LABEL=${VOLUME_ID} rootfstype=auto ro quiet splash
    initrd /boot/initrd.img
}
EOF_GRUB_LIVE

    # Usar o mesmo grub.cfg para o boot UEFI
    cp "$BOOT_DIR/grub/grub.cfg" "${ISO_WORK_DIR}/EFI/BOOT/grub.cfg"
    echo -e "${GREEN}Configuração de boot GRUB finalizada.${NC}"
}

# ====================================================
# 6. FASE DE SCRIPT DE SETUP
# ====================================================

create_setup_script() {
    echo -e "\n--- 5/6. CRIAÇÃO DO SCRIPT DE CONFIGURAÇÃO (initial_setup.sh) ---"
    local SETUP_SCRIPT_PATH="${ISO_WORK_DIR}/initial_setup.sh"

    # O script assume que o DATA_TARBALL está na raiz da ISO montada.
    cat << EOF_SETUP > "$SETUP_SCRIPT_PATH"
#!/bin/bash
# Script de Configuração Inicial (Execute DENTRO DO AMBIENTE LIVE)

DATA_TARBALL_PATH="/${DATA_TARBALL}"

echo "--- INÍCIO DO SCRIPT DE CONFIGURAÇÃO CUSTOMIZADO ---"

if [ ! -f "\$DATA_TARBALL_PATH" ]; then
    echo "ERRO: O arquivo de dados (\$DATA_TARBALL_PATH) não foi encontrado na raiz da ISO."
    echo "PASSO 1 FALHOU: Certifique-se de que a ISO foi montada corretamente."
    exit 1
fi

# 1. Extrair Dados (RPMs, Scripts, Repositórios)
echo "PASSO 2: Extraindo dados extras para /tmp/live_data..."
mkdir -p /tmp/live_data
tar -xzvpf "\$DATA_TARBALL_PATH" -C /tmp/live_data

# 2. Copiar Arquivo de Repositório e Linkar Repositório Local
echo "PASSO 3: Copiando repositórios e montando o diretório de dados local..."
cp -rv /tmp/live_data/etc/yum.repos.d/* /etc/yum.repos.d/
mkdir -p /opt/custom_data
# Monta o diretório de dados extraídos no caminho que o repositório local espera
mount --bind /tmp/live_data/install_data/opt/custom_data /opt/custom_data

# 3. Instalação de Pacotes Customizados
echo "PASSO 4: Instalando pacotes RPMs customizados via DNF..."
# Instala pacotes do repositório customizado, re-habilitando repositórios oficiais importantes
dnf clean all
dnf install -y /opt/custom_data/software_rpm/*.rpm --disablerepo=\* --enablerepo=ol_custom_rpms,ol_appstream,epel,rpmfusion-free

# 4. Executar Scripts de Pós-Instalação
echo "PASSO 5: Executando scripts de pós-instalação..."
SCRIPTS_DIR="/opt/custom_data/files/scripts"
if [ -d "\$SCRIPTS_DIR" ]; then
    find "\$SCRIPTS_DIR" -type f -executable -print -exec {} \;
fi

# 5. Limpar e Finalizar
echo "PASSO 6: Limpando montagens temporárias..."
umount /opt/custom_data
rm -rf /tmp/live_data
echo "Configuração inicial concluída. O ambiente Live está pronto."
EOF_SETUP

    chmod +x "$SETUP_SCRIPT_PATH"
    echo -e "${GREEN}Script de setup '$SETUP_SCRIPT_PATH' criado e pronto para uso no Live CD.${NC}"
}

# ====================================================
# 7. FASE DE GERAÇÃO DA ISO
# ====================================================

generate_iso() {
    echo -e "\n--- 6/6. GERAÇÃO DA IMAGEM ISO HÍBRIDA ---"
    echo "Iniciando xorriso para criar a ISO híbrida (UEFI + MBR/BIOS)..."

    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$VOLUME_ID" \
        \
        -eltorito-boot boot/grub/grub.cfg \
        -no-emul-boot \
        -boot-load-size 4 \
        \
        -eltorito-alt-boot \
        -e EFI/BOOT/grubx64.efi \
        -no-emul-boot \
        -boot-load-size 4 \
        \
        -isohybrid-mbr "$ISOHYBRID_MBR_FILE" \
        -o "$OUTPUT_ISO_NAME" \
        "$ISO_WORK_DIR"

    if [ $? -ne 0 ]; then
        echo -e "${RED}ERRO: Falha ao gerar a imagem ISO. Verifique os logs do xorriso.${NC}"
        exit 1
    fi

    echo -e "\n===================================================="
    echo -e "${GREEN}SUCESSO! A imagem ISO híbrida Live está pronta:${NC}"
    echo -e "--> $(pwd)/${OUTPUT_ISO_NAME}"
    echo -e "ID do Volume (Label): ${VOLUME_ID}"
    echo -e "====================================================\n"
}

# ====================================================
# FLUXO PRINCIPAL DE EXECUÇÃO
# ====================================================

check_dependencies
prepare_environment
create_squashfs
create_data_tarball
configure_boot
create_setup_script
generate_iso
