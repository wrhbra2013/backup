#!/usr/bin/env bash
# =============================================================================
# llm.sh — IA local OFFLINE (llama.cpp) para Oracle Linux 9.8
# -----------------------------------------------------------------------------
# Hardware alvo: Intel Celeron N2808 (2 nucleos, SEM AVX), 3.3 GB RAM.
# Por isso usamos llama.cpp compilado nativo (funciona sem AVX) e modelos
# pequenos quantizados (Q4). NAO use Ollama aqui: ele costuma exigir AVX e
# trava com "Illegal instruction" nesta CPU.
#
# Uso (rode como usuario NORMAL, NAO como root — usa sudo so p/ instalar pacotes):
#   ./llm.sh install          # dependencias + compila + baixa modelos leves
#   ./llm.sh doctor           # diagnostico do hardware/ambiente
#   ./llm.sh list             # lista modelos do catalogo e o que ja foi baixado
#   ./llm.sh pull <alias>     # baixa um modelo do catalogo
#   ./llm.sh run  <alias> [-p "prompt"] [outras flags do llama-cli]
#   ./llm.sh chat <alias>     # conversa interativa (modo -cnv)
#   ./llm.sh serve <alias> [--port 8080]   # servidor com API OpenAI
#   ./llm.sh bench <alias>    # mede tokens/s nesta maquina
#   ./llm.sh update           # git pull + recompila
#   ./llm.sh paths            # mostra onde esta cada coisa
#
# Variaveis:
#   LLM_HOME   (padrao: $HOME/llama.cpp)   onde compilar
#   MODELS_DIR (padrao: $HOME/models)      onde ficam os .gguf
#   THREADS    (padrao: nproc)             threads de inferencia
#   CTX        (padrao: 2048)              tamanho de contexto
#   JOBS       (padrao: nproc)             paralelismo da compilacao
#
# Instalado automaticamente tambem um atalho em ~/.local/bin/llm (se existir).
# =============================================================================
set -euo pipefail

# ---- config -----------------------------------------------------------------
LLM_HOME="${LLM_HOME:-$HOME/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
LLAMA_BIN="$LLM_HOME/build/bin"
THREADS="${THREADS:-$(nproc 2>/dev/null || echo 2)}"
CTX="${CTX:-2048}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
SELF="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF")"

# catalogo: alias|repo_huggingface|arquivo.gguf|tamanho_aprox_GB
CATALOG="qwen0.5b|Qwen/Qwen2.5-0.5B-Instruct-GGUF|qwen2.5-0.5b-instruct-q4_k_m.gguf|0.4
llama1b|bartowski/Llama-3.2-1B-Instruct-GGUF|Llama-3.2-1B-Instruct-Q4_K_M.gguf|0.8
qwen1.5b|Qwen/Qwen2.5-1.5B-Instruct-GGUF|qwen2.5-1.5b-instruct-q4_k_m.gguf|1.0
smollm2|HuggingFaceTB/SmolLM2-360M-Instruct-GGUF|smollm2-360m-instruct-q8_0.gguf|0.4
phi4mini|unsloth/Phi-4-mini-instruct-GGUF|Phi-4-mini-instruct-Q4_K_M.gguf|2.4
phi3mini|microsoft/Phi-3-mini-4k-instruct-gguf|Phi-3-mini-4k-instruct-q4.gguf|2.2"
DEFAULT_MODELS="qwen0.5b llama1b qwen1.5b"

# ---- helpers ----------------------------------------------------------------
say()  { printf '\033[1;36m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mAVISO: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

# executa como root: direto se ja root, senao via sudo
asroot() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

catalog_line() {
  printf '%s\n' "$CATALOG" | awk -F'|' -v a="$1" '$1==a{print; f=1} END{exit(f?0:1)}'
}
model_file() { catalog_line "$1" | cut -d'|' -f3; }
model_repo() { catalog_line "$1" | cut -d'|' -f2; }
model_size() { catalog_line "$1" | cut -d'|' -f4; }
model_path() { printf '%s/%s' "$MODELS_DIR" "$(model_file "$1")"; }

# resolve o binario do llama.cpp (nomes mudam entre versoes)
llama_exe() {
  local name="$1"
  if [ -x "$LLAMA_BIN/$name" ]; then printf '%s' "$LLAMA_BIN/$name"; return; fi
  case "$name" in
    llama-cli) [ -x "$LLAMA_BIN/main" ] && { printf '%s' "$LLAMA_BIN/main"; return; } ;;
  esac
  printf ''   # nao encontrado
}

require_built() {
  if [ -z "$(llama_exe llama-cli)" ]; then
    die "llama.cpp ainda nao compilado. Rode:  $0 install"
  fi
}

# ---- subcomandos ------------------------------------------------------------

cmd_deps() {
  say "Instalando dependencias de build (cmake, gcc-c++, make, git)"
  asroot dnf install -y cmake gcc gcc-c++ make git
  say "Dependencias OK"
}

cmd_build() {
  say "Compilando llama.cpp em $LLM_HOME (nativo, sem AVX)"
  mkdir -p "$(dirname "$LLM_HOME")"
  if [ -d "$LLM_HOME/.git" ]; then
    git -C "$LLM_HOME" pull --ff-only || warn "git pull falhou; usando codigo atual"
  else
    git clone --depth 1 https://github.com/ggerganov/llama.cpp "$LLM_HOME"
  fi
  cmake -S "$LLM_HOME" -B "$LLM_HOME/build" \
        -DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF
  cmake --build "$LLM_HOME/build" -j"$JOBS" \
        --target llama-cli llama-server llama-bench
  say "Build concluido: $(llama_exe llama-cli || echo '??')"
}

cmd_pull() {
  local alias="${1:?uso: $0 pull <alias>}"
  catalog_line "$alias" >/dev/null || die "alias desconhecido: $alias (veja: $0 list)"
  local repo file dest url
  repo="$(model_repo "$alias")"; file="$(model_file "$alias")"; dest="$MODELS_DIR/$file"
  mkdir -p "$MODELS_DIR"
  if [ -s "$dest" ]; then
    say "Ja existe: $dest ($(du -h "$dest" | cut -f1))"
    return 0
  fi
  url="https://huggingface.co/$repo/resolve/main/$file?download=true"
  say "Baixando $alias -> $dest"
  wget -c -O "$dest.part" "$url"
  mv -f "$dest.part" "$dest"
  say "Pronto: $(du -h "$dest" | cut -f1)  ($dest)"
}

cmd_install() {
  cmd_deps
  cmd_build
  local m
  for m in $DEFAULT_MODELS; do cmd_pull "$m"; done
  # atalho conveniente
  if [ -d "$HOME/.local/bin" ] && [ -w "$HOME/.local/bin" ]; then
    ln -sf "$SELF" "$HOME/.local/bin/llm"
    say "Atalho criado: ~/.local/bin/llm"
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
      warn "~/.local/bin nao esta no PATH — adicione: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
  fi
  cmd_doctor
  say "TUDO PRONTO. Teste:  $0 run qwen0.5b -p \"Ola!\""
}

cmd_list() {
  printf '%-10s %-8s %-10s %s\n' "ALIAS" "TAM." "STATUS" "REPO"
  local line a s
  while IFS='|' read -r a repo file s; do
    [ -n "$a" ] || continue
    local st="nao baixado"
    [ -s "$MODELS_DIR/$file" ] && st="OK ($(du -h "$MODELS_DIR/$file" | cut -f1))"
    printf '%-10s %-8s %-10s %s\n' "$a" "~${s}G" "$st" "$repo"
  done <<< "$CATALOG"
}

check_ram() {
  local alias="$1" f="" need_kb avail_kb
  f="$(model_path "$alias")"
  [ -s "$f" ] || return 0
  need_kb=$(( $(stat -c %s "$f" 2>/dev/null || echo 0) / 1024 ))
  avail_kb=$(( $(awk '/MemAvailable/{print $2}' /proc/meminfo) ))
  if [ "$need_kb" -gt "$avail_kb" ]; then
    warn "modelo ~$((need_kb/1024))MB > RAM disponivel ~$((avail_kb/1024))MB — vai usar swap e ficar LENTO."
    warn "se travar, use um modelo menor (qwen0.5b) ou reduza o contexto: CTX=1024 $0 run $alias"
  fi
}

cmd_run() {
  local alias="${1:?uso: $0 run <alias> [flags]}"; shift || true
  require_built
  local f; f="$(model_path "$alias")"
  catalog_line "$alias" >/dev/null || die "alias desconhecido: $alias (veja: $0 list)"
  [ -s "$f" ] || die "modelo nao baixado. Rode:  $0 pull $alias"
  check_ram "$alias"
  exec "$(llama_exe llama-cli)" -m "$f" -t "$THREADS" -c "$CTX" "$@"
}

cmd_chat() { cmd_run "$@"; }   # interativo quando sem -p: o llama-cli entra em modo conversa

cmd_serve() {
  local alias="${1:?uso: $0 serve <alias> [--port 8080]}"; shift || true
  require_built
  local f port=8080; f="$(model_path "$alias")"
  catalog_line "$alias" >/dev/null || die "alias desconhecido: $alias (veja: $0 list)"
  [ -s "$f" ] || die "modelo nao baixado. Rode:  $0 pull $alias"
  check_ram "$alias"
  local exe; exe="$(llama_exe llama-server)"
  [ -n "$exe" ] || die "llama-server nao encontrado no build"
  say "API em http://127.0.0.1:$port  (modelo: $alias, ctx=$CTX, threads=$THREADS)"
  exec "$exe" -m "$f" -t "$THREADS" -c "$CTX" --host 127.0.0.1 --port "$port" "$@"
}

cmd_bench() {
  local alias="${1:?uso: $0 bench <alias>}"
  require_built
  local f; f="$(model_path "$alias")"
  [ -s "$f" ] || die "modelo nao baixado. Rode:  $0 pull $alias"
  local exe; exe="$(llama_exe llama-bench)"
  [ -n "$exe" ] || exe="$(llama_exe llama-cli)"
  exec "$exe" -m "$f" -t "$THREADS" -p 64 -n 32 -r 1
}

cmd_update() { cmd_build; }

cmd_paths() {
  cat <<EOF
LLM_HOME   : $LLM_HOME
MODELS_DIR : $MODELS_DIR
llama-cli  : $(llama_exe llama-cli || echo '(nao compilado)')
llama-server: $(llama_exe llama-server || echo '(nao compilado)')
threads    : $THREADS
ctx        : $CTX
EOF
}

cmd_doctor() {
  say "Diagnostico"
  echo "CPU        : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
  echo "Nucleos    : $(nproc)"
  echo "Flags CPU  : $(grep -m1 flags /proc/cpuinfo | grep -oE 'avx2|avx|sse4_2|f16c|fma' | tr '\n' ' ' || echo '(sem AVX)')"
  echo "RAM        : $(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f GB total, %.1f GB disponivel", t/1048576, a/1048576}' /proc/meminfo)"
  echo "Disco (/)  : $(df -h / | awk 'NR==2{print $4" livres"}')"
  echo "Build dir  : $LLM_HOME"
  echo "Modelos dir: $MODELS_DIR"
  local cli; cli="$(llama_exe llama-cli || true)"
  [ -n "$cli" ] || cli="NAO COMPILADO (rode: $0 install)"
  echo "llama-cli  : $cli"
  local gg=0
  if [ -d "$MODELS_DIR" ]; then
    gg="$(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf' 2>/dev/null | wc -l)"
  fi
  echo "Modelos    : $gg arquivo(s) .gguf baixado(s)"
  if ! grep -q avx /proc/cpuinfo; then
    warn "Esta CPU nao tem AVX — use llama.cpp (este script). Ollama provavelmente falha aqui."
  fi
}

usage() {
  sed -n '2,40p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ---- dispatch ---------------------------------------------------------------
case "${1:-}" in
  install) cmd_install ;;
  deps)    cmd_deps ;;
  build)   cmd_build ;;
  pull)    shift; cmd_pull "$@" ;;
  list)    cmd_list ;;
  run)     shift; cmd_run "$@" ;;
  chat)    shift; cmd_chat "$@" ;;
  serve)   shift; cmd_serve "$@" ;;
  bench)   shift; cmd_bench "$@" ;;
  update)  cmd_update ;;
  paths)   cmd_paths ;;
  doctor)  cmd_doctor ;;
  ""|-h|--help|help) usage ;;
  *) die "comando desconhecido: $1 (use: $0 help)" ;;
esac
