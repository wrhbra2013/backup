 #!/bin/bash
# auto_fix_powerprofiles_selinux.sh
# Corrige contexto e instala módulo SELinux para power-profiles-daemon

MODULE_NAME="my-powerprofiles"
AVC_FILE="/tmp/${MODULE_NAME}.avc"

echo "[*] Verificando contexto SELinux de /var/lib/sss/mc..."
ls -Zd /var/lib/sss/mc

echo "[*] Restaurando contexto padrão..."
restorecon -Rv /var/lib/sss/mc

echo "[*] Checando por AVC denials relacionados ao power-profiles-daemon..."
ausearch -c 'power-profiles-' --raw > "$AVC_FILE"

if [ -s "$AVC_FILE" ]; then
    echo "[*] Removendo módulo antigo (se existir)..."
    semodule -r "$MODULE_NAME" 2>/dev/null

    echo "[*] Gerando novo módulo SELinux..."
    audit2allow -M "$MODULE_NAME" < "$AVC_FILE"

    echo "[*] Instalando módulo com prioridade 400..."
    semodule -X 400 -i "${MODULE_NAME}.pp"

    echo "[+] Módulo $MODULE_NAME instalado com sucesso."
else
    echo "[!] Nenhum AVC denial encontrado para power-profiles-daemon. Nada a corrigir."
fi

