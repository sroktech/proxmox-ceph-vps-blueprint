#!/usr/bin/env bash
# Keep the last N template builds per OS. Older ones are removed so the
# template datastore does not grow without bound. Never prune below 2 —
# you need at least one previous build to roll back to.
set -euo pipefail
KEEP=3
[ "${1:-}" = "--keep" ] && KEEP="${2}"
[ "$KEEP" -lt 2 ] && { echo "refusing to keep fewer than 2 builds"; exit 1; }
: "${PVE_HOST:?}"

for OS in ubuntu-2404 debian-13 rocky-10; do
  echo "==> ${OS}: keeping newest ${KEEP}"
  ssh "root@${PVE_HOST}" "qm list --full 2>/dev/null | awk '/tpl-${OS}-/ {print \$1, \$2}'" \
    | sort -k2 -r | tail -n "+$((KEEP+1))" \
    | while read -r vmid name; do
        echo "    destroying ${name} (${vmid})"
        ssh "root@${PVE_HOST}" "qm destroy ${vmid} --purge --destroy-unreferenced-disks 1"
      done
done
