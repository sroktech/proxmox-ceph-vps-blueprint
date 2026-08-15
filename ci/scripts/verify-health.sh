#!/usr/bin/env bash
# Post-apply health gate. Fails the pipeline if apply left the cluster unwell.
set -euo pipefail
: "${PVE_HOST:?}"
H() { ssh -o StrictHostKeyChecking=accept-new "root@${PVE_HOST}" "$@"; }
FAILED=0
chk() { if eval "$2"; then echo "  PASS  $1"; else echo "  FAIL  $1"; FAILED=1; fi; }

chk "cluster is quorate"          'H "pvecm status" | grep -q "Quorate:.*Yes"'
chk "both corosync links up"      '[ "$(H "corosync-cfgtool -s" | grep -c "connected")" -ge 2 ]'
chk "ceph HEALTH_OK"              'H "ceph health" | grep -q "HEALTH_OK"'
chk "all PGs active+clean"        '[ "$(H "ceph pg stat" | grep -c "active+clean")" -ge 1 ]'
chk "3 mons in quorum"            '[ "$(H "ceph mon stat" | grep -o "quorum" | wc -l)" -ge 1 ]'
chk "pool size=3 min_size=2"      'H "ceph osd pool get vm-disks size" | grep -q "size: 3" && H "ceph osd pool get vm-disks min_size" | grep -q "min_size: 2"'
chk "no OSDs down"                '[ "$(H "ceph osd stat" | grep -oP "\d+(?= osds: )" | head -1)" != "" ]'
chk "pool under 70% used"         '[ "$(H "ceph df --format json" | jq -r ".pools[]|select(.name==\"vm-disks\")|.stats.percent_used")" \< "0.70" ]'
chk "EVPN peers established"      'H "vtysh -c \"show bgp l2vpn evpn summary\"" | grep -q "Established"'

[ "$FAILED" -eq 0 ] || { echo "HEALTH VERIFICATION FAILED"; exit 1; }
echo "HEALTH VERIFICATION PASSED"
