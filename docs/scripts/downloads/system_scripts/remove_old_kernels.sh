#!/bin/bash
#
# remove-old-kernels.sh
# Safely remove old kernels on Oracle Linux 9.6
# Keeps the current kernel and one previous version

set -euo pipefail

echo "=== Current running kernel: $(uname -r) ==="
echo "Listing installed kernels..."
rpm -qa | grep '^kernel' | grep -v 'headers\|devel\|tools' | sort -V

echo
echo "Removing old kernels, keeping the latest 2..."
sudo dnf remove -y $(dnf repoquery --installonly --latest-limit=-2 -q)

echo
echo "Cleaning up cached packages..."
sudo dnf clean all
sudo rm -rf /var/cache/dnf

echo
echo "Done! Remaining kernels:"
rpm -qa | grep '^kernel' | grep -v 'headers\|devel\|tools' | sort -V
