 #!/bin/bash
# gnome-manager-full.sh — Oracle Linux 9.7
# Unico arquivo: Diagnóstico, Aplicação Automática e Restauração
set -euo pipefail

LOGDIR="$HOME/.local/share/gnome-optimize"
mkdir -p "$LOGDIR"

# ---------------------------------------------------------
# CONFIGURAÇÃO: Edite esta lista para definir o que desativar
# Formato: tipo:nome (user-svc, system-svc, ext, autostart)
# ---------------------------------------------------------
read -r -d '' TARGETS <<EOF || true
user-svc:tracker-miner-fs.service
user-svc:tracker-extract.service
user-svc:gsd-wacom.service
system-svc:cups.service
system-svc:abrt-journal-core.service
ext:ding@rastersoft.com
autostart:true
EOF

# ---- Helpers ----
open_log(){
    UNDO_LOG="$LOGDIR/undo-$(date +%Y%m%d-%H%M%S).log"
    echo "# Log de restauração" > "$UNDO_LOG"
}

log_cmd(){ echo "$*" >> "$UNDO_LOG"; }

safe_run(){
    echo "+ $*"
    bash -c "$*" || echo "  ! Falha ignorada"
}

# ---- Lógica de Otimização ----
apply(){
    echo "--- Iniciando Otimização Automática ---"
    sudo -v # Valida sudo uma vez
    open_log

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
        type="${line%%:*}"; val="${line#*:}"

        case "$type" in
            user-svc)
                if systemctl --user is-enabled "$val" &>/dev/null; then
                    log_cmd "systemctl --user unmask $val; systemctl --user enable --now $val"
                fi
                safe_run "systemctl --user disable --now $val &>/dev/null; systemctl --user mask $val"
                ;;
            system-svc)
                if systemctl is-enabled "$val" &>/dev/null; then
                    log_cmd "sudo systemctl unmask $val; sudo systemctl enable --now $val"
                fi
                safe_run "sudo systemctl disable --now $val &>/dev/null; sudo systemctl mask $val"
                ;;
            ext)
                log_cmd "gnome-extensions enable $val"
                safe_run "gnome-extensions disable $val"
                ;;
            autostart)
                mkdir -p ~/.config/autostart-disabled
                for f in ~/.config/autostart/*.desktop; do
                    [ -e "$f" ] || continue
                    log_cmd "mv ~/.config/autostart-disabled/$(basename "$f") ~/.config/autostart/"
                    mv "$f" ~/.config/autostart-disabled/
                done
                ;;
        esac
    done <<< "$TARGETS"
    
    echo -e "\nPronto! Log de restauração criado em: $UNDO_LOG"
}

# ---- Lógica de Restauração ----
restore(){
    local last_log
    last_log=$(ls -t "$LOGDIR"/undo-*.log 2>/dev/null | head -n 1)
    
    if [[ -z "$last_log" ]]; then
        echo "Erro: Nenhum log encontrado em $LOGDIR"
        exit 1
    fi

    echo "Restaurando do log: $last_log"
    sudo -v
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
        safe_run "$line"
    done < "$last_log"
    echo "Restauração concluída."
}

# ---- Menu Simples ----
case "${1:-}" in
    apply)   apply ;;
    restore) restore ;;
    *) echo "Uso: $0 {apply|restore}"; exit 1 ;;
esac
