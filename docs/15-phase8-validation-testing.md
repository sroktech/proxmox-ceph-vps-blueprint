# 08 — Phase 8: Validation and Testing

**Duration:** 2 weeks, and do not compress it
**Depends on:** Phases 3–7 complete
**Blocks:** taking a paying customer

Every number measured here becomes an input to your SLA, your runbooks, and your pricing. The Phase 3 bundle covers infrastructure failure tests T1–T16; this phase covers the four checklists that sit above them.

**Pass/fail discipline:** an item marked **[BLOCKER]** may not be waived. Anything else waived needs a written reason, a named approver, and a resolution date.

---

## 8.1 UAT checklist — the customer journey

Test as a stranger would. Use a different browser, a real card, and a fresh email address. Do not use admin shortcuts.

| # | Test | Pass criteria | Fail if |
|---|---|---|---|
| U1 | Signup with valid details | Account created, verification email arrives within 2 min | Email missing or in spam |
| U2 | Signup with disposable email | Rejected or queued for review | Auto-provisioned |
| U3 | Signup with VoIP phone | Rejected at verification | Accepted |
| U4 | **[BLOCKER]** Order + pay + provision | VPS live and reachable within 5 min; credentials delivered | Manual step required, or over 10 min |
| U5 | Invoice correctness | Correct tax rate for the customer's jurisdiction; compliant layout | Wrong rate or non-compliant |
| U6 | B2B order with valid business tax ID | Reverse-charge or exemption applied correctly | VAT/GST charged where it should not be |
| U7 | SSH in with the injected key | Works first attempt | Key not injected |
| U8 | Root filesystem size | Matches the ordered disk size | Filesystem smaller than ordered |
| U9 | **[BLOCKER]** Lock yourself out with a firewall rule, recover via serial console | Console reachable, login prompt, recovery possible | No console, or console shows nothing |
| U10 | VNC console | Renders, keyboard works | Broken |
| U11 | Reboot, stop, start from panel | All work; state reflected within 30 s | Stale state |
| U12 | Reinstall / rebuild | Completes, fresh OS, new host keys | Old host keys retained |
| U13 | Two VMs from the same template | **Different** machine-id and SSH host keys | Identical — security defect |
| U14 | Set a PTR record | Applied, resolvable within TTL | Not self-service |
| U15 | Password / key reset | Works without support contact | Requires a ticket |
| U16 | Bandwidth usage display | Matches actual transfer within 5% | Wildly inaccurate |
| U17 | Upgrade plan | Prorated correctly, resources change, no data loss | Data loss or wrong proration |
| U18 | Downgrade / disk shrink | Refused clearly with an explanation | Attempted and corrupts data |
| U19 | Open a support ticket | Received, acknowledged within stated SLA | Lost |
| U20 | Backup restore request | Customer's VM restored, data intact | Fails |
| U21 | **[BLOCKER]** Cancel | Suspend → grace → destroy → disk wiped → IP to cooldown | Data or IP not handled correctly |
| U22 | Failed payment | Dunning sequence runs; notifications sent; suspension at the stated point | Silent revenue loss |
| U23 | Refund | Processed; credit note issued | Manual mess |
| U24 | IPv6 connectivity | `/64` assigned, working out of the box | Not assigned, or broken |
| U25 | Provision 30 VMs, terminate all 30 | **Zero** orphaned disks, IPs, vnets, or monitoring entries | Any orphan |

U25 finds real bugs reliably. Run it.

---

## 8.2 Security checklist

| # | Test | Method | Pass criteria |
|---|---|---|---|
| S1 | **[BLOCKER]** Proxmox UI/API not internet-reachable | `nmap` from an external host against every public IP | Ports 8006, 22 closed from outside |
| S2 | **[BLOCKER]** Tenant → management isolation | Port-scan the management VLAN from inside a customer VM | Entirely unreachable |
| S3 | **[BLOCKER]** Cross-tenant isolation | `nmap` from tenant A's VM to tenant B's VM, both L2 and L3 | No response; not merely ICMP-blocked |
| S4 | **[BLOCKER]** MAC spoofing | Change MAC inside a guest, send traffic | Traffic dropped |
| S5 | **[BLOCKER]** IP spoofing | Add an unauthorised IP inside a guest, send from it | Dropped; logged |
| S6 | **[BLOCKER]** ARP spoofing | Run `arpspoof`/`ettercap` against the gateway from a guest | No effect; logged |
| S7 | uRPF / BCP38 | Send a packet with a forged source from a guest | Dropped at the edge |
| S8 | Port 25 egress | Attempt outbound SMTP from a new VM | Rejected |
| S9 | Reflection ports egress | Attempt outbound to 123, 1900, 11211 | Dropped |
| S10 | `firewall=1` audit | Run the audit job with a deliberately misconfigured VM | Flagged and alerted |
| S11 | Panel token scope | Attempt a cluster/Ceph/SDN change with the panel token | Refused |
| S12 | Panel admin exposure | Attempt to reach the admin path externally | Blocked or MFA-gated |
| S13 | SSH password auth | Attempt password login to a node | Refused |
| S14 | MFA enforcement | Log into PVE UI without TOTP | Refused |
| S15 | Secret scanning | `gitleaks detect` over full history | Clean |
| S16 | Template hygiene | Search a fresh clone for the Packer build key | Absent |
| S17 | Token/cert expiry monitoring | Set a token to expire soon | Alert fires before expiry |
| S18 | Audit logging | Perform a privileged action | Logged off-node with actor and timestamp |
| S19 | RPKI validity | Check from 3+ external vantage points | VALID everywhere |
| S20 | Outbound prefix filter | Attempt to announce a prefix you do not own | Blocked by your own filter |
| S21 | **[BLOCKER]** Credential escrow | Have the secondary contact retrieve escrowed credentials | Successful without your involvement |

S21 is the test nobody runs. Run it.

---

## 8.3 Performance checklist

Record every number. These are your baselines and your SLA inputs.

| # | Test | Method | Pass criteria |
|---|---|---|---|
| P1 | 4K random read IOPS, single VM | `fio` randread, 4 jobs, iodepth 32 | Meets your published figure |
| P2 | 4K random write IOPS, single VM | `fio` randwrite | Meets published figure |
| P3 | **[BLOCKER]** Single-queue write latency | `fio` randwrite, 1 job, iodepth 1 | **Under 3 ms.** Above suggests MTU, non-PLP drives, or a network bottleneck |
| P4 | Sequential throughput | `fio` 1M blocks | Meets published figure |
| P5 | **[BLOCKER]** I/O limits actually throttle | Run `fio` unbounded in a capped VM | Throughput capped at the plan limit |
| P6 | **[BLOCKER]** Noisy-neighbour isolation | One VM hammers I/O; measure another VM's latency | Victim latency rise under 2× |
| P7 | Multi-VM concurrent load | 10–20 VMs under moderate `fio` simultaneously | No VM starved; cluster stable |
| P8 | CPU steal under target overcommit | Load all VMs; measure steal | Under 5% |
| P9 | Network throughput VM → internet | `iperf3` to an external endpoint | Near line rate for the plan |
| P10 | Tenant MTU | `ping -M do -s 1472` from a guest to the internet | Succeeds |
| P11 | Jumbo frames on Ceph paths | `ping -M do -s 8972` between every node pair on VLANs 30/31/40 | All succeed |
| P12 | Recovery impact | Fail an OSD under load; measure client latency | Under 3× baseline — validates your recovery tuning |
| P13 | Provisioning time | 10 sequential orders | Consistently under 5 min |
| P14 | Concurrent provisioning | 5 simultaneous orders | No race conditions, no duplicate IP allocation |
| P15 | Panel responsiveness under load | Browse while provisioning runs | Usable |

P6 is the test that predicts your support load. If one customer's `fio` loop degrades everyone, you will discover it in production instead.

---

## 8.4 Failover checklist

Infrastructure tests T1–T16 live in Phase 3 (docs 05-08). These are the business-level failover tests that sit on top.

| # | Test | Pass criteria |
|---|---|---|
| F1 | **[BLOCKER]** All of T1–T16 complete | Results recorded, runbooks written |
| F2 | **[BLOCKER]** T5 — both Corosync rings down on one node | Fencing works; node self-fences **before** peers restart its guests. No split-brain possible |
| F3 | **[BLOCKER]** T13 — full cluster power loss | Self-recovers with no manual intervention; **RTO recorded** |
| F4 | **[BLOCKER]** T14 — restore with checksum verification | Data matches byte-for-byte |
| F5 | Transit A failure | Traffic continues via B; measure the convergence window |
| F6 | Border router failure | Second router carries traffic |
| F7 | Switch A power off | No quorum loss, no OSD loss, no customer impact beyond reduced bandwidth |
| F8 | SDN exit node failure | Tenant egress restored within seconds |
| F9 | Blackhole community | Tested with **both** transit providers |
| F10 | **[BLOCKER]** Panel database loss and restore | Panel restored; IP and VNI allocations intact; reconciles with Proxmox |
| F11 | Payment processor failover | Switch to secondary and take a live payment within 1 hour |
| F12 | Monitoring host loss | You still find out about a cluster problem — by some path |
| F13 | Offsite restore | VM restored from the offsite replica |
| F14 | Node rebuild from Git only | Node returns to production; time recorded |

F7 validates your entire physical design in one test. If anything unexpected goes down, your cabling has a single point of failure — most commonly both Corosync rings on the same switch.

---

## 8.5 Deriving the SLA from results

This is the deliverable of Phase 8 that connects engineering to commerce.

```
Worst measured RTO (F3, full power loss)     = ____ minutes
Planned maintenance per year                 = ____ minutes
Expected unplanned events per year × RTO     = ____ minutes
Safety margin (×2)                           = ____ minutes
                                              ─────────────
Total expected annual downtime                = ____ minutes
```

Then choose the SLA tier that this number fits **comfortably** inside:

| Tier | Annual budget | Choose if your total is below |
|---|---|---|
| 99.99% | 52 min | 26 min — implausible on 3 nodes |
| 99.95% | 263 min | 130 min |
| 99.9% | 526 min | 260 min |
| 99.5% | 2,628 min | 1,300 min |

**Publish the tier your measurements support, not the tier your competitors advertise.** Then model the credit exposure: worst-case monthly credits × customer count, against monthly gross margin. If a single bad month wipes a quarter's margin, your SLA is mispriced.

---

## 8.6 Go / no-go gate

Do not accept a paying customer until all of these are true:

- [ ] Every **[BLOCKER]** above passes
- [ ] T1–T16 complete with runbooks written
- [ ] SLA derived from measured results, credit exposure modelled
- [ ] Restore verified with checksum
- [ ] Credential escrow tested by a second person
- [ ] Abuse detection triggers automated rate-limiting within 60 s of a simulated spike
- [ ] `abuse@` live and registered in the RIR object
- [ ] Both processors can take a live payment
- [ ] Tax treatment confirmed by an accountant
- [ ] Status page live; incident templates written
- [ ] 30-VM provision/terminate cycle leaves zero orphans

## Phase 8 success criteria

You have a written results document with real numbers for every test, a published SLA you can defend against those numbers, sixteen-plus runbooks, and a signed go/no-go decision. Nothing on the blocker list is outstanding.
