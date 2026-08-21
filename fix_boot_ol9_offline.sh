#!/bin/bash
#============================================================
# Script: fix_boot_ol9_offline.sh
# Objetivo: Corrigir bugs de boot (UEFI e MBR) da ISO
#           OL9-Offline-Completa.iso e reescrever a imagem.
#
# Corrige:
#   1. Entrada padrão de boot era "Test this media" (rd.live.check)
#      em uma ISO sem checksum embutido => sistema travava.
#      Agora: default = Kickstart (auto) e checksum embutido
#      (implantisomd5) para a verificação de mídia funcionar.
#   2. inst.stage2 sem caminho explícito (dependia de .treeinfo).
#      Agora: inst.stage2=hd:LABEL=...:/images/install.img.
#   3. Arquivos ocultos (.discinfo) não copiados (glob ignorava
#      dotfiles). Agora restaurados.
#   4. ks.cfg usava 'bootloader --location=mbr' (incompatível com
#      UEFI). Removido para anaconda auto-detectar o modo.
#   5. console=ttyS0/tty0 para instalação headless observável.
#
# Pré-requisitos: sudo, xorriso, mtools, isomd5sum, syslinux
# Uso: sudo bash fix_boot_ol9_offline.sh
#============================================================
set -euo pipefail

ISO_ORIGEM="/home/wander/ISO/OL9-Offline-Completa.iso"
ISO_STAGING="/tmp/opencode/ol9bootfix.iso"
WORK_DIR="/tmp/opencode/rebuild"
SRC_MNT="/mnt/iso_ol9fix"
VOLUME_ID="OL9_OFFLINE_OPENBOX"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] OK:${NC} $1"; }
fatal(){ echo -e "${RED}[$(date +%H:%M:%S)] ERRO:${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && fatal "Execute como root: sudo bash $0"
for cmd in xorriso mcopy implantisomd5 mount umount; do
    command -v "$cmd" &>/dev/null || fatal "Dependência '$cmd' não encontrada."
done
[[ -f "$ISO_ORIGEM" ]] || fatal "ISO não encontrada: $ISO_ORIGEM"
[[ -f /usr/share/syslinux/isohdpfx.bin ]] || fatal "Falta /usr/share/syslinux/isohdpfx.bin"

log "========================================="
log "  FIX BOOT OL9 OFFLINE (UEFI + MBR)"
log "========================================="

log "ETAPA 1/6: Montando ISO fonte em $SRC_MNT..."
mkdir -p "$SRC_MNT"
mountpoint -q "$SRC_MNT" && umount "$SRC_MNT" 2>/dev/null || true
mount -o loop,ro "$ISO_ORIGEM" "$SRC_MNT"
ok "ISO fonte montada"

log "ETAPA 2/6: Copiando estrutura (incluindo dotfiles)..."
rm -rf "$WORK_DIR"; mkdir -p "$WORK_DIR"
cp -a "$SRC_MNT"/. "$WORK_DIR/"
ok "Estrutura copiada ($(du -sh "$WORK_DIR" | cut -f1))"

log "ETAPA 3/6: Aplicando correções de boot..."

# ---- isolinux.cfg (MBR / BIOS) ----
cat > "$WORK_DIR/isolinux/isolinux.cfg" << 'ISOLINUXEOF'
default vesamenu.c32
timeout 150

display boot.msg

menu clear
menu background splash.png
menu title Oracle Linux 9.8.0 (Offline - Openbox)
menu vshift 8
menu rows 18
menu margin 8
menu helpmsgrow 15
menu tabmsgrow 13

menu color border * #00000000 #00000000 none
menu color sel 0 #ffffffff #00000000 none
menu color title 0 #ff7ba3d0 #00000000 none
menu color tabmsg 0 #ff3a6496 #00000000 none
menu color unsel 0 #84b8ffff #00000000 none
menu color hotsel 0 #84b8ffff #00000000 none
menu color hotkey 0 #ffffffff #00000000 none
menu color help 0 #ffffffff #00000000 none
menu color scrollbar 0 #ffffffff #ff355594 none
menu color timeout 0 #ffffffff #00000000 none
menu color timeout_msg 0 #ffffffff #00000000 none
menu color cmdmark 0 #84b8ffff #00000000 none
menu color cmdline 0 #ffffffff #00000000 none

menu tabmsg Press Tab for full configuration options on menu items.

menu separator # insert an empty line
menu separator # insert an empty line

label linux
  menu label ^Install Oracle Linux 9.8.0
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img console=ttyS0,115200n8 console=tty0 quiet

label check
  menu label Test this ^media & install Oracle Linux 9.8.0
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img rd.live.check console=ttyS0,115200n8 console=tty0 quiet

label fips
  menu label ^Install Oracle Linux 9.8.0 in FIPS mode
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img console=ttyS0,115200n8 console=tty0 quiet fips=1

menu separator # insert an empty line

menu begin ^Troubleshooting
  menu title Troubleshooting

label text
  menu indent count 5
  menu label Install Oracle Linux 9.8.0 using ^text mode
  text help
	Try this option out if you're having trouble installing
	Oracle Linux 9.8.0.
  endtext
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.text console=ttyS0,115200n8 console=tty0 quiet

label rescue
  menu indent count 5
  menu label ^Rescue an Oracle Linux system
  text help
	If the system will not boot, this lets you access files
	and edit config files to try to get it booting again.
  endtext
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.rescue console=ttyS0,115200n8 console=tty0 quiet

label memtest
  menu label Run a ^memory test
  text help
	If your system is having issues, a problem with your
	system's memory may be the cause. Use this utility to
	see if the memory is working correctly.
  endtext
  kernel memtest

menu separator # insert an empty line

label local
  menu label Boot from ^local drive
  localboot 0xffff

menu separator # insert an empty line
menu separator # insert an empty line

label returntomain
  menu label Return to ^main menu
  menu exit

menu end

label kickstart
  menu label ^Instalar com Kickstart (auto, Openbox)
  menu default
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.ks=hd:LABEL=OL9_OFFLINE_OPENBOX:/ks.cfg console=ttyS0,115200n8 console=tty0 quiet
ISOLINUXEOF
ok "isolinux.cfg corrigido"

# ---- isolinux/grub.conf (BIOS legacy, alguns firmwares) ----
cat > "$WORK_DIR/isolinux/grub.conf" << 'GRUBCONFEOF'
default=0
timeout 15
hiddenmenu
title Instalar com Kickstart (auto, Openbox)
	findiso
	kernel @KERNELPATH@ @ROOT@ inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.ks=hd:LABEL=OL9_OFFLINE_OPENBOX:/ks.cfg console=ttyS0,115200n8 console=tty0 quiet
	initrd @INITRDPATH@
title Install Oracle Linux 9.8.0
	findiso
	kernel @KERNELPATH@ @ROOT@ inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img console=ttyS0,115200n8 console=tty0 quiet
	initrd @INITRDPATH@
title Test this media & install Oracle Linux 9.8.0
	findiso
	kernel @KERNELPATH@ @ROOT@ inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img rd.live.check console=ttyS0,115200n8 console=tty0 quiet
	initrd @INITRDPATH@
GRUBCONFEOF
ok "isolinux/grub.conf corrigido"

# ---- EFI/BOOT/grub.cfg (UEFI) ----
cat > "$WORK_DIR/EFI/BOOT/grub.cfg" << 'GRUBEOF'
set default="4"
set timeout=15

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l 'OL9_OFFLINE_OPENBOX'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Install Oracle Linux 9.8.0' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img console=ttyS0,115200n8 console=tty0 quiet
	initrdefi /images/pxeboot/initrd.img
}
menuentry 'Test this media & install Oracle Linux 9.8.0' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img rd.live.check console=ttyS0,115200n8 console=tty0 quiet
	initrdefi /images/pxeboot/initrd.img
}
menuentry 'Install Oracle Linux 9.8.0 in FIPS mode' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img console=ttyS0,115200n8 console=tty0 quiet fips=1
	initrdefi /images/pxeboot/initrd.img
}
submenu 'Troubleshooting -->' {
	menuentry 'Install Oracle Linux 9.8.0 in text mode' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.text console=ttyS0,115200n8 console=tty0 quiet
		initrdefi /images/pxeboot/initrd.img
	}
	menuentry 'Rescue an Oracle Linux system' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.rescue console=ttyS0,115200n8 console=tty0 quiet
		initrdefi /images/pxeboot/initrd.img
	}
}

menuentry 'Instalar com Kickstart (auto, Openbox)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=OL9_OFFLINE_OPENBOX:/images/install.img inst.ks=hd:LABEL=OL9_OFFLINE_OPENBOX:/ks.cfg console=ttyS0,115200n8 console=tty0 quiet
    initrdefi /images/pxeboot/initrd.img
}
GRUBEOF
ok "EFI/BOOT/grub.cfg corrigido"

# ---- efiboot.img (imagem FAT interna do UEFI) ----
mcopy -o -i "$WORK_DIR/images/efiboot.img" "$WORK_DIR/EFI/BOOT/grub.cfg" ::/EFI/BOOT/grub.cfg
ok "efiboot.img/grub.cfg atualizado"

# ---- ks.cfg (bootloader auto-detect UEFI/MBR) ----
sed -i 's/^bootloader --location=mbr --driveorder=sda/bootloader --driveorder=sda/' "$WORK_DIR/ks.cfg"
ok "ks.cfg: bootloader corrigido (auto-detect UEFI/MBR)"

# ---- .discinfo (arquivo oculto, exigido pela anaconda) ----
EPOCH=$(date +%s)
printf '%s.%s\nOracle Linux 9.8.0\nx86_64\n' "$EPOCH" "000000" > "$WORK_DIR/.discinfo"
ok ".discinfo criado"

log "ETAPA 4/6: Gerando nova ISO com xorriso..."
umount "$SRC_MNT"
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "$VOLUME_ID" \
    -output "$ISO_STAGING" \
    -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/boot.cat \
    -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    "$WORK_DIR"
ok "ISO gerada: $ISO_STAGING"

log "ETAPA 5/6: Embutindo checksum ISO (isomd5sum)..."
implantisomd5 --force "$ISO_STAGING"
ok "Checksum embutido"

log "ETAPA 6/6: Verificação final..."
isoinfo -d -i "$ISO_STAGING" | grep -E 'Volume id|El Torito' | head -5
checkisomd5 "$ISO_STAGING" 2>&1 || true
fdisk -l "$ISO_STAGING" 2>&1 | grep -E 'iso|EFI'

log "  -- Defaults de boot na ISO gerada --"
isoinfo -R -x /ISOLINUX/ISOLINUX.CFG -i "$ISO_STAGING" 2>/dev/null | grep -E '^\s*menu default|label kickstart|inst.ks=' || true
isoinfo -R -x /EFI/BOOT/GRUB.CFG -i "$ISO_STAGING" 2>/dev/null | grep -E 'set default|Instalar com Kickstart' || true
isoinfo -R -x /.DISCINFO -i "$ISO_STAGING" 2>/dev/null || echo "  [ERRO] .discinfo ausente na ISO!"
isoinfo -R -x /KS.CFG -i "$ISO_STAGING" 2>/dev/null | grep -E 'bootloader' || true

echo ""
log "========================================="
log "  ISO CORRIGIDA: $ISO_STAGING"
log "  Tamanho: $(du -h "$ISO_STAGING" | cut -f1)"
log "  Default: Kickstart auto (UEFI e MBR)"
log "  Para substituir a original:"
log "    cp $ISO_STAGING $ISO_ORIGEM"
log "========================================="
