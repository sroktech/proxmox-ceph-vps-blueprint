#!/bin/sh
set -eu
echo "==> Configuring cloud-init for the Proxmox NoCloud datasource"
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-pve.cfg <<'EOF'
# Proxmox presents cloud-init config as a NoCloud config drive.
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# Some vendor images ship a file that disables cloud-init networking entirely.
# Leaving it in place means the customer VM never gets an IP.
rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
rm -f /etc/cloud/cloud.cfg.d/90_dpkg.cfg

systemctl enable cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true

echo "==> Resetting cloud-init state so it runs fresh for the customer"
# WITHOUT this the template keeps the build-time instance-id, cloud-init will
# not re-run, and the customer gets a VM with no key and no way in.
cloud-init clean --logs --seed 2>/dev/null || cloud-init clean --logs
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance 2>/dev/null || true
echo "==> cloud-init reset"
