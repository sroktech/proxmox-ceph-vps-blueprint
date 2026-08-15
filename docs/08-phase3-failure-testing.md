# 04 — Step 20: Failure Testing Matrix

## Purpose

Discover how your cluster actually behaves under failure while the only person inconvenienced is you. Every number you measure here becomes an input to your SLA, your runbooks, and your capacity planning.

## Ground rules

1. **Run every test with load.** An idle cluster recovers beautifully and tells you nothing. Have 10–20 test VMs running moderate `fio` and network traffic throughout.
2. **Measure, do not just observe.** Record time-to-detect, time-to-recover, and customer-visible impact for each test. "It worked" is not a result.
3. **Never skip the recovery procedure.** Half of these tests teach you more about recovery than about failure.
4. **Write the runbook as you go.** The commands you type during the test are the runbook.
5. **Re-run the full matrix quarterly**, and after every Proxmox or Ceph major upgrade.

## Instrumentation to have running during all tests

```bash
# Terminal 1 — cluster state
watch -n2 'pvecm status | head -20; echo; ceph -s'

# Terminal 2 — Corosync link health
watch -n2 'corosync-cfgtool -s'

# Terminal 3 — Ceph recovery progress
watch -n5 'ceph -s | grep -E "recovery|degraded|misplaced"; ceph osd perf | head'

# Terminal 4 — customer-visible latency (from inside a test VM)
fio --name=latmon --ioengine=libaio --direct=1 --rw=randwrite --bs=4k \
    --numjobs=1 --iodepth=1 --size=10G --runtime=99999 \
    --write_lat_log=lat --log_avg_msec=1000

# Terminal 5 — ping a test VM from outside continuously
mtr -r -c 100 <test-vm-public-ip>
```

---

## Test matrix

### T1 — Graceful node reboot

| | |
|---|---|
| **Simulate** | `ssh pve-03 'reboot'` (with HA configured and guests running on it) |
| **Expected** | Quorum holds at 2/3 during reboot. Ceph goes `HEALTH_WARN`, PGs `undersized`. If HA is on, guests migrate or restart on other nodes. Node rejoins on boot; Ceph returns to `HEALTH_OK` after backfill. |
| **Recovery** | Automatic. |
| **Success criteria** | Cluster never loses quorum. No guest data loss. Return to `HEALTH_OK` within your backfill window. Customer-visible latency spike under 5× baseline. |
| **Record** | Time to `HEALTH_OK`. Peak latency. Whether HA moved guests and how long that took. |

### T2 — Hard node failure (power pull)

| | |
|---|---|
| **Simulate** | Physically remove both PSU cords from `pve-03`. Or `ipmitool -H <bmc> chassis power off`. |
| **Expected** | Corosync detects loss in a few seconds, 2/3 votes, quorate. Ceph marks that node's 6 OSDs `down` then `out` after `mon_osd_down_out_interval` (default 600 s). PGs `active+undersized+degraded` — **no recovery, because there is no fourth host**. HA fences and restarts the dead node's guests elsewhere after ~2 minutes. |
| **Recovery** | Power on. OSDs rejoin, backfill runs, cluster returns to `HEALTH_OK`. |
| **Success criteria** | Surviving VMs keep serving throughout. HA-managed guests restart within 3 minutes. No I/O stall on surviving VMs. |
| **Record** | HA restart time per guest. Time to `HEALTH_OK` after return. Whether any surviving VM saw I/O errors (it should not). |
| **Gotcha** | If `min_size` were 1 and something wrote during the outage, you would now have a divergence problem. This test is where you confirm `min_size=2`. |

### T3 — Two-node failure (the SLA-defining test)

| | |
|---|---|
| **Simulate** | Power off `pve-02` and `pve-03`. |
| **Expected** | Quorum **lost** — 1/3 votes. `/etc/pve` read-only on `pve-01`. Ceph below `min_size` on most PGs → **VM I/O blocks**. Guests do not crash; they hang on disk access. If HA is configured, `pve-01` will self-fence via watchdog after ~60 s. |
| **Recovery** | Restore at least one node. If both are truly unrecoverable and you must run degraded: `pvecm expected 1` and `ceph osd pool set vm-disks min_size 1` — **emergency only, understand the risk, revert immediately after**. |
| **Success criteria** | Behaviour is *predictable and understood*, not that service continues. You are confirming the cluster fails safely rather than corrupting data. |
| **Record** | Exactly what customers would experience. This is what your SLA must not promise away. |
| **Note** | If HA self-fencing reboots your last surviving node, that is correct anti-split-brain behaviour — but it means a 2-node loss becomes a full outage. Factor this into whether you enable HA on 3 nodes at all. |

### T4 — Corosync ring 0 failure

| | |
|---|---|
| **Simulate** | `ip link set <ring0-if> down` on `pve-02`. Or unplug that cable. Or reboot switch A. |
| **Expected** | `knet` fails over to ring 1 within a second. Quorum unaffected, 3/3 votes. Log entries in `/var/log/corosync` or `journalctl -u corosync`. Zero customer impact. |
| **Recovery** | Bring the link up; ring 0 rejoins and resumes as the higher-priority link. |
| **Success criteria** | No quorum loss, no fencing, no customer impact. `corosync-cfgtool -s` shows link 0 down / link 1 connected. |
| **If this test fails** | You have a single-ring cluster. Stop and fix Step 17 before continuing. |

### T5 — Both Corosync rings down on one node

| | |
|---|---|
| **Simulate** | Down both ring interfaces on `pve-03` while leaving Ceph and public networks up. |
| **Expected** | `pve-03` is in a 1-vote minority: read-only, self-fences if it hosts HA guests. `pve-01` + `pve-02` retain quorum and, if HA is on, restart `pve-03`'s guests — **while `pve-03` may still be running them**. This is the split-brain scenario fencing exists to prevent. |
| **Recovery** | Restore links. Confirm no guest is running in two places. |
| **Success criteria** | Fencing works: `pve-03` reboots itself before the other nodes start its guests. Verify the ordering. |
| **Why this matters** | This is the single most dangerous failure mode in a Proxmox cluster. If fencing does not work correctly, two copies of a VM write to the same RBD image and the filesystem is destroyed. Test it deliberately. |

### T6 — Single OSD failure

| | |
|---|---|
| **Simulate** | `systemctl stop ceph-osd@5` |
| **Expected** | OSD `down` immediately, `out` after 600 s. PGs degrade then recover onto remaining OSDs *on the same host* if capacity allows. `HEALTH_WARN` → `HEALTH_OK`. |
| **Recovery** | `systemctl start ceph-osd@5`, backfill. |
| **Success criteria** | Automatic recovery, latency spike under 3× baseline (this is where your `osd_max_backfills` tuning proves itself). |
| **Record** | Recovery duration. Peak client latency during recovery. |

### T7 — Physical disk failure and replacement

| | |
|---|---|
| **Simulate** | Hot-pull an NVMe drive (if hot-swap capable), or `echo 1 > /sys/block/nvmeXn1/device/delete` |
| **Expected** | OSD down, `HEALTH_WARN`, SMART/monitoring alert fires. |
| **Recovery** | Full documented procedure: `ceph osd out <id>` → wait for rebalance → `systemctl stop ceph-osd@<id>` → `ceph osd purge <id> --yes-i-really-mean-it` → replace hardware → `pveceph osd create /dev/nvmeXn1` → wait for backfill. |
| **Success criteria** | Procedure runs without improvisation. Cluster returns to `HEALTH_OK`. Total elapsed time recorded. |
| **Record** | Write this up as a standalone runbook. You will do this many times. |

### T8 — Ceph cluster-network failure

| | |
|---|---|
| **Simulate** | `ip link set <ceph-cluster-vlan-if> down` on `pve-02` |
| **Expected** | `pve-02`'s OSDs cannot replicate or heartbeat to peers. Peers report them down; they may report themselves up ("flapping"). Ceph may mark them down and out. |
| **Recovery** | Restore the interface. Check for OSD flapping in logs; if flapping continues, `ceph osd set noup`/`nodown` temporarily while diagnosing. |
| **Success criteria** | Cluster degrades but continues serving from the other two nodes. No data loss. |
| **Note** | Flapping OSDs are worse than dead ones because Ceph repeatedly starts and aborts recovery. Alert on OSD state transitions, not just on OSD down. |

### T9 — Ceph public-network failure

| | |
|---|---|
| **Simulate** | Down the Ceph public VLAN interface on `pve-01` |
| **Expected** | VMs *on that node* lose access to their disks and hang. VMs on other nodes are unaffected. That node's OSDs may still replicate over the cluster network but MON communication breaks. |
| **Recovery** | Restore interface. Hung VMs typically resume; some guest filesystems may have remounted read-only and need a reboot. |
| **Success criteria** | Blast radius limited to one node. Understand that guests may need reboots — this informs your incident comms. |

### T10 — MON failure

| | |
|---|---|
| **Simulate** | `systemctl stop ceph-mon@pve-03` |
| **Expected** | 2/3 MONs, quorum retained, `HEALTH_WARN` about 1 MON down. No I/O impact. |
| **Recovery** | Restart the MON. |
| **Then** | Stop a second MON: 1/3, **MON quorum lost**, all Ceph I/O blocks cluster-wide even though OSDs are healthy. This surprises people — recover it. |
| **Success criteria** | Single MON loss is a non-event. Double MON loss behaviour is understood and documented. |

### T11 — MGR failover

| | |
|---|---|
| **Simulate** | `systemctl stop ceph-mgr@pve-01` (the active MGR) |
| **Expected** | Standby MGR on `pve-02` becomes active within seconds. Prometheus scrape target changes — **your monitoring must handle this**, or you lose Ceph metrics silently. |
| **Recovery** | Automatic. |
| **Success criteria** | Metrics continue flowing. If they stop, fix your scrape config (scrape all MGRs, or use the MGR's active endpoint discovery). |

### T12 — Switch failure

| | |
|---|---|
| **Simulate** | Power off switch A entirely. |
| **Expected** | Every LACP bond drops to one member. Corosync ring 0 dies, ring 1 carries. Ceph continues at reduced bandwidth. Public traffic continues. **No quorum loss, no OSD loss, no customer impact beyond reduced throughput.** |
| **Recovery** | Power on; bonds re-form; MLAG peer sync completes. |
| **Success criteria** | This is the test that validates your entire physical design. If anything goes down, your cabling or bond config has a single point of failure — find it. |
| **Common finding** | People discover Corosync ring 0 and ring 1 were both patched into the same switch. Check the physical cabling against the diagram before running this. |

### T13 — Full cluster power loss

| | |
|---|---|
| **Simulate** | Kill power to all three nodes simultaneously. |
| **Expected** | Everything stops. On restore: nodes boot, Corosync forms quorum, MONs form quorum, OSDs come up, PGs peer, cluster returns to `HEALTH_OK`. Guests with `onboot=1` start. Some guest filesystems may need `fsck`. |
| **Recovery** | Powered boot order matters if anything depends on external services. Document a cold-start procedure. |
| **Success criteria** | Cluster self-recovers with no manual intervention. Total time from power-on to all guests running, recorded. |
| **Record** | This number is your worst-case RTO. Publish an SLA consistent with it. |
| **Note** | This is also where PLP on your drives proves itself. Non-PLP drives can lose acknowledged writes here. |

### T14 — Backup and restore

| | |
|---|---|
| **Simulate** | Delete a test VM entirely (`qm destroy <vmid> --purge`). |
| **Expected** | Restore from PBS: `qmrestore` or via the UI, into the cluster. |
| **Recovery** | Full restore, boot, verify data integrity against a known checksum you took beforehand. |
| **Success criteria** | Restored VM boots and data matches. Restore time recorded for a 50 GB and a 500 GB disk. |
| **Also test** | Single-file restore from a backup. Restore to a *different* node. Restore when the cluster is degraded. Restore with the PBS datastore full. |
| **Frequency** | Monthly, forever. An untested backup is not a backup. |

### T15 — Exit node failure (SDN)

| | |
|---|---|
| **Simulate** | Power off the primary EVPN exit node. |
| **Expected** | EVPN reconverges; the second exit node takes over tenant egress. Brief packet loss during BGP convergence. |
| **Recovery** | Automatic on node return. |
| **Success criteria** | Tenant internet connectivity restored within seconds. Measure the outage window with continuous `mtr`. |

### T16 — Certificate and API token expiry

| | |
|---|---|
| **Simulate** | Set a PVE API token's expiry to the past; let a monitoring cert expire in a test environment. |
| **Expected** | Provisioning fails with an auth error; monitoring scrape fails. |
| **Success criteria** | You get an *alert* about it before it breaks provisioning, not a customer ticket. Add expiry monitoring for all certs and tokens. |
| **Why it is on the list** | This is a very common real-world outage cause and it is entirely preventable. |

---

## Results table — fill this in

Copy into your repo as `docs/failure-test-results.md` (create this) and complete during testing.

| Test | Date run | Time to detect | Time to recover | Customer impact | Runbook written | Pass |
|------|----------|----------------|-----------------|-----------------|-----------------|------|
| T1 Graceful node reboot | | | | | | |
| T2 Hard node failure | | | | | | |
| T3 Two-node failure | | | | | | |
| T4 Corosync ring 0 down | | | | | | |
| T5 Both rings down, one node | | | | | | |
| T6 Single OSD down | | | | | | |
| T7 Disk replacement | | | | | | |
| T8 Ceph cluster net down | | | | | | |
| T9 Ceph public net down | | | | | | |
| T10 MON failure | | | | | | |
| T11 MGR failover | | | | | | |
| T12 Switch failure | | | | | | |
| T13 Full power loss | | | | | | |
| T14 Backup restore | | | | | | |
| T15 Exit node failure | | | | | | |
| T16 Cert/token expiry | | | | | | |

## What to do with the results

Three concrete outputs:

1. **Your real SLA.** If T13 takes 25 minutes and T2 restarts guests in 3 minutes, do not advertise 99.99% (52 minutes/year of downtime budget). A single cold start would consume half your annual budget. 99.9% (8.7 hours/year) is defensible on 3 nodes; 99.5% is honest.
2. **Runbooks.** One per test, in Git, with the exact commands. Written now, while calm.
3. **A prioritised fix list.** Anything that failed unexpectedly gets fixed before customers arrive, not after.
