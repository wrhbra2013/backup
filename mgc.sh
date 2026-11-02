#!/bin/bash

USER="debian"
HOST="201.54.22.122"

EMBEDDED_KEY_B64="LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUNGd0FBQUFkemMyZ3RjbgpOaEFBQUFBd0VBQVFBQUFnRUF0UDhaSWRQbEJ5TEhYM3V4K0c1dkJQTCtIV1dZNmJSY2IwVm5GdkMrTjVodzhRc2k2RGtJCkw5RDIza3VZRkxJemNCc3NmYk00TDFiUUdXSHY1K2FaL21jUzUzUmlVK2JJa04xVzBHTk5BRXJ0a3pOMFM1U1dta2Y3N1kKVjlKU3Q3dEVrSnJ0czIwYlZ3N0p2RjRpS0lhd1VUQUFkMVl0OGZxSXRYNzUydExsYjg5SVdreUJIeTRnOHN2VjdFRjVOZwp6T0p5RTNrbVlxQWVBbXZqQ2lreVpNQU5Dbjd1dWIzUWxkTmd0Yld2SnBXK2p5Qkh5Vk9TWW9nNEkvdWp4dHd5eXR1MHBHCkF6YXhSWEFSZkZNNHRFNDNVRW9TOGpISEFlaGdBdWMzRGQ3ZmhoaWp2T1h5TmcrWXZMYzFZeUI2VWthNFBhWHdzaEJkSi8Ka2Y1dFBBWUIzZDU0MDNUeFNDUkxiMmkvVC9rMnhzdnE0eGFwOTBjVytJQWdjNmVtc0lndk5qd2FpazUrZUIwYjBBWlJvcQpVYkpWbkx6SUxDR0tpcTVIVjR2UThtWmxZZU9iak52cHErSHhKYVdYTEpKaEdkbVllUGJOWjh0STAvREpkdThtTFJkQk9lCkVONkNpT2FMOTBzTTNjM3FMTXB4S3Y1NTg0YXZyL2xVRzBSVGVtN3VCemhBVEtSM0dsRjFlYWVZTGczV0V2bi9KelhIanMKRHZkaHRUVEZDUTlUT0Rvblp2ekpQVkdjUCs0QU5zUUpHZHI0MmNXd091bDRkV1pNT2hPNlJzL0RjTUExejFoMTJMbS81RApGYkZVNXlTWjRqTHJudEw2NmFDVmI4MThpK0VnSjl5QzhINnB5VlZFT082dU5mQjkwYjlCcFQ3NklqbmFKUkllc3lvMDNoCjBBQUFkWUxacGpEaTJhWXc0QUFBQUhjM05vTFhKellRQUFBZ0VBdFA4WklkUGxCeUxIWDN1eCtHNXZCUEwrSFdXWTZiUmMKYjBWbkZ2QytONWh3OFFzaTZEa0lMOUQyM2t1WUZMSXpjQnNzZmJNNEwxYlFHV0h2NSthWi9tY1M1M1JpVStiSWtOMVcwRwpOTkFFcnRrek4wUzVTV21rZjc3WVY5SlN0N3RFa0pydHMyMGJWdzdKdkY0aUtJYXdVVEFBZDFZdDhmcUl0WDc1MnRMbGI4CjlJV2t5Qkh5NGc4c3ZWN0VGNU5nek9KeUUza21ZcUFlQW12akNpa3laTUFOQ243dXViM1FsZE5ndGJXdkpwVytqeUJIeVYKT1NZb2c0SS91anh0d3l5dHUwcEdBemF4UlhBUmZGTTR0RTQzVUVvUzhqSEhBZWhnQXVjM0RkN2ZoaGlqdk9YeU5nK1l2TApjMVl5QjZVa2E0UGFYd3NoQmRKL2tmNXRQQVlCM2Q1NDAzVHhTQ1JMYjJpL1QvazJ4c3ZxNHhhcDkwY1crSUFnYzZlbXNJCmd2Tmp3YWlrNStlQjBiMEFaUm9xVWJKVm5MeklMQ0dLaXE1SFY0dlE4bVpsWWVPYmpOdnBxK0h4SmFXWExKSmhHZG1ZZVAKYk5aOHRJMC9ESmR1OG1MUmRCT2VFTjZDaU9hTDkwc00zYzNxTE1weEt2NTU4NGF2ci9sVUcwUlRlbTd1QnpoQVRLUjNHbApGMWVhZVlMZzNXRXZuL0p6WEhqc0R2ZGh0VFRGQ1E5VE9Eb25adnpKUFZHY1ArNEFOc1FKR2RyNDJjV3dPdWw0ZFdaTU9oCk82UnMvRGNNQTF6MWgxMkxtLzVERmJGVTV5U1o0akxybnRMNjZhQ1ZiODE4aStFZ0o5eUM4SDZweVZWRU9PNnVOZkI5MGIKOUJwVDc2SWpuYUpSSWVzeW8wM2gwQUFBQURBUUFCQUFBQ0FBNEhQWlB0SC9HekpOL0dMdytSdzZJUEVWb0c3MWloeFk1TQpRMGE0WnczWkQxdm5ZSSsrSjkvSTR2RnN5MzlESnBCNFVyVDFhSlBtdHg5WWcyY21iT1lXYUJVdlpKV2JMQTFxVWxtNWNKClRtdWM0d2JVR1VaUzNWQ1hZcDQvNjNCWkgrSFRXRHdSWjA2U2sxazV0STBPajJqamZ3M0F6TFBXRnJWMmYzZ1I0MzJNZzgKK1g0V1FneDZYNTNYMC92OXpNRmtoYkh6c0dGeGhwSHFlY0RtVzRVS2k1ZzJLVnVWRmk4ZW9IN0U4NnZhYkZnY2lPUFdTZQpEQUxSWEE0YnMrZ3VOTkx3MlVkVGZGN2s1ajRNRnplR1htd25LWnZDOXVremNRbVlrU0JPbDJXRjBGOEtOWUV5S1VUck1FClNjRms3OU16ZDMvcFZXaGxuY1NiZ3l6bFRFeWJxcWRwTG9acFBYN2IzYi9zMEZKZXVOd1lQaVlDZ09IT3FSZU8vbXN4eDUKc0lReEpFR2o2cmhCWjVLSFNGRUtwbzdsVnUwWDkxcXVaUVFDdnVrMGgxQmpzNXpkZ3JQeEZ2b3JUazJYUnFEalF1dWFuZQpoNkpOTzVxcXZoQzFtRFFiNGMrakFNMU51YjlNeThpaEFPVDZRRXJ1M0FqTVhyeGlPM1ZmRXdFbXMzci9PRXdOSzhhKy9qCnJTbldJVUI4SVI1TnB6b0ZrTy9sbkhsVHlNdXd1VXdSNjVlejVyejNOUncwNWgyV3NpWmtwYW1rVXBCMnV0clh3SlRsY0wKN0ZYTUZzYnAvWlFNbkdnMmlqa0VwL21oampUVFVnWFFUYTJZbStQY3FMeTNxU0t5M0ljTC9Fa2U0eW0waWtVMnJTY0ZubwppNnQvWlJ5YUFXb1BtelZaOGpBQUFCQVFDTTNRM1F3VlVydWc3aGErbm5iVHBLcEkvSlNtaDFBZHV5RVRyZEljbmJwTUQ2Cks0TEtKNmFucGpaY0kvTTlrZW5QeVUxdGFPV1Y3amtZSlZCY253WlZ5dS8yY1MrMnJ0elY0bVJOeVB1aG1PT1VtMUZiK0MKMGo3NGczRHdHcTA0Qi9EdVZSV2xCMnkwem9iK202V0dMWU01WURXVThIS2V1cVJXaTRFdm02QVZBK0RlendHTnJJaHpJWApzcHIyYUo1ZzdqLzBtcUZGYkRZSER4ZWd1ZWtxTjBmMDY5MnU2NlJvamdhMjZFZTNqQ0l3b0w3aVFPM2R4WG1uU0kxaHoxCmtDeG1YVWN2c1pNK09XdDRMSm5BSUp0US9KWFFxWkdjVWRFN1kwa1ZLbGNVY3hMaS80UWtaaUNxVGhPbG1sdmwxVmhUc2oKSHIxZkszRnprQlp3QkVQZ0FBQUJBUUQ5ZWlsYkkxb1Foc1Q4OVVwUjB1V1ByemkvRzdhU3NyVjBHbHkwRmVOOWdoaEhZVApJOWNWbUxFZTZhU3Q2d2E2Z0NxWDlPSGs1REN6NnZlTFJtUWJFTzQwcTlyZ2p2RUdUNmxaTnlheGlWdHZlR1VvQTF6RVc1CkVJMTVPQVNQSkx6Q2hxNUpTYThiVTgvOG10bEwvNk5FdXVGSFVrMnZieVRRc2tiSldTSjlqWHZ5Tk5hdXJyUWxrcnAxdWwKNE5jVkZUenUrT3RFVWpYeWJBL2pMZEV4RjdiOXR3V2Z2dGtrZFhNY0tHQ0Q4azFhN2l3VnJBZm1ZUTk1VmQ0emViVitXNwpPbGpQL09hREMxaEpld0lXQjVEMUJIWkVLNWtQcEdIaE1LOFMvaitUL3NCVFdwdVU4SGkzOHNGeHdXcjBiNGoyZUhoekxsCndaSGJMS0dBK3FEcllQQUFBQkFRQzJ6RU1MTjV4K1hiaXcydVFWelJwY0ppZUc4WUFNVVV2ZFZhSUZyMklwVGJKV0ZzZ2UKaUVldXdMbzVnV0JkOVg2ZTQ3QW4zZ01qTkkwbFo5SVhPdjB1Z0FyczI0V0pDdlNMaHZVL1VxeXE2cnB6cHBTU1ROcUptSwpxWU45QThHdWNLUEIvd3Bmazl2MndaTWVvUEZPWHlOTzQxZ1lhZnFTSWF0SEowRGVsNzNiTDZSK0FHa3dHREFFTzUxT2hNClRWM05RRTFta3oyTmtSUFBhRjdHc2ZYNU5SZU9RNVQ1aHExZkNUdkZoV3V6SGNzbVFCWmx5R2x6U2E2c2p3QlJZcDEwZ2UKa0Jub25wbjNIbU0xOVdOTFBUTmd4VE04Z1BBeE04bGFRWmZXV29MdDR6RnlaK3d0d3ZWWVRvdENnLy8veCtCRC8xeExkWgpOZW5XNExKMEQvVVRBQUFBSEhkaGJtUmxja0JzYjJOaGJHaHZjM1F1Ykc5allXeGtiMjFoYVc0QkFnTUVCUVk9Ci0tLS0tRU5EIE9QRU5TU0ggUFJJVkFURSBLRVktLS0tLQo="

restore_key() {
    local key_file
    key_file=$(mktemp /tmp/ssh_key_XXXXXX)
    echo "$EMBEDDED_KEY_B64" | openssl base64 -d -A > "$key_file" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "ERRO: Falha ao decodificar a chave embutida" >&2
        exit 1
    fi
    chmod 600 "$key_file"
    echo "$key_file"
}

connect() {
    local key_file
    key_file=$(restore_key)
    ssh -i "$key_file" -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$USER@$HOST"
    local rc=$?
    rm -f "$key_file"
    exit $rc
}

download() {
    local key_file remote_path local_path
    key_file=$(restore_key)
    remote_path="${1:-}"
    local_path="${2:-.}"

    if [[ -z "$remote_path" ]]; then
        read -rp "Caminho do arquivo no servidor: " remote_path
        read -rp "Destino local (Enter para o diretorio atual): " local_path
        local_path="${local_path:-.}"
    fi

    scp -i "$key_file" -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$USER@$HOST:$remote_path" "$local_path"

    local rc=$?
    rm -f "$key_file"
    exit $rc
}

arquitetura() {
    local key_file
    key_file=$(restore_key)
    ssh -i "$key_file" -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$USER@$HOST" '
        echo "== Arquitetura =="
        uname -m; uname -r
        lscpu | grep -E "Architecture|CPU\(s\)|Model name" | head -5
        echo "== Memoria =="
        free -h | grep -E "Mem|Swap"
        echo "== Disco =="
        df -h / | tail -1
        echo "== Uptime / Load =="
        uptime
        echo "== Containers =="
        docker ps --format "{{.Names}}\t{{.Image}}" 2>/dev/null || sudo docker ps --format "{{.Names}}\t{{.Image}}" 2>/dev/null
        echo "== Docker imagens =="
        docker image ls --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" 2>/dev/null || sudo docker image ls --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" 2>/dev/null
    '

    local rc=$?
    rm -f "$key_file"
    exit $rc
}

disco() {
    local key_file
    key_file=$(restore_key)
    ssh -i "$key_file" -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$USER@$HOST" '
        echo "== Uso geral =="
        df -h /
        echo ""
        echo "== Top 15 maiores diretorios (raiz) =="
        sudo du -h --max-depth=1 / 2>/dev/null | sort -rh | head -15
        echo ""
        echo "== /var detalhado =="
        sudo du -h --max-depth=2 /var 2>/dev/null | sort -rh | head -15
        echo ""
        echo "== Docker volumes =="
        docker system df -v 2>/dev/null | head -30 || sudo docker system df -v 2>/dev/null | head -30
        echo ""
        echo "== Docker images detalhado =="
        docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null || sudo docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null
        echo ""
        echo "== Containers (logs grandes) =="
        for c in $(docker ps -q 2>/dev/null); do
            name=$(docker inspect --format "{{.Name}}" $c 2>/dev/null)
            size=$(docker inspect --format "{{.LogPath}}" $c 2>/dev/null | xargs sudo du -h 2>/dev/null | tail -1)
            echo "$name -> log: $size"
        done
    '

    local rc=$?
    rm -f "$key_file"
    exit $rc
}

upload() {
    local key_file local_path remote_path
    key_file=$(restore_key)
    local_path="${1:-}"
    # Default: upload para /home/ do sistema (raiz do home).
    # Para manter o comportamento antigo (/home/debian), passe /home/debian/ como segundo argumento.
    remote_path="${2:-/home/$USER/}"

    if [[ -z "$local_path" ]]; then
        read -rp "Caminho do arquivo/local no seu PC: " local_path
        local_path="${local_path:-.}"
    fi

    if [[ -z "$remote_path" ]]; then
        read -rp "Caminho de destino no servidor (Enter para /home/debian/): " remote_path
        remote_path="${remote_path:-/home/$USER/}"
    fi

    scp -i "$key_file" -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$local_path" "$USER@$HOST:$remote_path"

    local rc=$?
    rm -f "$key_file"
    exit $rc
}



arquivos() {
    local action="${1:-}"
    local key_file="$HOME/.ssh/mgc_key"
    local mount_dir="$HOME/servidor_mgc"

    if [[ "$action" == "desmontar" || "$action" == "umount" ]]; then
        if mountpoint -q "$mount_dir"; then
            fusermount -u "$mount_dir" && echo "Desmontado: $mount_dir"
        else
            echo "Nada montado em $mount_dir"
        fi
        exit $?
    fi

    mkdir -p "$(dirname "$key_file")"
    if [[ ! -s "$key_file" ]]; then
        echo "$EMBEDDED_KEY_B64" | openssl base64 -d -A > "$key_file" 2>/dev/null
        chmod 600 "$key_file"
    fi

    command -v thunar >/dev/null 2>&1 || { echo "ERRO: thunar nao encontrado" >&2; exit 1; }

    if command -v sshfs >/dev/null 2>&1; then
        mkdir -p "$mount_dir"
        if ! mountpoint -q "$mount_dir"; then
            sshfs -o IdentityFile="$key_file" \
                  -o PasswordAuthentication=no \
                  -o StrictHostKeyChecking=accept-new \
                  -o ConnectTimeout=5 \
                  -o reconnect,ServerAliveInterval=15 \
                  "$USER@$HOST:/home/$USER" "$mount_dir" || { echo "ERRO: falha ao montar via sshfs" >&2; exit 1; }
        fi
        echo "Servidor montado em: $mount_dir"
        thunar "$mount_dir" >/dev/null 2>&1 &
    else
        echo "sshfs ausente; usando sftp:// via GVFS (requer gvfs-backends)"
        thunar "sftp://$USER@$HOST/" >/dev/null 2>&1 &
    fi
    exit 0
}

case "${1:-}" in
    download|dl|-d|--download)
        download "$2" "$3"
        ;;
    upload|ul|-u|--upload)
        upload "$2" "$3"
        ;;
    arquitetura|arch|-a|--arquitetura)
        arquitetura
        ;;
    disco|disk|-g|--disco)
        disco
        ;;
    arquivos|files|-t|--thunar)
        arquivos "$2"
        ;;
    *)
        connect
        ;;
esac
