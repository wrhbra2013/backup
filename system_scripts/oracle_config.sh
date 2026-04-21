#!/bin/bash

# Nome do script: config_ol9.sh
# Descrição: Instala EPEL, RPM Fusion e atualiza o sistema no Oracle Linux 9.x
# Requer execução como root (sudo)

echo "🚀 Iniciando configuração do sistema Oracle Linux 9.5..."

# --- 1. Verificação de Permissão ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Este script deve ser executado como root. Use 'sudo ./config_ol9.sh'"
  exit 1
fi

# --- 2. Instalação do Repositório EPEL ---
echo "---"
echo "✅ 1/4: Instalando o repositório EPEL..."
dnf install -y oracle-epel-release-el9
if [ $? -ne 0 ]; then
  echo "❌ Falha ao instalar o pacote 'oracle-epel-release-el9'. Abortando."
  exit 1
fi
echo "EPEL configurado com sucesso."

# --- 3. Habilitar CRB (CodeReady Linux Builder) e Instalar RPM Fusion ---
echo "---"
echo "✅ 2/4: Habilitando CRB e instalando RPM Fusion..."

# Habilita o CRB, necessário para algumas dependências do RPM Fusion
dnf config-manager --enable ol9_codeready_builder

# Instala os pacotes de configuração RPM Fusion (Free e Nonfree)
# O uso de --nogpgcheck é comum para este tipo de instalação inicial de repositórios
dnf install -y --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm

if [ $? -ne 0 ]; then
  echo "⚠️ Aviso: Falha ao instalar os pacotes RPM Fusion. Prosseguindo para a atualização."
fi
echo "RPM Fusion configurado (se a instalação foi bem-sucedida)."

# --- 4. Atualização do Cache DNF ---
echo "---"
echo "✅ 3/4: Limpando o cache e sincronizando repositórios..."
dnf clean all
dnf makecache
echo "Cache DNF atualizado."

# --- 5. Atualização Completa do Sistema ---
echo "---"
echo "✅ 4/4: Iniciando a atualização completa do sistema (dnf update)..."
dnf update -y

if [ $? -ne 0 ]; then
  echo "❌ A atualização do sistema falhou. Verifique as mensagens de erro acima."
  exit 1
fi

# --- 6. Conclusão ---
echo "---"
echo "🎉 Configuração e atualização concluídas com sucesso!"
echo "Os repositórios EPEL e RPM Fusion foram instalados e o sistema está atualizado."

# Fim do script
