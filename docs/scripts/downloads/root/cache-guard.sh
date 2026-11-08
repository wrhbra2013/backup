#!/usr/bin/env bash
# =============================================================================
# cache-guard.sh — Proteção de memória e liberação AUTOMÁTICA de cache
# -----------------------------------------------------------------------------
# Alvo: Oracle Linux 9.8 / UEK 6.12 / systemd 252 / cgroup v2 / 2 CPUs / 3.3 GB
#
# Objetivo: impedir que UMA aplicação (navegador, editor, llama.cpp, opencode)
# bloqueie o desempenho do sistema inteiro por pressão de memória.
#
# Estratégia em 4 camadas:
#   1) Limites por cgroup no app.slice   -> o kernel faz reclaim automático de
#                                            cache e estrangula o app (MemoryHigh)
#                                            antes de derrubar o sistema.
#   2) Watchdog nativo (este script)     -> sob pressão, libera cache via
#                                            memory.reclaim do cgroup culpado e,
#                                            em último caso, encerra SÓ esse app.
#   3) PSI + systemd-oomd (root)         -> rede de segurança do kernel/sistema.
#   4) Helpers: run (roda app com teto), reclaim (liberação manual), status.
#
# Uso:
#   ./cache-guard.sh user-install     limites (1) + watchdog (2) — SEM sudo
#   ./cache-guard.sh user-uninstall
#   ./cache-guard.sh system-install   PSI + systemd-oomd (3) — COM sudo + reboot
#   ./cache-guard.sh system-uninstall
#   ./cache-guard.sh install          user-install + system-install (sudo)
#   ./cache-guard.sh status           diagnóstico do estado atual
#   ./cache-guard.sh reclaim [bytes]  libera cache AGORA do maior app (padrão 256M)
#   ./cache-guard.sh run <cmd> [...]  roda um app dentro de um scope com teto
#   ./cache-guard.sh watch            uma passada do watchdog (usado pelo timer)
#   ./cache-guard.sh work-setup       slice dedicado p/ Edge+Codium+opencode (tetos por app)
#   ./cache-guard.sh work-status      situação dos tetos do work.slice
#   ./cache-guard.sh work-uninstall   remove slice + atalhos + override do watchdog
#   ./cache-guard.sh help
#
# Variáveis (ajustáveis por env):
#   GUARD_APP_HIGH=50%       MemoryHigh do app.slice (limite SUAVE = reclaim auto)
#   GUARD_APP_MAX=80%        MemoryMax do app.slice (limite DURO = último recurso)
#   GUARD_APP_SWAP_MAX=1G    MemorySwapMax do app.slice (teto de swap dos apps)
#   GUARD_LOW_MB=300         abaixo disso o watchdog começa a agir
#   GUARD_CRIT_MB=120        abaixo disso o watchdog pode encerrar o app pior
#   GUARD_RECLAIM_MB=256     quanto de cache liberar por passada
#   GUARD_KILL=yes|no        permite encerrar o app culpado em caso crítico
#   GUARD_PSI_LIMIT=25       pressão de memória (PSI avg10 %) para agir
#   GUARD_OOMD_SWAP_LIMIT=50%  SwapUsedLimit do systemd-oomd (padrão: 50% do swap)
#   GUARD_WORK_MEM_HIGH=1.3G  MemoryHigh coletivo do work.slice (trio pesado)
#   GUARD_WORK_MEM_MAX=1.9G   MemoryMax coletivo do work.slice
#   GUARD_WORK_SWAP_MAX=1G    MemorySwapMax do work.slice
#   GUARD_WORK_APPS=...       tabela "funcao|binario|High|Max" (1 por linha)
# =============================================================================

set -uo pipefail

# ---- config -----------------------------------------------------------------
GUARD_APP_HIGH="${GUARD_APP_HIGH:-50%}"
GUARD_APP_MAX="${GUARD_APP_MAX:-80%}"
GUARD_APP_SWAP_MAX="${GUARD_APP_SWAP_MAX:-1G}"
GUARD_LOW_MB="${GUARD_LOW_MB:-300}"
GUARD_CRIT_MB="${GUARD_CRIT_MB:-120}"
GUARD_RECLAIM_MB="${GUARD_RECLAIM_MB:-256}"
GUARD_KILL="${GUARD_KILL:-yes}"
GUARD_KILL_MIN_MB="${GUARD_KILL_MIN_MB:-80}"     # só encerra app com anon >= isso
GUARD_KILL_COOLDOWN="${GUARD_KILL_COOLDOWN:-60}" # segundos entre encerramentos
GUARD_PSI_LIMIT="${GUARD_PSI_LIMIT:-25}"
# SwapUsedLimit do systemd-oomd: % do swap total a partir do qual o oomd age.
# Valor baixo (50%) evita thrash no swap de disco (4,9G) nesta maquina.
GUARD_OOMD_SWAP_LIMIT="${GUARD_OOMD_SWAP_LIMIT:-50%}"

# ---- work.slice: trio pesado (Edge + VSCodium + opencode) ------------------
GUARD_WORK_SLICE="${GUARD_WORK_SLICE:-work.slice}"
GUARD_WORK_MEM_HIGH="${GUARD_WORK_MEM_HIGH:-1.3G}"
GUARD_WORK_MEM_MAX="${GUARD_WORK_MEM_MAX:-1.9G}"
GUARD_WORK_SWAP_MAX="${GUARD_WORK_SWAP_MAX:-1G}"
# formato por linha: <funcao>|<binario>|<MemoryHigh>|<MemoryMax>
GUARD_WORK_APPS="${GUARD_WORK_APPS:-edge|microsoft-edge|450M|700M
codium|codium|450M|700M
opencode|opencode|700M|1G}"

# Nunca encerrar: shell/desktop/sessão e componentes do próprio sistema.
GUARD_PROTECT="${GUARD_PROTECT:-gnome-shell|Xorg|gnome-session|session-manager|gdm|dbus|systemd|pipewire|wireplumber|xdg-desktop-portal|gvfs|evolution|gsd-|goa-|cache-guard|spawn-|dwarfs|tracker|ibus}"

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/cache-guard.state"

SELF="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF")"

USER_UNIT_DIR="$HOME/.config/systemd/user"
APP_SLICE_DROPIN="$USER_UNIT_DIR/app.slice.d/50-cache-guard.conf"
WATCH_SERVICE="$USER_UNIT_DIR/cache-guard-watch.service"
WATCH_TIMER="$USER_UNIT_DIR/cache-guard-watch.timer"

OOMD_CFG_DIR=/etc/systemd/oomd.conf.d
OOMD_CFG="$OOMD_CFG_DIR/50-cache-guard.conf"
OOMD_USER_DROPIN=/etc/systemd/system/user@.service.d/50-cache-guard-oomd.conf
GRUB_FILE=/etc/default/grub
KCMD=/etc/kernel/cmdline

# ---- helpers ----------------------------------------------------------------
say()  { printf '\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mAVISO: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }
log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; logger -t cache-guard -p daemon.notice -- "$*" 2>/dev/null || true; }

need_root() { [ "$(id -u)" -eq 0 ] || die "execute com sudo:  sudo $0 ${1:-}"; }
asroot()    { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
has()       { command -v "$1" >/dev/null 2>&1; }

meminfo() { awk -v k="$1:" '$1==k{print $2}' /proc/meminfo; }
mb()      { echo $(( ${1:-0} / 1024 )); }
unit_active()  { systemctl is-active  --quiet "$1" 2>/dev/null && echo active   || echo inactive; }
unit_active_u(){ systemctl --user is-active  --quiet "$1" 2>/dev/null && echo active   || echo inactive; }
unit_state()   { local s; s="$(systemctl is-enabled "$1" 2>/dev/null)"; echo "${s:-n/a}"; }
unit_state_u() { local s; s="$(systemctl --user is-enabled "$1" 2>/dev/null)"; echo "${s:-n/a}"; }

# raiz do cgroup do usuário atual
user_cg() { printf '/sys/fs/cgroup/user.slice/user-%s.slice/user@%s.service' "$(id -u)" "$(id -u)"; }

psi_mem_avg10() {
  [ -r /proc/pressure/memory ] || return 0
  sed -n 's/^some .*avg10=\([0-9.]*\).*/\1/p' /proc/pressure/memory
}

# cgroup de app com maior valor da chave (file|anon|slab) dentro do app.slice
biggest_app_cgroup() {
  local key="$1" base worst_val=0 worst="" d val
  base="$(user_cg)/app.slice"
  [ -d "$base" ] || return 0
  shopt -s nullglob
  for d in "$base"/*/; do
    [ -r "$d/memory.stat" ] || continue
    val=$(awk -v k="$key" '$1==k{print $2}' "$d/memory.stat" 2>/dev/null)
    [ -n "${val:-}" ] || continue
    if [ "$val" -gt "$worst_val" ]; then worst_val="$val"; worst="${d%/}"; fi
  done
  shopt -u nullglob
  [ -n "$worst" ] && printf '%s' "$worst"
}

# nome de unit do systemd usa \xNN para escapar (ex.: app-gnome\x2dsession\x2dmanager)
unescape_name() { printf '%s' "$1" | sed -e 's/\\x2d/-/g' -e 's/\\x2e/./g' -e 's/\\x20/ /g'; }

# cgroup de app que pode ser encerrado (maior anon, respeitando a proteção)
biggest_killable_cgroup() {
  local base worst_val=0 worst="" d val name name_d min_kb
  min_kb=$(( GUARD_KILL_MIN_MB * 1024 ))
  base="$(user_cg)/app.slice"
  [ -d "$base" ] || return 0
  shopt -s nullglob
  for d in "$base"/*/; do
    [ -r "$d/memory.stat" ] || continue
    name="$(basename "$d")"
    name_d="$(unescape_name "$name")"
    printf '%s' "$name_d" | grep -qiE "$GUARD_PROTECT" && continue
    val=$(awk -v k="anon" '$1==k{print $2}' "$d/memory.stat" 2>/dev/null)
    [ -n "${val:-}" ] || continue
    # só considera candidato se tiver memória anônima relevante (evita matar app pequeno)
    [ "$val" -lt "$min_kb" ] && continue
    if [ "$val" -gt "$worst_val" ]; then worst_val="$val"; worst="${d%/}"; fi
  done
  shopt -u nullglob
  [ -n "$worst" ] && printf '%s' "$worst"
}

# encerra todos os processos de um cgroup (preferindo cgroup.kill do kernel)
kill_cgroup() {
  local cg="$1" p
  if [ -w "$cg/cgroup.kill" ]; then
    echo 1 > "$cg/cgroup.kill" 2>/dev/null && return 0
  fi
  for p in $(cat "$cg/cgroup.procs" 2>/dev/null); do kill -TERM "$p" 2>/dev/null || true; done
  sleep 2
  for p in $(cat "$cg/cgroup.procs" 2>/dev/null); do kill -KILL "$p" 2>/dev/null || true; done
}

# =============================================================================
# CAMADA 2 — watchdog: libera cache sob pressão (usado pelo timer do usuário)
# =============================================================================
cmd_watch() {
  local avail_kb low_kb crit_kb psi pressured=no worst bytes
  low_kb=$(( GUARD_LOW_MB * 1024 ))
  crit_kb=$(( GUARD_CRIT_MB * 1024 ))
  avail_kb=$(meminfo MemAvailable)
  psi="$(psi_mem_avg10)"

  # ---- guarda-corpo: NUNCA agir com leitura inválida de memória -------------
  case "${avail_kb:-}" in
    ''|*[!0-9]*) log "MemAvailable inválido ('${avail_kb:-}'); abortando por segurança"; return 0 ;;
  esac
  [ "$avail_kb" -gt 0 ] || { log "MemAvailable=0 (leitura suspeita); abortando por segurança"; return 0; }

  if [ -n "$psi" ] && awk -v p="$psi" -v l="$GUARD_PSI_LIMIT" 'BEGIN{exit !(p>l)}'; then
    pressured=yes
  fi

  # Sem pressão e com RAM suficiente: nada a fazer (silencioso).
  if [ "$avail_kb" -ge "$low_kb" ] && [ "$pressured" = no ]; then
    return 0
  fi

  log "pressão: MemAvailable=$(mb "$avail_kb")MB psi=${psi:-n/a} -> liberando cache"

  worst="$(biggest_app_cgroup file)"
  if [ -n "$worst" ]; then
    bytes="${GUARD_RECLAIM_MB}M"
    if echo "$bytes" > "$worst/memory.reclaim" 2>/dev/null; then
      log "reclaim $bytes de $(basename "$worst")"
    fi
  fi

  avail_kb=$(meminfo MemAvailable)
  case "${avail_kb:-}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$avail_kb" -ge "$crit_kb" ] && return 0
  [ "$GUARD_KILL" = yes ] || return 0

  # ---- cooldown: não encerra mais de um app a cada N segundos --------------
  local now last=0
  now=$(date +%s)
  if [ -f "$STATE_FILE" ]; then
    read -r last _ < "$STATE_FILE" 2>/dev/null || last=0
    case "${last:-0}" in ''|*[!0-9]*) last=0 ;; esac
  fi
  if [ $(( now - last )) -lt "$GUARD_KILL_COOLDOWN" ]; then
    log "crítico, mas em cooldown (última ação há $(( now - last ))s)"
    return 0
  fi

  # Ainda crítico: encerra SÓ o app culpado (maior memória anônima).
  worst="$(biggest_killable_cgroup)"
  if [ -n "$worst" ]; then
    log "CRÍTICO: encerrando $(basename "$worst") (MemAvailable=$(mb "$avail_kb")MB)"
    kill_cgroup "$worst"
    printf '%s %s\n' "$now" "$(basename "$worst")" > "$STATE_FILE" 2>/dev/null || true
  fi
  return 0
}

# =============================================================================
# CAMADA 1 — limites per-app (app.slice) + timer do watchdog  [SEM sudo]
# =============================================================================
install_watch_timer() {
  mkdir -p "$USER_UNIT_DIR"
  cat > "$WATCH_SERVICE" <<EOF
[Unit]
Description=cache-guard — watchdog de memória (liberação automática de cache)

[Service]
Type=oneshot
ExecStart=$SELF watch
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=6
EOF

  cat > "$WATCH_TIMER" <<EOF
[Unit]
Description=cache-guard — watchdog de memória (timer)

[Timer]
OnBootSec=2min
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now cache-guard-watch.timer >/dev/null 2>&1 || true
}

cmd_user_install() {
  say "Camada 1 — limites do app.slice (sem sudo)"
  mkdir -p "$USER_UNIT_DIR/app.slice.d"
  cat > "$APP_SLICE_DROPIN" <<EOF
# cache-guard.sh — teto coletivo de memória para os apps do usuário.
# MemoryHigh: limite SUAVE -> o kernel libera cache do app e o estrangula
#             antes de comprometer o sistema. É o "reclaim automático".
# MemoryMax : limite DURO -> último recurso (OOM só dentro do app.slice).
# MemorySwapMax: impede que os apps entupam o zram/swap (evita thrashing).
[Slice]
MemoryHigh=$GUARD_APP_HIGH
MemoryMax=$GUARD_APP_MAX
MemorySwapMax=$GUARD_APP_SWAP_MAX
EOF
  systemctl --user daemon-reload
  # aplica já em runtime (sem reiniciar sessão)
  if systemctl --user set-property app.slice \
        MemoryHigh="$GUARD_APP_HIGH" \
        MemoryMax="$GUARD_APP_MAX" \
        MemorySwapMax="$GUARD_APP_SWAP_MAX" 2>/dev/null; then
    ok "app.slice: MemoryHigh=$GUARD_APP_HIGH MemoryMax=$GUARD_APP_MAX MemorySwapMax=$GUARD_APP_SWAP_MAX"
  else
    warn "não foi possível aplicar em runtime; valerá na próxima sessão"
  fi

  say "Camada 2 — watchdog do usuário (sem sudo)"
  install_watch_timer
  ok "timer: $(systemctl --user is-enabled cache-guard-watch.timer 2>/dev/null || echo '?')/$(systemctl --user is-active cache-guard-watch.timer 2>/dev/null || echo '?')"

  echo
  ok "Pronto (parte do usuário). Para a camada 3 (sistema):  sudo $SELF system-install"
}

cmd_user_uninstall() {
  say "Removendo limites e watchdog do usuário"
  systemctl --user disable --now cache-guard-watch.timer >/dev/null 2>&1 || true
  rm -f "$WATCH_SERVICE" "$WATCH_TIMER" "$APP_SLICE_DROPIN"
  rmdir "$USER_UNIT_DIR/app.slice.d" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user set-property app.slice MemoryHigh=infinity MemoryMax=infinity MemorySwapMax=infinity 2>/dev/null || true
  ok "removido"
}

# =============================================================================
# CAMADA 3 — PSI + systemd-oomd  [sudo + reboot]
# =============================================================================
grub_add_arg() {
  local arg="$1" cur new
  # /etc/default/grub
  if [ -f "$GRUB_FILE" ]; then
    cur="$(sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"/\1/p' "$GRUB_FILE")"
    case " $cur " in *" $arg "*) : ;; *)
      new="${cur:+$cur }$arg"
      cp -a "$GRUB_FILE" "${GRUB_FILE}.bak.cache-guard" 2>/dev/null || true
      sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$new\"|" "$GRUB_FILE" ;;
    esac
  fi
  # /etc/kernel/cmdline (kernels futuros)
  if [ -f "$KCMD" ]; then
    cur="$(tr '\n' ' ' < "$KCMD")"
    case " $cur " in *" $arg "*) : ;; *)
      cp -a "$KCMD" "${KCMD}.bak.cache-guard" 2>/dev/null || true
      printf '%s\n' "$(printf '%s %s' "$cur" "$arg" | tr -s ' ' | sed 's/^ //; s/ $//')" > "$KCMD" ;;
    esac
  fi
  # BLS (kernel atual)
  if has grubby; then
    grubby --update-kernel=ALL --args="$arg" >/dev/null 2>&1 || true
  fi
}

cmd_system_install() {
  need_root system-install
  say "Camada 3a — habilitando PSI na cmdline do kernel (psi=1)"
  if grep -q 'psi=1' /proc/cmdline; then
    ok "psi=1 já ativo"
  else
    grub_add_arg psi=1
    ok "psi=1 adicionado (efetivo após REBOOT; hoje /proc/pressure não existe)"
  fi

  say "Camada 3b — instalando systemd-oomd"
  if rpm -q systemd-oomd >/dev/null 2>&1; then
    ok "systemd-oomd já instalado"
  elif has dnf; then
    dnf -y install systemd-oomd 2>&1 | tail -3
  else
    yum -y install systemd-oomd 2>&1 | tail -3
  fi

  say "Camada 3c — limiares do oomd"
  mkdir -p "$OOMD_CFG_DIR"
  cat > "$OOMD_CFG" <<EOF
# cache-guard.sh — limiares do systemd-oomd
# SwapUsedLimit: com zram de 1G + swap de disco, não deixar o swap passar de 50%
#                (evita thrash no disco lento antes de o PSI agir).
# DefaultMemoryPressureLimit/DurationSec: mata o cgroup mais problemático
# quando a pressão de memória (PSI) fica alta por tempo sustentado.
[OOM]
SwapUsedLimit=$GUARD_OOMD_SWAP_LIMIT
DefaultMemoryPressureLimit=55%
DefaultMemoryPressureDurationSec=20s
EOF
  ok "$OOMD_CFG"

  say "Camada 3d — oomd monitora o user@.service (protege o desktop)"
  mkdir -p "$(dirname "$OOMD_USER_DROPIN")"
  cat > "$OOMD_USER_DROPIN" <<EOF
# cache-guard.sh — deixa o systemd-oomd agir sobre a sessão do usuário
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=50%
ManagedOOMSwap=kill
EOF
  ok "$OOMD_USER_DROPIN"

  systemctl daemon-reload
  systemctl enable systemd-oomd.service >/dev/null 2>&1 || true
  if systemctl start systemd-oomd.service 2>/dev/null; then
    ok "systemd-oomd ativo"
  else
    warn "systemd-oomd habilitado, mas só ativa após REBOOT (precisa do psi=1)"
  fi
  echo
  ok "Parte do sistema pronta. Reinicie e confira:  oomctl ; cat /proc/pressure/memory"
}

cmd_system_uninstall() {
  need_root system-uninstall
  say "Revertendo camada 3 (sistema)"
  rm -f "$OOMD_CFG" "$OOMD_USER_DROPIN"
  systemctl disable --now systemd-oomd.service >/dev/null 2>&1 || true
  if has grubby; then
    grubby --update-kernel=ALL --remove-args="psi=1" >/dev/null 2>&1 || true
  fi
  [ -f "$GRUB_FILE" ] && sed -i 's/[[:space:]]\?psi=1//g' "$GRUB_FILE"
  [ -f "$KCMD" ] && sed -i 's/[[:space:]]\?psi=1//g' "$KCMD"
  systemctl daemon-reload
  ok "removido (psi=1 sai no próximo reboot)"
}

# =============================================================================
# Helpers: reclaim / run / status
# =============================================================================
cmd_reclaim() {
  local bytes="${1:-${GUARD_RECLAIM_MB}M}" worst
  worst="$(biggest_app_cgroup file)"
  [ -n "$worst" ] || die "nenhum cgroup de app encontrado em $(user_cg)/app.slice"
  if echo "$bytes" > "$worst/memory.reclaim" 2>/dev/null; then
    ok "reclaim $bytes de $(basename "$worst")"
  else
    die "falha ao reclamar de $worst"
  fi
}

cmd_run() {
  [ $# -gt 0 ] || die "uso: $0 run <comando> [args...]"
  exec systemd-run --user --scope --collect --quiet \
    -p MemoryHigh="$GUARD_APP_HIGH" \
    -p MemoryMax="$GUARD_APP_MAX" \
    -p MemorySwapMax="$GUARD_APP_SWAP_MAX" \
    -p ManagedOOMMemoryPressure=kill \
    -- "$@"
}

cmd_status() {
  local avail total psi high max swapmax
  total=$(meminfo MemTotal); avail=$(meminfo MemAvailable)
  say "cache-guard — status"
  printf '   RAM ............. %sMiB total / %sMiB disponível\n' "$(mb "$total")" "$(mb "$avail")"
  printf '   Swap usado ...... %s\n' "$(free -h | awk '/Swap/{print $3" / "$2}')"
  psi="$(psi_mem_avg10)"
  if [ -n "$psi" ]; then
    printf '   PSI memória ..... avg10=%s%%\n' "$psi"
  else
    printf '   PSI memória ..... INDISPONÍVEL (sem psi=1 no kernel)\n'
  fi
  printf '   systemd-oomd .... %s / %s\n' \
    "$(unit_state systemd-oomd.service)" \
    "$(unit_active systemd-oomd.service)"
  high=$(systemctl --user show app.slice -p MemoryHigh --value 2>/dev/null || echo n/a)
  max=$(systemctl --user show app.slice -p MemoryMax --value 2>/dev/null || echo n/a)
  swapmax=$(systemctl --user show app.slice -p MemorySwapMax --value 2>/dev/null || echo n/a)
  printf '   app.slice ....... MemoryHigh=%s MemoryMax=%s MemorySwapMax=%s\n' "$high" "$max" "$swapmax"
  printf '   watchdog ........ %s / %s\n' \
    "$(unit_state_u cache-guard-watch.timer)" \
    "$(unit_active_u cache-guard-watch.timer)"
  echo "   maiores apps (memory.current):"
  local base d c n
  base="$(user_cg)/app.slice"; shopt -s nullglob
  for d in "$base"/*/; do
    c=$(cat "$d/memory.current" 2>/dev/null || echo 0)
    n=$(basename "${d%/}")
    printf '     %10s  %s\n' "$(numfmt --to=iec "$c" 2>/dev/null || echo "$c")" "$n"
  done | sort -rh | head -8
  shopt -u nullglob
}

# =============================================================================
# work.slice — slice dedicado + tetos por app (Edge + VSCodium + opencode)
# =============================================================================
work_aliases_text() {
  cat <<'EOF'
# >>> cache-guard work.slice (auto) — NÃO edite entre as marcas
# Abre Edge, VSCodium e opencode dentro dos tetos do work.slice.
# Recrie com:  ./scripts/cache-guard.sh work-setup
EOF
  local fn bin high max
  while IFS='|' read -r fn bin high max; do
    [ -n "$fn" ] || continue
    printf 'function %s() { local b; b="$(type -P %s)" || b=""; [ -n "$b" ] || { echo "%s: binario %s nao encontrado" >&2; return 1; }; systemd-run --user --scope --collect --quiet --slice=%s -p MemoryHigh=%s -p MemoryMax=%s -- "$b" "$@"; }\n' \
      "$fn" "$bin" "$fn" "$bin" "$GUARD_WORK_SLICE" "$high" "$max"
  done <<< "$GUARD_WORK_APPS"
  printf '%s\n' "# <<< cache-guard work.slice (auto)"
}

# remove apenas o bloco marcado do ~/.bashrc (mantém o resto intacto)
strip_work_aliases() {
  local rc="$HOME/.bashrc" tmp
  [ -f "$rc" ] || return 0
  tmp="$(mktemp)"
  awk '
    /^# >>> cache-guard work.slice \(auto\)$/ { skip=1; next }
    /^# <<< cache-guard work.slice \(auto\)$/ { skip=0; next }
    !skip { print }
  ' "$rc" > "$tmp" && mv "$tmp" "$rc"
}

install_work_aliases() {
  local rc="$HOME/.bashrc"
  strip_work_aliases
  if [ ! -f "$rc" ]; then
    printf '# ~/.bashrc\n[ -f /etc/bashrc ] && . /etc/bashrc\n' > "$rc"
  fi
  work_aliases_text >> "$rc"
  ok "atalhos 'edge', 'codium' e 'opencode' em $rc (rode: source ~/.bashrc)"
}

cmd_work_setup() {
  say "work.slice — slice dedicado p/ os tres pesados (Edge + Codium + opencode)"
  mkdir -p "$USER_UNIT_DIR"
  cat > "$USER_UNIT_DIR/$GUARD_WORK_SLICE" <<EOF
# cache-guard.sh (work-setup) — orcamento coletivo dos tres pesados
[Slice]
MemoryHigh=$GUARD_WORK_MEM_HIGH
MemoryMax=$GUARD_WORK_MEM_MAX
MemorySwapMax=$GUARD_WORK_SWAP_MAX
EOF
  systemctl --user daemon-reload
  systemctl --user start "$GUARD_WORK_SLICE" 2>/dev/null || true
  ok "$GUARD_WORK_SLICE: high=$GUARD_WORK_MEM_HIGH max=$GUARD_WORK_MEM_MAX swap=$GUARD_WORK_SWAP_MAX"

  # watchdog: libera cache mas NAO encerra apps (os limites agora sao os tetos)
  mkdir -p "$WATCH_SERVICE.d"
  cat > "$WATCH_SERVICE.d/override.conf" <<'EOF'
[Service]
Environment=GUARD_KILL=no
EOF
  systemctl --user daemon-reload
  ok "watchdog: GUARD_KILL=no (libera cache, mas nao encerra apps)"
  install_work_aliases
  echo "   Abra com:  edge / codium / opencode"
}

cmd_work_uninstall() {
  say "Removendo work.slice + atalhos + override do watchdog"
  systemctl --user stop "$GUARD_WORK_SLICE" 2>/dev/null || true
  rm -f "$USER_UNIT_DIR/$GUARD_WORK_SLICE"
  rm -rf "$WATCH_SERVICE.d"
  systemctl --user daemon-reload
  strip_work_aliases
  ok "removido (apps ja abertos continuam; novos voltam ao app.slice padrao)"
}

cmd_work_status() {
  local base d cur sum=0
  base="$(user_cg)/$GUARD_WORK_SLICE"
  say "work.slice — orcamento dos tres pesados"
  printf '   slice ......... %s (ativo: %s)\n' "$GUARD_WORK_SLICE" "$(unit_active_u "$GUARD_WORK_SLICE")"
  printf '   tetos ......... high=%s max=%s swap=%s\n' "$GUARD_WORK_MEM_HIGH" "$GUARD_WORK_MEM_MAX" "$GUARD_WORK_SWAP_MAX"
  local fn bin high max
  echo "   por app (configurado no cache-guard.sh):"
  while IFS='|' read -r fn bin high max; do
    [ -n "$fn" ] || continue
    printf '     %-9s  High=%-5s Max=%-5s  (%s)\n' "$fn" "$high" "$max" "$bin"
  done <<< "$GUARD_WORK_APPS"
  echo "   uso real por scope dentro do slice:"
  if [ -d "$base" ]; then
    shopt -s nullglob
    for d in "$base"/*/; do
      cur=$(cat "$d/memory.current" 2>/dev/null || echo 0)
      sum=$(( sum + cur ))
      printf '     %10s  %s\n' "$(numfmt --to=iec "$cur" 2>/dev/null || echo "$cur")" "$(basename "${d%/}")"
    done
    shopt -u nullglob
    printf '   total em uso: %s  (coletivo max %s)\n' "$(numfmt --to=iec "$sum" 2>/dev/null || echo "$sum")" "$GUARD_WORK_MEM_MAX"
  else
    echo "   (slice vazio/inativo — abra um app com edge / codium / opencode)"
  fi
}

# =============================================================================
# dispatch
# =============================================================================
usage() { sed -n '2,59p' "$SELF" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  user-install)    cmd_user_install ;;
  user-uninstall)  cmd_user_uninstall ;;
  system-install)  cmd_system_install ;;
  system-uninstall) cmd_system_uninstall ;;
  install)         cmd_user_install; cmd_system_install ;;
  status)          cmd_status ;;
  reclaim)         shift; cmd_reclaim "$@" ;;
  run)             shift; cmd_run "$@" ;;
  watch)           cmd_watch ;;
  work-setup)      cmd_work_setup ;;
  work-status)     cmd_work_status ;;
  work-uninstall)  cmd_work_uninstall ;;
  ""|-h|--help|help) usage ;;
  *) die "comando desconhecido: $1 (use: $0 help)" ;;
esac
