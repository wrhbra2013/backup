#!/bin/bash

# ============================================
# bt-ctl.sh - Script de gerenciamento Bluetooth
# Usa bluetoothctl e seus parametros
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/var/log/bt-ctl.log"

log_msg() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_bluetooth() {
    if ! command -v bluetoothctl &>/dev/null; then
        echo -e "${RED}bluetoothctl nao encontrado. Instale bluez.${NC}"
        exit 1
    fi
}

# --- Informacoes do controlador ---
info_controller() {
    echo -e "${CYAN}=== Informacoes do Controlador ===${NC}"
    bluetoothctl show
    echo ""
}

# --- Listar dispositivos pareados ---
list_devices() {
    echo -e "${CYAN}=== Dispositivos Conhecidos ===${NC}"
    bluetoothctl devices
    echo ""
}

# --- Ligacao do Bluetooth ---
power_on() {
    echo -e "${YELLOW}Ligando Bluetooth...${NC}"
    bluetoothctl power on
    log_msg "Bluetooth ligado"
}

power_off() {
    echo -e "${YELLOW}Desligando Bluetooth...${NC}"
    bluetoothctl power off
    log_msg "Bluetooth desligado"
}

# --- Scan de dispositivos ---
scan_on() {
    echo -e "${YELLOW}Iniciando scan por 15 segundos...${NC}"
    timeout 15 bluetoothctl scan on 2>/dev/null
    echo -e "${GREEN}Scan finalizado. Dispositivos encontrados:${NC}"
    bluetoothctl devices
    log_msg "Scan executado"
}

# --- Emparelhar dispositivo ---
pair_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 pair <MAC_ADDRESS>${NC}"
        echo "Exemplo: $0 pair 67:F0:01:5D:BC:31"
        return 1
    fi
    echo -e "${YELLOW}Emparalhando com $MAC...${NC}"
    bluetoothctl pair "$MAC"
    log_msg "Tentativa de pareamento com $MAC"
}

# --- Conectar dispositivo ---
connect_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 connect <MAC_ADDRESS>${NC}"
        return 1
    fi
    echo -e "${YELLOW}Conectando a $MAC...${NC}"
    bluetoothctl connect "$MAC"
    log_msg "Tentativa de conexao com $MAC"
}

# --- Desconectar dispositivo ---
disconnect_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 disconnect <MAC_ADDRESS>${NC}"
        return 1
    fi
    echo -e "${YELLOW}Desconectando $MAC...${NC}"
    bluetoothctl disconnect "$MAC"
    log_msg "Desconectado de $MAC"
}

# --- Confiar no dispositivo ---
trust_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 trust <MAC_ADDRESS>${NC}"
        return 1
    fi
    echo -e "${YELLOW}Confiando em $MAC...${NC}"
    bluetoothctl trust "$MAC"
    log_msg "Dispositivo $MAC marcado como confiavel"
}

# --- Remover dispositivo ---
remove_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 remove <MAC_ADDRESS>${NC}"
        return 1
    fi
    echo -e "${RED}Removendo $MAC...${NC}"
    bluetoothctl remove "$MAC"
    log_msg "Dispositivo $MAC removido"
}

# --- Tornar discoverable ---
discoverable_on() {
    echo -e "${YELLOW}Tornando dispositivo visivel...${NC}"
    bluetoothctl discoverable on
    log_msg "Discoverable ligado"
}

discoverable_off() {
    echo -e "${YELLOW}Ocultando dispositivo...${NC}"
    bluetoothctl discoverable off
    log_msg "Discoverable desligado"
}

# --- Tornar pairable ---
pairable_on() {
    bluetoothctl pairable on
    echo -e "${GREEN}Pairable: ON${NC}"
}

pairable_off() {
    bluetoothctl pairable off
    echo -e "${YELLOW}Pairable: OFF${NC}"
}

# --- Informacoes de um dispositivo ---
device_info() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 info <MAC_ADDRESS>${NC}"
        return 1
    fi
    echo -e "${CYAN}=== Info: $MAC ===${NC}"
    bluetoothctl info "$MAC"
}

# --- Bloquear / Desbloquear ---
block_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 block <MAC_ADDRESS>${NC}"
        return 1
    fi
    bluetoothctl block "$MAC"
    log_msg "Dispositivo $MAC bloqueado"
}

unblock_device() {
    local MAC=$1
    if [ -z "$MAC" ]; then
        echo -e "${RED}Uso: $0 unblock <MAC_ADDRESS>${NC}"
        return 1
    fi
    bluetoothctl unblock "$MAC"
    log_msg "Dispositivo $MAC desbloqueado"
}

# --- Renomear controlador ---
set_alias() {
    local NAME=$1
    if [ -z "$NAME" ]; then
        echo -e "${RED}Uso: $0 alias <NOME>${NC}"
        return 1
    fi
    bluetoothctl system-alias "$NAME"
    log_msg "Controlador renomeado para $NAME"
}

# --- Remover alias ---
reset_alias() {
    bluetoothctl reset-alias
    log_msg "Alias resetado"
}

# --- Modo de emparelhamento ---
pairable_mode() {
    local MODE=$1
    if [ -z "$MODE" ]; then
        echo -e "${RED}Uso: $0 pairable-mode <on|off>${NC}"
        return 1
    fi
    bluetoothctl pairable "$MODE"
    log_msg "Pairable mode: $MODE"
}

# --- Menu interativo ---
interactive() {
    while true; do
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}   Gerenciador Bluetooth - Interativo   ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo "  1)  Info do controlador"
        echo "  2)  Listar dispositivos"
        echo "  3)  Ligar Bluetooth"
        echo "  4)  Desligar Bluetooth"
        echo "  5)  Scan (15s)"
        echo "  6)  Emparelhar (pair)"
        echo "  7)  Conectar"
        echo "  8)  Desconectar"
        echo "  9)  Confiar (trust)"
        echo " 10)  Remover dispositivo"
        echo " 11)  Discoverable on/off"
        echo " 12)  Pairable on/off"
        echo " 13)  Info de dispositivo"
        echo " 14)  Block/Unblock"
        echo " 15)  Renomear controlador"
        echo "  0)  Sair"
        echo -e "${CYAN}========================================${NC}"
        read -p "Opcao: " opt

        case $opt in
            1) info_controller ;;
            2) list_devices ;;
            3) power_on ;;
            4) power_off ;;
            5) scan_on ;;
            6) read -p "MAC: " mac; pair_device "$mac" ;;
            7) read -p "MAC: " mac; connect_device "$mac" ;;
            8) read -p "MAC: " mac; disconnect_device "$mac" ;;
            9) read -p "MAC: " mac; trust_device "$mac" ;;
            10) read -p "MAC: " mac; remove_device "$mac" ;;
            11)
                read -p "on/off: " mode
                if [ "$mode" = "on" ]; then discoverable_on; else discoverable_off; fi
                ;;
            12)
                read -p "on/off: " mode
                if [ "$mode" = "on" ]; then pairable_on; else pairable_off; fi
                ;;
            13) read -p "MAC: " mac; device_info "$mac" ;;
            14)
                read -p "MAC: " mac
                read -p "block/unblock: " action
                if [ "$action" = "block" ]; then block_device "$mac"; else unblock_device "$mac"; fi
                ;;
            15) read -p "Nome: " name; set_alias "$name" ;;
            0) echo "Saindo..."; exit 0 ;;
            *) echo -e "${RED}Opcao invalida${NC}" ;;
        esac
    done
}

# --- Ajuda ---
show_help() {
    echo -e "${CYAN}Uso: $0 [comando] [parametros]${NC}"
    echo ""
    echo "Comandos:"
    echo "  info                     - Mostra info do controlador"
    echo "  list                     - Lista dispositivos conhecidos"
    echo "  power on|off             - Liga/desliga Bluetooth"
    echo "  scan                     - Scan por 15 segundos"
    echo "  pair <MAC>               - Emparella com dispositivo"
    echo "  connect <MAC>            - Conecta ao dispositivo"
    echo "  disconnect <MAC>         - Desconecta dispositivo"
    echo "  trust <MAC>              - Confiar no dispositivo"
    echo "  remove <MAC>             - Remove dispositivo"
    echo "  discoverable on|off      - Visivel/invisivel"
    echo "  pairable on|off          - Permite/nega pareamento"
    echo "  info <MAC>               - Info de um dispositivo"
    echo "  block <MAC>              - Bloqueia dispositivo"
    echo "  unblock <MAC>            - Desbloqueia dispositivo"
    echo "  alias <NOME>             - Renomeia controlador"
    echo "  reset-alias              - Reseta nome do controlador"
    echo "  interactive              - Menu interativo"
    echo "  help                     - Esta ajuda"
}

# --- Main ---
check_bluetooth

case "${1:-help}" in
    info)          info_controller ;;
    list)          list_devices ;;
    power)         power_on; power_off ;;
    scan)          scan_on ;;
    pair)          pair_device "$2" ;;
    connect)       connect_device "$2" ;;
    disconnect)    disconnect_device "$2" ;;
    trust)         trust_device "$2" ;;
    remove)        remove_device "$2" ;;
    discoverable)
        if [ "$2" = "on" ]; then discoverable_on; else discoverable_off; fi
        ;;
    pairable)
        if [ "$2" = "on" ]; then pairable_on; else pairable_off; fi
        ;;
    info-dev)      device_info "$2" ;;
    block)         block_device "$2" ;;
    unblock)       unblock_device "$2" ;;
    alias)         set_alias "$2" ;;
    reset-alias)   reset_alias ;;
    interactive)   interactive ;;
    help|--help|-h) show_help ;;
    *)
        echo -e "${RED}Comando desconhecido: $1${NC}"
        show_help
        ;;
esac
