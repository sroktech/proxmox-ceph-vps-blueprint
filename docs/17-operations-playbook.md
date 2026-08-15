# 10 — Operations Playbook

Eight runbooks. Each is written to be followed at 3am by someone who is tired, which means: numbered steps, explicit commands, and a stated stopping point.

**Universal first three actions, before any specific runbook:**

1. **Note the time.** Everything downstream needs a timeline.
2. **Update the status page** if customers are affected. Silence is what turns an incident into a reputation problem.
3. **Do not improvise a fix on a system you do not yet understand the state of.** Diagnose, then act.

Severity definitions used throughout: **Sev1** = multiple customers down or data at risk · **Sev2** = one customer down or platform degraded · **Sev3** = single-customer non-urgent.

---

## RB-01 — Node failure

**Severity:** Sev1 if guests were running · **Expected duration:** 15 min to restore service, hours to full health

### Diagnose

```bash
pvecm status                    # quorum state, vote count
ceph -s                         # OSD and PG state
corosync-cfgtool -s             # ring health from a surviving node
ipmitool -H <bmc-ip> -U <user> -I lanplus chassis power status
ipmitool -H <bmc-ip> -U <user> -I lanplus sel list | tail -30
```

### Act

1. **Confirm the node is genuinely down, not partitioned.** A partitioned node still running guests while you restart them elsewhere is split-brain. Check via IPMI power state, not just network reachability.
2. Verify quorum survives: `pvecm status` shows `Quorate: Yes` with 2 of 3 votes.
3. If HA is configured, guests restart automatically. Watch: `ha-manager status`.
4. If HA is not configured, start affected guests manually on surviving nodes.
5. Confirm Ceph is serving: `ceph -s` should show `HEALTH_WARN`, PGs `active+undersized+degraded`. **On 3 nodes it will NOT recover** — this is expected, not a fault.
6. Throttle recovery before the node returns, so the rebuild does not hurt customers:
   ```bash
   ceph config set osd osd_max_backfills 1
   ceph config set osd osd_recovery_op_priority 1
   ```
7. Try remote power cycle via IPMI. If it boots, verify it rejoins: `pvecm nodes`, both rings connected, OSDs come up.
8. If it does not boot, engage DC remote hands. Ask for: PSU LEDs, POST state, and a photo of the console.

### Recover

- On return, watch backfill to completion. Do not start more work during it.
- Restore recovery tuning to normal once `HEALTH_OK`.
- If the node is unrecoverable, follow RB-01a below.

### RB-01a — Replace an unrecoverable node

```bash
# From a SURVIVING node, remove the dead one BEFORE reinstalling
pvecm delnode pve-03

# Remove its OSDs from the crush map
for id in <osd-ids>; do
  ceph osd purge $id --yes-i-really-mean-it
done
ceph osd crush remove pve-03
ceph mon remove pve-03      # if it hosted a MON

# Then: reinstall PVE with the IDENTICAL hostname and ZFS layout,
# run the Ansible rebuild playbook, rejoin, recreate OSDs.
```

**Do not skip `pvecm delnode` before reinstalling.** Rejoining with stale cluster state is a mess to unpick.

### Stop and escalate if
Quorum is lost (2+ nodes affected) → RB-02. Or the node returns but OSDs flap repeatedly → RB-02.

---

## RB-02 — Ceph failure

**Severity:** Sev1 · This runbook covers the several distinct failures people conflate.

### First, classify

```bash
ceph health detail
ceph -s
ceph osd tree
ceph mon stat
```

| Symptom | Go to |
|---|---|
| One OSD down | §A |
| OSDs repeatedly up/down | §B — flapping |
| PGs stuck, not recovering | §C |
| MON quorum lost | §D |
| Pool full or near-full | §E |
| I/O completely blocked | §F |

### §A — Single OSD down

```bash
systemctl status ceph-osd@<id>
journalctl -u ceph-osd@<id> -n 200
smartctl -a /dev/nvmeXn1        # check the underlying device
```
Restart it: `systemctl start ceph-osd@<id>`. If it fails repeatedly, treat as a drive failure → RB-04 §disk replacement.

### §B — Flapping OSDs

**This is worse than a dead OSD**, because Ceph repeatedly starts and aborts recovery. Almost always a network problem, not a disk problem.

```bash
# Stop the flapping first so you can diagnose calmly
ceph osd set noup
ceph osd set nodown

# Then check the cluster network
ping -M do -s 8972 <peer-ceph-cluster-ip>    # jumbo frames
ethtool -S <ceph-if> | grep -iE 'err|drop'
ip -s link show <ceph-if>
```
Common causes: MTU broken on one path, a failing optic, a switch buffer problem. Fix the network, then `ceph osd unset noup; ceph osd unset nodown`.

### §C — PGs stuck

```bash
ceph pg dump_stuck
ceph pg <pgid> query
ceph osd df tree        # is an OSD full and blocking?
```
On 3 nodes, `undersized` with a node down is expected and not stuck. Genuinely stuck (`incomplete`, `down`, `peering` for a long time) means an OSD holding needed data is unavailable — get it back online rather than forcing anything. **Do not use `ceph pg force-recovery` or mark OSDs lost until you have exhausted recovery of the actual OSD.** Marking an OSD lost can discard data.

### §D — MON quorum lost

```bash
ceph mon stat
systemctl status ceph-mon@<host>
journalctl -u ceph-mon@<host> -n 200
```
With 3 MONs you tolerate 1 loss. Two down means **all Ceph I/O blocks even though every OSD is healthy** — this surprises people. Restore a MON. Check clock skew first (`chronyc tracking`); MONs are intolerant of drift.

### §E — Pool full

```bash
ceph df
ceph osd df tree
```
Immediate relief, in order of preference:
1. Delete unneeded snapshots and old templates
2. Raise the full ratio **temporarily and slightly** to unblock I/O while you actually fix it:
   ```bash
   ceph osd set-full-ratio 0.94
   ```
3. Add capacity

**Do not raise the full ratio and walk away.** It buys hours, not a solution. A genuinely full Ceph cluster cannot rebalance, which is how a capacity problem becomes an availability problem.

### §F — I/O completely blocked

Check in this order: MON quorum (§D) → PGs below `min_size` (two nodes down) → pool full (§E) → network.

If two nodes are down and you must restore service before they can return, this is the break-glass path:
```bash
# EMERGENCY ONLY. Understand the risk before running.
# Reduces durability to a single copy. Revert the moment nodes return.
ceph osd pool set vm-disks min_size 1
```
Document who authorised it and when. Revert immediately on recovery.

---

## RB-03 — Network outage

**Severity:** Sev1

### Classify first — this determines everything

```bash
# From a node
ping <gateway>                     # local fabric
ping 8.8.8.8                       # upstream reachability
curl -s ifconfig.me                # egress path working
# From OUTSIDE your network
mtr <your-public-ip>               # inbound path
```

| Symptom | Cause class | Go to |
|---|---|---|
| Internal node-to-node fails | Fabric | §A |
| Internal fine, no internet | Transit or routing | §B |
| Reachable from some networks only | BGP / RPKI | §C |
| Traffic present but customers unreachable | SDN | §D |

### §A — Fabric

```bash
ip -s link show                    # errors, drops
ethtool <if>                       # link state, speed
cat /proc/net/bonding/bond0        # LACP member state
lldpctl                            # which switch port am I on
```
A single LACP member down is degraded, not down. Both down = check the switch. Switch unreachable = remote hands.

### §B — Transit / routing

```bash
# On the border router (FRR example)
vtysh -c "show bgp summary"
vtysh -c "show bgp ipv4 unicast summary"
vtysh -c "show ip route 0.0.0.0/0"
```
- One session down → traffic should flow via the other. Verify it is. Open a ticket with that provider.
- Both down → check physical links, then call both providers. Simultaneous failure of two providers usually means a shared dependency (same cross-connect panel, same power) — find it and fix the topology afterwards.
- Session up but no default route → check your inbound filter and max-prefix state: `vtysh -c "show bgp neighbor <ip>"` and look for `Maximum prefixes` errors.

### §C — Reachable from some networks only

This is almost always **RPKI-invalid**.

```bash
# Check from multiple external vantage points, not one
# Compare your ROA maxLength against what you are actually announcing
vtysh -c "show bgp ipv4 unicast <your-prefix>"
```
If you are announcing a longer prefix than your ROA's `maxLength` permits, you are invalid and being dropped by validating networks. Fix the ROA in the RIR portal; propagation takes minutes to hours.

Also check: IRR object matches, and your upstream's prefix filter includes what you are announcing.

### §D — SDN / tenant networking

```bash
vtysh -c "show bgp l2vpn evpn summary"      # peers established?
vtysh -c "show bgp l2vpn evpn"              # routes present?
pvesh get /cluster/sdn/vnets
ip -d link show type vxlan
```
- Exit node down → verify the second exit node took over
- EVPN peers not established → check underlay (VLAN 40) reachability and MTU
- After any SDN change: `pvesh set /cluster/sdn` (the apply step people forget)

### Communication

Update the status page within 5 minutes for any Sev1 network event, even with "investigating." Then every 30 minutes until resolved.

---

## RB-04 — Storage outage

**Severity:** Sev1 or Sev2

### Disk failure and replacement

```bash
# 1. Identify
ceph osd tree | grep down
smartctl -a /dev/nvmeXn1
nvme smart-log /dev/nvmeXn1

# 2. Remove it gracefully — let Ceph rebalance BEFORE destroying
ceph osd out <id>
# wait for HEALTH_OK or acceptable rebalance completion
watch ceph -s

# 3. Stop and purge
systemctl stop ceph-osd@<id>
ceph osd purge <id> --yes-i-really-mean-it

# 4. Physically replace (remote hands: give them the drive bay number,
#    which you should have documented in your cable/bay map)

# 5. Recreate
pveceph osd create /dev/nvmeXn1

# 6. Throttle backfill, then watch to completion
ceph config set osd osd_max_backfills 1
watch ceph -s
```

**On a 3-node cluster, step 2 will not reach `HEALTH_OK`** — there is no fourth host. Proceed once rebalance has done what it can, accepting the degraded window.

### Boot drive failure

ZFS mirror means the node keeps running.

```bash
zpool status rpool
# Replace, then:
zpool replace rpool <old-device> <new-device>
zpool status rpool          # watch resilver
# CRITICAL: install the bootloader on the new disk, or it won't boot
proxmox-boot-tool format /dev/sdX2
proxmox-boot-tool init /dev/sdX2
proxmox-boot-tool status
```

The bootloader step is the one people miss. The mirror resilvers, everything looks fine, and then the node will not boot from the new disk when the other one fails.

### PBS datastore full

```bash
proxmox-backup-manager datastore list
# Prune per retention policy, then garbage-collect to actually free space
proxmox-backup-client prune --keep-daily 7 --keep-weekly 4 <group>
proxmox-backup-manager garbage-collection start <datastore>
```
Pruning marks chunks unused; **garbage collection is what reclaims space.** Running prune alone and wondering why nothing freed is a common confusion.

---

## RB-05 — Hypervisor compromise

**Severity:** Sev1, highest. **Assume everything on that host is compromised, including every customer VM on it.**

### Immediate (first 10 minutes)

1. **Note the time and preserve evidence. Do not reboot.** A reboot destroys memory-resident evidence and may not remove persistence anyway.
2. **Isolate at the network level, not at the host.** Have the switch port shut, or apply an upstream filter. Do not rely on the compromised host's own firewall to isolate itself.
3. **Do not log into it with credentials you use elsewhere.** Use console/IPMI, not SSH with your normal key.
4. Assume all credentials present on that host are compromised: Ceph keyrings, API tokens, SSH keys, anything in `/etc/pve`.

### Contain (first hour)

```bash
# From an UNCOMPROMISED node
# 1. Revoke every token that host could have used
pveum user token remove panel@pve <tokenid>
# 2. Rotate Ceph keys used by that host
# 3. Fence the node from the cluster
pvecm delnode <compromised-node>
```

5. Rotate, everywhere: PVE root passwords, all API tokens, SSH keys, SOPS/age keys, PBS encryption key if it was on that host, registrar and RIR portal credentials if accessed from it.
6. **Check for lateral movement.** Review audit logs (shipped off-node, which is why you did that) and authentication logs on every other node.
7. Check whether the backup encryption key was exposed. If so, your backups' confidentiality is compromised even though their integrity may not be.

### Assess

- What was the entry point? Unpatched service, credential leak, compromised customer VM escaping, supply chain?
- Did it reach Ceph? If Ceph keyrings were taken, **all customer data on the cluster should be considered exposed**, not just data on that host.
- Were customer VMs modified? You may not be able to prove otherwise.

### Recover

8. **Rebuild the host from scratch.** Do not clean it. Reinstall, Ansible from Git, rejoin.
9. Restore customer VMs from backups predating the compromise, if you can establish when it started.
10. Verify integrity before returning to service.

### Notify

11. **Breach notification obligations may apply and may have a hard deadline** — 72 hours under GDPR from becoming aware. Involve your lawyer immediately; this is not a decision to make alone.
12. Notify affected customers honestly, with what you know and what you do not.
13. Written post-incident review, and the remediation actually implemented.

**Do not attempt to hide or minimise a compromise.** It is discoverable, and the reputational damage from concealment exceeds the damage from the incident.

---

## RB-06 — Abuse complaint

**Severity:** per classification. Target: acknowledge within 4 hours, always.

### Triage

```
1. Acknowledge receipt to the complainant. Always, even if you will reject it.
   Silence is what makes them escalate to your upstream.
2. Identify the customer from the IP + timestamp.
   Your panel must support IP→customer lookup for a historical timestamp,
   not just current allocations. Reassigned IPs make this essential.
3. Classify:
   P0 — active harm: outbound DDoS, live phishing, spam run, CSAM
   P1 — compromised host, malware C2, scanning
   P2 — copyright, single spam report, ToS breach
   P3 — vague or unsubstantiated
```

### P0 — act first

```bash
# 1. Rate-limit immediately (stops harm without destroying evidence)
qm set <vmid> --net0 <existing-config>,rate=1
# 2. Then suspend, retaining the disk
qm stop <vmid>
# 3. Then notify the customer with the evidence
```

Preserve the disk. It is evidence, and it is the customer's data if they turn out to be a victim rather than a perpetrator.

**For CSAM specifically: do not investigate the content further.** Preserve, do not view beyond what is necessary to confirm, and report to the appropriate national authority or hotline immediately. Your lawyer should have briefed you on the specific obligation in your jurisdiction before launch. Handle this path exactly as pre-agreed, not improvised.

### P1–P2 — notify with a deadline

Template structure: what was reported · the evidence · what they must do · the deadline · what happens if the deadline passes.

### Then

- Respond to the complainant with the action taken
- Log everything: complaint, evidence, customer, actions, timestamps, communications
- On termination: IP to extended cooldown, check against blocklists before reissue
- If the customer was compromised rather than malicious, help them remediate. They usually become a loyal customer.

### If your upstream contacts you about abuse

Respond immediately and with specifics. An upstream who sees fast, competent handling works with you. One who sees delay nullroutes your prefix, and that decision is theirs, not yours.

---

## RB-07 — DDoS attack

**Severity:** Sev1 or Sev2 depending on blast radius

### Determine direction first — this changes everything

```bash
# Where is the volume?
iftop -i <uplink-if>
# Or from flow data / switch counters
```

| Direction | Meaning | Priority |
|---|---|---|
| **Inbound** to a customer IP | Availability problem | Protect the platform |
| **Outbound** from a customer VM | **Reputation problem** | Stop it in seconds |

### Inbound

```
1. Identify the target IP and attack type (volumetric / protocol / application)
2. If scrubbing available → divert. Customer stays up.
3. If not, and the attack is saturating your transit:
   Announce a /32 with your upstream's blackhole community.

   # FRR example — community value is provider-specific, from your Phase 1 docs
   router bgp <your-asn>
     address-family ipv4 unicast
       network <target-ip>/32 route-map BLACKHOLE-OUT

   # This takes the TARGET customer offline and keeps everyone else up.

4. Verify your own /32 announcement does not break your ROA maxLength.
   If your ROA only permits /24, the /32 will be RPKI-invalid and ignored.
   THIS IS WHY maxLength MATTERS. Check it before you need it.
5. Notify the customer: what happened, what you did, what their options are.
6. Monitor; withdraw the blackhole when the attack subsides.
7. Post-incident note to the customer.
```

Step 4 is the trap. A blackhole announcement that is RPKI-invalid does nothing, and you will be debugging it during an attack.

### Outbound

```
1. Rate-limit the VM to near zero IMMEDIATELY (automated, ideally)
2. Suspend it, retaining the disk
3. Notify the customer with evidence
4. Notify your upstream proactively if there is any chance they noticed.
   Getting ahead of it preserves the relationship.
5. Human review: compromised or deliberate?
   Compromised + cooperative → assist, reinstate with monitoring
   Deliberate → terminate per AUP, IP to extended cooldown
```

### Communication

Status page for any attack with multi-customer impact. Be specific about what is affected. Customers understand DDoS; they do not understand silence.

---

## RB-08 — Customer data recovery

**Severity:** Sev2. Frequency: this will be one of your most common serious requests.

### Intake

```
1. What exactly is lost? Whole VM, a filesystem, specific files, a database?
2. WHEN was it last known good? This determines which backup to use.
3. Was it deletion, corruption, or ransomware?
   Ransomware changes things: the encryption may predate the visible symptom,
   so the newest backup may already be encrypted. Work backwards.
4. Set expectations immediately, honestly:
   - Your RPO is 24 hours with nightly backups. Data since the last backup is gone.
   - Restore time depends on disk size.
   Say this at the start. Discovering it at the end is much worse.
```

### Restore options

```bash
# List available backups
proxmox-backup-client snapshots --repository <repo> vm/<vmid>

# Option A: restore to a NEW VMID, so the original is preserved
qmrestore <backup-volid> <new-vmid> --storage vm-disks

# Option B: single-file restore — usually what the customer actually wants
proxmox-backup-client restore vm/<vmid>/<timestamp> \
  drive-scsi0.img.fidx /mnt/restore --repository <repo>
# Then mount and extract the specific files

# Option C: mount the backup as a filesystem for browsing
proxmox-backup-client mount vm/<vmid>/<timestamp> drive-scsi0.img /mnt/browse
```

**Always restore to a new VMID first.** Restoring over the original destroys the current state, which you may still need — and if the restore itself fails, you have lost both.

### Verify before handing back

- Boot the restored VM in an isolated network
- Confirm with the customer that the data is what they expected **before** you destroy anything
- Only then swap it into place

### Close

- Document what was lost and what was recovered
- If your process caused the loss, say so and issue appropriate credit
- If their action caused it, explain kindly and point at the backup add-on

### If you cannot recover it

Say so clearly and early. Explain what is available and what is not. Offer what you can — the backup add-on, application-level replication guidance. **Do not keep trying silently for hours while the customer waits without information.**

---

## Post-incident review template

For every Sev1 and Sev2. Keep it short enough that you actually write it.

```markdown
## Incident: <short description>
Date/time detected:        Date/time resolved:
Severity:                  Customers affected:
Detection: (alert / customer report / noticed manually)

### Timeline
HH:MM  what happened

### Root cause

### What went well

### What did not

### Actions
| Action | Owner | Due |
```

**The most valuable field is "Detection."** If the answer is "a customer told us," that is a monitoring gap, and it is usually a bigger finding than the incident itself.
