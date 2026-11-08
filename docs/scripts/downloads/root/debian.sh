#!/bin/bash
set -e

# 1. Definir o nome da pasta de trabalho (ao lado deste script)
BASE_DIR="$(dirname "$(readlink -f "$0")")/build-debian"
mkdir -p "$BASE_DIR/auto"
mkdir -p "$BASE_DIR/config/package-lists"

cd "$BASE_DIR"

# 2. Criar o script auto/config (baseado no seu recorte)
cat <<EOF > auto/config
#!/bin/sh
set -e

lb config noauto \\
--mode debian \\
--architectures amd64 \\
--debian-installer live \\
--archive-areas "main contrib non-free non-free-firmware" \\
--apt-indices true \\
--memtest none \\
"\${@}"
EOF

chmod +x auto/config

# 3. Criar a lista de pacotes (my-list.list.chroot)
cat <<EOF > config/package-lists/my-list.list.chroot
xserver-xorg
xserver-xorg-video-intel
intel-microcode
i965-va-driver
intel-hdcp
firmware-intel-sound
firmware-zd1211
intel-media-va-driver
firmware-iwlwifi
net-tools
wireless-tools
wpasupplicant
lxde
chromium
yt-dlp
default-jre
nodejs
npm
idle
python3-full
python3-pip
EOF

# 4. Iniciar a montagem (Build)
echo "Iniciando a configuração e build da ISO..."
sudo lb clean --purge
lb config
sudo lb build

echo "Processo concluído! A ISO deve estar na pasta: $BASE_DIR"
