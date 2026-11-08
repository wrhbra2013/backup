#!/usr/bin/env bash

# ============================================================
#  gerar_sku_ebook.sh - Gera SKU para produtos digitais (ebook)
#
#  Formato:
#     TEMA-SUBCATEGORIA-NUMERO
#
#  Ex.: TEC-PROG-001  (Tecnologia / Programação / 1º ebook)
#
#  O número é sequencial e é acompanhado em um arquivo de
#  controle (contador). O status do nº mais recente é gravado
#  em sku_ebook_contador.txt.
# ============================================================

# Usa o diretório onde o script está em vez dos paths hardcoded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTADOR_FILE="${SCRIPT_DIR}/sku_ebook_contador.txt"

# --- Cores -----------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------------------------------------------------
# Prefixo: remove acentos/caracteres especiais, pega 3 letras
# ---------------------------------------------------------
prefixo() {
    local t="$1"
    local padrao="${2:-N/A}"
    t=$(echo "$t" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || echo "$t")
    t=$(echo "$t" | sed 's/[^A-Za-z0-9]//g' | tr '[:lower:]' '[:upper:]')
    [[ -z "$t" ]] && { echo "$padrao"; return; }
    echo "${t:0:3}"
}

# ---------------------------------------------------------
# Ler o contador atual a partir do arquivo de controle.
# Se não existir, começa em 0.
# ---------------------------------------------------------
ler_contador() {
    if [[ -f "$CONTADOR_FILE" ]]; then
        cat "$CONTADOR_FILE"
    else
        echo "0"
    fi
}

# ---------------------------------------------------------
# Incrementar e salvar o contador
# ---------------------------------------------------------
gravar_contador() {
    echo "$1" > "$CONTADOR_FILE"
}

# ---------------------------------------------------------
# Input com suporte a valor padrão
# ---------------------------------------------------------
perguntar() {
    local msg="$1" padrao="${2:-}"
    local resp
    if [[ -n "$padrao" ]]; then
        read -r -p "$(echo -e "${CYAN}${msg}${NC} [padrão: ${padrao}]: ")" resp
        resp="${resp:-$padrao}"
    else
        read -r -p "$(echo -e "${CYAN}${msg}${NC}: ")" resp
    fi
    echo "$resp"
}

# =========================================================
# MAIN
# =========================================================

echo -e "${GREEN}Gerador de SKU para EBOOK${NC}"
echo -e "Formato: ${YELLOW}TEMA-SUBCATEGORIA-NUMERO${NC} (ex.: TEC-PROG-001)"
echo

tema=$(perguntar "Tema/assunto (ex: Tecnologia)"             "GERAL")
subtema=$(perguntar "Subcategoria (ex: Programação)"          "GERAL")

contador=$(ler_contador)
novo=$((contador + 1))
numero=$(printf "%03d" "$novo")
gravar_contador "$novo"

p_tema=$(prefixo "$tema" "GER")
p_sub=$(prefixo "$subtema" "GER")

sku="${p_tema}-${p_sub}-${numero}"

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${CYAN}SKU do ebook gerado:${NC} ${GREEN}${sku}${NC}"
echo -e "${GREEN}============================================${NC}"
echo

printf "  %-18s %-8s %s\n" "Campo" "Prefixo" "Original"
printf "  %-18s %-8s %s\n" "-------" "-------" "--------"
printf "  %-18s %-8s %s\n" "Tema"          "$p_tema" "$tema"
printf "  %-18s %-8s %s\n" "Subcategoria"  "$p_sub"  "$subtema"
printf "  %-18s %-8s %s\n" "Número"        "$numero" "sequencial"

echo
read -r -p "$(echo -e "${CYAN}Salvar em arquivo de ebooks? [s/N]: ${NC}")" salvar
if [[ "${salvar,,}" == "s" ]]; then
    echo "$sku" >> "${SCRIPT_DIR}/skus_ebook.txt"
    echo -e "${GREEN}Salvo em skus_ebook.txt${NC}"
fi

echo
echo -e "${YELLOW}Próximo número será:${NC} $(printf '%03d' $((novo + 1)))"
exit 0
