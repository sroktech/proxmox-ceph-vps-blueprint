# 14 — Final Master Checklist

Zero infrastructure → production-ready VPS hosting company.

**How to use:** every item needs an owner and a date, not just a tick. Items marked **[BLOCKER]** must not be waived — each one represents a failure mode that is either existential or effectively irreversible. Any blocker waived requires a written reason, a named approver, and a resolution date.

Phase 3 and Phase 4 technical detail lives in Phase 3 and 4 (docs 05-11); this checklist references those items rather than repeating them.

---

## 1. Business and legal

### Entity and banking
- [ ] Legal entity registered; incorporation documents on file
- [ ] Jurisdiction of incorporation vs jurisdiction of infrastructure decided and documented
- [ ] Entity that will hold the RIR membership confirmed
- [ ] Business bank account operational
- [ ] Second account for reserves and deferred revenue
- [ ] Corporate card for vendor billing

### Tax and accounting
- [ ] Corporate tax registration complete
- [ ] **[BLOCKER]** Cross-border indirect tax obligations determined in writing by an accountant **before the first payment**
- [ ] Business tax ID validation capability in the billing system
- [ ] Evidence-of-customer-location capture (required by some regimes)
- [ ] Accounting system live
- [ ] Chart of accounts separates revenue by product, COGS, and capex
- [ ] Depreciation schedule for all hardware
- [ ] **Deferred revenue treatment for annual prepayments** confirmed
- [ ] Monthly close process defined

### Payments
- [ ] Primary payment processor live
- [ ] **[BLOCKER]** Secondary processor onboarded and test-transacted
- [ ] Processor's written hosting-industry policy read before signing
- [ ] Reserve terms understood and modelled in cash flow
- [ ] Card data never touches your systems (hosted fields / tokenisation)
- [ ] Dunning workflow: retry schedule, notifications, suspension point
- [ ] Chargeback response process documented
- [ ] Refund and credit-note process tested

### Policies
- [ ] **[BLOCKER]** AUP published, with an **explicit immediate-suspension right** for active harm
- [ ] AUP defines resource abuse numerically, not vaguely
- [ ] ToS published: liability cap, payment terms, data-destruction timing, backup responsibility
- [ ] **[BLOCKER]** SLA derived from measured failure-test results, not chosen for marketing
- [ ] SLA exclusions cover maintenance, DDoS, upstream, customer-caused
- [ ] SLA credit exposure modelled against monthly gross margin
- [ ] Privacy policy published
- [ ] DPA template available for B2B customers
- [ ] DMCA / takedown procedure with designated agent where applicable
- [ ] Law-enforcement request procedure documented
- [ ] Abuse policy published with the `abuse@` address
- [ ] **[BLOCKER]** All policies reviewed by a lawyer with hosting or telecoms experience

### Compliance and insurance
- [ ] **[BLOCKER]** Local ISP / telecoms registration requirement verified (can block prefix announcement)
- [ ] GDPR or local data-protection assessment complete
- [ ] Sanctions / export-control screening at signup
- [ ] Data-retention or lawful-intercept obligations checked
- [ ] Insurance quoted: general liability, professional indemnity, cyber
- [ ] **Cyber policy exclusions read**, not just the summary

### Financial planning
- [ ] Financial model built with **real quotes**, not placeholders
- [ ] Binding resource identified by calculation
- [ ] **[BLOCKER]** Required-ARPU-to-break-even computed and the pricing decision made against it
- [ ] Fully-loaded break-even below 60% of sellable capacity
- [ ] **Peak cash requirement computed** (larger than startup cost) and capital confirmed available
- [ ] 18 months of runway modelled, not 6
- [ ] Accountant has reviewed the assumptions

---

## 2. Network and addressing

### Allocation
- [ ] LIR membership active, or sponsoring LIR with **transferability confirmed in writing**
- [ ] ASN allocated
- [ ] IPv6 allocation received; addressing plan documented **before** first assignment
- [ ] Joined the RIR IPv4 waiting list
- [ ] **[BLOCKER]** IPv4 block reputation due diligence completed before acquisition
- [ ] IPv4 lease-vs-buy decision modelled
- [ ] Every VM gets a free IPv6 `/64`

### Routing
- [ ] Two transit providers from **topologically diverse** networks (check AS paths, not brand names)
- [ ] **[BLOCKER]** DDoS handling confirmed in writing: nullroute threshold and scrubbing availability
- [ ] Two border routers; FIB capacity verified against current global table size
- [ ] **[BLOCKER]** RPKI ROAs created with deliberate `maxLength`
- [ ] **[BLOCKER]** RPKI validated VALID from 3+ external vantage points
- [ ] IRR route/route6 objects published and matching announcements
- [ ] Outbound prefix filter tested (attempt to announce a prefix you do not own → blocked)
- [ ] Max-prefix limits configured on both sessions
- [ ] Inbound RPKI validation dropping invalids
- [ ] **[BLOCKER]** uRPF / BCP38 active; spoofed packet from a test VM confirmed dropped
- [ ] **[BLOCKER]** Blackhole community tested end to end with **both** providers
- [ ] Transit failover tested
- [ ] **Reverse DNS delegated and self-serviceable in the panel**
- [ ] `abuse@` registered in the RIR object

---

## 3. Hardware and datacenter

- [ ] Datacenter visited in person; power feeds and remote-hands desk inspected
- [ ] Colo contract signed with documented **exit terms**
- [ ] Remote hands tested with a trivial request
- [ ] All nodes identical: firmware, BIOS, microcode
- [ ] Redundant PSUs on separate feeds (A+B)
- [ ] **[BLOCKER]** Both boot SSDs bootable — verified by physically pulling each
- [ ] **[BLOCKER]** Enterprise NVMe with **PLP confirmed by name in the datasheet**
- [ ] Drive endurance (DWPD) checked against write-amplification budget
- [ ] Boot drives separate from OSD drives
- [ ] Two switches with MLAG and 9216 MTU support
- [ ] Switch buffer capacity considered (Ceph incast)
- [ ] **[BLOCKER]** Cable map documented and **physically verified**: Corosync ring 0 and ring 1 on different switches
- [ ] **[BLOCKER]** Jumbo frames verified on every node pair on VLANs 30/31/40
- [ ] BMC on isolated VLAN; default credentials changed; unreachable from tenant and internet
- [ ] Power draw within circuit limit with headroom
- [ ] Spares kit on site: NVMe, optics, PSU, boot SSD, fan, console cable
- [ ] Vendor RMA terms documented; advance replacement if available
- [ ] Firmware baseline documented

---

## 4. Cluster, storage and tenant networking

*(Detail in Phase 3 and 4 (docs 05-11).)*

- [ ] **[BLOCKER]** `pvecm status` quorate; both Corosync links connected
- [ ] Zero Corosync retransmits under sustained Ceph load
- [ ] **[BLOCKER]** `ceph -s` HEALTH_OK; all PGs `active+clean`
- [ ] **[BLOCKER]** Pool confirmed `size 3 min_size 2`; CRUSH failure domain `host`
- [ ] ZFS ARC capped and verified
- [ ] `osd_memory_target` set; total reserved RAM fits with room for VMs
- [ ] Recovery tuning applied (`osd_max_backfills`, `osd_recovery_op_priority`)
- [ ] Scrub windows off-peak
- [ ] Raw utilisation under 60%; node-4 capacity plan documented
- [ ] `fio` baselines in Git; **single-queue write latency under 3 ms**
- [ ] Multi-VM concurrent load test passed; no VM starved
- [ ] **[BLOCKER]** Per-VM IOPS and bandwidth caps enforced at provision time and verified to throttle
- [ ] HA decision documented: enabled with tested fencing, or deliberately disabled with reasoning
- [ ] **[BLOCKER]** One vnet per tenant, enforced in provisioning code
- [ ] **[BLOCKER]** Cross-vnet isolation proven with `nmap`, not ping
- [ ] **[BLOCKER]** `macfilter: 1`; MAC spoof from a guest confirmed blocked
- [ ] **[BLOCKER]** `ipfilter: 1` with populated ipset; IP spoof confirmed blocked
- [ ] **[BLOCKER]** ARP spoof attempt from a guest has no effect and is logged
- [ ] **[BLOCKER]** Tenant VM cannot reach the management VLAN (verified by port scan from inside a guest)
- [ ] `firewall=1` continuous audit job scheduled and alerting
- [ ] Two SDN exit nodes; failover tested
- [ ] Tenant MTU 1500 working end to end

---

## 5. Automation, images and IaC

- [ ] Ansible: `--check --diff` clean; second run reports `changed=0`
- [ ] **[BLOCKER]** Node rebuild from Git alone tested and timed
- [ ] Terraform plan shows zero changes against the live cluster
- [ ] Provider version pinned exactly; lock file committed
- [ ] Remote state with locking and versioning; backed up
- [ ] `prevent_destroy` on storage and pool resources
- [ ] Nightly drift detection alerting
- [ ] **[BLOCKER]** No customer VM resource anywhere in Terraform
- [ ] OS templates built by CI, validated, published, manifest in Git
- [ ] **[BLOCKER]** Two clones of one template have different machine-id and SSH host keys
- [ ] Build-time key absent from templates (automated CI check)
- [ ] Root filesystem grows to ordered disk size
- [ ] Serial console works (`qm terminal` gives a login prompt)
- [ ] Monthly image rebuild scheduled; rollback drill performed
- [ ] Validate stage catches a deliberately broken image
- [ ] `main` protected: MR, approval, passing CI
- [ ] Apply jobs **manual**, never automatic on merge
- [ ] SOPS/age working in CI; key rotation drill performed
- [ ] `gitleaks` clean across full history

---

## 6. Control plane and billing

- [ ] Platform chosen with the buy-vs-build reasoning documented
- [ ] **[BLOCKER]** Panel uses a **scoped API token**, never `root@pam`; scope limits verified
- [ ] **[BLOCKER]** Proxmox UI/API not reachable by customers
- [ ] **[BLOCKER]** Console (VNC **and serial**) available to customers
- [ ] Reverse DNS self-service
- [ ] Power control, reinstall, resize, password/key reset all self-service
- [ ] Bandwidth accounting accurate within 5% and customer-visible
- [ ] **[BLOCKER]** I/O limits, `firewall=1`, and `ipfilter` applied automatically at provision time
- [ ] Tenant vnet created per customer automatically
- [ ] **[BLOCKER]** Termination flow: suspend → grace → destroy → **disk wipe** → **IP cooldown (30+ days)** → blocklist check before reissue
- [ ] Panel database is the source of truth for IPs, VNIs, plan limits
- [ ] **Continuous reconciliation** panel vs Proxmox with divergence alerting
- [ ] IP → customer lookup works for a **historical timestamp** (needed for abuse)
- [ ] Suspension callable programmatically by the abuse system
- [ ] Audit log of every privileged action
- [ ] Panel admin on a non-public path, behind MFA
- [ ] **[BLOCKER]** 30-VM provision/terminate cycle leaves **zero** orphaned disks, IPs, vnets, or monitoring entries
- [ ] Provisioning verification step: roll back and alert rather than billing for a VM that never booted

---

## 7. Abuse, fraud and security

### Anti-spam
- [ ] **[BLOCKER]** Outbound TCP/25 blocked by default, verified from a test VM
- [ ] Port 25 unlock workflow with account age, payment history, identity verification
- [ ] Post-unlock rate limiting
- [ ] Reflection-port egress blocked (19, 111, 123, 389, 1900, 11211)
- [ ] Reputation monitoring registered: Spamhaus, Google Postmaster, Microsoft SNDS
- [ ] **[BLOCKER]** Alert on any new blocklist listing of your ranges
- [ ] Feedback loop registrations submitted

### Anti-DDoS
- [ ] Scrubbing in place, **or** blackhole-only posture documented in SLA exclusions
- [ ] Inbound anomaly detection with alerting
- [ ] **[BLOCKER]** Outbound anomaly detection with **automated rate-limiting within 60 s**, threshold-tested
- [ ] Runbooks for inbound and outbound attacks
- [ ] Customer notification templates for both
- [ ] Blackhole `/32` announcement verified **RPKI-valid** against your ROA `maxLength`

### Fraud
- [ ] Automated risk scoring at signup
- [ ] **Non-VoIP phone verification enforced**
- [ ] AVS/CVV failure auto-declines
- [ ] Velocity checks on card, IP, device
- [ ] Device fingerprinting active
- [ ] Manual review queue working
- [ ] Policy: manual review of all first orders for the first 3 months
- [ ] Crypto/prepaid signups reviewed manually for the first 6 months

### Abuse response
- [ ] **[BLOCKER]** `abuse@` live, monitored, registered in the RIR object
- [ ] Severity classification P0–P3 with timelines documented
- [ ] Case state machine implemented
- [ ] Response templates for each state
- [ ] Suspension retains disk and is reversible; tested
- [ ] Full audit logging of abuse actions
- [ ] Termination authority documented
- [ ] **CSAM handling path pre-agreed with your lawyer**, not improvised

### Security
- [ ] **[BLOCKER]** Proxmox UI/API unreachable from the internet, verified externally
- [ ] MFA/TOTP on all admin access
- [ ] SSH keys only, no password auth
- [ ] Scoped tokens with expiry; **expiry monitored and alerting**
- [ ] Audit logs shipped off-node
- [ ] Dedicated CI runner for infrastructure, not shared
- [ ] Quarterly access review scheduled
- [ ] **[BLOCKER]** Credential escrow: offline copy, documented retrieval, **tested by the secondary contact**

---

## 8. Monitoring and observability

- [ ] **[BLOCKER]** Entire stack runs **outside** the production cluster
- [ ] Exporters live: node, PVE, Ceph MGR, PBS, IPMI, SNMP
- [ ] **Blackbox checks running from outside your network**
- [ ] **[BLOCKER]** MGR failover tested; Ceph metrics continue
- [ ] Four dashboards including the **business dashboard with growth triggers as gauges**
- [ ] Loki ingesting journald, Ceph, Corosync, pve-firewall, PVE tasks, panel logs
- [ ] **Loki label cardinality reviewed** — no VMID or IP in labels
- [ ] **[BLOCKER]** Alertmanager pages a phone; test alert received and acknowledged
- [ ] All page-tier alerts configured
- [ ] **Every alert has a runbook link in its annotation**
- [ ] Escalation chain with a secondary contact configured
- [ ] Monthly alert-fatigue audit scheduled
- [ ] Status page live with incident templates

---

## 9. Backup and disaster recovery

- [ ] **[BLOCKER]** PBS on separate physical hardware
- [ ] Offsite replication running and verified
- [ ] Client-side encryption enabled; **key stored offline and in escrow**
- [ ] Retention policy documented and **published to customers with the RPO stated**
- [ ] Backup bandwidth throttled; window off-peak
- [ ] **[BLOCKER]** Full restore tested with checksum verification
- [ ] Restore to a different node tested
- [ ] Restore during degraded cluster tested
- [ ] Single-file restore tested
- [ ] **[BLOCKER]** Restore using **only the escrowed encryption key** tested
- [ ] **[BLOCKER]** Panel database backed up separately; **restore tested**
- [ ] All restore times recorded; SLA consistent with them
- [ ] **Monthly restore test scheduled with a named owner**
- [ ] DR runbooks for every scenario including control-plane loss and credential loss
- [ ] Cold-start procedure documented with explicit ordering
- [ ] Escalation contact list: remote hands, both transits, hardware vendor, Proxmox, registrar

---

## 10. Testing and validation

- [ ] **[BLOCKER]** T1–T16 complete with results recorded and runbooks written
- [ ] **[BLOCKER]** T5: fencing works, split-brain impossible
- [ ] **[BLOCKER]** T13: full power loss self-recovers, RTO recorded
- [ ] Switch failure test (F7) passed with no unexpected impact
- [ ] UAT checklist U1–U25 passed
- [ ] Security checklist S1–S21 passed
- [ ] Performance checklist P1–P15 passed; baselines recorded
- [ ] Failover checklist F1–F14 passed
- [ ] **Noisy-neighbour isolation verified** (P6)
- [ ] All findings fixed and re-tested
- [ ] Quarterly re-test scheduled with an owner

---

## 11. Customer support

- [ ] Ticketing system live
- [ ] Canned responses for the top 10 questions
- [ ] Response targets published and **conservative enough to meet while asleep**
- [ ] Knowledge base with getting-started content
- [ ] Onboarding email sequence including **explicit disclosure of limitations** (port 25, RPO, DDoS posture, maintenance)
- [ ] Day-3 personal check-in process for early customers
- [ ] Ticket categorisation in place
- [ ] **Tickets-per-customer-per-month metric tracked**
- [ ] Escalation path from support to engineering defined

---

## 12. Launch readiness

- [ ] Every **[BLOCKER]** above resolved
- [ ] SLA published, derived from measurement, credit exposure modelled
- [ ] Soft-launch signup cap enforced in the panel
- [ ] Early-adopter cohort identified
- [ ] Full journey tested as a stranger: signup → pay → provision → break it → recover via console → ticket → cancel
- [ ] Both processors verified live
- [ ] Status page live
- [ ] **One node's worth of spare capacity kept free**
- [ ] Capacity growth triggers defined with owners
- [ ] Post-launch review scheduled at week 2 and week 6
- [ ] A defined trigger to **pause signups** if ops capacity is exceeded

---

## Sign-off

| Section | Owner | Date | Blockers outstanding |
|---|---|---|---|
| 1. Business and legal | | | |
| 2. Network and addressing | | | |
| 3. Hardware and datacenter | | | |
| 4. Cluster and tenant networking | | | |
| 5. Automation and IaC | | | |
| 6. Control plane and billing | | | |
| 7. Abuse, fraud and security | | | |
| 8. Monitoring | | | |
| 9. Backup and DR | | | |
| 10. Testing and validation | | | |
| 11. Customer support | | | |
| 12. Launch readiness | | | |

---

## The five items to check first if you are short of time

If you can only verify five things before taking money, make them these — each maps to one of the top failure modes:

1. **Outbound abuse controls** (§7) — port 25 blocked, automated outbound rate-limiting, `abuse@` live. *Prevents the most common cause of provider failure.*
2. **A restore you have actually verified** (§9) — with checksum, using the escrowed key. *Prevents the most unrecoverable reputational loss.*
3. **SLA derived from measurement** (§1, §10) — including T13's real RTO. *Prevents selling promises you cannot keep.*
4. **Required-ARPU break-even computed** (§1) — with real quotes. *Prevents building a business that cannot make money.*
5. **Tenant isolation proven with attack tools** (§4) — not just ping. *Prevents the failure that ends the company in one incident.*
