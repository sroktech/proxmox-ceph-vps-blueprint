#!/bin/sh
set -eu
echo "==> Updating and installing base packages"
dnf -y update
dnf -y install \
  cloud-init cloud-utils-growpart \
  qemu-guest-agent openssh-server \
  ca-certificates curl \
  chrony rsync less vim-minimal \
  nvme-cli
systemctl enable qemu-guest-agent
systemctl enable chronyd
echo "==> Base packages done"
