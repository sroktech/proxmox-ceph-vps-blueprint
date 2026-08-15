#!/bin/sh
set -eu
echo "==> Waiting for any in-progress cloud-init / package locks"
cloud-init status --wait 2>/dev/null || true
i=0
while pgrep -x apt-get >/dev/null || pgrep -x dnf >/dev/null || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -gt 120 ] && { echo "timed out waiting for package locks"; exit 1; }
  sleep 5
done
echo "==> Ready"
