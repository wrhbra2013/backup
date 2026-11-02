#!/usr/bin/env bash
# =============================================================================
# setup-performance.sh
# -----------------------------------------------------------------------------
# Reproduz as alteracoes de memoria/desempenho/boot aplicadas no Oracle Linux 9.8
# (UEK 6.12). IDEMPOTENTE: pode rodar varias vezes sem efeito colateral.
#
# Uso:
#   sudo ./setup-performance.sh
#
# Etapas aplicadas:
#   1) /etc/sysctl.d/99-performance.conf      vm.swappiness=15 e vm.vfs_cache_pressure=50
#   2) /etc/systemd/system/zram-swap.service  swap zram (SEM "Before=swap.target",
#                                             que causava ciclo de ordenacao no systemd)
#   3) kdump desabilitado + crashkernel removido (libera ~448 MiB no reboot)
#   4) sysstat instalado e com coleta ativa   (historico sar/rpm de desempenho)
#   5) NetworkManager wifi.powersave=2        (power-save do Wi-Fi desligado)
#   6) Video Intel i915                       remove "rhgb" (mantem "quiet") e aplica
#                                             i915.enable_psr=0 i915.enable_fbc=0
#   7) GRUB timeout                           GRUB_TIMEOUT=1 / TIMEOUT_STYLE=menu
#   8) Console serial ttyS0                   menu do GRUB + console=ttyS0 no kernel
#                                             + getty de login (DO_SERIAL=no p/ pular)
#   9) NVRAM EFI                              remove entradas mortas (rEFInd/rede/
#                                             genericas) e deixa Oracle Linux + fallback
#  10) backlight intel_backlight              regra udev + valor salvo (painel aceso)
#  11) journald persistente (opcional)        logs sobrevivem a reboot  PERSIST_JOURNALD=yes
#  12) fsck                                   checagem no proximo boot (DO_FSCK=auto|yes|no)
#  13) kernels antigos                        remove versoes antigas mantendo KEEP_KERNELS
#                                             por flavor (DO_KERNELS=yes|no)
# =============================================================================
#
# Variaveis de ambiente (yes/no) para PULAR etapas:
#   DO_VIDEO=no            pula a etapa 6
#   DO_GRUB_TIMEOUT=no     pula a etapa 7
#   DO_SERIAL=no           pula a etapa 8 (console serial)
#   DO_EFI=no              pula a etapa 9
#   DO_BACKLIGHT=no        pula a etapa 10
#   PERSIST_JOURNALD=yes   ativa a etapa 11 (padrao: no)
#   DO_FSCK=yes|auto|no    etapa 12 (padrao: auto = so agenda se algum fs estiver sujo)
#   DO_KERNELS=no          pula a etapa 13 (limpeza de kernels antigos)
#   KEEP_KERNELS=2         quantos kernels manter por flavor (minimo 2, padrao: 2)
#   INSTALL_SYSSTAT=no     pula a instalacao do sysstat
#   ZRAM_SIZE=2G           tamanho do zram (padrao: 1G)
#   SERIAL_PORT=ttyS0      porta serial da etapa 8 (padrao: ttyS0)
#   SERIAL_SPEED=115200    velocidade da serial da etapa 8 (padrao: 115200)
#
# Exemplo:
#   sudo DO_EFI=no ./setup-performance.sh
# =============================================================================
set -euo pipefail

# ---- pre-requisitos ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERRO: execute com sudo:  sudo $0" >&2
  exit 1
fi

# ---- opcoes ----------------------------------------------------------------
ZRAM_SIZE="${ZRAM_SIZE:-1G}"
DO_VIDEO="${DO_VIDEO:-yes}"
DO_GRUB_TIMEOUT="${DO_GRUB_TIMEOUT:-yes}"
DO_SERIAL="${DO_SERIAL:-yes}"
SERIAL_PORT="${SERIAL_PORT:-ttyS0}"
SERIAL_SPEED="${SERIAL_SPEED:-115200}"
DO_EFI="${DO_EFI:-yes}"
DO_BACKLIGHT="${DO_BACKLIGHT:-yes}"
DO_FSCK="${DO_FSCK:-auto}"
DO_KERNELS="${DO_KERNELS:-yes}"
KEEP_KERNELS="${KEEP_KERNELS:-2}"
PERSIST_JOURNALD="${PERSIST_JOURNALD:-no}"
INSTALL_SYSSTAT="${INSTALL_SYSSTAT:-yes}"

SYSCTL_FILE=/etc/sysctl.d/99-performance.conf
ZRAM_UNIT=/etc/systemd/system/zram-swap.service
SYSSTAT_CFG=/etc/sysconfig/sysstat
GRUB_FILE=/etc/default/grub
KCMD=/etc/kernel/cmdline
TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo ">>> setup-performance.sh iniciado em $TS (zram=${ZRAM_SIZE})"

# helper: aplica uma lista de args numa linha GRUB_CMDLINE_LINUX="..."
grub_cmdline_set() {
  # uso: grub_cmdline_set "remover=rhgb|quiet" "adicionar=i915.foo=1"
  local cur new tok want remove_list add_list
  # NAO removemos "quiet" (decisao do usuario): apenas "rhgb" e removido.
  remove_list="rhgb"
  add_list="i915.enable_psr=0 i915.enable_fbc=0"
  cur="$(sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"/\1/p' "$GRUB_FILE" 2>/dev/null || true)"
  new=""
  for tok in $cur; do
    case " $remove_list " in *" $tok "*) continue ;; esac
    new="${new:+$new }$tok"
  done
  for want in $add_list; do
    case " $new " in *" $want "*) ;; *) new="${new:+$new }$want" ;; esac
  done
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$new\"|" "$GRUB_FILE"
}

# helper: adiciona tokens (idempotente) em GRUB_CMDLINE_LINUX, preservando o resto
grub_cmdline_add() {
  local cur new want
  cur="$(sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"/\1/p' "$GRUB_FILE" 2>/dev/null || true)"
  new="$cur"
  for want in "$@"; do
    case " $new " in *" $want "*) ;; *) new="${new:+$new }$want" ;; esac
  done
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$new\"|" "$GRUB_FILE"
}

# helper: adiciona tokens (idempotente) em /etc/kernel/cmdline (kernels futuros)
kcmdline_add() {
  local f="$KCMD" cur new want
  [ -f "$f" ] || return 0
  cur="$(tr '\n' ' ' < "$f")"
  new="$cur"
  for want in "$@"; do
    case " $new " in *" $want "*) ;; *) new="${new:+$new }$want" ;; esac
  done
  printf '%s\n' "$(printf '%s' "$new" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')" > "$f"
}

# helper: garante dono root, permissao 0644 e contexto SELinux correto do arquivo
fixfile() {
  local f="$1"
  [ -e "$f" ] || return 0
  chown root:root "$f" 2>/dev/null || true
  chmod 0644 "$f" 2>/dev/null || true
  if command -v restorecon >/dev/null 2>&1; then
    restorecon -F "$f" >/dev/null 2>&1 || true
  fi
}

# =============================================================================
# 1) sysctl de memoria ---------------------------------------------------------
# =============================================================================
echo
echo "== [1/13] sysctl -> $SYSCTL_FILE"
cat > "$SYSCTL_FILE" <<'EOF'
# Tuning de memória (setup-performance.sh)
# swappiness < 30  -> menos uso de swap; mantém páginas anônimas na RAM
# vfs_cache_pressure < 100 -> mantém mais page cache de inodes/dentries
vm.swappiness=15
vm.vfs_cache_pressure=50
EOF
fixfile "$SYSCTL_FILE"
sysctl --system >/dev/null 2>&1 || true
echo "   ativo: vm.swappiness=$(sysctl -n vm.swappiness) | vm.vfs_cache_pressure=$(sysctl -n vm.vfs_cache_pressure)"

# =============================================================================
# 2) zram swap (corrigido: sem Before=swap.target -> evita ciclo de ordenacao) -
# =============================================================================
echo
echo "== [2/13] zram-swap -> $ZRAM_UNIT (${ZRAM_SIZE}, prioridade 200)"
cat > "$ZRAM_UNIT" <<EOF
[Unit]
Description=ZRAM swap (${ZRAM_SIZE}, prioridade 200)
After=local-fs.target
Documentation=man:zramctl(8)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/modprobe zram
ExecStartPre=-/bin/sh -c 'if [ -e /sys/block/zram0 ] && [ "\$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)" != "0" ]; then /sbin/modprobe -r zram&&/sbin/modprobe zram; fi'
ExecStartPre=/bin/sh -c 'echo ${ZRAM_SIZE} > /sys/block/zram0/disksize'
ExecStart=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon -p 200 /dev/zram0
ExecStop=/sbin/swapoff /dev/zram0
ExecStopPost=-/sbin/modprobe -r zram

[Install]
WantedBy=multi-user.target
EOF
fixfile "$ZRAM_UNIT"
systemctl daemon-reload
systemctl enable zram-swap.service >/dev/null 2>&1 || true
systemctl restart zram-swap.service
echo "   estado: $(systemctl is-active zram-swap.service)"
echo "   swap ativo:"
swapon --show | sed 's/^/      /'

# =============================================================================
# 3) kdump desabilitado + crashkernel removido (libera RAM no proximo boot) ----
# =============================================================================
echo
echo "== [3/13] kdump / crashkernel"
if systemctl is-enabled kdump 2>/dev/null | grep -q enabled; then
  systemctl disable --now kdump || true
  echo "   kdump desabilitado (reserva crashkernel só libera ~448 MiB após REBOOT)"
else
  echo "   kdump já desabilitado"
fi

[ -f "$GRUB_FILE" ] && cp -a "$GRUB_FILE" "${GRUB_FILE}.bak.$(date +%F)" 2>/dev/null || true
[ -f "$KCMD" ]     && cp -a "$KCMD"     "${KCMD}.bak.$(date +%F)"     2>/dev/null || true
sed -ri 's/([[:space:]]|")crashkernel=[^"[:space:]]+/\1/' "$GRUB_FILE"
[ -f "$KCMD" ] && sed -ri 's/crashkernel=[^[:space:]]+//' "$KCMD" || true

if command -v grubby >/dev/null 2>&1; then
  grubby --update-kernel=ALL --remove-args=crashkernel 2>&1 | sed 's/^/   grubby: /' || true
else
  command -v grub2-mkconfig >/dev/null 2>&1 && grub2-mkconfig -o /boot/grub2/grub.cfg || true
fi
echo "   GRUB_CMDLINE_LINUX: $(grep -o 'GRUB_CMDLINE_LINUX=.*' "$GRUB_FILE" 2>/dev/null || echo n/a)"
if grep -qs crashkernel /boot/loader/entries/*.conf 2>/dev/null; then
  echo "   AVISO: ainda há crashkernel em /boot/loader/entries — confira pós-reboot"
else
  echo "   ok: nenhum entry BLS com crashkernel"
fi

# =============================================================================
# 4) sysstat (historico de desempenho) ----------------------------------------
# =============================================================================
echo
echo "== [4/13] sysstat"
if [ "${INSTALL_SYSSTAT}" = "yes" ] && ! rpm -q sysstat >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install sysstat 2>&1 | tail -3
  else
    yum -y install sysstat 2>&1 | tail -3
  fi
else
  echo "   sysstat já instalado ou pulado"
fi
if [ -f "$SYSSTAT_CFG" ]; then
  sed -i 's/^ENABLED=.*/ENABLED="true"/' "$SYSSTAT_CFG" 2>/dev/null || true
  grep -q '^ENABLED=' "$SYSSTAT_CFG" || echo 'ENABLED="true"' >> "$SYSSTAT_CFG"
fi
systemctl enable --now sysstat.service       >/dev/null 2>&1 || true
systemctl enable --now sysstat-collect.timer 2>/dev/null || true
systemctl enable --now sysstat-summary.timer 2>/dev/null || true
echo "   timers: $(systemctl is-active sysstat-collect.timer 2>/dev/null || true)"

# =============================================================================
# 5) Wi-Fi power-save desligado (latencia/rede) -------------------------------
# =============================================================================
echo
echo "== [5/13] NetworkManager wifi.powersave=2"
NM=/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
if [ -d /etc/NetworkManager/conf.d ]; then
  cat > "$NM" <<'EOF'
[connection]
wifi.powersave = 2
EOF
  fixfile "$NM"
  systemctl reload NetworkManager 2>/dev/null || true
  echo "   $NM gravado"
else
  echo "   NetworkManager ausente — etapa ignorada"
fi

# =============================================================================
# 6) Video Intel i915 (remove "rhgb"; "quiet" e mantido) -----------------------
# =============================================================================
echo
echo "== [6/13] video i915 + remover 'rhgb' (mantem 'quiet')"
if [ "${DO_VIDEO}" = "yes" ]; then
  if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --remove-args="rhgb" 2>&1 | sed 's/^/   grubby: /' || true
    grubby --update-kernel=ALL --args="i915.enable_psr=0 i915.enable_fbc=0" 2>&1 | sed 's/^/   grubby: /' || true
  fi
  grub_cmdline_set
  echo "   GRUB_CMDLINE_LINUX: $(grep -o 'GRUB_CMDLINE_LINUX=.*' "$GRUB_FILE" 2>/dev/null || echo n/a)"
  echo "   kernel padrao: $(grubby --default-kernel 2>/dev/null || echo n/a)"
else
  echo "   pulado (DO_VIDEO=no)"
fi

# =============================================================================
# 7) GRUB timeout curto -------------------------------------------------------
# =============================================================================
echo
echo "== [7/13] GRUB timeout=1"
if [ "${DO_GRUB_TIMEOUT}" = "yes" ] && [ -f "$GRUB_FILE" ]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_FILE"
  if grep -q '^GRUB_TIMEOUT_STYLE=' "$GRUB_FILE"; then
    sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$GRUB_FILE"
  else
    echo 'GRUB_TIMEOUT_STYLE=menu' >> "$GRUB_FILE"
  fi
  command -v grub2-mkconfig >/dev/null 2>&1 && grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
  echo "   $(grep -E '^GRUB_TIMEOUT(_STYLE)?=' "$GRUB_FILE" | tr '\n' ' ')"
else
  echo "   pulado (DO_GRUB_TIMEOUT=no)"
fi

# =============================================================================
# 8) console serial ttyS0 (menu GRUB + kernel console + getty de login) --------
# =============================================================================
echo
echo "== [8/13] console serial ${SERIAL_PORT} (${SERIAL_SPEED} 8N1)"
if [ "${DO_SERIAL}" = "yes" ]; then
  SERIAL_CONSOLE_ARGS="console=tty0 console=${SERIAL_PORT},${SERIAL_SPEED}n8"

  # 8a) saida do menu do GRUB na serial, mantendo o console de video
  if [ -f "$GRUB_FILE" ]; then
    if grep -q '^GRUB_TERMINAL=' "$GRUB_FILE"; then
      sed -i 's|^GRUB_TERMINAL=.*|GRUB_TERMINAL="console serial"|' "$GRUB_FILE"
    else
      # GRUB_TERMINAL tem prioridade; comenta GRUB_TERMINAL_OUTPUT p/ evitar conflito
      sed -i 's|^GRUB_TERMINAL_OUTPUT=.*|# &|' "$GRUB_FILE"
      echo 'GRUB_TERMINAL="console serial"' >> "$GRUB_FILE"
    fi
    if grep -q '^GRUB_SERIAL_COMMAND=' "$GRUB_FILE"; then
      sed -i "s|^GRUB_SERIAL_COMMAND=.*|GRUB_SERIAL_COMMAND=\"serial --speed=${SERIAL_SPEED} --unit=0 --word=8 --parity=no --stop=1\"|" "$GRUB_FILE"
    else
      echo "GRUB_SERIAL_COMMAND=\"serial --speed=${SERIAL_SPEED} --unit=0 --word=8 --parity=no --stop=1\"" >> "$GRUB_FILE"
    fi
  fi

  # 8b) parametros do kernel: BLS (kernel atual) + /etc/kernel/cmdline (futuros)
  if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --args="$SERIAL_CONSOLE_ARGS" 2>&1 | sed 's/^/   grubby: /' || true
  fi
  kcmdline_add $SERIAL_CONSOLE_ARGS
  grub_cmdline_add $SERIAL_CONSOLE_ARGS

  # 8c) regenera o grub.cfg para aplicar GRUB_TERMINAL/GRUB_SERIAL_COMMAND no menu
  if command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
  fi

  # 8d) getty de login na serial (login ja disponivel sem reboot)
  systemctl enable --now "serial-getty@${SERIAL_PORT}.service" >/dev/null 2>&1 || true

  echo "   menu GRUB ..... $(grep -E '^GRUB_TERMINAL=' "$GRUB_FILE" 2>/dev/null || echo n/a)"
  echo "   serial cmd .... $(grep -E '^GRUB_SERIAL_COMMAND=' "$GRUB_FILE" 2>/dev/null || echo n/a)"
  echo "   kernel console  $(grep -ho 'console=[^ ]*' /boot/loader/entries/*.conf 2>/dev/null | sort -u | tr '\n' ' ')"
  echo "   getty ......... $(systemctl is-enabled "serial-getty@${SERIAL_PORT}.service" 2>/dev/null || echo n/a) / $(systemctl is-active "serial-getty@${SERIAL_PORT}.service" 2>/dev/null || echo n/a)"
  echo "   (reboot necessario para o menu e o console do kernel valerem)"
else
  echo "   pulado (DO_SERIAL=no)"
fi

# =============================================================================
# 9) NVRAM EFI: remover entradas mortas (rEFInd/rede/genericas) ---------------
# =============================================================================
echo
echo "== [9/13] limpeza NVRAM EFI"
if [ "${DO_EFI}" = "yes" ] && command -v efibootmgr >/dev/null 2>&1; then
  keep="$(efibootmgr 2>/dev/null | awk '/^BootCurrent:/{print $2}')"
  [ -n "$keep" ] || keep="$(efibootmgr -v 2>/dev/null | awk '/SHIMX64.EFI/{print $1}' | sed 's/Boot//; s/\*//' | head -1)"
  echo "   mantendo BootCurrent=$keep"
  while read -r num rest; do
    clean="${num#Boot}"; clean="${clean%\*}"
    [ "$clean" = "$keep" ] && continue
    case "$rest" in
      *rEFInd*|*"EFI Shell"*|*IP4*|*IP6*|*PXE*|*VenHw*)
        echo "   removendo $num ($rest)"
        efibootmgr -b "$clean" -B >/dev/null 2>&1 || true
        ;;
    esac
  done < <(efibootmgr -v 2>/dev/null | grep -E '^Boot[0-9A-Fa-f]{4}')

  order="$keep"
  for b in $(efibootmgr 2>/dev/null | awk '/^Boot[0-9A-Fa-f]{4}\*/{print $1}' | sed 's/Boot//; s/\*//'); do
    [ "$b" = "$keep" ] && continue
    order="${order:+$order,}$b"
  done
  [ -n "$order" ] && efibootmgr -o "$order" >/dev/null 2>&1 || true
  efibootmgr -t 1 >/dev/null 2>&1 || true
  echo "   depois:"
  efibootmgr 2>/dev/null | grep -E "BootCurrent|Timeout|BootOrder|^Boot" | sed 's/^/      /'
else
  echo "   pulado (DO_EFI=no ou efibootmgr ausente)"
fi

# =============================================================================
# 10) backlight intel_backlight (painel aceso desde o inicio do boot) ---------
# =============================================================================
echo
echo "== [10/13] backlight intel_backlight"
BL_DIR=/sys/class/backlight/intel_backlight
BL_RULE=/etc/udev/rules.d/99-backlight-brightness.rules
if [ "${DO_BACKLIGHT}" = "yes" ] && [ -d "$BL_DIR" ]; then
  bl_max="$(cat "$BL_DIR/max_brightness" 2>/dev/null || echo 0)"
  if [ "${bl_max:-0}" -gt 0 ] 2>/dev/null; then
    bl_val=$(( bl_max * 77 / 100 ))
    cat > "$BL_RULE" <<EOF
# Forca o brilho do painel logo que o dispositivo de backlight aparece (setup-performance.sh).
# Valor atual: ${bl_val}/${bl_max} (~77%). Ajuste conforme necessario.
ACTION=="add", SUBSYSTEM=="backlight", KERNEL=="intel_backlight", ATTR{brightness}="${bl_val}"
EOF
    fixfile "$BL_RULE"
    udevadm control --reload-rules 2>/dev/null || true
    echo "$bl_val" > "$BL_DIR/brightness" 2>/dev/null || true
    /usr/lib/systemd/systemd-backlight save backlight:intel_backlight 2>/dev/null || true
    echo "   brilho fixado em ${bl_val}/${bl_max} + $BL_RULE"
  else
    echo "   max_brightness indisponivel — etapa ignorada"
  fi
else
  echo "   pulado (DO_BACKLIGHT=no ou interface ausente)"
fi

# =============================================================================
# 11) journald persistente (opcional) -----------------------------------------
# =============================================================================
echo
echo "== [11/13] journald"
JOURNAL_DIR=/var/log/journal
if [ "${PERSIST_JOURNALD}" = "yes" ]; then
  mkdir -p "$JOURNAL_DIR"
  chown root:systemd-journal "$JOURNAL_DIR" 2>/dev/null || true
  chmod 2755 "$JOURNAL_DIR" 2>/dev/null || true
  command -v restorecon >/dev/null 2>&1 && restorecon -RF "$JOURNAL_DIR" >/dev/null 2>&1 || true
  systemctl restart systemd-journald 2>/dev/null || true
  echo "   journald persistente ativado em $JOURNAL_DIR"
else
  echo "   pulado (PERSIST_JOURNALD=no) — logs ficam só em /run (perdem no reboot)"
fi

# =============================================================================
# 12) fsck (auto|yes|no) — checagem no proximo boot --------------------------
# =============================================================================
# DO_FSCK=auto (padrao): só agenda se algum ext4 estiver sujo
# DO_FSCK=yes           : agenda checagem completa no proximo boot
# DO_FSCK=no            : não faz nada (só relatório de estado)
echo
echo "== [12/13] fsck (modo: ${DO_FSCK})"
FSCK_DEVS="$(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2=="ext4"{print "/dev/"$1}')"
need_fsck=no
for dev in $FSCK_DEVS; do
  st="$(dumpe2fs -h "$dev" 2>/dev/null | awk '/Filesystem state/{print $NF}' || true)"
  echo "   $dev: ${st:-n/a}"
  [ "${st:-}" != "clean" ] && need_fsck=yes
done
if [ "${DO_FSCK}" = "no" ]; then
  echo "   pulado (DO_FSCK=no)"
elif [ "${DO_FSCK}" = "yes" ] || [ "$need_fsck" = "yes" ]; then
  if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --args="fsck.mode=force fsck.repair=yes" 2>&1 | sed 's/^/   grubby: /' || true
  fi
  echo "   AGENDADO: fsck.mode=force fsck.repair=yes no proximo boot."
  echo "   (pode demorar no HDD; remova depois com:)" 
  echo "     sudo grubby --update-kernel=ALL --remove-args=\"fsck.mode=force fsck.repair=yes\""
else
  echo "   nada a fazer: filesystems limpos (use DO_FSCK=yes para forçar)"
fi

# =============================================================================
# 13) kernels antigos: manter KEEP_KERNELS por flavor --------------------------
# =============================================================================
# Remove versoes antigas com "dnf remove --oldinstallonly", que faz a transacao
# correta dos pacotes DIVIDIDOS (kernel, kernel-core, kernel-modules,
# kernel-modules-core) e do equivalente -uek. O kernel EM USO e o kernel PADRAO
# sao protegidos via --exclude. O dnf exige installonly_limit >= 2 (minimo 2).
echo
echo "== [13/13] kernels antigos (manter ${KEEP_KERNELS} por flavor)"
if [ "${DO_KERNELS}" = "yes" ]; then
  # dnf aceita no minimo 2; sanear entrada
  case "${KEEP_KERNELS}" in ''|*[!0-9]*) KEEP_KERNELS=2 ;; esac
  if [ "${KEEP_KERNELS}" -lt 2 ]; then KEEP_KERNELS=2; fi

  # release sem arquitetura (ex.: "6.12.0-206.104.4.4.el9uek")
  running_rel="$(uname -r)"; running_rel="${running_rel%.*}"
  default_rel=""
  if command -v grubby >/dev/null 2>&1; then
    default_rel="$(grubby --default-kernel 2>/dev/null | sed 's#.*/vmlinuz-##; s#\.[^.]*$##')"
  fi

  # protege em uso + padrao (glob cobre todos os subpacotes do mesmo flavor)
  excludes=(--exclude="kernel*-${running_rel}*")
  if [ -n "$default_rel" ] && [ "$default_rel" != "$running_rel" ]; then
    excludes+=(--exclude="kernel*-${default_rel}*")
  fi

  echo "   em uso ..... $(uname -r)"
  [ -n "$default_rel" ] && echo "   padrao ..... ${default_rel}"
  echo "   protegido .. ${excludes[*]}"
  echo "   antes ...... $(rpm -q --qf '%{VERSION}-%{RELEASE} ' kernel kernel-uek 2>/dev/null || echo n/a)"

  # dry-run antes de agir (locale C -> saida estavel para o parse)
  plan="$(LC_ALL=C dnf --assumeno remove --oldinstallonly \
            --setopt=installonly_limit="${KEEP_KERNELS}" "${excludes[@]}" 2>&1 || true)"
  if printf '%s\n' "$plan" | grep -q 'Nothing to do'; then
    echo "   nada a remover (ja dentro do limite de ${KEEP_KERNELS})"
  elif printf '%s\n' "$plan" | grep -q '^Removing:'; then
    printf '%s\n' "$plan" | sed -n '/^Removing:/,/^$/p' | sed 's/^/   /'
    dnf -y remove --oldinstallonly --setopt=installonly_limit="${KEEP_KERNELS}" \
        "${excludes[@]}" 2>&1 | sed 's/^/   /' || true
    echo "   depois ..... $(rpm -q --qf '%{VERSION}-%{RELEASE} ' kernel kernel-uek 2>/dev/null || echo n/a)"
  else
    echo "   dry-run inconclusivo; nenhuma alteracao feita."
    printf '%s\n' "$plan" | sed 's/^/      /' | head -n 5
  fi
else
  echo "   pulado (DO_KERNELS=no)"
fi

# =============================================================================
# resumo -----------------------------------------------------------------------
# =============================================================================
echo
echo "=================================================================="
echo " RESUMO (${ZRAM_SIZE}):"
echo "   sysctl memória ....... $(sysctl -n vm.swappiness 2>/dev/null)/15 e $(sysctl -n vm.vfs_cache_pressure 2>/dev/null)/50"
echo "   zram ................. $(swapon --show | awk '$1=="/dev/zram0"{print $2,$3,$4; f=1} END{if(!f)print "NÃO ATIVO!"}')"
echo "   kdump ................ $(systemctl is-enabled kdump 2>/dev/null || true)"
echo "   sar/sysstat .......... $(command -v sar >/dev/null 2>&1 && echo 'instalado' || echo 'ausente') | coleta: $(systemctl is-active sysstat-collect.timer 2>/dev/null || true)"
echo "   video i915 ........... $(grep -o 'i915.enable_psr=0' "$GRUB_FILE" >/dev/null 2>&1 && echo 'parametros aplicados' || echo 'n/a')"
echo "   GRUB timeout ......... $(grep -oE 'GRUB_TIMEOUT=[0-9]+' "$GRUB_FILE" 2>/dev/null || echo n/a)"
echo "   serial console ....... $(systemctl is-enabled "serial-getty@${SERIAL_PORT}.service" >/dev/null 2>&1 && echo "getty@${SERIAL_PORT} ok" || echo 'n/a') | $(grep -ho "console=${SERIAL_PORT}[^ ]*" /boot/loader/entries/*.conf 2>/dev/null | sort -u | tr '\n' ' ')"
echo "   EFI .................. $(efibootmgr 2>/dev/null | awk '/^BootOrder:/{print $2}' || echo n/a)"
echo "   backlight ............ $(cat "$BL_DIR/brightness" 2>/dev/null || echo n/a)/$(cat "$BL_DIR/max_brightness" 2>/dev/null || echo n/a)"
echo "   journald ............. $([ -d /var/log/journal ] && echo 'persistente' || echo 'volátil (/run)')"
echo "   fsck ................. $(grep -qs 'fsck.mode=force' /boot/loader/entries/*.conf 2>/dev/null && echo 'agendado p/ próximo boot' || echo 'não agendado')"
echo "   kernels .............. $(rpm -q --qf '%{VERSION}-%{RELEASE} ' kernel kernel-uek 2>/dev/null | sed 's/ *$//' || echo n/a)"
echo "   REBOOT pendente? ..... crashkernel removido do boot irá liberar ~448 MiB de RAM"
echo "=================================================================="
exit 0
