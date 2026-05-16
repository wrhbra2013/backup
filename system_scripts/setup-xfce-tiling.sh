#!/bin/bash

# Ativa window tiling no XFCE4 (mouse + teclado)
# Testado no XFCE 4.16+ (Oracle Linux, RHEL, Fedora, Debian)

set -euo pipefail

echo "[1/3] Verificando dependencias..."
if ! command -v xfconf-query &>/dev/null; then
    echo "XFCE (xfconf) nao encontrado. Instale o XFCE desktop primeiro."
    echo "  Oracle Linux/RHEL: sudo dnf groupinstall 'XFCE'"
    exit 1
fi

echo "[2/3] Ativando tiling com mouse..."
xfconf-query -c xfwm4 -p /general/tile_on_move -s true 2>/dev/null || \
    xfconf-query -c xfwm4 -p /general/tile_on_move -n -t bool -s true

# Ativar tambem tile por arrasto para bordas
xfconf-query -c xfwm4 -p /general/tile_on_move_centered -s false 2>/dev/null || \
    xfconf-query -c xfwm4 -p /general/tile_on_move_centered -n -t bool -s false

echo "[3/3] Configurando atalhos de teclado..."

# --- Tiling basico: Super + setas ---
# Tile left / right (metade da tela)
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Left" -n -t string -s tile_left_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Left" -t string -s tile_left_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Right" -n -t string -s tile_right_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Right" -t string -s tile_right_key

# Tile up / down (metade vertical)
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Up" -n -t string -s tile_up_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Up" -t string -s tile_up_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Down" -n -t string -s tile_down_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Super>Down" -t string -s tile_down_key

# --- Cantos: Super + Ctrl + setas ---
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Left" -n -t string -s tile_top_left_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Left" -t string -s tile_top_left_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Right" -n -t string -s tile_top_right_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Right" -t string -s tile_top_right_key

xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Down" -n -t string -s tile_bottom_left_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Down" -t string -s tile_bottom_left_key

# --- Tile vertical maximizado (Super + Ctrl + Up = tile bottom + up = full vertical) ---
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Up" -n -t string -s tile_bottom_right_key 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/"<Primary><Super>Up" -t string -s tile_bottom_right_key

echo ""
echo "Pronto! Efeitos aplicados:"
echo "  - Tiling por arrasto (bordas da tela)"
echo "  - Super + <-/->        : tile left/right"
echo "  - Super + cima/baixo   : tile top/bottom"
echo "  - Super + Ctrl + setas : tile nos cantos"
echo ""
echo "NOTA: Se o Whisker menu estiver mapeado para Super sozinho,"
echo "      o tiling com Super+setas pode parar de funcionar (bug XFCE 4.20+)."
echo "      Solucao: va em Teclado -> Atalhos e mude Whisker para Super+Z"
