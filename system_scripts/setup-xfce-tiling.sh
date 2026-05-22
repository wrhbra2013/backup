#!/bin/bash

# Ativa window tiling no XFCE4 (mouse + teclado)
# Força tiling left/right via xdotool para sobrepor qualquer aplicativo (Firefox, etc.)

set -euo pipefail

echo "[1/3] Verificando dependencias..."
for cmd in xfconf-query xdotool xprop xrandr; do
    if ! command -v $cmd &>/dev/null; then
        echo "Erro: $cmd nao encontrado. Instale-o primeiro."
        exit 1
    fi
done

echo "[2/3] Ativando tiling com mouse..."
xfconf-query -c xfwm4 -p /general/tile_on_move -s true 2>/dev/null || \
    xfconf-query -c xfwm4 -p /general/tile_on_move -n -t bool -s true

xfconf-query -c xfwm4 -p /general/tile_on_move_centered -s false 2>/dev/null || \
    xfconf-query -c xfwm4 -p /general/tile_on_move_centered -n -t bool -s false

echo "[3/3] Configurando atalhos de teclado (com override total via xdotool)..."

BINDIR="${HOME}/.local/bin"
mkdir -p "$BINDIR"

# --- Tile Left ---
cat > "$BINDIR/xfce-tile-left.sh" << 'XFCE_TILE_LEFT'
#!/bin/bash
set -euo pipefail

WIN=$(xdotool getactivewindow 2>/dev/null) || exit 1

# Ignora se for a área de trabalho
if xprop -id "$WIN" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DESKTOP; then
    exit 0
fi

# Workarea global (exclui painéis)
read -r WA_X WA_Y WA_W WA_H <<< "$(xprop -root _NET_WORKAREA | awk -F'= ' '{print $2}' | tr ',' ' ')"
WA_X=${WA_X:-0}; WA_Y=${WA_Y:-0}; WA_W=${WA_W:-1920}; WA_H=${WA_H:-1080}

# Pega posição da janela para descobrir em qual monitor está
WIN_X=$(xdotool getwindowgeometry "$WIN" 2>/dev/null | awk '/Position:/{print $2}' | cut -d',' -f1)
WIN_X=${WIN_X:-0}
CENTER=$((WIN_X + WA_X))

# Acha o monitor onde a janela está centrada
MON_X=0; MON_W=$WA_W
while read -r line; do
    [[ "$line" != *" connected"* ]] && continue
    RECT=$(echo "$line" | grep -oP '\d+x\d+\+\d+\+\d+')
    [[ -z "$RECT" ]] && continue
    MX=$(echo "$RECT" | cut -d'+' -f2)
    MY=$(echo "$RECT" | cut -d'+' -f3)
    MW=$(echo "$RECT" | cut -d'x' -f1)
    MH=$(echo "$RECT" | cut -d'x' -f2 | cut -d'+' -f1)
    if (( CENTER >= MX && CENTER < MX + MW )); then
        MON_X=$MX; MON_Y=$MY; MON_W=$MW; MON_H=$MH
        break
    fi
done < <(xrandr --current)

HALF=$((MON_W / 2))

xdotool windowmove "$WIN" "$MON_X" "$MON_Y"
xdotool windowsize "$WIN" "$HALF" "$MON_H"
XFCE_TILE_LEFT
chmod +x "$BINDIR/xfce-tile-left.sh"

# --- Tile Right ---
cat > "$BINDIR/xfce-tile-right.sh" << 'XFCE_TILE_RIGHT'
#!/bin/bash
set -euo pipefail

WIN=$(xdotool getactivewindow 2>/dev/null) || exit 1

if xprop -id "$WIN" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DESKTOP; then
    exit 0
fi

read -r WA_X WA_Y WA_W WA_H <<< "$(xprop -root _NET_WORKAREA | awk -F'= ' '{print $2}' | tr ',' ' ')"
WA_X=${WA_X:-0}; WA_Y=${WA_Y:-0}; WA_W=${WA_W:-1920}; WA_H=${WA_H:-1080}

WIN_X=$(xdotool getwindowgeometry "$WIN" 2>/dev/null | awk '/Position:/{print $2}' | cut -d',' -f1)
WIN_X=${WIN_X:-0}
CENTER=$((WIN_X + WA_X))

MON_X=0; MON_W=$WA_W
while read -r line; do
    [[ "$line" != *" connected"* ]] && continue
    RECT=$(echo "$line" | grep -oP '\d+x\d+\+\d+\+\d+')
    [[ -z "$RECT" ]] && continue
    MX=$(echo "$RECT" | cut -d'+' -f2)
    MY=$(echo "$RECT" | cut -d'+' -f3)
    MW=$(echo "$RECT" | cut -d'x' -f1)
    MH=$(echo "$RECT" | cut -d'x' -f2 | cut -d'+' -f1)
    if (( CENTER >= MX && CENTER < MX + MW )); then
        MON_X=$MX; MON_Y=$MY; MON_W=$MW; MON_H=$MH
        break
    fi
done < <(xrandr --current)

HALF=$((MON_W / 2))

xdotool windowmove "$WIN" "$((MON_X + HALF))" "$MON_Y"
xdotool windowsize "$WIN" "$HALF" "$MON_H"
XFCE_TILE_RIGHT
chmod +x "$BINDIR/xfce-tile-right.sh"

# Remove atalhos XFWM antigos (que são interceptados por apps)
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Left" -r 2>/dev/null || true
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Right" -r 2>/dev/null || true

# Registra os scripts como comandos customizados (não passam pelo XFWM)
xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/"<Super>Left" -n -t string -s "$BINDIR/xfce-tile-left.sh" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/"<Super>Left" -t string -s "$BINDIR/xfce-tile-left.sh"

xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/"<Super>Right" -n -t string -s "$BINDIR/xfce-tile-right.sh" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /commands/custom/"<Super>Right" -t string -s "$BINDIR/xfce-tile-right.sh"

# Manter os demais atalhos XFWM (up/down/cantos) que geralmente não tem conflito
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Up" -n -t string -s tile_up_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Up" -t string -s tile_up_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Down" -n -t string -s tile_down_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Down" -t string -s tile_down_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Left" -n -t string -s tile_top_left_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Left" -t string -s tile_top_left_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Right" -n -t string -s tile_top_right_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Right" -t string -s tile_top_right_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Down" -n -t string -s tile_bottom_left_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Down" -t string -s tile_bottom_left_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Up" -n -t string -s tile_bottom_right_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Up" -t string -s tile_bottom_right_key

echo ""
echo "Pronto! Efeitos aplicados:"
echo "  - Tiling por arrasto (bordas da tela)"
echo "  - Super + <-/->        : tile left/right (via xdotool - sobrepoe qualquer app)"
echo "  - Super + cima/baixo   : tile top/bottom"
echo "  - Super + Ctrl + setas : tile nos cantos"
echo ""
echo "Diferente do XFWM padrao, Super+Left/Right usa xdotool diretamente,"
echo "entao funciona mesmo no Firefox, terminal, etc."
echo "Scripts instalados em: $BINDIR/xfce-tile-{left,right}.sh"
