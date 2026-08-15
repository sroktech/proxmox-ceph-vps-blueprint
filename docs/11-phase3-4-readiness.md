# 07 — Production Readiness and Go-Live Checklists

Two separate documents with two separate purposes.

**Production readiness** = the platform is technically sound. Run this at the end of week 10.
**Go-live** = you are ready for paying customers. This includes commercial and operational items that are not in Phase 3 or 4 at all, and is deliberately included because a technically perfect cluster with no abuse process will still hurt you.

---

# Production Readiness Checklist

Every item needs a name and a date, not just a tick. Items marked **[BLOCKER]** must not be waived.

## Hardware and network

- [ ] All three nodes identical: same firmware, same BIOS settings, same CPU microcode
- [ ] BIOS: virtualisation extensions on, C-states configured for latency, watchdog enabled
- [ ] Redundant PSUs, each on a separate power feed (A+B)
- [ ] **[BLOCKER]** Both boot SSDs bootable — physically verified by pulling each in turn
- [ ] All NVMe drives are enterprise-class with power-loss protection, confirmed against datasheets
- [ ] SMART monitoring active on every device; a pre-fail condition triggers an alert
- [ ] **[BLOCKER]** Jumbo frames verified on every node pair on VLANs 30, 31, 40 (`ping -M do -s 8972`)
- [ ] LACP bonds verified: each member individually downed, traffic continues
- [ ] **[BLOCKER]** Corosync ring 0 and ring 1 physically traverse *different* switches — verified against the cable map
- [ ] MLAG peer link redundant and tested
- [ ] BMC on isolated VLAN 99, default credentials changed, unreachable from tenant and internet
- [ ] Cable map documented and matches reality
- [ ] Spare parts on site: 1 NVMe, 1 SFP/DAC, 1 PSU

## Proxmox cluster

- [ ] `pveversion -v` identical across all nodes
- [ ] `pvesubscription get` active on all nodes; enterprise repos only
- [ ] **[BLOCKER]** `pvecm status` quorate, expected votes 3
- [ ] **[BLOCKER]** `corosync-cfgtool -s` both links connected on all nodes
- [ ] Zero Corosync retransmits observed under sustained Ceph load
- [ ] `/etc/pve` replication verified in both directions
- [ ] `corosync.conf` backed up outside the cluster
- [ ] HA decision made and documented: enabled with tested fencing, or deliberately disabled with reasoning
- [ ] Time sync: chrony active, drift under 50 ms on all nodes

## Ceph

- [ ] **[BLOCKER]** `ceph -s` = `HEALTH_OK`, all PGs `active+clean`
- [ ] **[BLOCKER]** `ceph osd pool ls detail` confirms `size 3 min_size 2`
- [ ] CRUSH failure domain is `host`, verified with `ceph osd crush rule dump`
- [ ] 3 MONs in quorum; 2 MGRs (1 active, 1 standby)
- [ ] `ceph osd df tree` distribution within 10% of mean
- [ ] `ceph versions` uniform
- [ ] Recovery tuning applied: `osd_max_backfills`, `osd_recovery_op_priority`, `osd_recovery_max_active`
- [ ] Scrub windows set to off-peak hours
- [ ] `osd_memory_target` set explicitly; total OSD memory + ARC + host fits with room for VM allocation
- [ ] **[BLOCKER]** ZFS ARC capped and verified (`cat /sys/module/zfs/parameters/zfs_arc_max`)
- [ ] Nearfull/backfillfull/full ratios set
- [ ] Raw utilisation under 60%, and capacity plan documented for node 4
- [ ] `fio` baselines in Git; single-queue 4K write latency under 3 ms
- [ ] Multi-VM concurrent load test passed with no VM starved
- [ ] **[BLOCKER]** Per-VM IOPS and bandwidth caps enforced at provision time, verified to actually throttle

## SDN and tenant isolation

- [ ] EVPN controller peering established on all nodes (`show bgp l2vpn evpn summary`)
- [ ] Two exit nodes configured; failover tested
- [ ] **[BLOCKER]** One vnet per tenant enforced in provisioning code, not just policy
- [ ] **[BLOCKER]** Cross-vnet isolation proven with `nmap`, not just `ping`
- [ ] **[BLOCKER]** `macfilter: 1` at datacenter level; MAC spoof from a guest confirmed blocked
- [ ] **[BLOCKER]** `ipfilter: 1` + `ipfilter-net0` per VM; IP spoof confirmed blocked
- [ ] **[BLOCKER]** ARP spoof attempt from a test guest has no effect and is logged
- [ ] **[BLOCKER]** Tenant VM cannot reach VLAN 10 — verified by port-scanning from inside a guest
- [ ] `firewall=1` on every customer NIC; continuous audit job scheduled and alerting
- [ ] Outbound TCP/25 blocked by default; unlock workflow documented
- [ ] Reflection-port egress blocked or rate-limited (19, 111, 123, 389, 1900, 11211)
- [ ] uRPF / BCP38 configured at the network edge
- [ ] Tenant MTU 1500 working end to end (`ping -M do -s 1472` to the internet from a guest)
- [ ] VNI and subnet allocation plan documented and enforced by the panel's database

## Backup and recovery

- [ ] **[BLOCKER]** PBS on separate physical hardware, not in the cluster
- [ ] Backup jobs scheduled for all VMs; retention policy set
- [ ] Datastore encryption enabled; encryption key backed up offline
- [ ] Offsite replication configured and verified
- [ ] **[BLOCKER]** Full VM restore tested; data integrity verified against a pre-taken checksum
- [ ] Restore to a *different* node tested
- [ ] Restore while the cluster is degraded tested
- [ ] Single-file restore tested
- [ ] Restore times recorded for 50 GB and 500 GB disks
- [ ] Monthly restore test scheduled as a recurring calendar item with an owner

## Monitoring and alerting

- [ ] Monitoring stack runs **outside** the production cluster
- [ ] `node_exporter`, `prometheus-pve-exporter`, Ceph MGR Prometheus module, PBS metrics all scraping
- [ ] MGR failover does not silently break Ceph metrics — tested
- [ ] Grafana dashboards for cluster, Ceph, per-node, per-VM
- [ ] Loki collecting logs from all nodes
- [ ] **[BLOCKER]** Alertmanager routes critical alerts to a phone that wakes someone; test alert received
- [ ] Alerts configured for: quorum loss, Ceph not OK 15 min, OSD down, PG not clean 30 min, pool over 70%, CPU steal over 10%, SMART pre-fail, backup failure or none in 36 h, per-VM outbound traffic spike, cert/token expiry
- [ ] Every alert has a runbook link in its annotation
- [ ] Alert fatigue check: fewer than 5 non-actionable alerts per week

## Automation and IaC

- [ ] `ansible-playbook site.yml --check --diff` clean; second real run `changed=0`
- [ ] **[BLOCKER]** Node rebuild from Git alone tested and timed
- [ ] `terraform plan` shows zero changes against live cluster
- [ ] Provider version pinned exactly; lock file committed
- [ ] Remote state with locking and versioning; backed up
- [ ] `prevent_destroy` on storage and pool resources
- [ ] Nightly drift detection alerting
- [ ] **[BLOCKER]** No customer VM resource anywhere in Terraform
- [ ] Three OS templates built by CI, validated, published, manifest in Git
- [ ] Monthly image rebuild scheduled; rollback drill performed
- [ ] Template validation suite catches a deliberately broken image

## Security

- [ ] **[BLOCKER]** PVE UI and API not reachable from the internet — verified from an external host
- [ ] SSH: keys only, no password auth, verified
- [ ] TOTP required for all PVE UI logins
- [ ] Datacenter firewall enabled, default-deny inbound
- [ ] Valid TLS certificate on the PVE API; `insecure = false` in Terraform
- [ ] **[BLOCKER]** Panel uses a scoped API token, never `root@pam`; verified it cannot exceed its scope
- [ ] API tokens have expiry dates; expiry monitored and alerting
- [ ] `gitleaks` clean across full repository history
- [ ] SOPS/age working in CI; age private key is a masked and protected variable
- [ ] Age key rotation drill performed; offline recovery key in a physical safe
- [ ] `main` protected: MR, approval, passing CI required
- [ ] Apply jobs manual, not automatic on merge
- [ ] Audit logs shipped off-node
- [ ] Dedicated CI runner for infrastructure; not shared

## Failure testing

- [ ] **[BLOCKER]** T1–T16 all complete with results recorded
- [ ] **[BLOCKER]** T5 confirmed: fencing works, no split-brain possible
- [ ] **[BLOCKER]** T13 full power loss: cluster self-recovers, RTO recorded
- [ ] 16 runbooks written and stored in Git
- [ ] All findings from testing fixed and re-tested
- [ ] Quarterly re-test scheduled with an owner

## Documentation

- [ ] Architecture and network diagrams current
- [ ] Address plan in Git
- [ ] Cable map in Git
- [ ] All 16 failure runbooks
- [ ] Disk replacement procedure
- [ ] Node rebuild procedure
- [ ] Emergency procedures documented with authorisation rules: `pvecm expected 1`, `min_size 1`
- [ ] Escalation contacts: DC remote hands, transit providers, Proxmox support
- [ ] Known limitations documented honestly — especially the 3-node no-self-heal constraint

---

# Go-Live Checklist

Technical readiness above is necessary but not sufficient. These items are outside Phase 3 and 4 but will determine whether the business survives its first month.

## Control plane and provisioning

- [ ] Panel provisions end to end via the API without manual steps
- [ ] Rebuild/reinstall flow works
- [ ] Resize flow works (disk grow; confirm shrink is refused, not attempted)
- [ ] **Serial and VNC console available to customers** — this is your ticket-volume valve
- [ ] Password/key reset flow works without support involvement
- [ ] Cancellation flow works: suspend → grace → destroy → IP cooldown → disk wipe
- [ ] Bandwidth accounting accurate and visible to the customer
- [ ] 30 test VMs provisioned through the panel; no orphaned resources or race conditions
- [ ] Full journey tested as a stranger: signup → pay → provision → break it → recover via console → ticket → cancel

## Abuse and fraud

- [ ] **`abuse@` mailbox live, monitored, tied to the RIR object**
- [ ] Abuse response SLA and escalation ladder documented (notify → suspend → terminate)
- [ ] Outbound traffic anomaly alerting live, threshold tested with real traffic
- [ ] Fraud screening at signup: geo/IP risk, non-VoIP phone verification, manual review on first order
- [ ] Suspension mechanism tested: VM stopped, disk retained, customer notified
- [ ] Port 25 unlock request workflow with identity verification
- [ ] RPKI ROAs published for all announced prefixes; verified with a public validator
- [ ] IRR objects current

## Commercial and legal

- [ ] AUP, ToS, SLA, Privacy Policy published, lawyer-reviewed
- [ ] **SLA numbers match measured T13 recovery time** — not aspirational
- [ ] Known limitations disclosed (3-node storage behaviour, maintenance windows)
- [ ] Payment processing live; backup processor available
- [ ] Refund and SLA-credit process defined
- [ ] DMCA and law-enforcement request procedures documented
- [ ] Unit economics validated: break-even VM count per node known

## Operations

- [ ] Ticketing system live with canned responses for the top 10 questions
- [ ] Public status page live; incident communication template written
- [ ] On-call rotation defined, even if it is one person with a documented escalation
- [ ] Maintenance window policy published
- [ ] **One node's worth of spare capacity kept free** for maintenance and failover
- [ ] Capacity trigger defined: at what utilisation do you order node 4
- [ ] DC remote hands contact and process tested with a real trivial request

## Launch discipline

- [ ] Soft launch: signups capped, "early access" framing, 10–20 friendly users
- [ ] Ticket-volume-per-customer tracked; above ~0.5/customer/month means fix the product before scaling
- [ ] A defined trigger to pause signups if ops capacity is exceeded
- [ ] Post-launch review scheduled at week 2 and week 6

---

## Sign-off

| Section | Owner | Date | Notes |
|---|---|---|---|
| Hardware and network | | | |
| Proxmox cluster | | | |
| Ceph | | | |
| SDN and isolation | | | |
| Backup and recovery | | | |
| Monitoring | | | |
| Automation and IaC | | | |
| Security | | | |
| Failure testing | | | |
| Documentation | | | |
| Control plane | | | |
| Abuse and fraud | | | |
| Commercial and legal | | | |
| Operations | | | |

Any **[BLOCKER]** waived requires a written reason, a named approver, and a date by which it will be resolved.
