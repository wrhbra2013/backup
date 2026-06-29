#!/bin/bash
set -e

cat > /etc/sysctl.d/90-swappiness.conf <<'CONF'
vm.swappiness=10
CONF
sysctl -w vm.swappiness=10

cat > /etc/systemd/zram-generator.conf <<'CONF'
[zram0]
zram-fraction = 0.75
max-zram-size = 8192
compression-algorithm = zstd
CONF

systemctl restart systemd-zram-setup@zram0
echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true

swapon -p 100 /dev/zram0 2>/dev/null || true

sed -i 's/^UUID=2b485078-24d1-4f23-9538-807a056f3d99 none                    swap    defaults        0 0$/#UUID=2b485078-24d1-4f23-9538-807a056f3d99 none                    swap    defaults        0 0/' /etc/fstab
sed -i 's|^/swapfile none swap sw 0 0$|#/swapfile none swap sw 0 0|' /etc/fstab

swapoff /swapfile 2>/dev/null || true
swapoff /dev/sda3 2>/dev/null || true

echo "zram configurado com zstd, swappiness=10, swaps de disco desativados. Status:"
zramctl
free -m
cat /proc/swaps
