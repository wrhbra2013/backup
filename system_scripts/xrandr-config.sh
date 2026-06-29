#!/usr/bin/env bash

LOG_FILE="$HOME/.local/share/xrandr-config.log"
PRESETS_DIR="$HOME/.local/share/xrandr-presets"
mkdir -p "$(dirname "$LOG_FILE")" "$PRESETS_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

get_outputs() {
    xrandr --query 2>/dev/null | awk '/ connected/ {print $1}'
}

get_modes() {
    local output="$1"
    xrandr --query 2>/dev/null | sed -n "/^$output/,/^[^ ]/p" | grep -E '^\s+[0-9]+x[0-9]+' | awk '{print $1}' | sort -u
}

list_outputs() {
    echo
    echo "=== DISPLAYS DETECTADOS ==="
    xrandr --query 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q " connected"; then
            local out=$(echo "$line" | awk '{print $1}')
            local res=$(echo "$line" | awk '{print $3}')
            printf "  \e[1;32m%s\e[0m  %s\n" "$out" "$res"
        elif echo "$line" | grep -q " disconnected"; then
            local out=$(echo "$line" | awk '{print $1}')
            printf "  \e[1;31m%s\e[0m  desconectado\n" "$out"
        fi
    done
    echo
}

list_modes() {
    local output="$1"
    echo
    echo "=== RESOLUCOES DISPONIVEIS: $output ==="
    local i=1
    while IFS= read -r mode; do
        printf "  %2d) %s\n" "$i" "$mode"
        i=$((i + 1))
    done < <(get_modes "$output")
    echo
}

mirror() {
    local primary="$1" secondary="$2" mode="$3"
    log "MIRROR: $secondary -> $primary @ $mode"
    xrandr --output "$secondary" --same-as "$primary" --mode "$mode"
    log "OK: mirror $primary <- $secondary ($mode)"
}

extend() {
    local primary="$1" secondary="$2" dir="$3" mode="$4"
    log "EXTEND: $secondary $dir de $primary @ $mode"
    xrandr --output "$secondary" --mode "$mode" "--$dir-of" "$primary"
    log "OK: extend $secondary $dir de $primary ($mode)"
}

single() {
    local output="$1" mode="$2"
    log "SINGLE: apenas $output @ $mode"
    local others=()
    for o in $(get_outputs); do
        [ "$o" != "$output" ] && others+=("$o")
    done
    xrandr --output "$output" --mode "$mode"
    for o in "${others[@]}"; do
        xrandr --output "$o" --off
    done
    log "OK: single $output ($mode), demais desligados"
}

turn_off() {
    local output="$1"
    log "OFF: $output"
    xrandr --output "$output" --off
    log "OK: $output desligado"
}

preset_save() {
    local name="$1"
    local file="$PRESETS_DIR/$name.conf"
    > "$file"
    for o in $(get_outputs); do
        local state line
        line=$(xrandr --query 2>/dev/null | grep "^$o ")
        state=$(echo "$line" | awk '{print $2}')
        if [ "$state" = "connected" ]; then
            local res=$(echo "$line" | awk '{print $3}' | cut -d+ -f1)
            local pos=$(echo "$line" | awk '{print $3}' | grep -o '+[0-9]++[0-9]' | tr '+' ' ')
            local primary=""
            echo "$line" | grep -q "primary" && primary="--primary"
            echo "$o $res $primary" >> "$file"
        fi
    done
    log "PRESET SALVO: $name"
}

preset_load() {
    local name="$1"
    local file="$PRESETS_DIR/$name.conf"
    [ ! -f "$file" ] && { error "Preset '$name' nao encontrado"; return 1; }

    for o in $(get_outputs); do
        xrandr --output "$o" --off 2>/dev/null
    done

    while read -r output res primary; do
        [ -z "$output" ] && continue
        xrandr --output "$output" --mode "$res" $primary 2>/dev/null
    done < "$file"

    # re-apply mirror/positions
    local first_out="" first_res=""
    while read -r output res primary; do
        [ -z "$first_out" ] && { first_out="$output"; first_res="$res"; continue; }
        xrandr --output "$output" --same-as "$first_out" --mode "$res" 2>/dev/null
    done < "$file"

    log "PRESET CARREGADO: $name"
    xrandr --query 2>/dev/null | grep " connected" | tee -a "$LOG_FILE"
}

preset_list() {
    shopt -s nullglob
    local files=("$PRESETS_DIR"/*.conf)
    shopt -u nullglob
    [ ${#files[@]} -eq 0 ] && return
    for f in "${files[@]}"; do
        basename "$f" .conf
    done
}

preset_save_current() {
    local name
    read -rp "Nome do preset: " name
    [ -z "$name" ] && { error "Nome invalido"; return; }
    preset_save "$name"
    echo -e "\e[1;32mPreset '$name' salvo!\e[0m"
    read -rp "Pressione Enter para continuar..."
}

preset_load_menu() {
    shopt -s nullglob
    local files=("$PRESETS_DIR"/*.conf)
    shopt -u nullglob
    if [ ${#files[@]} -eq 0 ]; then
        error "Nenhum preset salvo"
        sleep 1
        return
    fi
    echo
    echo "--- PRESETS DISPONIVEIS ---"
    local i=1 names=()
    for f in "${files[@]}"; do
        local n
        n=$(basename "$f" .conf)
        names+=("$n")
        echo "  $i) $n"
        i=$((i + 1))
    done
    read -rp "Escolha o numero: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#names[@]} ]; then
        preset_load "${names[$((sel - 1))]}"
        echo -e "\e[1;32mPreset '${names[$((sel - 1))]}' carregado!\e[0m"
    else
        error "Opcao invalida"
    fi
    read -rp "Pressione Enter para continuar..."
}

quick_hdmi_full() {
    log "QUICK: HDMI 1920x1080 + eDP mirror"
    local edp_mode="1366x768"
    xrandr --output eDP-1 --off 2>/dev/null
    xrandr --output HDMI-1 --mode 1920x1080 2>/dev/null
    xrandr --output eDP-1 --same-as HDMI-1 --mode "$edp_mode" 2>/dev/null
    log "OK: HDMI 1920x1080 espelhando eDP-1 $edp_mode"
    xrandr --query | grep " connected"
    read -rp "Pressione Enter para continuar..."
}

quick_hdmi_1360() {
    log "QUICK: HDMI 1360x768 + eDP mirror"
    local edp_mode="1366x768"
    xrandr --output eDP-1 --off 2>/dev/null
    xrandr --output HDMI-1 --mode 1360x768 2>/dev/null
    xrandr --output eDP-1 --same-as HDMI-1 --mode "$edp_mode" 2>/dev/null
    log "OK: HDMI 1360x768 espelhando eDP-1 $edp_mode"
    xrandr --query | grep " connected"
    read -rp "Pressione Enter para continuar..."
}

error() {
    echo -e "\e[1;31mERRO: $*\e[0m" >&2
}

menu_principal() {
    local outputs
    mapfile -t outputs < <(get_outputs)
    [ ${#outputs[@]} -eq 0 ] && { error "Nenhum display detectado"; exit 1; }

    while true; do
        clear
        echo "=========================================="
        echo "       CONFIGURACAO DE VIDEO (XRANDR)     "
        echo "=========================================="
        list_outputs
        echo "ESCOLHA UMA OPCAO:"
        echo
        echo "  QUICK CONFIGS:"
        echo "  hdmi_best) HDMI 1920x1080 + eDP mirror (full HD)"
        echo "  edp_best)  HDMI 1360x768 + eDP mirror (resolucao interna)"
        echo "  ---"
        echo "  1) Espelhar (mirror)"
        echo "  2) Estender (extend)"
        echo "  3) Apenas um display (single)"
        echo "  4) Desligar um display"
        echo "  5) Auto-detect (--auto)"
        echo "  6) Carregar preset"
        echo "  7) Salvar preset atual"
        echo "  8) Sair"
        echo
        read -rp "Opcao: " opt

        case "$opt" in
            hdmi_best) quick_hdmi_full ;;
            edp_best)  quick_hdmi_1360 ;;
            1) menu_mirror "${outputs[@]}" ;;
            2) menu_extend "${outputs[@]}" ;;
            3) menu_single "${outputs[@]}" ;;
            4) menu_off "${outputs[@]}" ;;
            5) auto_detect "${outputs[@]}" ;;
            6) preset_load_menu ;;
            7) preset_save_current ;;
            8) log "Saindo"; exit 0 ;;
            *) error "Opcao invalida"; sleep 1 ;;
        esac
    done
}

escolher_output() {
    local prompt="$1"; shift
    local outputs=("$@")
    local i=1
    for o in "${outputs[@]}"; do
        echo "  $i) $o"
        i=$((i + 1))
    done
    read -rp "$prompt: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#outputs[@]} ]; then
        echo "${outputs[$((sel - 1))]}"
    else
        return 1
    fi
}

escolher_modo() {
    local output="$1"
    local modes=()
    while IFS= read -r m; do
        modes+=("$m")
    done < <(get_modes "$output")
    [ ${#modes[@]} -eq 0 ] && { error "Nenhum modo encontrado para $output"; return 1; }

    list_modes "$output"
    read -rp "Escolha o numero da resolucao (Enter=primeira): " sel
    if [ -z "$sel" ]; then
        echo "${modes[0]}"
    elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#modes[@]} ]; then
        echo "${modes[$((sel - 1))]}"
    else
        error "Selecao invalida"
        return 1
    fi
}

menu_mirror() {
    local outputs=("$@")
    [ ${#outputs[@]} -lt 2 ] && { error "Precisa de pelo menos 2 displays para espelhar"; sleep 1; return; }
    echo
    echo "--- ESPELHAR ---"
    echo "Display principal (origem):"
    local primary
    primary=$(escolher_output "Numero" "${outputs[@]}") || return
    local secundarios=()
    for o in "${outputs[@]}"; do [ "$o" != "$primary" ] && secundarios+=("$o"); done
    echo "Display para espelhar:"
    local secondary
    secondary=$(escolher_output "Numero" "${secundarios[@]}") || return
    local mode
    mode=$(escolher_modo "$primary") || return
    mirror "$primary" "$secondary" "$mode"
    log "MENU: mirror concluido"
    read -rp "Pressione Enter para continuar..."
}

menu_extend() {
    local outputs=("$@")
    [ ${#outputs[@]} -lt 2 ] && { error "Precisa de pelo menos 2 displays para estender"; sleep 1; return; }
    echo
    echo "--- ESTENDER ---"
    echo "Display principal:"
    local primary
    primary=$(escolher_output "Numero" "${outputs[@]}") || return
    local secundarios=()
    for o in "${outputs[@]}"; do [ "$o" != "$primary" ] && secundarios+=("$o"); done
    echo "Display secundario:"
    local secondary
    secondary=$(escolher_output "Numero" "${secundarios[@]}") || return
    local mode
    mode=$(escolher_modo "$secondary") || return
    echo "Direcao: 1) right-of  2) left-of  3) above  4) below"
    read -rp "Opcao (1-4): " dir
    case "$dir" in
        1) d="right" ;;
        2) d="left" ;;
        3) d="above" ;;
        4) d="below" ;;
        *) d="right" ;;
    esac
    extend "$primary" "$secondary" "$d" "$mode"
    log "MENU: extend concluido"
    read -rp "Pressione Enter para continuar..."
}

menu_single() {
    local outputs=("$@")
    echo
    echo "--- APENAS UM DISPLAY ---"
    local target
    target=$(escolher_output "Numero do display que ficara ativo" "${outputs[@]}") || return
    local mode
    mode=$(escolher_modo "$target") || return
    single "$target" "$mode"
    log "MENU: single concluido"
    read -rp "Pressione Enter para continuar..."
}

menu_off() {
    local outputs=("$@")
    [ ${#outputs[@]} -lt 1 ] && return
    echo
    echo "--- DESLIGAR DISPLAY ---"
    local target
    target=$(escolher_output "Numero do display para desligar" "${outputs[@]}") || return
    turn_off "$target"
    log "MENU: desligado"
    read -rp "Pressione Enter para continuar..."
}

auto_detect() {
    log "AUTO: xrandr --auto"
    xrandr --auto
    log "OK: auto-detect concluido"
    read -rp "Pressione Enter para continuar..."
}

if ! command -v xrandr &>/dev/null; then
    error "xrandr nao encontrado. Instale com: sudo dnf install xorg-x11-server-utils"
    exit 1
fi

menu_principal "$@"
