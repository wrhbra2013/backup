#!/bin/bash

# Script de atualização do repositório Amor Animal Marília

echo "--- Iniciando processo de atualização da VM ---"

# 1. Solicitar confirmação do usuário
read -p "Deseja realmente remover a pasta atual e clonar o repositório novamente>

if [[ "$confirmacao" == "s" || "$confirmacao" == "S" ]]; then
    
    # 2. Removendo a pasta antiga
    echo "Removendo pasta antiga: amoranimalmarilia..."
    sudo rm -Rv amoranimalmarilia
    
    # 3. Clonando o repositório atualizado
    echo "Clonando a versão mais recente do GitHub..."
    git clone https://github.com/wrhbra2013/amoranimalmarilia.git
    
    echo "--- Processo concluído com sucesso! ---"
else
    echo "Operação cancelada pelo usuário."
fi

