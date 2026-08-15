#!/usr/bin/env bash
# Clone a freshly built template, boot it, assert it is actually usable,
# then destroy it. Failing this stage must fail the pipeline.
set -euo pipefail

: "${PVE_HOST:?set PVE_HOST}"
: "${PVE_TOKEN:?set PVE_TOKEN}"
: "${TEMPLATE_ID:?set TEMPLATE_ID}"
TEST_VMID="${TEST_VMID:-9999}"
REPORT=validation-report.txt
: > "$REPORT"

pass() { echo "  PASS  $1" | tee -a "$REPORT"; }
fail() { echo "  FAIL  $1" | tee -a "$REPORT"; FAILED=1; }
FAILED=0

api() { curl -sSf -H "Authorization: PVEAPIToken=${PVE_TOKEN}" "$@"; }

cleanup() {
  echo "==> Destroying test VM ${TEST_VMID}"
  ssh "root@${PVE_HOST}" "qm stop ${TEST_VMID} --skiplock 2>/dev/null; sleep 3; qm destroy ${TEST_VMID} --purge --destroy-unreferenced-disks 1" || true
}
trap cleanup EXIT

echo "==> Cloning ${TEMPLATE_ID} -> ${TEST_VMID}"
ssh "root@${PVE_HOST}" "qm clone ${TEMPLATE_ID} ${TEST_VMID} --name imgtest --full 1"
ssh "root@${PVE_HOST}" "qm set ${TEST_VMID} --sshkey /root/.ssh/imgtest.pub --ipconfig0 ip=dhcp --ciuser imgtest --scsi0 vm-disks:vm-${TEST_VMID}-disk-0,size=20G"
ssh "root@${PVE_HOST}" "qm start ${TEST_VMID}"

echo "==> Waiting for guest agent (max 90s)"
for i in $(seq 1 18); do
  if ssh "root@${PVE_HOST}" "qm agent ${TEST_VMID} ping" >/dev/null 2>&1; then break; fi
  sleep 5
done
ssh "root@${PVE_HOST}" "qm agent ${TEST_VMID} ping" >/dev/null 2>&1 \
  && pass "boots within 90s and guest agent responds" \
  || fail "guest agent did not respond within 90s"

IP=$(ssh "root@${PVE_HOST}" "qm guest cmd ${TEST_VMID} network-get-interfaces" \
     | jq -r '.[]|select(.name!="lo")|."ip-addresses"[]?|select(."ip-address-type"=="ipv4")|."ip-address"' | head -1)
[ -n "$IP" ] && pass "guest reports an IPv4 address ($IP)" || fail "no IPv4 reported"

G() { ssh -o StrictHostKeyChecking=no -i /root/.ssh/imgtest "imgtest@${IP}" "$@"; }

G "cloud-init status" | grep -q "done" && pass "cloud-init completed" || fail "cloud-init not done"
G "cloud-init analyze blame 2>&1 | grep -ci fail" | grep -q '^0$' && pass "no cloud-init failures" || fail "cloud-init reported failures"
[ -n "$(G 'cat /etc/machine-id')" ] && pass "machine-id populated on first boot" || fail "machine-id empty"
G "sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub" >/dev/null && pass "host keys regenerated" || fail "host keys missing"
G "test \$(sudo grep -c . /root/.ssh/authorized_keys 2>/dev/null || echo 0) -eq 0" && pass "no build key left in image" || fail "BUILD KEY PRESENT IN IMAGE"
G "sudo systemctl is-enabled serial-getty@ttyS0" | grep -q enabled && pass "serial console enabled" || fail "serial console not enabled"
G "getent hosts deb.debian.org >/dev/null" && pass "DNS resolution works" || fail "DNS broken"
G "curl -sSf -m 10 -o /dev/null https://deb.debian.org" && pass "outbound IPv4 works" || fail "no outbound IPv4"
# Catches the very common "customer ordered 200GB, got 10GB" bug.
ROOTGB=$(G "df -BG --output=size / | tail -1 | tr -dc 0-9")
[ "${ROOTGB:-0}" -ge 18 ] && pass "root filesystem grew to disk size (${ROOTGB}G of 20G)" || fail "root did not grow (${ROOTGB}G of 20G) — check growpart/growroot"
G "sudo ss -tlnp" > /tmp/listening.txt
LISTENERS=$(grep -cE 'LISTEN' /tmp/listening.txt || echo 0)
[ "$LISTENERS" -le 4 ] && pass "no unexpected listening services ($LISTENERS)" || fail "too many listeners ($LISTENERS)"

echo
if [ "$FAILED" -ne 0 ]; then echo "IMAGE VALIDATION FAILED" | tee -a "$REPORT"; exit 1; fi
echo "IMAGE VALIDATION PASSED" | tee -a "$REPORT"
