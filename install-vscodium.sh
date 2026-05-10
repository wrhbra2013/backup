#!/bin/bash
set -euo pipefail

REPO="VSCodium/vscodium"
BIN_PATH="/usr/local/bin/vscodium"
ICON_DIR="/usr/local/share/icons"
ICON_PATH="$ICON_DIR/vscodium.png"
DESKTOP_PATH="/usr/share/applications/vscodium.desktop"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Instalador VSCodium ==="
echo ""

# --- Buscar AppImage ---
APPIMAGE_PATH=""
shopt -s nullglob
for f in "$SRC_DIR"/VSCodium-*-x86_64.AppImage; do
    APPIMAGE_PATH="$f"
    break
done
shopt -u nullglob

if [ -n "$APPIMAGE_PATH" ] && [ -f "$APPIMAGE_PATH" ]; then
    echo "AppImage encontrado localmente: $(basename "$APPIMAGE_PATH")"
else
    echo "AppImage não encontrado localmente. Buscando última versão via GitHub API..."
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
    echo "  API: $API_URL"

    JSON=$(curl -sfL "$API_URL" 2>/dev/null || true)
    if [ -z "$JSON" ]; then
        echo "  Aviso: não foi possível consultar a API do GitHub (limite de taxa?)."
        JSON=$(curl -sfL "${API_URL/latest}?per_page=1" 2>/dev/null || true)
    fi

    DOWNLOAD_URL=$(echo "$JSON" \
        | grep -Po '"browser_download_url":\s*"\K[^"]+(?=")' \
        | grep -i 'AppImage' \
        | grep -v 'arm64\|armhf\|aarch64' \
        | head -1 || true)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "  Não foi possível obter o link automaticamente."
        echo ""
        echo "Acesse e baixe manualmente o AppImage:"
        echo "  https://github.com/$REPO/releases/latest"
        read -rp "Cole aqui o link do AppImage (ou Enter para cancelar): " DOWNLOAD_URL
        [ -z "$DOWNLOAD_URL" ] && echo "Cancelado." && exit 1
    fi

    APPIMAGE_NAME=$(basename "$DOWNLOAD_URL")
    APPIMAGE_PATH="$SRC_DIR/$APPIMAGE_NAME"

    echo ""
    echo "AppImage: $APPIMAGE_NAME"
    echo "Tamanho:  $(curl -sI "$DOWNLOAD_URL" | grep -i content-length | awk '{printf "%.0f MB\n", $2/1024/1024}')"
    read -rp "Deseja baixar e instalar? (S/n): " CONFIRM
    CONFIRM=${CONFIRM:-S}
    if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
        echo "Baixando..."
        wget -q --show-progress -O "$APPIMAGE_PATH" "$DOWNLOAD_URL"
    else
        echo "Cancelado pelo usuário."
        exit 1
    fi
fi

# --- Confirmar instalação ---
echo ""
read -rp "Instalar $(basename "$APPIMAGE_PATH") no sistema? (S/n): " CONFIRM
CONFIRM=${CONFIRM:-S}
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo "Cancelado."
    exit 1
fi

# --- Instalação ---
echo ""
echo "[1/4] Copiando AppImage para /usr/local/bin..."
sudo cp "$APPIMAGE_PATH" "$BIN_PATH"
sudo chmod +x "$BIN_PATH"

echo "[2/4] Extraindo ícone..."
sudo mkdir -p "$ICON_DIR"
ICON_EXTRACTED=false

EXTRACT_DIR=$(mktemp -d)
cd "$EXTRACT_DIR"
for path in \
    "usr/share/icons/hicolor/256x256/apps/vscodium.png" \
    "usr/share/icons/hicolor/128x128/apps/vscodium.png" \
    "usr/share/icons/hicolor/96x96/apps/vscodium.png" \
    "usr/share/icons/hicolor/64x64/apps/vscodium.png" \
    "usr/share/icons/hicolor/48x48/apps/vscodium.png" \
    "usr/share/icons/hicolor/32x32/apps/vscodium.png" \
    "usr/share/icons/hicolor/256x256/apps/codium.png" \
    "usr/share/icons/hicolor/128x128/apps/codium.png" \
    "usr/share/icons/hicolor/64x64/apps/codium.png" \
    "usr/share/icons/hicolor/48x48/apps/codium.png" \
    "vscodium.png" \
    "codium.png" \
    ".DirIcon"; do
    if "$BIN_PATH" --appimage-extract "$path" >/dev/null 2>&1 && [ -f "squashfs-root/$path" ]; then
        sudo cp "squashfs-root/$path" "$ICON_PATH"
        ICON_EXTRACTED=true
        break
    fi
done

cd /tmp
rm -rf "$EXTRACT_DIR"

if [ "$ICON_EXTRACTED" = false ]; then
    echo "Ícone não encontrado no AppImage. Baixando do repositório oficial..."
    sudo wget -q -O "$ICON_PATH" \
        "https://raw.githubusercontent.com/VSCodium/vscodium/master/icons/vscodium.png" \
        || sudo wget -q -O "$ICON_PATH" \
        "https://raw.githubusercontent.com/VSCodium/vscodium/refs/heads/master/icons/vscodium.png" \
        || {
        echo "Aviso: baixando ícone alternativo..."
        sudo wget -q -O "$ICON_PATH" \
            "https://upload.wikimedia.org/wikipedia/commons/e/e8/VSCodium_logo.png" \
            || {
            echo "Erro: não foi possível obter nenhum ícone."
            ICON_PATH="code"
        }
    }
fi

echo "[3/4] Criando atalho .desktop..."
sudo tee "$DESKTOP_PATH" > /dev/null << DESKTOP
[Desktop Entry]
Name=VSCodium
Comment=Editor de código livre e open-source
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=vscodium
StartupNotify=true
DESKTOP

echo "[4/4] Atualizando banco de dados do menu..."
sudo update-desktop-database /usr/share/applications 2>/dev/null || true

echo ""
echo "Pronto! VSCodium instalado em $BIN_PATH"
echo "Atalho criado em $DESKTOP_PATH"
