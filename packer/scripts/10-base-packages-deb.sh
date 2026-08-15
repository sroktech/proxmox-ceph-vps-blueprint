#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "==> Updating and installing base packages"
apt-get update
apt-get -y dist-upgrade
apt-get -y install \
  cloud-init cloud-guest-utils cloud-initramfs-growroot \
  qemu-guest-agent openssh-server \
  ca-certificates curl gnupg \
  chrony rsync less vim-tiny \
  nvme-cli
apt-get -y purge snapd 2>/dev/null || true
systemctl enable qemu-guest-agent
systemctl enable chrony
echo "==> Base packages done"
