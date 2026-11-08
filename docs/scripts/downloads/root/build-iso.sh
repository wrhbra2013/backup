#!/usr/bin/env bash
# =============================================================================
# build-iso.sh - Oracle Linux 9.8 GNOME -> ISO instalavel UEFI
#
# Estrategia: remasteriza o boot.iso OFICIAL do Oracle Linux 9.8 com mkksiso,
# injetando um kickstart (GNOME + AppImages + configs) sem precisar montar
# um ambiente de build em QEMU. O boot UEFI original e preservado.
#
# Fases:
#   download  Baixa o boot.iso oficial (~1.5 GiB) para cache/
#   check     Pre-flight + inventario + gera kickstart + overlay (sem root)
#   build     Gera a ISO customizada com mkksiso (sem root)
#   verify    Valida EFI, kickstart, overlay e checksum
#   clean     Remove temporarios (mantem ISO e cache)
#
# Uso:
#   ./build-iso.sh download
#   ./build-iso.sh check
#   ./build-iso.sh build
#   ./build-iso.sh verify
# =============================================================================
set -Eeuo pipefail

# Usuario real mesmo sob sudo (HOME vira /root).
SCRIPT_USER="${SUDO_USER:-${USER}}"
TARGET_HOME="$(getent passwd "$SCRIPT_USER" | cut -d: -f6)"
[ -n "${TARGET_HOME:-}" ] || TARGET_HOME="$HOME"

BASE_DIR="${BASE_DIR:-$TARGET_HOME/iso-build}"
CACHE_DIR="$BASE_DIR/cache"
OUT_DIR="$BASE_DIR/out"
WORK_DIR="$BASE_DIR/work"
KS_DIR="$BASE_DIR/kickstart"
OVERLAY_DIR="$BASE_DIR/overlay"
LOG_DIR="$BASE_DIR/logs"

RELEASEVER="${RELEASEVER:-9.8}"
PROFILE_NAME="${PROFILE_NAME:-OL98-GNOME-Custom}"
VOLID="${VOLID:-OL98_GNOME_CUSTOM}"
ISO_NAME="${ISO_NAME:-OL98-GNOME-Custom.iso}"
ISO_PATH="$OUT_DIR/$ISO_NAME"

BOOT_ISO_NAME="OracleLinux-R9-U8-x86_64-boot.iso"
BOOT_ISO="$CACHE_DIR/$BOOT_ISO_NAME"
BOOT_URL="https://yum.oracle.com/ISOS/OracleLinux/OL9/u8/x86_64/$BOOT_ISO_NAME"
BOOT_SIZE=1561657344

TARGET_USER="${TARGET_USER:-$SCRIPT_USER}"
TARGET_HOST="${TARGET_HOST:-ol98-custom}"
TARGET_PASS="${TARGET_PASS:-}"

KS_FILE="$KS_DIR/ol98-custom.ks"
OVERLAY_TGZ="$OVERLAY_DIR/overlay.tar.gz"
CREDS_FILE="$BASE_DIR/credentials.txt"

mkdir -p "$CACHE_DIR" "$OUT_DIR" "$WORK_DIR" "$KS_DIR" "$OVERLAY_DIR" "$LOG_DIR"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'

log()  { printf '%s[ %s ]%s %s\n' "$c_blue" "$(date +%H:%M:%S)" "$c_reset" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$c_yellow" "$c_reset" "$*"; }
die()  { printf '%s[FAIL]%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "Precisa de root. Rode: sudo $0 ${1:-verify}"; }
have() { command -v "$1" >/dev/null 2>&1; }

# -----------------------------------------------------------------------------
# Kickstart
# -----------------------------------------------------------------------------
generate_kickstart() {
  local pass="$TARGET_PASS"
  if [ -z "$pass" ] && [ -f "$CREDS_FILE" ]; then
    pass="$(awk -F': *' '/^senha:/{print $2}' "$CREDS_FILE" | head -1)"
  fi
  if [ -z "$pass" ]; then
    pass="$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-16)"
    {
      echo "usuario: $TARGET_USER"
      echo "senha:   $pass"
      echo "host:    $TARGET_HOST"
      echo "gerado:  $(date -Is)"
    } > "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"
    warn "Senha do usuario gerada e salva em: $CREDS_FILE"
  fi

  local pass_hash
  pass_hash="$(openssl passwd -6 "$pass")"

  log "Gerando kickstart: $KS_FILE"
  cat > "$KS_FILE" <<KS
#version=OL9
# Kickstart gerado por build-iso.sh em $(date -Is)
lang pt_BR.UTF-8
keyboard --vckeymap=br-abnt2 --xlayouts='br'
timezone America/Sao_Paulo --utc
text
selinux --enforcing
firewall --enabled --service=ssh
network --bootproto=dhcp --device=link --activate --hostname=${TARGET_HOST}
rootpw --lock
user --name=${TARGET_USER} --groups=wheel --shell=/bin/bash --password=${pass_hash}
firstboot --disable
zerombr
clearpart --all --initlabel
autopart --type=plain --nohome
bootloader --location=mbr --timeout=5 --append="rhgb quiet"
reboot

url --url="https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/"
repo --name="appstream" --baseurl="https://yum.oracle.com/repo/OracleLinux/OL9/appstream/latest/x86_64/"
repo --name="uek" --baseurl="https://yum.oracle.com/repo/OracleLinux/OL9/UEKR8/latest/x86_64/"

%packages
@^graphical-server-environment
@gnome-desktop
@fonts
@input-methods
kernel-uek
fuse
fuse-libs
fuse3
fuse3-libs
rsync
curl
tar
gnome-tweaks
gnome-terminal
nautilus
%end

# Copia AppImages/configs do ISO para o sistema instalado.
%post --nochroot --log=/root/ks-post-nochroot.log
set -x
for d in /run/install/repo /mnt/install/repo /run/install/isodir; do
  if [ -f "\$d/overlay.tar.gz" ] && [ -d /mnt/sysimage ]; then
    tar -xzf "\$d/overlay.tar.gz" -C /mnt/sysimage/
    break
  fi
done
%end

%post --log=/root/ks-post.log
set -x
chown -R 1000:1000 /home/${TARGET_USER} 2>/dev/null || true
find /home/${TARGET_USER}/Applications -name '*.AppImage' -exec chmod +x {} \\; 2>/dev/null || true
restorecon -R /home/${TARGET_USER} 2>/dev/null || true

# Fallback: se libfuse2 nao existir, AppImages extraem em vez de montar.
cat >/etc/profile.d/99-appimage-fallback.sh <<'EOS'
if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\\.so\\.2'; then
  export APPIMAGE_EXTRACT_AND_RUN=1
fi
EOS
chmod 644 /etc/profile.d/99-appimage-fallback.sh

# Usa o kernel UEK como padrao, igual ao sistema atual.
if ls /boot/vmlinuz-*uek* >/dev/null 2>&1; then
  grubby --set-default "\$(ls -1 /boot/vmlinuz-*uek* | sort -V | tail -1)" 2>/dev/null || true
fi

systemctl enable gdm.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true
systemctl set-default graphical.target 2>/dev/null || true
%end
KS
  ok "Kickstart criado."
}

# -----------------------------------------------------------------------------
# Overlay (allowlist: sem .ssh/.gnupg/keyrings/browsers)
# -----------------------------------------------------------------------------
make_overlay() {
  local root="$OVERLAY_DIR/root"
  log "Montando overlay (AppImages + configuracoes seguras)..."
  rm -rf "$root"
  mkdir -p "$root/home/$TARGET_USER/Applications" \
           "$root/home/$TARGET_USER/.local/share/applications" \
           "$root/home/$TARGET_USER/.config"

  if [ -d "$TARGET_HOME/Applications" ]; then
    rsync -a --include='*.AppImage' --include='*.version' --exclude='*' \
      "$TARGET_HOME/Applications/" "$root/home/$TARGET_USER/Applications/"
  fi
  if [ -d "$TARGET_HOME/.local/bin" ]; then
    find "$TARGET_HOME/.local/bin" -maxdepth 1 -name '*.AppImage' -exec cp -a {} \
      "$root/home/$TARGET_USER/Applications/" \; 2>/dev/null || true
  fi
  if [ -d "$TARGET_HOME/.local/share/applications" ]; then
    find "$TARGET_HOME/.local/share/applications" -maxdepth 1 -name '*.desktop' \
      -exec cp -a {} "$root/home/$TARGET_USER/.local/share/applications/" \; 2>/dev/null || true
  fi
  if [ -d "$TARGET_HOME/Desktop" ]; then
    find "$TARGET_HOME/Desktop" -maxdepth 1 -name '*.desktop' \
      -exec cp -a {} "$root/home/$TARGET_USER/.local/share/applications/" \; 2>/dev/null || true
  fi

  local cfg
  for cfg in gtk-3.0 gtk-4.0 dconf fontconfig nautilus gedit; do
    if [ -d "$TARGET_HOME/.config/$cfg" ]; then
      cp -a "$TARGET_HOME/.config/$cfg" "$root/home/$TARGET_USER/.config/"
    fi
  done
  if [ -d "$TARGET_HOME/.local/share/fonts" ]; then
    mkdir -p "$root/home/$TARGET_USER/.local/share"
    cp -a "$TARGET_HOME/.local/share/fonts" "$root/home/$TARGET_USER/.local/share/"
  fi
  if [ -d "$TARGET_HOME/.local/share/themes" ]; then
    mkdir -p "$root/home/$TARGET_USER/.local/share"
    cp -a "$TARGET_HOME/.local/share/themes" "$root/home/$TARGET_USER/.local/share/"
  fi
  [ -f "$TARGET_HOME/.bashrc" ] && cp -a "$TARGET_HOME/.bashrc" "$root/home/$TARGET_USER/.bashrc"
  [ -f "$TARGET_HOME/.gitconfig" ] && cp -a "$TARGET_HOME/.gitconfig" "$root/home/$TARGET_USER/.gitconfig"

  rm -f "$OVERLAY_TGZ"
  tar -czf "$OVERLAY_TGZ" -C "$root" .
  chmod 644 "$OVERLAY_TGZ"
  ok "Overlay: $OVERLAY_TGZ ($(du -h "$OVERLAY_TGZ" | cut -f1))"
}

# -----------------------------------------------------------------------------
# download
# -----------------------------------------------------------------------------
cmd_download() {
  mkdir -p "$CACHE_DIR"
  if [ -f "$BOOT_ISO" ]; then
    local size
    size=$(stat -c %s "$BOOT_ISO")
    if [ "$size" -eq "$BOOT_SIZE" ]; then
      ok "boot.iso ja existe e esta completo: $BOOT_ISO"
      return 0
    fi
    warn "boot.iso incompleto ($size bytes). Retomando download..."
  fi
  log "Baixando boot.iso oficial (~1.5 GiB) para $CACHE_DIR"
  curl -fL --retry 3 --retry-delay 5 -C - -o "$BOOT_ISO" "$BOOT_URL"
  local size
  size=$(stat -c %s "$BOOT_ISO")
  [ "$size" -eq "$BOOT_SIZE" ] || die "Tamanho inesperado: $size (esperado $BOOT_SIZE)"
  ok "Download concluido: $BOOT_ISO"
}

# -----------------------------------------------------------------------------
# check
# -----------------------------------------------------------------------------
cmd_check() {
  local fatal=0
  log "Pre-flight em $(hostname) - $(date -Is)"
  echo

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "SO........: ${PRETTY_NAME:-desconhecido}"
    case "${ID:-}:${VERSION_ID:-}" in
      ol:9.*) ok "Oracle Linux 9 detectado." ;;
      *) warn "Script desenhado para Oracle Linux 9.x." ;;
    esac
  fi
  echo "Kernel....: $(uname -r)"
  echo "Arch......: $(uname -m)"
  [ "$(uname -m)" = "x86_64" ] || { warn "Somente x86_64 testado."; fatal=1; }

  local avail_gb
  avail_gb=$(df -BG --output=avail "$BASE_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
  echo "Disco.....: ${avail_gb:-?} GiB livres em $BASE_DIR"
  if [ "${avail_gb:-0}" -lt 8 ]; then warn "Recomendado >= 8 GiB livres."; fatal=1; else ok "Espaco suficiente."; fi

  echo
  echo "Ferramentas:"
  local t missing=0
  for t in dnf rpm mkksiso xorriso implantisomd5 curl rsync; do
    if have "$t"; then printf '  %-16s %s\n' "$t" "OK"; else printf '  %-16s %s\n' "$t" "AUSENTE"; missing=1; fi
  done
  [ "$missing" -eq 1 ] && warn "Instale as ausentes (pacotes: lorax xorriso isomd5sum rsync curl)."

  echo
  if [ -f "$BOOT_ISO" ]; then
    ok "boot.iso presente ($(du -h "$BOOT_ISO" | cut -f1))."
  else
    warn "boot.iso ausente. Rode: $0 download"
  fi

  echo
  echo "Repositorios Oracle usados no kickstart:"
  echo "  baseos   : https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64/"
  echo "  appstream: https://yum.oracle.com/repo/OracleLinux/OL9/appstream/latest/x86_64/"
  echo "  uek      : https://yum.oracle.com/repo/OracleLinux/OL9/UEKR8/latest/x86_64/"

  echo
  log "Inventario do sistema atual"
  echo "  Pacotes RPM.....: $(rpm -qa | wc -l)"
  echo "  AppImages.......: $(find "$TARGET_HOME/Applications" "$TARGET_HOME/.local/bin" -maxdepth 1 -name '*.AppImage' 2>/dev/null | wc -l)"
  echo "  Atalhos .desktop: $(find "$TARGET_HOME/.local/share/applications" "$TARGET_HOME/Desktop" -maxdepth 1 -name '*.desktop' 2>/dev/null | wc -l)"
  echo "  libfuse.so.2....: $(ldconfig -p 2>/dev/null | grep -c 'libfuse\.so\.2' || true)"

  echo
  generate_kickstart
  make_overlay

  echo
  if [ "$fatal" -eq 0 ]; then ok "Pre-flight concluido."; else warn "Pre-flight com bloqueios (veja avisos)."; fi
  cat <<EOF

Proximos passos:
  1) $0 download
  2) $0 build
  3) $0 verify

Arquivos:
  boot.iso : $BOOT_ISO
  Kickstart: $KS_FILE
  Overlay  : $OVERLAY_TGZ
  ISO final: $ISO_PATH
EOF
}

# -----------------------------------------------------------------------------
# build
# -----------------------------------------------------------------------------
cmd_build() {
  have mkksiso || die "mkksiso ausente. Instale: sudo dnf install -y lorax xorriso isomd5sum"
  [ -f "$BOOT_ISO" ] || die "boot.iso ausente. Rode: $0 download"
  [ -f "$KS_FILE" ] || die "Kickstart ausente. Rode: $0 check"
  [ -f "$OVERLAY_TGZ" ] || die "Overlay ausente. Rode: $0 check"

  local size
  size=$(stat -c %s "$BOOT_ISO")
  [ "$size" -eq "$BOOT_SIZE" ] || die "boot.iso incompleto ($size/$BOOT_SIZE). Rode: $0 download"

  mkdir -p "$OUT_DIR"
  rm -f "$ISO_PATH"

  log "Remasterizando boot.iso com mkksiso..."
  log "Log: $LOG_DIR/mkksiso.log"
  set +e
  mkksiso --ks "$KS_FILE" --add "$OVERLAY_TGZ" --volid "$VOLID" \
    "$BOOT_ISO" "$ISO_PATH" 2>&1 | tee -a "$LOG_DIR/mkksiso.log"
  local rc=${PIPESTATUS[0]}
  set -e
  [ "$rc" -eq 0 ] || die "mkksiso falhou (rc=$rc). Veja $LOG_DIR/mkksiso.log"
  [ -f "$ISO_PATH" ] || die "ISO nao gerada."
  # Build roda como root via sudo: devolve a propriedade ao usuario real.
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER": "$ISO_PATH" 2>/dev/null || true
    chown -R "$SUDO_USER": "$LOG_DIR" 2>/dev/null || true
  fi
  ok "ISO gerada: $ISO_PATH"
  ls -lh "$ISO_PATH"

  verify_iso
}

# -----------------------------------------------------------------------------
# verify
# -----------------------------------------------------------------------------
verify_iso() {
  log "Validando ISO..."
  [ -f "$ISO_PATH" ] || die "ISO inexistente: $ISO_PATH"

  local report
  report=$(xorriso -indev "$ISO_PATH" -report_el_torito plain 2>/dev/null || true)
  if grep -qi 'efi' <<<"$report"; then ok "Entrada EFI (El Torito) detectada."; else warn "Entrada EFI nao detectada."; fi

  if [ "$(id -u)" -eq 0 ]; then
    local mnt="$WORK_DIR/mnt"
    mkdir -p "$mnt"
    if mount -o loop,ro "$ISO_PATH" "$mnt" 2>/dev/null; then
      [ -f "$mnt/EFI/BOOT/BOOTX64.EFI" ] || [ -f "$mnt/EFI/BOOT/bootx64.efi" ] \
        && ok "EFI/BOOT/BOOTX64.EFI presente." || warn "BOOTX64.EFI ausente."
      [ -f "$mnt/overlay.tar.gz" ] && ok "overlay.tar.gz presente no ISO." || warn "overlay.tar.gz ausente."
      if [ -f "$mnt/ol98-custom.ks" ] || [ -f "$mnt/ks.cfg" ]; then
        ok "Kickstart presente no ISO."
      else
        warn "Kickstart ausente no ISO."
      fi
      if grep -q 'inst\.ks=' "$mnt/EFI/BOOT/grub.cfg" 2>/dev/null; then
        ok "inst.ks configurado no GRUB (UEFI)."
      else
        warn "inst.ks nao encontrado no grub.cfg."
      fi
      umount "$mnt"
    else
      warn "Nao foi possivel montar a ISO para inspecao."
    fi
  else
    warn "Sem root: verificando conteudo sem montar (use sudo $0 verify para checagem completa)."
  fi

  if have checkisomd5; then
    checkisomd5 "$ISO_PATH" >/dev/null 2>&1 && ok "Checksum MD5 valido." || warn "Checksum MD5 invalido/ausente."
  fi

  local ovmf=""
  local p
  for p in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd \
           /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
    [ -f "$p" ] && { ovmf="$p"; break; }
  done
  ovmf="${ovmf:-/usr/share/OVMF/OVMF_CODE.fd}"

  cat <<EOF

Teste em VM UEFI (host com OVMF):
  qemu-system-x86_64 -enable-kvm -m 1536 -machine q35 \\
    -bios "$ovmf" \\
    -cdrom "$ISO_PATH" -boot d

Gravar em pendrive (CONFIRME o dispositivo antes):
  sudo dd if="$ISO_PATH" of=/dev/sdX bs=8M status=progress oflag=sync
EOF
}

# -----------------------------------------------------------------------------
# clean
# -----------------------------------------------------------------------------
cmd_clean() {
  log "Limpando temporarios (mantendo ISO, boot.iso e kickstart)..."
  rm -rf "$WORK_DIR/tmp" "$WORK_DIR/mnt" "$OVERLAY_DIR/root"
  ok "Limpeza concluida."
}

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  case "${1:-check}" in
    download) cmd_download ;;
    check)    cmd_check ;;
    build)    cmd_build ;;
    verify)   verify_iso ;;
    clean)    cmd_clean ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
