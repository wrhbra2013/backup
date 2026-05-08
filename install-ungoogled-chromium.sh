#!/bin/bash
set -euo pipefail

APPIMAGE="ungoogled-chromium-147.0.7727.137-1-x86_64.AppImage"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APPIMAGE_PATH="$SRC_DIR/$APPIMAGE"
BIN_PATH="/usr/local/bin/ungoogled-chromium"
ICON_DIR="/usr/local/share/icons"
ICON_PATH="$ICON_DIR/ungoogled-chromium.png"
DESKTOP_PATH="/usr/share/applications/ungoogled-chromium.desktop"

if [ ! -f "$APPIMAGE_PATH" ]; then
    echo "Erro: $APPIMAGE não encontrado em $SRC_DIR"
    exit 1
fi

echo "[1/4] Copiando AppImage para /usr/local/bin..."
sudo cp "$APPIMAGE_PATH" "$BIN_PATH"
sudo chmod +x "$BIN_PATH"

echo "[2/4] Extraindo ícone..."
sudo mkdir -p "$ICON_DIR"
ICON_EXTRACTED=false

EXTRACT_DIR=$(mktemp -d)
cd "$EXTRACT_DIR"
for path in \
    "usr/share/icons/hicolor/256x256/apps/chromium.png" \
    "usr/share/icons/hicolor/128x128/apps/chromium.png" \
    "usr/share/icons/hicolor/96x96/apps/chromium.png" \
    "usr/share/icons/hicolor/64x64/apps/chromium.png" \
    "usr/share/icons/hicolor/48x48/apps/chromium.png" \
    "usr/share/icons/hicolor/32x32/apps/chromium.png" \
    "chromium.png" \
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
        "https://raw.githubusercontent.com/ungoogled-software/ungoogled-chromium/master/logo/ungoogled_chromium_logo_256.png" \
        || sudo wget -q -O "$ICON_PATH" \
        "https://raw.githubusercontent.com/ungoogled-software/ungoogled-chromium/refs/heads/master/logo/ungoogled_chromium_logo_256.png" \
        || {
        echo "Aviso: baixando ícone genérico do Chromium..."
        sudo wget -q -O "$ICON_PATH" \
            "https://upload.wikimedia.org/wikipedia/commons/a/a5/Chromium_11_Logo.png" \
            || sudo wget -q -O "$ICON_PATH" \
            "https://raw.githubusercontent.com/chromium/chromium/main/chrome/app/theme/chromium/linux/product_logo_256.png" \
            || {
            echo "Erro: não foi possível obter nenhum ícone."
            ICON_PATH="chromium-browser"
        }
    }
fi

echo "[3/4] Criando atalho .desktop..."
sudo tee "$DESKTOP_PATH" > /dev/null << DESKTOP
[Desktop Entry]
Name=Ungoogled Chromium
Comment=Navegador sem serviços do Google
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=ungoogled-chromium
DESKTOP

echo "[4/4] Atualizando banco de dados do menu..."
sudo update-desktop-database /usr/share/applications 2>/dev/null || true

echo ""
echo "Pronto! Ungoogled Chromium instalado em $BIN_PATH"
echo "Atalho criado em $DESKTOP_PATH"
