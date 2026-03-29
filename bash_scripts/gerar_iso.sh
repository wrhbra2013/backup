 #!/bin/bash

# Este script configura repositórios adicionais no Oracle Linux 10 (OL10)

echo "--- 1. Verificando Repositórios Oficiais da Oracle (OL10) ---"

# Os repositórios ol10_baseos_latest, ol10_appstream e ol10_UEKR8
# são geralmente habilitados por padrão no Oracle Linux.
# O CodeReady Builder (necessário para dependências do RPM Fusion) precisa ser habilitado:
echo "Habilitando o repositório CodeReady Builder (ol10_codeready_builder)..."
sudo dnf config-manager --enable ol10_codeready_builder

# Atualiza o índice de pacotes
sudo dnf check-update

echo ""
echo "--- 2. Adicionando Repositório EPEL (Extra Packages for Enterprise Linux) ---"

# Instala o pacote de release do EPEL para a versão 10 do Enterprise Linux (EL10)
# que é o upstream do Oracle Linux.
echo "Instalando o pacote epel-release para EL10..."
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

# Habilita o repositório EPEL mantido pela Oracle, que espelha o EPEL oficial.
# O pacote acima pode já ter feito isso, mas este comando garante a ativação.
echo "Garantindo que o repositório EPEL da Oracle esteja habilitado (ol10_developer_EPEL)..."
sudo dnf config-manager --enable ol10_developer_EPEL

echo ""
echo "--- 3. Adicionando Repositórios RPM Fusion (Free e Non-free) ---"

# O RPM Fusion usa a versão principal do RHEL (10) para encontrar o RPM correto.
# A variável $(rpm -E %rhel) resolve para '10'.
echo "Instalando RPM Fusion Free e Non-free para EL10..."
sudo dnf install -y --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

echo ""
echo "--- 4. Conclusão e Limpeza ---"

# Limpa o cache do DNF e verifica a lista de repositórios ativados.
echo "Limpando o cache do DNF e listando repositórios habilitados..."
sudo dnf clean all
sudo dnf repolist

echo ""
echo "Configuração de repositórios concluída no Oracle Linux 10!"
echo "Execute 'sudo dnf upgrade' para atualizar o sistema com os novos pacotes."
