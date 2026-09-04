#!/usr/bin/env bash

VERSION="1.0.0"

# ============================================================
#  gerar_sku.sh - Gera SKU no padrão comercial
#
#  Formato padrão comercial:
#     CATEGORIA-SUBCATEGORIA-CARACTERISTICA-COR-TAMANHO
#
#  Cada campo é representado por um prefixo (abreviação).
#  Ex.: CAMISETA MASCULINA BÁSICA PRETA M -> CAM-MASC-BAS-PRE-M
# ============================================================

set -euo pipefail

# --- Cores para output --------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------
# Função: extrair prefixo de um texto
#   - Remove acentos, espaços, caracteres especiais
#   - Se o campo for vazio, retorna um valor padrão
# ------------------------------------------------------------
gerar_prefixo() {
    local texto="$1"
    local padrao="${2:-N/A}"

    # Remove acentos
    texto=$(echo "$texto" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || echo "$texto")

    # Remove caracteres especiais e espaços, deixa letras/numero
    texto=$(echo "$texto" | sed 's/[^A-Za-z0-9]//g' | tr -d ' ')

    # Converte para maiúsculas
    texto=$(echo "$texto" | tr '[:lower:]' '[:upper:]')

    if [[ -z "$texto" ]]; then
        echo "$padrao"
        return
    fi

    # Pega as primeiras 3 letras
    echo "${texto:0:3}"
}

# ------------------------------------------------------------
# Função: ler input do usuário (com suporte a valor padrão)
# ------------------------------------------------------------
perguntar() {
    local msg="$1"
    local padrao="${2:-}"

    if [[ -n "$padrao" ]]; then
        read -r -p "$(echo -e "${CYAN}$msg${NC} [padrão: ${padrao}]: ")" resposta
        resposta="${resposta:-$padrao}"
    else
        read -r -p "$(echo -e "${CYAN}$msg${NC}: ")" resposta
    fi

    echo "$resposta"
}

# ------------------------------------------------------------
# Função: máscara de conversão de cor para código
# ------------------------------------------------------------
codigo_cor() {
    local cor="$1"
    cor=$(echo "$cor" | tr '[:upper:]' '[:lower:]' | sed 's/[áàâã]/a/g; s/[éèê]/e/g; s/[íì]/i/g; s/[óòôõ]/o/g; s/[úùû]/u/g; s/[ç]/c/g')

    case "$cor" in
        preto|black)           echo "PRE" ;;
        branco|white)          echo "BRA" ;;
        vermelho|red)          echo "VER" ;;
        azul|blue)             echo "AZU" ;;
        verde|green)           echo "VERD" ;;
        amarelo|yellow)        echo "AMA" ;;
        rosa|pink)             echo "ROS" ;;
        roxo|purple|violeta)   echo "ROX" ;;
        laranja|orange)        echo "LAR" ;;
        cinza|gray|grey)       echo "CIN" ;;
        marrom|brown)          echo "MAR" ;;
        bege|beige)            echo "BEG" ;;
        dourado|gold)          echo "DOU" ;;
        prata|prateado|silver) echo "PRA" ;;
        *)                     gerar_prefixo "$1" ;;
    esac
}

# ------------------------------------------------------------
# Função: máscara de conversão de tamanho
# ------------------------------------------------------------
codigo_tamanho() {
    local tam="$1"
    tam=$(echo "$tam" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Za-z0-9]//g')

    case "$tam" in
        P)        echo "P" ;;
        M)        echo "M" ;;
        G)        echo "G" ;;
        GG)       echo "GG" ;;
        XG|XGG)   echo "XG" ;;
        UNICO)    echo "UNI" ;;
        *)        echo "${tam:0:3}" ;;
    esac
}

# ------------------------------------------------------------
# Função: gerar um sufixo aleatório (evita duplicidade total)
# ------------------------------------------------------------
gerar_sufixo() {
    echo "$(date +%s%N | sha256sum | tr -d 'a-f0-9 ' | head -c 2 | tr '[:lower:]' '[:upper:]')"
}

# ------------------------------------------------------------
# Banner de apresentação
# ------------------------------------------------------------
mostrar_banner() {
    cat <<"EOF"
  ____  _  _  _  __   __  ____
 / ___|| || || | \ \ / / |  _ \
| |   | | || | __\ V /  | |_) |
| |___| |__' |/ _ \| |   |  _ <
 \____|_|  |_| \___/|_|   |_| \_\  -- Gerador de SKU v1.0
EOF
    echo -e "${GREEN}Formato de saída:${NC} CATEGORIA-SUBCATEGORIA-CARACTERISTICA-COR-TAMANHO"
    echo
}

# ============================================================
# MAIN
# ============================================================

mostrar_banner

echo -e "${YELLOW}Preencha os dados do produto para gerar o SKU.${NC}"
echo

# --- Coleta de inputs -------------------------------------
categoria=$(perguntar "Categoria (ex: Camiseta)"              "GERAL")
subcategoria=$(perguntar "Subcategoria (ex: Masculina)"        "BÁSIC")
caracteristica=$(perguntar "Característica (ex: Básica)"       "CLÁSS")
cor=$(perguntar "Cor (ex: Preta)"                              "PRETA")
tamanho=$(perguntar "Tamanho (ex: M)"                          "UNI")

# --- Geração de prefixos ------------------------------------
p_cat=$(gerar_prefixo "$categoria" "GER")
p_sub=$(gerar_prefixo "$subcategoria" "BAS")
p_car=$(gerar_prefixo "$caracteristica" "CLA")

# Usa máscara inteligente para cor e tamanho (mais amigável)
p_cor=$(codigo_cor "$cor")
p_tam=$(codigo_tamanho "$tamanho")

# --- Monta e exibe o SKU ------------------------------------
sku="${p_cat}-${p_sub}-${p_car}-${p_cor}-${p_tam}"

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${CYAN}SKU gerado:${NC} ${GREEN}${sku}${NC}"
echo -e "${GREEN}============================================${NC}"
echo

# -- Resumo dos inputs (debug / conferência) ----------------
echo -e "${YELLOW}Resumo:${NC}"
printf "  %-18s %-8s %s\n" "Campo" "Prefixo" "Original"
printf "  %-18s %-8s %s\n" "-------" "-------" "--------"
printf "  %-18s %-8s %s\n" "Categoria"       "$p_cat" "$categoria"
printf "  %-18s %-8s %s\n" "Subcategoria"    "$p_sub" "$subcategoria"
printf "  %-18s %-8s %s\n" "Característica"  "$p_car" "$caracteristica"
printf "  %-18s %-8s %s\n" "Cor"             "$p_cor" "$cor"
printf "  %-18s %-8s %s\n" "Tamanho"         "$p_tam" "$tamanho"

echo

# --- Opção de copiar para clipboard ------------------------
read -r -p "$(echo -e "${CYAN}Copiar SKU para a área de transferência? [s/N]: ${NC}")" copiar
if [[ "${copiar,,}" == "s" ]]; then
    if command -v xclip >/dev/null 2>&1; then
        echo -n "$sku" | xclip -selection clipboard
        echo -e "${GREEN}SKU copiado!${NC}"
    elif command -v xsel >/dev/null 2>&1; then
        echo -n "$sku" | xsel --clipboard --input
        echo -e "${GREEN}SKU copiado!${NC}"
    elif command -v wl-copy >/dev/null 2>&1; then
        echo -n "$sku" | wl-copy
        echo -e "${GREEN}SKU copiado!${NC}"
    else
        echo -e "${RED}Ferramenta de clipboard não encontrada (xclip/xsel/wl-copy).${NC}"
    fi
fi

# --- Opção de salvar em arquivo ----------------------------
read -r -p "$(echo -e "${CYAN}Salvar SKU em arquivo skus.txt? [s/N]: ${NC}")" salvar
if [[ "${salvar,,}" == "s" ]]; then
    echo "$sku" >> "skus.txt"
    echo -e "${GREEN}SKU salvo em skus.txt${NC}"
fi

echo -e "${GREEN}Pronto!${NC}"
exit 0
