#!/bin/sh
set -eu
echo "==> Cleanup: removing build credentials"
# The build key MUST NOT ship in the template.
rm -f /root/.ssh/authorized_keys
rm -f /home/*/.ssh/authorized_keys
rm -f /etc/sudoers.d/packerbuild
userdel -r packerbuild 2>/dev/null || true

echo "==> Cleanup: SSH host keys"
# Identical host keys across every customer VM enables trivial MITM
# between customers. Regenerate on first boot instead.
rm -f /etc/ssh/ssh_host_*
if [ -d /etc/systemd/system ]; then
cat > /etc/systemd/system/regen-sshd-keys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys on first boot
ConditionPathExistsGlob=!/etc/ssh/ssh_host_ed25519_key
Before=ssh.service sshd.service
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl enable regen-sshd-keys.service
fi

echo "==> Cleanup: machine-id"
# Duplicate machine-ids cause DHCP collisions and duplicate hosts in monitoring.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

echo "==> Cleanup: caches, logs, history"
if command -v apt-get >/dev/null 2>&1; then
  apt-get -y autoremove --purge
  apt-get clean
  rm -rf /var/lib/apt/lists/*
else
  dnf clean all
  rm -rf /var/cache/dnf/*
fi
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || true
unset HISTFILE

echo "==> Cleanup: final cloud-init reset (must be last)"
cloud-init clean --logs --seed 2>/dev/null || true
rm -rf /var/lib/cloud/instances/* 2>/dev/null || true

echo "==> Cleanup: zeroing free space to keep the template small"
dd if=/dev/zero of=/EMPTY bs=1M status=none 2>/dev/null || true
rm -f /EMPTY
sync
echo "==> Cleanup complete"
