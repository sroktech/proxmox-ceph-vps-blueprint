#!/bin/sh
set -eu
echo "==> Configuring serial console"
grubby --update-kernel=ALL --args="console=tty0 console=ttyS0,115200n8 net.ifnames=0"
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8 net.ifnames=0"|' /etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=2|' /etc/default/grub
grep -q '^GRUB_TERMINAL' /etc/default/grub || cat >> /etc/default/grub <<'EOF'
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOF
grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
[ -f /boot/efi/EFI/rocky/grub.cfg ] && grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
systemctl enable serial-getty@ttyS0.service
echo "==> Serial console configured"
