#!/bin/bash

# Configuracao completa: Oracle Linux 9 + EPEL + RPM Fusion + XFCE + LibreOffice + Codecs
# Sem --nobest nem --skip-broken: repositorios corretos eliminam dependencias quebradas

set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
info()  { echo -e "${C}[INFO]${N}  $1"; }
ok()    { echo -e "${G}[OK]${N}    $1"; }
warn()  { echo -e "${Y}[WARN]${N}  $1"; }
err()   { echo -e "${R}[ERRO]${N} $1"; }

[[ $EUID -ne 0 ]] && { err "Execute como root (sudo)."; exit 1; }
[[ ! -f /etc/oracle-release ]] && { err "Apenas Oracle Linux 9."; exit 1; }
VERSAO=$(grep -oP '\d+\.\d+' /etc/oracle-release | head -1)
info "Oracle Linux $VERSAO detectado"

# Backup limpo dos repos atuais
BACKUP="/etc/yum.repos.d/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"
cp /etc/yum.repos.d/*.repo "$BACKUP/" 2>/dev/null || true
ok "Backup dos repos atuais em: $BACKUP"
rm -f /etc/yum.repos.d/*.repo

# ============================================================
# 1. Oracle Linux repos (BaseOS + AppStream + CRB + UEK)
# ============================================================
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

[ol9_codeready_builder]
name=Oracle Linux 9 CodeReady Builder ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/codeready/builder/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
REPO
ok "Oracle Linux repos: BaseOS + AppStream + CRB"

# ============================================================
# 2. EPEL (via Oracle mirror - mais estavel e compativel)
# ============================================================
info "Instalando EPEL..."
if dnf install -y oracle-epel-release-el9 &>/dev/null; then
    ok "EPEL via Oracle mirror"
else
    warn "Oracle EPEL mirror falhou. Usando EPEL upstream..."
    cat > /etc/yum.repos.d/epel.repo << 'REPO'
[epel]
name=Extra Packages for Enterprise Linux 9 - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-9&arch=$basearch
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
gpgcheck=1
REPO
    curl -sL https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9 \
        -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
    ok "EPEL upstream configurado"
fi

# Exclui ffmpeg do EPEL para nao conflitar com versao mais completa do RPM Fusion
REPO_FILE=$(ls /etc/yum.repos.d/*epel*.repo 2>/dev/null | head -1)
if [[ -n "$REPO_FILE" ]]; then
    if ! grep -q "exclude=" "$REPO_FILE" 2>/dev/null; then
        # Injeta exclude no primeiro repo section
        sed -i '/^\[epel\]/,/^\[/{/^enabled=/a\exclude=ffmpeg* libavcodec* libavdevice* libavfilter* libavformat* libavutil* libpostproc* libswresample* libswscale*' "$REPO_FILE}" 2>/dev/null
        # Fallback: adiciona ao final
        if ! grep -q "exclude=ffmpeg" "$REPO_FILE" 2>/dev/null; then
            echo -e "\n[epel]\nexclude=ffmpeg*" >> "$REPO_FILE"
        fi
    fi
    ok "EPEL configurado para excluir ffmpeg (evita conflito com RPM Fusion)"
fi

# ============================================================
# 3. RPM Fusion (Free + Nonfree)
# ============================================================
info "Instalando RPM Fusion..."
dnf install -y --nogpgcheck \
    https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm
ok "RPM Fusion Free + Nonfree"

# ============================================================
# 4. Sincroniza e atualiza
# ============================================================
info "Sincronizando repositorios e atualizando sistema..."
dnf makecache
dnf update -y
ok "Cache e sistema atualizados"

# ============================================================
# 5. Window Manager - XFCE
# ============================================================
info "Instalando XFCE..."
if dnf group install -y "Xfce" &>/dev/null; then
    ok "XFCE via grupo 'Xfce'"
else
    dnf install -y \
        xfce4-session xfce4-panel xfce4-whiskermenu-plugin \
        xfce4-terminal xfdesktop xfwm4 thunar \
        xfce4-notifyd xfce4-power-manager xfce4-screenshooter \
        xfce4-taskmanager mousepad parole ristretto
    ok "XFCE via pacotes individuais"
fi

# ============================================================
# 6. LibreOffice
# ============================================================
info "Instalando LibreOffice..."
dnf install -y \
    libreoffice \
    libreoffice-langpack-pt-BR \
    libreoffice-calc \
    libreoffice-writer \
    libreoffice-impress
ok "LibreOffice + pt-BR"

# ============================================================
# 7. Codecs de audio e video
# ============================================================
info "Instalando codecs multimedia..."
dnf install -y \
    ffmpeg ffmpeg-libs \
    gstreamer1-plugins-base gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free gstreamer1-plugins-good-extras \
    gstreamer1-plugins-bad-free-extras gstreamer1-plugins-ugly-free \
    gstreamer1-libav \
    gstreamer1-plugins-ugly \
    gstreamer1-plugins-bad-freeworld \
    vlc \
    x264 x265 \
    libvpx \
    opus-tools flac lame-libs vorbis-tools \
    libdvdcss libdvdread libdvdnav \
    sox
ok "Codecs instalados"

# ============================================================
# 8. Utilitarios
# ============================================================
info "Instalando utilitarios..."
dnf install -y \
    curl wget git htop \
    unzip bzip2 p7zip p7zip-plugins \
    file-roller \
    firefox \
    keepassxc \
    cabextract
ok "Utilitarios instalados"

# ============================================================
echo ""
echo "================================================"
echo "  Instalacao concluida sem erros de dependencia!"
echo "================================================"
echo "  Repos: Oracle Linux Base/AppStream/CRB"
echo "         EPEL (Oracle mirror)"
echo "         RPM Fusion Free + Nonfree"
echo ""
echo "  Sistema atualizado sem --nobest nem --skip-broken"
echo ""
echo "  XFCE  - Window Manager"
echo "  LibreOffice (pt-BR)"
echo "  Codecs: ffmpeg, gstreamer (ugly+bad-freeworld),"
echo "          VLC, x264, x265, libdvdcss"
echo "================================================"
