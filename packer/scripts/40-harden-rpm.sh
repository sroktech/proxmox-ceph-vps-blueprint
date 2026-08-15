#!/bin/sh
set -eu
echo "==> Applying guest baseline hardening"
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-baseline.conf <<'EOF'
# Sane defaults for a fresh VPS. The customer owns this file and may change it.
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 6
LoginGraceTime 60
EOF
cat > /etc/sysctl.d/99-baseline.conf <<'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
EOF
echo "==> Guest hardening applied"
