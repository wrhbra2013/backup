#!/bin/bash
#
# fix-repos-ol9.sh
# Script para corrigir repositórios do Oracle Linux 9.7
# Remove configs antigas, instala repositórios atualizados,
# desabilita plugins quebrados e limpa o cache do DNF.
#

set -e

VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${AZUL}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${VERDE}[OK]${NC}    $1"; }
log_warn()  { echo -e "${AMARELO}[WARN]${NC}  $1"; }
log_erro()  { echo -e "${VERMELHO}[ERRO]${NC} $1"; }

###############################################################################
# Verifica se está rodando como root
###############################################################################
if [[ $EUID -ne 0 ]]; then
    log_erro "Este script precisa ser executado como root (sudo)."
    exit 1
fi

###############################################################################
# Verifica se é Oracle Linux 9.x
###############################################################################
if ! grep -qi "Oracle Linux" /etc/oracle-release 2>/dev/null; then
    log_erro "Este script é exclusivo para Oracle Linux 9."
    exit 1
fi

VERSAO=$(grep -oP '\d+\.\d+' /etc/oracle-release | head -1)
log_info "Oracle Linux detectado: $VERSAO"

###############################################################################
# Backup dos repositórios atuais
###############################################################################
BACKUP_DIR="/etc/yum.repos.d/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/yum.repos.d/*.repo "$BACKUP_DIR/" 2>/dev/null || true
log_ok "Backup dos .repo em: $BACKUP_DIR"

###############################################################################
# Remove todos os arquivos .repo existentes (vamos recriar)
###############################################################################
rm -f /etc/yum.repos.d/*.repo
log_info "Arquivos .repo antigos removidos."

###############################################################################
# oracle-linux.repo — repositórios oficiais Oracle Linux 9
###############################################################################
cat > /etc/yum.repos.d/oracle-linux.repo << 'REPO'
[ol9_baseos_latest]
name=Oracle Linux 9 BaseOS Latest ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1

[ol9_appstream]
name=Oracle Linux 9 Application Stream ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/appstream/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1

[ol9_UEKR7]
name=Oracle Linux 9 UEK R7 ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/UEKR7/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1

[ol9_kvm_utils]
name=Oracle Linux 9 KVM Utilities ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/kvm/utils/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1

[ol9_codeready_builder]
name=Oracle Linux 9 CodeReady Builder ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/codeready/builder/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=0

[ol9_distro_builder]
name=Oracle Linux 9 Distro Builder ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/distro/builder/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=0

[ol9_optional_latest]
name=Oracle Linux 9 Optional Latest ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/optional/latest/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=0
REPO
log_ok "oracle-linux.repo criado com repositórios oficiais."

###############################################################################
# oracle-epel-ol9.repo — EPEL via Oracle (mais estável para OL9)
###############################################################################
if rpm -q oracle-epel-release-el9 &>/dev/null; then
    log_info "oracle-epel-release-el9 já instalado. Usando repositório EPEL do Oracle."

    cat > /etc/yum.repos.d/oracle-epel-ol9.repo << 'REPO'
[ol9_epel]
name=Oracle Linux 9 EPEL ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/epel/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
REPO
    log_ok "oracle-epel-ol9.repo criado (EPEL via Oracle)."
else
    log_warn "oracle-epel-release-el9 NÃO instalado. Instalando..."

    dnf install -y oracle-epel-release-el9 2>/dev/null || {
        log_erro "Falha ao instalar oracle-epel-release-el9 via DNF."
        log_info "Criando EPEL manual como fallback..."

        cat > /etc/yum.repos.d/epel.repo << 'REPO'
[epel]
name=Extra Packages for Enterprise Linux 9 - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-9&arch=$basearch
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
gpgcheck=1

[epel-next]
name=Extra Packages for Enterprise Linux 9 - Next - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-next-9&arch=$basearch
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
gpgcheck=1
REPO

        log_info "Baixando chave GPG do EPEL..."
        curl -sL https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9 \
            -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9 2>/dev/null && \
            log_ok "Chave GPG EPEL-9 baixada."
    }
fi

###############################################################################
# Desabilita plugins quebrados (ulninfo, spacewalk)
###############################################################################
for PLUGIN in ulninfo spacewalk; do
    CONF="/etc/dnf/plugins/${PLUGIN}.conf"
    if [[ -f "$CONF" ]]; then
        if grep -qi "^enabled" "$CONF" 2>/dev/null; then
            sed -i 's/^enabled.*/enabled=0/' "$CONF"
        else
            echo "enabled=0" >> "$CONF"
        fi
        log_ok "Plugin '$PLUGIN' desabilitado em: $CONF"
    fi
done

# Fallback: caso os .conf não existam, cria um disable via drop-in
for PLUGIN in ulninfo spacewalk; do
    CONF="/etc/dnf/plugins/${PLUGIN}.conf"
    if [[ ! -f "$CONF" ]]; then
        mkdir -p /etc/dnf/plugins
        cat > "$CONF" << 'EOF'
[main]
enabled=0
EOF
        log_ok "Plugin '$PLUGIN' desabilitado (conf criado do zero)."
    fi
done

###############################################################################
# Remove caches inválidos do DNF
###############################################################################
log_info "Limpando cache do DNF..."
dnf clean all 2>/dev/null || true

###############################################################################
# Testa os repositórios
###############################################################################
log_info "Testando conectividade dos repositórios..."
dnf repolist 2>&1 | grep -E "^ol9_|^epel" || true

log_info ""
log_ok "Script concluído!"
log_info "Repositórios configurados e prontos para uso."
log_info "Backup disponível em: $BACKUP_DIR"
log_info ""
log_info "Para testar a instalação de um pacote, execute:"
log_info "  dnf install -y <pacote>"
