#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-$HOME/Applications}"
LOGFILE="$HOME/.cache/update-appimages.log"
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR" "$(dirname "$LOGFILE")" "$DESKTOP_DIR"

exec > >(tee -a "$LOGFILE") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

get_latest_appimage() {
    local repo="$1"
    local filter="${2:-AppImage}"
    curl -sL "https://api.github.com/repos/$repo/releases/latest" |
        python3 -c "
import json,sys
data=json.load(sys.stdin)
for a in data.get('assets', []):
    if '$filter' in a['name'] and 'zsync' not in a['name']:
        print(a['browser_download_url'])
        break
" 2>/dev/null
}

install_desktop_entry() {
    local app="$1"
    local exec_path="$2"
    local desktop_file="$3"
    local content="$4"

    echo "$content" > "$DESKTOP_DIR/$desktop_file"
    chmod 644 "$DESKTOP_DIR/$desktop_file"
    log "[OK] .desktop criado: $DESKTOP_DIR/$desktop_file → $exec_path"
}

set_default_mime() {
    local desktop_file="$1"
    shift
    local mime_types=("$@")
    for mime in "${mime_types[@]}"; do
        if command -v xdg-mime &>/dev/null; then
            xdg-mime default "$desktop_file" "$mime" 2>/dev/null
            log "[OK] Padrão $mime → $desktop_file"
        fi
    done
}

set_default_browser() {
    local desktop_file="$1"
    if command -v xdg-settings &>/dev/null; then
        xdg-settings set default-web-browser "$desktop_file" 2>/dev/null
        log "[OK] Navegador padrão → $desktop_file"
    fi
}

update_appimage() {
    local name="$1"
    local url="$2"
    local app_label="$3"
    local desktop_id="$4"
    local desktop_name="$5"
    local desktop_comment="$6"
    local icon_name="$7"
    shift 7
    local mime_list=("$@")

    local output="$APP_DIR/$name"
    local old_size=0
    local new_size=0
    local updated=false

    log "=== Iniciando: $app_label ==="

    [[ -z "$url" ]] && { log "[ERRO] URL vazia"; return 1; }

    if [[ -f "$output" ]]; then
        old_size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        log "Arquivo existente: $(numfmt --to=iec $old_size)"
    else
        log "Arquivo não existe, será baixado"
    fi

    # Remove versão anterior e resíduos de download
    rm -f "$output.part"
    if [[ -f "$output" ]]; then
        rm -f "$output"
        log "Versão anterior removida"
    fi

    log "Baixando..."
    if wget -c -q --show-progress \
        --connect-timeout=30 --read-timeout=30 --dns-timeout=15 \
        --tries=5 --retry-connrefused \
        -O "$output.part" "$url"; then

        new_size=$(stat -c%s "$output.part" 2>/dev/null || echo 0)
        if [[ "$new_size" -eq 0 ]]; then
            log "[ERRO] Download vazio"
            rm -f "$output.part"
            return 1
        fi
        chmod +x "$output.part"
        mv "$output.part" "$output"

        if [[ "$old_size" -eq "$new_size" ]]; then
            log "[OK] $app_label — mesmo tamanho, já atualizado ($(numfmt --to=iec $new_size))"
        else
            log "[OK] $app_label: $(numfmt --to=iec $old_size) → $(numfmt --to=iec $new_size)"
        fi
    else
        log "[AVISO] Download interrompido"
        log "        Re-execute o script para retomar"
        return 1
    fi

    # Criar entrada .desktop
    local desktop_content="[Desktop Entry]
Type=Application
Name=$desktop_name
Comment=$desktop_comment
Exec=\"$output\" %F
Icon=$icon_name
Terminal=false
Categories=Development;Network;WebBrowser;
MimeType=$(IFS=';'; echo "${mime_list[*]};")
StartupNotify=true"

    install_desktop_entry "$app_label" "$output" "$desktop_id" "$desktop_content"

    # Configurar como padrão
    if [[ "$desktop_id" == *"chromium"* ]]; then
        set_default_browser "$desktop_id"
    fi
    set_default_mime "$desktop_id" "${mime_list[@]}"
}

# ─────────────────────────────────────────────

echo "========================================"
echo " Atualizador de AppImages"
echo " Início: $(date '+%Y-%m-%d %H:%M:%S')"
echo " Diretório: $APP_DIR"
echo " Log: $LOGFILE"
echo "========================================"
echo ""

FAIL=0

echo "[.] Obtendo URL do VSCodium..."
VSC_URL=$(get_latest_appimage "VSCodium/vscodium" "glibc2.30-x86_64.AppImage")
echo "    → ${VSC_URL:-falhou}"

echo "[.] Obtendo URL do ungoogled-chromium..."
UCL_URL=$(get_latest_appimage "ungoogled-software/ungoogled-chromium-portablelinux" "x86_64.AppImage")
echo "    → ${UCL_URL:-falhou}"

echo "[.] Obtendo URL do opencode..."
OC_URL=$(get_latest_appimage "anomalyco/opencode" "opencode-desktop-linux-x86_64.AppImage")
echo "    → ${OC_URL:-falhou}"

echo ""

update_appimage "VSCodium.AppImage" "$VSC_URL" \
    "VSCodium" "codium-appimage.desktop" \
    "VSCodium (AppImage)" "Editor de código e texto" "vscodium" \
    "text/plain" "text/x-python" "text/x-shellscript" "text/x-c" \
    "text/x-c++" "text/x-java" "text/javascript" "application/json" \
    "text/x-markdown" "text/x-yaml" "text/x-toml" "text/xml" \
    "text/css" "text/html" "application/typescript" \
    || FAIL=1

update_appimage "ungoogled-chromium.AppImage" "$UCL_URL" \
    "ungoogled-chromium" "ungoogled-chromium-appimage.desktop" \
    "Chromium" "Navegador web" "chromium" \
    "x-scheme-handler/http" "x-scheme-handler/https" "text/html" \
    "application/xhtml+xml" "x-scheme-handler/ftp" "text/plain" \
    || FAIL=1

update_appimage "opencode-desktop-linux-x86_64.AppImage" "$OC_URL" \
    "OpenCode" "opencode-appimage.desktop" \
    "OpenCode" "Agente de IA para codigo" "opencode" \
    "text/plain" \
    || FAIL=1

# Atualizar cache do desktop
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null
    log "[OK] Cache desktop atualizado"
fi

echo ""
echo "========================================"
echo " Resumo"
echo "========================================"
if [[ "$FAIL" -eq 0 ]]; then
    echo " Status: ✓ Sucesso"
else
    echo " Status: ⚠ Falha em algum item"
fi
echo " Log: $LOGFILE"
echo "========================================"
exit "$FAIL"
