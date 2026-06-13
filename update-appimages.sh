#!/usr/bin/env bash
set -uo pipefail

LOGFILE="$HOME/.cache/update-appimages.log"
DESKTOP_DIR="$HOME/.local/share/applications"

MODE="update"
case "${1:-}" in
    --menu) MODE="menu"; shift ;;
    --status) MODE="status"; shift ;;
    --uninstall) MODE="uninstall"; UNINSTALL_APP="${2:-}"; shift 2 ;;
esac

APP_DIR="${1:-$HOME/Applications}"
mkdir -p "$APP_DIR" "$(dirname "$LOGFILE")" "$DESKTOP_DIR"

# Apps data: repo|filter|filename|label|desktop|icon|mime|icon_url
APPS_DATA=(
    "srevinsaju/Brave-AppImage|x86_64.AppImage|brave.AppImage|Brave Browser|brave-browser.desktop|brave-browser|x-scheme-handler/http;x-scheme-handler/https;text/html|"
    "VSCodium/vscodium|glibc2.30-x86_64.AppImage|VSCodium.AppImage|VSCodium|codium-appimage.desktop|vscodium|text/plain;text/x-python;text/x-c;text/html;application/json|https://raw.githubusercontent.com/VSCodium/vscodium/master/icons/stable/codium_clt.svg"
    "ungoogled-software/ungoogled-chromium-portablelinux|x86_64.AppImage|ungoogled-chromium.AppImage|Chromium|ungoogled-chromium-appimage.desktop|chromium|x-scheme-handler/http;x-scheme-handler/https;text/html|"
    "anomalyco/opencode|opencode-desktop-linux-x86_64.AppImage|opencode-desktop-linux-x86_64.AppImage|OpenCode|opencode-appimage.desktop|opencode|text/plain|https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/desktop/icons/prod/icon.png"
)

[[ "$MODE" != "update" ]] && exec > >(tee -a "$LOGFILE")
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

download_icon() {
    local url="$1" icon_name="$2"
    [[ -z "$url" || -z "$icon_name" ]] && return 1

    local ext
    ext=$(basename "$url" | sed 's/.*\.//')
    [[ -z "$ext" || "$ext" == "$(basename "$url")" ]] && ext="png"

    mkdir -p "$HOME/.local/share/icons"
    local output="$HOME/.local/share/icons/${icon_name}.${ext}"
    curl -sL --connect-timeout 10 --max-time 20 "$url" -o "$output" 2>/dev/null && [[ -s "$output" ]] && return 0
    rm -f "$output"
    return 1
}

download_icon_from_repo() {
    local repo="$1" icon_name="$2"
    [[ -z "$repo" ]] && return 1

    local base="https://raw.githubusercontent.com/$repo"
    local paths=(
        "main/.DirIcon"
        "main/icon.png"
        "main/icon.svg"
        "main/logo.png"
        "main/logo.svg"
        "main/assets/icon.png"
        "main/assets/icon.svg"
        "main/src/resources/linux/${icon_name}.png"
        "main/chrome/app/theme/${icon_name}/linux/product_logo_256.png"
        "master/.DirIcon"
        "master/icon.png"
        "master/icon.svg"
        "master/logo.png"
        "master/logo.svg"
        "master/assets/icon.png"
        "master/assets/icon.svg"
        "master/src/resources/linux/${icon_name}.png"
        "master/chrome/app/theme/${icon_name}/linux/product_logo_256.png"
        "dev/.DirIcon"
        "dev/icon.png"
        "dev/icon.svg"
    )

    for path in "${paths[@]}"; do
        local url="$base/$path"
        local http_code
        http_code=$(curl -sI --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | head -1 | awk '{print $2}')
        if [[ "$http_code" == "200" || "$http_code" == "302" ]]; then
            local ext="${path##*.}"
            mkdir -p "$HOME/.local/share/icons"
            curl -sL --connect-timeout 10 --max-time 20 "$url" -o "$HOME/.local/share/icons/${icon_name}.${ext}" 2>/dev/null && return 0
        fi
    done

    return 1
}

install_icon() {
    local appimage="$1" icon_name="$2" repo="${3:-}" icon_url="${4:-}"
    [[ -n "$icon_name" ]] || return 1

    local existing
    existing=$(find "$HOME/.local/share/icons" -maxdepth 1 -name "${icon_name}.*" 2>/dev/null | head -1)
    [[ -n "$existing" ]] && return 0

    if [[ -f "$appimage" ]]; then
        local tmpdir icon_src
        tmpdir=$(mktemp -d)
        (cd "$tmpdir" && "$appimage" --appimage-extract) >/dev/null 2>&1 || {
            rm -rf "$tmpdir"
            try_download "$icon_url" "$icon_name" "$repo" && return 0
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
    fi

    try_download "$icon_url" "$icon_name" "$repo" && return 0
    return 1
}

try_download() {
    local icon_url="$1" icon_name="$2" repo="$3"
    if [[ -n "$icon_url" ]]; then
        download_icon "$icon_url" "$icon_name" && return 0
    fi
    if [[ -n "$repo" ]]; then
        download_icon_from_repo "$repo" "$icon_name" && return 0
    fi
    return 1
}

# ── Status / List ──────────────────────────────

list_installed() {
    echo ""
    echo "═══ Apps Instalados ═══"
    echo ""
    local found=0
    local outdated=0
    for entry in "${APPS_DATA[@]}"; do
        IFS='|' read -r repo filter filename label desktop icon mime <<< "$entry"
        local output="$APP_DIR/$filename"
        local vfile="$output.version"
        if [[ -f "$output" ]]; then
            found=1
            local version=""
            [[ -f "$vfile" ]] && version=$(cat "$vfile")
            echo "  $label"
            echo "    Arquivo: $filename ($(numfmt --to=iec "$(stat -c%s "$output" 2>/dev/null)" 2>/dev/null || echo "?"))"
            if [[ -n "$version" ]]; then
                echo "    Versao: $version"
            else
                echo "    Versao: desconhecida"
            fi
        fi
    done
    [[ "$found" -eq 0 ]] && echo "  Nenhum AppImage instalado em $APP_DIR"
    echo ""
}

# ── Uninstall ──────────────────────────────────

uninstall_app() {
    local target_label="$1"
    for entry in "${APPS_DATA[@]}"; do
        IFS='|' read -r repo filter filename label desktop icon mime <<< "$entry"
        if [[ "$label" == "$target_label" ]]; then
            local output="$APP_DIR/$filename"
            local vfile="$output.version"
            local removed=0

            if [[ -f "$output" ]]; then
                rm -f "$output" && echo "  Removido: $output" && removed=1
            fi
            if [[ -f "$vfile" ]]; then
                rm -f "$vfile" && echo "  Removido: $vfile"
            fi
            if [[ -f "$DESKTOP_DIR/$desktop" ]]; then
                rm -f "$DESKTOP_DIR/$desktop" && echo "  Removido: $DESKTOP_DIR/$desktop"
            fi

            local icon_file
            icon_file=$(find "$HOME/.local/share/icons" -maxdepth 1 -name "${icon}.*" 2>/dev/null | head -1)
            if [[ -n "$icon_file" ]]; then
                rm -f "$icon_file" && echo "  Removido: $icon_file"
            fi

            if [[ "$removed" -eq 0 ]]; then
                echo "  '$label' nao esta instalado."
            else
                echo "  '$label' desinstalado com sucesso."
            fi
            return 0
        fi
    done
    echo "  App '$target_label' nao encontrado."
}

uninstall_menu() {
    local installed=()
    local labels=()
    for entry in "${APPS_DATA[@]}"; do
        IFS='|' read -r repo filter filename label desktop icon mime <<< "$entry"
        if [[ -f "$APP_DIR/$filename" ]]; then
            installed+=("$entry")
            labels+=("$label")
        fi
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo ""
        echo "Nenhum app instalado para desinstalar."
        return
    fi

    echo ""
    echo "═══ Desinstalar App ═══"
    echo ""
    for i in "${!labels[@]}"; do
        echo "  $((i+1))) ${labels[$i]}"
    done
    echo "  q) Cancelar"
    echo ""
    read -rp "Escolha um app para desinstalar: " choice

    [[ "$choice" == "q" ]] && return

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#labels[@]} ]]; then
        local idx=$((choice-1))
        local label="${labels[$idx]}"
        echo ""
        read -rp "Tem certeza que deseja desinstalar '$label'? (s/N): " confirm
        if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            uninstall_app "$label"
        else
            echo "Cancelado."
        fi
    else
        echo "Opcao invalida."
    fi
}

# ── Menu ───────────────────────────────────────

show_menu() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════╗"
        echo "║      Gerenciador de AppImages        ║"
        echo "╚══════════════════════════════════════╝"
        echo ""
        echo "1) Atualizar todos os apps"
        echo "2) Listar apps instalados e status"
        echo "3) Desinstalar um app"
        echo "4) Sair"
        echo ""
        read -rp "Escolha uma opcao: " choice

        case "$choice" in
            1) update_all ;;
            2) list_installed ;;
            3) uninstall_menu ;;
            4) echo ""; exit 0 ;;
            *) echo "Opcao invalida." ;;
        esac
        echo ""
        read -rp "Pressione Enter para continuar..."
    done
}

# ── Main ───────────────────────────────────────

update_all() {
    echo ""
    echo "Atualizador de AppImages — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Diretorio: $APP_DIR"
    echo ""

    local FAIL=0

    for entry in "${APPS_DATA[@]}"; do
        IFS='|' read -r repo filter filename label desktop icon mime icon_url <<< "$entry"
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

        local output="$APP_DIR/$filename"
        local vfile="$output.version"

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
            install_icon "$output" "$icon" "$repo" "$icon_url" && echo "  Icone instalado" || echo "  Icone nao instalado"
        fi

        if command -v xdg-settings &>/dev/null; then
            case "$label" in
                "Brave Browser"|"Chromium")
                    xdg-settings set default-web-browser "$(basename "$desktop" .desktop)" 2>/dev/null || true
                    ;;
            esac
        fi

        echo ""
    done

    command -v update-desktop-database &>/dev/null && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache "$HOME/.local/share/icons" 2>/dev/null || true

    echo "---"
    echo "Status: $([ "$FAIL" -eq 0 ] && echo "Sucesso" || echo "Falha em algum item")"
    echo "Log: $LOGFILE"
    return "$FAIL"
}

# ── Entrypoint ─────────────────────────────────

case "$MODE" in
    menu) show_menu ;;
    status) list_installed ;;
    uninstall) uninstall_app "$UNINSTALL_APP" ;;
    update) update_all ;;
esac
