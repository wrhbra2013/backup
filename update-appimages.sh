#!/usr/bin/env bash
set -uo pipefail

APP_DIR="${1:-$HOME/Applications}"
LOGFILE="$HOME/.cache/update-appimages.log"
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR" "$(dirname "$LOGFILE")" "$DESKTOP_DIR"

exec > >(tee -a "$LOGFILE")
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# IPs conhecidos do GitHub API (DNS local resolve para IP invalido)
GH_API_IPS=("140.82.112.5" "140.82.113.5" "140.82.114.5" "140.82.116.5")
GH_RESOLVE=""
for ip in "${GH_API_IPS[@]}"; do
    GH_RESOLVE+=" --resolve api.github.com:443:$ip"
done

fetch_release() {
    local repo="$1" filter="$2"
    local json

    # Tentar API com --resolve (contorna DNS invalido)
    json=$(curl -sL $GH_RESOLVE --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/$repo/releases/latest" 2>&1) || {
        # Fallback: scraping da pagina HTML (funciona para alguns repos)
        fetch_release_html "$repo" "$filter" && return 0
        fetch_err="API e fallback HTML falharam"
        return 1
    }

    VERSION=$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null) || VERSION=""
    URL=$(echo "$json" | python3 -c "
import json,sys
for a in json.load(sys.stdin).get('assets', []):
    if '$filter' in a['name'] and 'zsync' not in a['name']:
        print(a['browser_download_url'])
        break
" 2>/dev/null) || URL=""

    if [[ -z "$URL" ]]; then
        fetch_err="nenhum asset encontrado para: $filter"
        return 1
    fi
}

fetch_release_html() {
    local repo="$1" filter="$2"

    local page_url
    page_url=$(curl -sL --connect-timeout 10 --max-time 20 \
        -o /dev/null -w '%{url_effective}' \
        "https://github.com/$repo/releases/latest") || return 1

    VERSION=$(echo "$page_url" | sed 's|.*/tag/||')
    [[ -z "$VERSION" ]] && return 1

    local html
    html=$(curl -sL --connect-timeout 10 --max-time 20 "$page_url") || return 1

    local path
    path=$(echo "$html" | python3 -c "
import sys, re
html = sys.stdin.read()
repo = '$repo'
f = '$filter'
for m in re.finditer(r'href=\"([^\"]+?)\"', html):
    u = m.group(1)
    if repo in u and '/releases/download/' in u and f in u and 'zsync' not in u:
        print(u)
        break
" 2>/dev/null) || return 1

    [[ -z "$path" ]] && return 1

    if [[ "$path" == https://* ]]; then
        URL="$path"
    else
        URL="https://github.com$path"
    fi
}

download_app() {
    local url="$1" output="$2"
    local start elapsed bytes total_size

    # Mostrar tamanho do arquivo antes de baixar
    total_size=$(curl -sI --connect-timeout 10 --max-time 15 "$url" 2>/dev/null \
        | grep -i '^content-length:' | awk '{print $2}' | tr -d '\r ')
    if [[ -n "$total_size" ]]; then
        echo "  Tamanho: $(numfmt --to=iec "$total_size")"
    fi

    start=$(date +%s%N)
    curl -L --connect-timeout 10 --progress-bar \
        -o "$output.part" "$url" || return 1
    elapsed=$(( ($(date +%s%N) - start) / 1000000 )) # ms

    chmod +x "$output.part"
    mv "$output.part" "$output"

    bytes=$(stat -c%s "$output" 2>/dev/null)
    if [[ "$elapsed" -gt 0 && -n "$bytes" && "$bytes" -gt 0 ]]; then
        local speed=$(( bytes * 1000 / elapsed ))
        DOWNLOAD_SPEED="$(numfmt --to=iec "$speed")/s"
        DOWNLOAD_SIZE="$bytes"
    fi
}

install_desktop() {
    local name="$1" exec="$2" file="$3" icon="$4" mime="$5"
    cat > "$DESKTOP_DIR/$file" <<-EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$exec %F
Icon=$icon
Terminal=false
Categories=Development;Network;WebBrowser;
MimeType=$mime
StartupNotify=true
EOF
    chmod 644 "$DESKTOP_DIR/$file"
}

install_icon() {
    local appimage="$1" icon_name="$2"
    [[ -f "$appimage" && -n "$icon_name" ]] || return 1

    local existing
    existing=$(find "$HOME/.local/share/icons" -name "${icon_name}.*" 2>/dev/null | head -1)
    [[ -n "$existing" ]] && return 0

    local tmpdir icon_src
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && "$appimage" --appimage-extract) >/dev/null 2>&1 || {
        rm -rf "$tmpdir"
        return 1
    }

    local root="$tmpdir/squashfs-root"

    if [[ -f "$root/.DirIcon" ]]; then
        icon_src="$root/.DirIcon"
    else
        icon_src=$(find "$root" -name "${icon_name}.png" -o -name "${icon_name}.svg" 2>/dev/null | head -1)
    fi

    if [[ -z "$icon_src" ]]; then
        icon_src=$(find "$root" -name "*.png" 2>/dev/null | head -1)
    fi

    if [[ -n "$icon_src" ]]; then
        local ext="${icon_src##*.}"
        mkdir -p "$HOME/.local/share/icons"
        cp "$icon_src" "$HOME/.local/share/icons/${icon_name}.${ext}"
        rm -rf "$tmpdir"
        return 0
    fi

    rm -rf "$tmpdir"
    return 1
}

# ── Apps ──────────────────────────────────────

echo ""
echo "Atualizador de AppImages — $(date '+%Y-%m-%d %H:%M:%S')"
echo "Diretório: $APP_DIR"
echo ""

FAIL=0

while IFS='|' read -r repo filter filename label desktop icon mime; do
    echo "--- $label ---"

    printf "  Release... "
    VERSION="" URL="" fetch_err=""
    if fetch_release "$repo" "$filter"; then
        echo "$VERSION"
    else
        echo "FALHOU ($fetch_err)"
        FAIL=1
        continue
    fi

    output="$APP_DIR/$filename"
    vfile="$output.version"

    if [[ -f "$vfile" ]] && [[ "$(cat "$vfile")" == "$VERSION" ]] && [[ -f "$output" ]]; then
        echo "  Ja atualizado ($VERSION)"
    else
        echo "  Baixando... "
        if download_app "$URL" "$output"; then
            echo "  OK ($(numfmt --to=iec "$DOWNLOAD_SIZE") em ${DOWNLOAD_SPEED:-?})"
            echo "$VERSION" > "$vfile"
        else
            echo "  FALHOU"
            FAIL=1
            continue
        fi
    fi

    install_desktop "$label" "$output" "$desktop" "$icon" "$mime"
    echo "  .desktop criado"
    if [[ -f "$output" ]]; then
        install_icon "$output" "$icon" && echo "  Icone instalado" || echo "  Icone nao encontrado no AppImage"
    fi

    if command -v xdg-settings &>/dev/null; then
        case "$label" in
            "Brave Browser"|"Chromium")
                xdg-settings set default-web-browser "$(basename "$desktop" .desktop)" 2>/dev/null || true
                ;;
        esac
    fi

    echo ""
done <<-APPS
srevinsaju/Brave-AppImage|x86_64.AppImage|brave.AppImage|Brave Browser|brave-browser.desktop|brave-browser|x-scheme-handler/http;x-scheme-handler/https;text/html
VSCodium/vscodium|glibc2.30-x86_64.AppImage|VSCodium.AppImage|VSCodium|codium-appimage.desktop|vscodium|text/plain;text/x-python;text/x-c;text/html;application/json
ungoogled-software/ungoogled-chromium-portablelinux|x86_64.AppImage|ungoogled-chromium.AppImage|Chromium|ungoogled-chromium-appimage.desktop|chromium|x-scheme-handler/http;x-scheme-handler/https;text/html
anomalyco/opencode|opencode-desktop-linux-x86_64.AppImage|opencode-desktop-linux-x86_64.AppImage|OpenCode|opencode-appimage.desktop|opencode|text/plain
APPS

command -v update-desktop-database &>/dev/null && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache "$HOME/.local/share/icons" 2>/dev/null || true

echo "---"
echo "Status: $([ "$FAIL" -eq 0 ] && echo "Sucesso" || echo "Falha em algum item")"
echo "Log: $LOGFILE"
exit "$FAIL"
