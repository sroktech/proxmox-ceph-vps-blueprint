# 03 — Step 18 (Ceph) and Step 19 (SDN)

---

# Step 18 — Deploy Ceph

## Purpose

Provide shared, replicated block storage (RBD) so VMs can live-migrate between nodes and survive the loss of a node without data loss.

## Hardware recommendations

| Component | Minimum | Recommended for VPS | Why |
|---|---|---|---|
| Nodes | 3 | 4–5 | 3 tolerates a node loss but cannot self-heal (see `05-phase3-cluster-architecture.md` §1.1) |
| OSD devices | 4 per node | 6–8 per node NVMe U.2 | More OSDs = finer failure granularity, faster recovery |
| Drive class | Enterprise NVMe **with PLP** | Same, mixed-use endurance (1–3 DWPD) | Without PLP, sync-write IOPS collapse |
| Network | 10 GbE | 2× 25 GbE LACP | Replication is ~2× write traffic; backfill saturates links |
| RAM | 4 GiB per OSD + 16 GiB host | 6 GiB per OSD + host + VM allocation | `osd_memory_target` default is 4 GiB and OSDs will use it |
| CPU | 2 cores per NVMe OSD | Same, plus VM cores | NVMe OSDs are CPU-hungry; do not under-spec |

Concrete example for 6 NVMe OSDs per node: `6 × 6 GiB = 36 GiB` reserved for OSDs, plus 4 GiB ZFS ARC, plus ~8 GiB host overhead = **48 GiB unavailable to VMs**. On a 512 GiB node you can sell ~460 GiB. Budget this into your pricing or you will oversell RAM.

Set the memory target explicitly rather than relying on defaults:
```bash
ceph config set osd osd_memory_target 6442450944   # 6 GiB
```

## Network design

```bash
pveceph init \
  --network 10.10.30.0/24 \
  --cluster-network 10.10.31.0/24
```

- `--network` (public): clients (KVM/librbd), MONs, and MGRs.
- `--cluster-network`: OSD-to-OSD replication, heartbeats, backfill, recovery.

Both on the 25 GbE LACP bond, separate VLANs, MTU 9000. Verify jumbo frames work on both before proceeding — a broken MTU manifests as intermittent slow I/O that is miserable to diagnose later.

## OSD layout

One OSD per NVMe device. Do not use a separate DB/WAL device: with all-NVMe, colocated BlueStore DB/WAL on the same device is correct, and a separate device just creates a single point of failure for multiple OSDs.

```bash
# Confirm devices are clean and unused first
lsblk -o NAME,SIZE,MODEL,ROTA,MOUNTPOINT

# Create OSDs — repeat per device, per node
for dev in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1 /dev/nvme5n1 /dev/nvme6n1; do
  pveceph osd create "$dev"
done
```

Result: 18 OSDs across 3 nodes.

**Two OSDs per device?** The old advice to split very fast NVMe into 2 OSDs to use more CPU threads is largely obsolete with modern Ceph releases, which parallelise better internally. Start with one OSD per device. Only revisit if benchmarking shows a single OSD saturating before the drive does.

## MON and MGR placement

```bash
# MON on all three nodes — odd count, tolerates 1 loss
pveceph mon create   # run on each node, or via UI

# MGR on two nodes — one active, one standby
pveceph mgr create   # on pve-01 and pve-02
```

MON quorum is separate from Corosync quorum. Both must be satisfied. 3 MONs tolerate 1 failure. Never run 2 MONs (worse than 1 — any failure loses quorum). Never run 4 (no benefit over 3).

MGR does dashboard, Prometheus module, autoscaler, and balancer. Only one is active; a second is enough for failover.

## Replica settings

```bash
# Create the RBD pool for customer VM disks
pveceph pool create vm-disks \
  --size 3 \
  --min_size 2 \
  --pg_autoscale_mode on \
  --application rbd \
  --add_storages 1
```

### Why `size = 3`

Three copies on three separate hosts. The alternatives are worse:

- **`size = 2, min_size = 1`** — the configuration that destroys hosting companies. With 2 copies, if one OSD dies and a second dies during the multi-hour recovery window, the data is gone permanently. Worse, `min_size = 1` allows writes to a single surviving copy; when the other node returns, Ceph must decide which version is authoritative, and in some failure sequences you get silent inconsistency. Every experienced Ceph operator has a story about this. Do not run `size = 2` for customer data.
- **`size = 4`** — 4 copies needs 4 hosts, costs 33% more capacity than `size=3`, and buys very little additional durability at this scale.
- **Erasure coding** — excellent capacity efficiency (e.g. k=4,m=2 gives 1.5× overhead vs 3×) but higher latency and CPU per I/O, requires 6+ hosts for meaningful profiles, and RBD needs an overwrite-enabled EC pool plus care with small random writes. Not appropriate for the latency-sensitive random I/O of customer VPS disks. Consider EC later for a backup or archive tier only.

### Why `min_size = 2`

`min_size` is the number of replicas that must acknowledge a write for it to be accepted.

- `min_size = 2` means: with one node down, writes continue (2 of 3 available). With two nodes down, **writes block** rather than proceeding unsafely. Blocking is the correct behaviour — a stalled VM is recoverable, silently divergent data is not.
- `min_size = 1` means writes proceed on a single copy. You have traded durability for availability in a way your customers cannot see and cannot forgive.

The rule: `min_size = 2` with `size = 3`. Accept that a two-node failure means an I/O stall, and design your monitoring so you never get there unnoticed.

## CRUSH map design

The default CRUSH rule for a replicated pool already uses `host` as the failure domain, which is what you want on 3 nodes. Verify rather than assume:

```bash
ceph osd crush rule dump replicated_rule
# Look for: "type": "host" in the chooseleaf step
```

Confirm the tree looks right:
```bash
ceph osd tree
# Expect: root default → host pve-01 (6 OSDs), pve-02 (6), pve-03 (6)
```

If you later add nodes in a second rack or a second power domain, introduce a `rack` bucket and change the failure domain:

```bash
ceph osd crush add-bucket rack-a rack
ceph osd crush add-bucket rack-b rack
ceph osd crush move rack-a root=default
ceph osd crush move pve-01 rack=rack-a
# ... then a rule with chooseleaf firstn 0 type rack
```

Do not do this on 3 nodes — you cannot satisfy `size=3` across 2 racks with host-level distribution intact.

### Placement groups

Leave the autoscaler on. Set a target ratio so it sizes the pool correctly from the start instead of splitting PGs later under load:

```bash
ceph osd pool set vm-disks target_size_ratio 0.9
ceph osd pool autoscale-status
```

Target is roughly 100 PGs per OSD across all pools. With 18 OSDs and one main pool, expect the autoscaler to settle around 512 PGs.

### Additional safety settings

```bash
# Enable the balancer (usually on by default)
ceph balancer mode upmap
ceph balancer on

# Full-ratio thresholds — defaults are usually fine, but know them
ceph osd set-nearfull-ratio 0.80
ceph osd set-backfillfull-ratio 0.88
ceph osd set-full-ratio 0.92

# Enable deep scrub during off-peak only
ceph config set osd osd_scrub_begin_hour 2
ceph config set osd osd_scrub_end_hour 6
ceph config set osd osd_scrub_load_threshold 2.0

# Limit recovery impact on customer I/O — the setting that matters most for VPS
ceph config set osd osd_max_backfills 2
ceph config set osd osd_recovery_max_active 4
ceph config set osd osd_recovery_op_priority 1
```

Those last four lines are what separates "a node failed and customers noticed nothing" from "a node failed and every VPS was unusable for six hours." Ceph's defaults favour fast recovery over client latency. For a hosting platform, invert that.

## Per-VM I/O limits — mandatory before any customer

Ceph shares IOPS across all clients. One customer running a tight `fio` loop can starve every other VM on the cluster. Cap every disk at provision time.

```bash
# Example: 3000 IOPS, 200 MB/s, with a short burst allowance
qm set 100 --scsi0 vm-disks:vm-100-disk-0,\
iops_rd=3000,iops_wr=3000,iops_rd_max=6000,iops_wr_max=6000,\
mbps_rd=200,mbps_wr=200,mbps_rd_max=400,mbps_wr_max=400,\
iothread=1,discard=on,ssd=1
```

Bake these into your provisioning API call, not a manual step. Set them per plan tier and publish the numbers — customers respect published limits and resent undisclosed throttling.

## Cluster validation steps

```bash
ceph -s                          # HEALTH_OK, all PGs active+clean
ceph health detail
ceph osd tree                    # 18 OSDs, correctly distributed
ceph osd df tree                 # even distribution, no outliers
ceph df                          # pool usage and available
ceph mon stat                    # 3 MONs, quorum
ceph mgr stat                    # 1 active, 1 standby
ceph osd pool ls detail          # size 3, min_size 2 confirmed
ceph config dump                 # your tuning applied
ceph versions                    # all daemons on the same release
```

Every one of these must be clean before Step 19.

## Performance tests

Run these on a test VM, not the host, so you measure what a customer measures.

```bash
# Baseline the raw pool first (from a node)
rados bench -p vm-disks 60 write --no-cleanup
rados bench -p vm-disks 60 seq
rados bench -p vm-disks 60 rand
rados -p vm-disks cleanup

# RBD-level
rbd bench --io-type write --io-size 4K --io-pattern rand --io-total 10G vm-disks/testimg
```

Inside a test VM, the four numbers that matter:

```bash
# 4K random read IOPS
fio --name=randread --ioengine=libaio --direct=1 --rw=randread \
    --bs=4k --numjobs=4 --iodepth=32 --size=4G --runtime=120 --group_reporting

# 4K random write IOPS
fio --name=randwrite --ioengine=libaio --direct=1 --rw=randwrite \
    --bs=4k --numjobs=4 --iodepth=32 --size=4G --runtime=120 --group_reporting

# Sequential throughput
fio --name=seqwrite --ioengine=libaio --direct=1 --rw=write \
    --bs=1M --numjobs=2 --iodepth=16 --size=8G --runtime=120 --group_reporting

# Single-queue latency — the number customers actually feel
fio --name=lat --ioengine=libaio --direct=1 --rw=randwrite \
    --bs=4k --numjobs=1 --iodepth=1 --size=1G --runtime=60
```

Record the results in Git as your baseline. Rough expectations for all-NVMe, 25 GbE, `size=3`: tens of thousands of 4K random IOPS per VM, sequential in the low GB/s, and **single-queue write latency around 0.5–1.5 ms**. If that latency figure is above ~3 ms, something is wrong — usually MTU, a non-PLP drive, or a network bottleneck. Chase it before launch.

Then run the test that actually predicts production: **many VMs at once**. Ten test VMs each running moderate `fio` tells you far more than one VM running hard.

## Failure tests

Do these before customers exist. Timings measured here become your real SLA.

```bash
# 1. Single OSD down (softest failure)
systemctl stop ceph-osd@0
ceph -s                          # expect HEALTH_WARN, degraded, then recovery
# Confirm: VMs keep running, latency rise is tolerable
systemctl start ceph-osd@0

# 2. OSD destroyed and rebuilt (simulates drive replacement)
ceph osd out 0
# wait for rebalance to complete
ceph osd purge 0 --yes-i-really-mean-it
pveceph osd create /dev/nvme1n1

# 3. Whole node down — the important one
# Physically pull power from pve-03 while 10 VMs run I/O
ceph -s                          # degraded, PGs undersized, NOT recovering (no 4th host)
pvecm status                     # 2/3 votes, still quorate
# Confirm: VMs on surviving nodes keep working; measure the latency spike
# Confirm: HA (if enabled) restarts pve-03's guests on other nodes — time it
# Power on pve-03, time full return to HEALTH_OK

# 4. Ceph network partition
ip link set <ceph-cluster-if> down   # on one node
# Expect OSDs on that node marked down, cluster degrades but serves

# 5. MON loss
systemctl stop ceph-mon@pve-03
ceph -s                          # 2/3 MONs, still quorum, HEALTH_WARN
```

## Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| `size=2` or `min_size=1` | Permanent data loss on double failure | `size=3, min_size=2`, verify with `ceph osd pool ls detail` |
| Consumer NVMe without PLP | 5–20× worse sync IOPS, early wear-out | Enterprise NVMe only, verify PLP in the datasheet |
| MTU mismatch on Ceph VLANs | Intermittent stalls, very hard to diagnose | `ping -M do -s 8972` on every path before deploy |
| Default recovery tuning | Customer-visible outage during any rebuild | Set `osd_max_backfills`, `osd_recovery_op_priority` |
| Pool above 80% | Rebalancing cannot complete, cluster may go read-only | Alert at 70%, hard stop at 75% on 3 nodes |
| No per-VM I/O caps | One customer starves the cluster | Enforce at provision time in the panel |
| ZFS ARC uncapped | OSDs OOM-killed | Cap in Step 15, verify |

## Validation checklist — Step 18

- [ ] `ceph -s` reports `HEALTH_OK`, all PGs `active+clean`
- [ ] `ceph osd pool ls detail` confirms `size 3 min_size 2` on the VM pool
- [ ] `ceph osd crush rule dump` confirms failure domain `host`
- [ ] `ceph osd df tree` shows even distribution, no OSD more than ~10% off the mean
- [ ] Jumbo frames verified on Ceph public and cluster VLANs, all node pairs
- [ ] Recovery tuning applied (`ceph config dump` shows your values)
- [ ] `fio` baselines recorded in Git; single-queue write latency under 3 ms
- [ ] Multi-VM concurrent load test run; no VM starved
- [ ] Per-VM I/O caps applied and verified to actually throttle
- [ ] Single OSD failure tested and recovered
- [ ] Full node power-pull tested with live VMs; recovery time recorded
- [ ] MON failure tested
- [ ] `ceph versions` shows uniform daemon versions

---

# Step 19 — Configure SDN

## Purpose

Give each customer a network that is invisible to every other customer, without hand-editing bridges or running out of VLAN IDs.

## VXLAN and EVPN in one paragraph each

**VXLAN** encapsulates a tenant Ethernet frame inside a UDP packet (dest port 4789) and carries it across a routed underlay. The 24-bit VNI field gives ~16.7 million segments instead of 4094 VLANs. Two VMs on different physical nodes in the same VNI behave as if on the same switch, regardless of the underlay topology.

**EVPN** is the control plane for VXLAN. Instead of flooding to learn MAC addresses, nodes advertise their local MAC and IP reachability to each other over BGP (address family L2VPN/EVPN). Proxmox implements this with FRR. This gives you: no flooding, fast convergence, distributed gateways, and — the part that matters for a VPS provider — clean routing between tenant subnets and the internet from designated **exit nodes**.

For a VPS platform, EVPN is the right choice over plain VXLAN because you need routing and internet egress per tenant, not just L2 segments.

## Sample SDN design

Three-layer model:

```
EVPN Controller (BGP ASN 65000, peers = all 3 nodes)
    └── EVPN Zone "tenants"  (VRF vrf_tenants, exit nodes: pve-01, pve-02)
            ├── vnet t1001  VNI 1001  subnet 10.201.1.0/24   → customer 1001
            ├── vnet t1002  VNI 1002  subnet 10.201.2.0/24   → customer 1002
            └── vnet t1003  VNI 1003  subnet 10.201.3.0/24   → customer 1003
```

Configure via UI (Datacenter → SDN) or CLI:

```bash
# 1. EVPN controller
pvesh create /cluster/sdn/controllers --controller evpnctl --type evpn \
  --asn 65000 --peers 10.10.40.11,10.10.40.12,10.10.40.13

# 2. EVPN zone
pvesh create /cluster/sdn/zones --zone tenants --type evpn \
  --controller evpnctl \
  --vrf-vxlan 4000 \
  --exitnodes pve-01,pve-02 \
  --mtu 1450 \
  --ipam pve

# 3. A tenant vnet
pvesh create /cluster/sdn/vnets --vnet t1001 --zone tenants --tag 1001

# 4. Subnet with gateway and SNAT for internet egress
pvesh create /cluster/sdn/vnets/t1001/subnets \
  --subnet 10.201.1.0/24 --type subnet \
  --gateway 10.201.1.1 --snat 1

# 5. Apply — nothing takes effect until this runs
pvesh set /cluster/sdn
```

Notes on the parameters:

- `--peers` uses the **VXLAN underlay** addresses (VLAN 40), not management.
- `--vrf-vxlan 4000` is the VNI for the VRF itself; keep it outside your tenant VNI range.
- `--exitnodes` designates which nodes route tenant traffic to the internet. Two for redundancy. These nodes carry all north-south tenant traffic, so size their uplinks accordingly.
- `--mtu 1450` on the zone accounts for VXLAN overhead if your underlay is 1500. **With a 9000-byte underlay you can leave tenant MTU at 1500** — strongly preferred, as discussed in `05-phase3-cluster-architecture.md`.
- `pvesh set /cluster/sdn` is the apply step. Forgetting it is the single most common SDN confusion.

Config lands in `/etc/pve/sdn/` and is replicated by pmxcfs. FRR config is generated into `/etc/frr/frr.conf` — inspect it with `vtysh -c "show running-config"` when debugging.

## VNI and address allocation strategy

Decide this once, write it down, enforce it in code:

| Range | Purpose |
|---|---|
| VNI 1–999 | Reserved: infrastructure, management overlays |
| VNI 1000–1999 | Shared/pooled customer networks (customers on public IPs, no private net) |
| VNI 2000–99999 | One per customer private network, allocated sequentially by the panel |
| VNI 4000 | VRF VNI (keep it out of tenant space — adjust if it collides with the above) |
| VNI 100000+ | Reserved for future zones/regions |

Private subnets: allocate `/24` per tenant vnet from `10.200.0.0/13` (that is 10.200.0.0–10.207.255.255, ~2000 `/24`s). Track allocations in your panel's database as the source of truth, not in your head and not only in SDN config.

Public IPv4: assign directly to VMs from your pool, one per VM, extras as a paid add-on. Public IPv6: allocate a `/64` per VM free from your `/32` or `/48`.

**Do not use `10.0.0.0/8` broadly or `192.168.0.0/16`** for tenant networks — customers will want to VPN into their VPS from home networks that use those ranges, and you will create routing conflicts.

## Preventing ARP spoofing, MAC spoofing, and cross-tenant leaks

These are three distinct controls. You need all three.

### 1. Cross-tenant isolation — one vnet per tenant

The structural control. Two customers in the same vnet share a broadcast domain, and no amount of firewalling makes that safe. **Never place two customers in one vnet.** Your provisioning code should treat the vnet as a per-customer resource, created on account signup, destroyed on account closure.

### 2. MAC spoofing prevention

Enabled at the datacenter firewall level and per-VM.

```
# /etc/pve/firewall/cluster.fw
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
macfilter: 1
```

`macfilter: 1` (the default, but verify it) makes the host drop frames whose source MAC does not match the MAC configured on the VM's virtual NIC. The customer can change the MAC inside their guest OS all they like; the hypervisor discards the traffic.

### 3. IP and ARP spoofing prevention

Per-VM firewall with IP filtering. This is the control that stops a customer from claiming another customer's IP or poisoning the gateway's ARP cache.

```
# /etc/pve/firewall/100.fw   (VMID 100)
[OPTIONS]
enable: 1
ipfilter: 1
policy_in: ACCEPT
policy_out: ACCEPT

[IPSET ipfilter-net0]
203.0.113.42
2001:db8:1234:5678::/64
10.201.1.10
```

`ipfilter: 1` combined with an `ipfilter-net0` ipset means only those source addresses may leave `net0`. Anything else — including forged ARP replies and spoofed source IPs for reflection attacks — is dropped at the tap interface.

Additionally, the VM's NIC must have the firewall flag on:
```bash
qm set 100 --net0 virtio=BC:24:11:XX:XX:XX,bridge=t1001,firewall=1
```

Without `firewall=1`, none of the per-VM rules apply. **Enforce this in your provisioning code** and add a periodic audit job that flags any running VM with `firewall=0`.

### 4. Egress filtering the customer cannot bypass

Beyond spoofing, block the traffic classes that make you an abuse source:

```
# /etc/pve/firewall/100.fw  — continued
[RULES]
OUT REJECT -p tcp -dport 25 -log info        # SMTP, unlock on request only
OUT DROP   -p udp -dport 19 -log info        # chargen
OUT DROP   -p udp -dport 111
OUT DROP   -p udp -dport 123 -log info       # NTP amplification (allow if you run NTP for them)
OUT DROP   -p udp -dport 389
OUT DROP   -p udp -dport 1900 -log info      # SSDP
OUT DROP   -p udp -dport 11211 -log info     # memcached
```

Note that these block the VM from *reaching* those ports outbound, which stops it participating in reflection attacks against others. Blocking a VM from *serving* on those ports is a separate rule set and generally not something you should do — customers legitimately run DNS and NTP servers. Rate-limit instead of block where you can.

Also apply `uRPF` (strict reverse-path filtering) on your switch ports facing the nodes, and BCP38 filtering at your border. Host-level filtering plus network-level filtering is defence in depth; either alone has gaps.

### 5. Security recommendations summary

- One vnet per tenant, no exceptions
- `macfilter: 1` at datacenter level
- `ipfilter: 1` + `ipfilter-net0` ipset per VM, populated by the provisioning code
- `firewall=1` on every customer NIC, audited continuously
- Outbound port 25 blocked by default with a verified unlock flow
- Reflection-port egress blocked or rate-limited
- uRPF and BCP38 at the network edge
- Exit nodes hardened; they see all tenant north-south traffic
- Never expose the Proxmox API or UI to tenant networks — tenant vnets must have no route to VLAN 10

## Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| Two tenants in one vnet | Cross-tenant sniffing, ARP poisoning | One vnet per tenant, enforced in code |
| `firewall=0` on a customer NIC | All spoofing protections silently inactive | Set in provisioning; continuous audit job |
| MTU mismatch overlay/underlay | Large packets silently dropped; SSH and VPN hang | 9000 underlay, 1500 tenant; verify with `ping -M do` |
| Tenant network can reach VLAN 10 | Customer reaches the Proxmox API | Explicit deny; verify by scanning from a test VM |
| Single exit node | All tenant internet traffic dies with one node | Two exit nodes, tested failover |
| Forgetting `pvesh set /cluster/sdn` | Config exists but does nothing; confusing debugging | Make apply part of every automation run |
| FRR config drift | EVPN routes vanish after a reload | Manage via SDN config only; never hand-edit `frr.conf` |

## Validation checklist — Step 19

- [ ] `pvesh get /cluster/sdn/zones` and `/vnets` return expected config on all nodes
- [ ] `vtysh -c "show bgp l2vpn evpn summary"` shows all peers `Established`
- [ ] `vtysh -c "show bgp l2vpn evpn"` shows tenant MAC/IP routes
- [ ] Two VMs in the same vnet on **different physical nodes** can ping each other
- [ ] Two VMs in **different** vnets cannot reach each other — verified with `nmap`, not just ping
- [ ] A VM can reach the internet via the exit node; SNAT working
- [ ] Exit node failover tested: stop the primary exit node, confirm egress continues
- [ ] MAC spoof test: change MAC inside a test guest, confirm traffic stops
- [ ] IP spoof test: add a second IP inside the guest that is not in `ipfilter-net0`, confirm it cannot send
- [ ] ARP spoof test: run `arpspoof`/`ettercap` from a test guest against the gateway, confirm no effect and drops are logged
- [ ] From a tenant VM, port-scan VLAN 10 (management) — must be entirely unreachable
- [ ] Port 25 egress blocked from a test VM
- [ ] MTU verified: `ping -M do -s 1472` from a tenant VM to the internet succeeds
- [ ] `firewall=1` audit script written and scheduled
