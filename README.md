# VPS Hosting Provider — Complete Platform and Business Repository

Everything needed to build and operate a Proxmox VE + Ceph VPS hosting provider: business roadmap, infrastructure implementation guide, working IaC scaffolds, operations runbooks, and a financial model.

**21 documents · working Ansible/Packer/Terraform/CI scaffolds · 10-sheet financial model with 536 live formulas.**

---

## Start here: the finding that should shape your plan

The financial model, run with indicative costs and conventional budget-VPS pricing, says:

| 3-node cluster | Baseline | Viable config |
|---|---|---|
| Break-even as % of sellable capacity | **188%** | **43%** |
| Monthly profit at 75% utilisation | −$3,632 | **+$4,484** |
| Payback | never | 24 months |

**A 3-node cluster at budget-VPS pricing cannot break even** — break-even needs 222 VMs and it can only sell 118. Even filled completely it loses money.

The cause is structural: roughly $4,400/month of fixed costs (two transits, cross-connects, scrubbing, LIR, insurance, accounting) spread across 118 sellable VMs is $37/VM/month before you buy a single server. Hetzner spreads the same class of cost across hundreds of thousands of VMs.

**The fix requires three levers moving together** — bigger drives, more RAM, and premium pricing. Moving any one alone achieves nothing: doubling RAM to 1 TB changes sellable capacity by **0.0%**, because disk binds at almost exactly the same point. See `docs/19-financial-model.md` §12.9 and the `Viable Config` sheet.

---

## Repository layout

```
├── docs/                 21 documents, read in numbered order
├── ansible/              Host configuration: roles, inventory, playbooks
├── packer/               Ubuntu 24.04, Debian 13, Rocky 10 templates
├── terraform/            Platform-level resources (NOT customer VMs)
├── ci/                   GitLab pipeline + validation scripts
├── VPS-Financial-Model.xlsx
├── .sops.yaml            Secret encryption rules
└── .gitlab-ci.yml
```

## Reading order

### Business foundation — start in week 1
| # | Document | Covers |
|---|---|---|
| 01 | `01-executive-architecture.md` | Four-layer architecture, dependency chains, relationship map of what breaks what |
| 02 | `02-phase0-business-foundation.md` | Entity, banking, tax, payments, accounting, AUP/ToS/SLA/Privacy, compliance |
| 03 | `03-phase1-network-addressing.md` | LIR, ASN, IPv6, IPv4, RPKI, IRR, BGP, transit, IXP, DDoS procurement |
| 04 | `04-phase2-hardware.md` | Sizing formulas, CPU/RAM/storage/switch selection, spares, growth models |

### Technical implementation — Phases 3 and 4
| # | Document | Covers |
|---|---|---|
| 05 | `05-phase3-cluster-architecture.md` | Architecture + network diagrams, VLAN plan, capacity math, monitoring placement |
| 06 | `06-phase3-cluster-build.md` | PVE install, Ansible automation, cluster creation, Corosync |
| 07 | `07-phase3-ceph-and-sdn.md` | Ceph deployment, EVPN SDN, tenant isolation |
| 08 | `08-phase3-failure-testing.md` | T1–T16 failure tests with expected behaviour and success criteria |
| 09 | `09-phase4-images-and-iac.md` | Packer, image CI/CD, Terraform design, GitOps and secrets |
| 10 | `10-phase3-4-build-order.md` | Week-by-week roadmap, milestones, critical path |
| 11 | `11-phase3-4-readiness.md` | Production readiness + go-live checklists |

### Platform, operations and launch
| # | Document | Covers |
|---|---|---|
| 12 | `12-phase5-control-plane-billing.md` | WHMCS vs HostBill vs Blesta vs custom, with a recommendation |
| 13 | `13-phase6-abuse-fraud-security.md` | Anti-spam, anti-DDoS, fraud prevention, abuse workflow, hardening |
| 14 | `14-phase7-monitoring-backup.md` | Prometheus, Grafana, Loki, PBS, alerting, escalation, DR |
| 15 | `15-phase8-validation-testing.md` | UAT, security, performance, failover checklists with pass/fail criteria |
| 16 | `16-phase9-10-launch-and-growth.md` | Soft launch, onboarding, then scaling Ceph/Proxmox/network/team |

### Cross-cutting
| # | Document | Covers |
|---|---|---|
| 17 | `17-operations-playbook.md` | Eight step-by-step runbooks for real failures |
| 18 | `18-org-and-hiring.md` | Year 1/2/3 team structure, hiring sequence, RACI, anti-patterns |
| 19 | `19-financial-model.md` | How to use the workbook, and what it revealed |
| 20 | `20-timeline.md` | 30-day, 90-day, 6-month, 12-month roadmaps |
| 21 | `21-master-checklist.md` | Complete progress tracking, zero → production |

---

## What kills VPS providers, ranked

This ordering shapes the whole repository. Infrastructure failure is *last*.

1. **Abuse and IP reputation damage** — space gets blocklisted, deliverability dies, customers leave → doc 13
2. **Cash flow** — capex up front, revenue over 24 months, peak cash need exceeds startup cost → doc 19
3. **An untested backup** — discovered at the worst moment → doc 14
4. **Selling availability you cannot deliver** — SLA written by marketing, not measured → doc 15
5. **Infrastructure failure** — genuinely least likely if you follow docs 05–11

Most founders spend 90% of their effort on item 5.

---

## Non-negotiables

Ten things that are either existential or effectively irreversible:

1. **Start the LIR application in week 1.** Longest lead time in the build; gates everything downstream.
2. **Verify local ISP/telecoms registration requirements on day 1.** In some jurisdictions a hard, multi-month blocker on announcing prefixes.
3. **Check IPv4 block reputation before acquiring.** A cheap `/24` is cheap for a reason; delisting takes months.
4. **Block outbound port 25 by default**, with a verified unlock workflow.
5. **Automate outbound abuse suspension.** If a human must act before a compromised VM stops attacking, you will be nullrouted while they sleep.
6. **Test T5 (fencing).** Two copies of a VM writing to one RBD image destroys the filesystem, unrecoverably.
7. **Derive the SLA from measured recovery times**, not from what competitors advertise.
8. **Set up credential escrow in month 1.** One person holding every key is a non-technical single point of failure.
9. **Verify a restore with checksums**, including one using only the escrowed encryption key.
10. **Compute required-ARPU break-even before buying hardware.** It is much cheaper to discover a problem in a spreadsheet than in month fourteen.

---

## Three design decisions worth understanding before you change them

**1. Cluster, Ceph, and SDN bootstrap are not fully automated.** Ansible converges host configuration well and orchestrates one-shot distributed bootstraps badly. `pvecm create` and `pveceph init` are not idempotent and are destructive if run wrongly. Playbooks prepare prerequisites and gate the destructive commands behind `allow_*_bootstrap` variables defaulting to false.

**2. Customer VMs are not in Terraform.** State locking would serialise provisioning, plans would grow unusable, and a misdirected destroy could queue deletion of every customer VM. The control panel calls the Proxmox API directly. Boundary test: *would a customer's action ever change this resource?* If yes, it is not Terraform's.

**3. A 3-node Ceph cluster tolerates a node loss but cannot self-heal.** With `size=3` and failure domain `host`, there is no fourth host to rebuild the third replica onto. Do not advertise self-healing storage or four-nines availability on three nodes. Order node 4 at 55% raw utilisation.

---

## Before you run anything

```bash
grep -rn "REPLACE" . --include="*.yml" --include="*.yaml" --include="*.hcl" \
  --include="*.cfg" --include="user-data" --include="preseed.cfg" --include="ks.cfg"
```

Fill in: SSH keys (`ansible/inventories/prod/group_vars/all.yml`), age public keys (`.sops.yaml`), PVE endpoint (`packer/common.pkrvars.hcl`, `terraform/envs/prod/terraform.tfvars`), Packer build key and password hashes, and your real IP allocations (`docs/05-phase3-cluster-architecture.md` §1.7).

Confirm ISO URLs and checksums still resolve — distributions move minor versions.

---

## The hard gate

Do not provision a paying customer before the full failure test matrix (doc 08) is complete — in particular **T5**, which confirms fencing works and split-brain is impossible.

---

## Caveats

- **Not legal, tax, or financial advice.** I am not a lawyer, accountant, or licensed financial advisor. Requirements vary enormously by jurisdiction. Use these documents to brief professionals efficiently, not to replace them.
- **All cost figures are indicative placeholders** from training data with a May 2026 cutoff. IPv4, RAM, transit, and colo pricing move substantially. Replace every one with a real quote.
- **Vendor pricing and licensing models change**, particularly billing platforms and RIR fee schedules. Verify directly.
- **Version details drift.** Written against Proxmox VE 9.x (Debian 13) and Ceph 19.2 Squid; verify against current release notes and the `bpg/proxmox` provider changelog.

## Ownership

**Organization:** [SrokTech](https://sroktech.com)  
**Repository:** `proxmox-ceph-vps-blueprint`  
**Purpose:** VPS hosting provider architecture, implementation, operations, and business planning

Prepared and maintained by **[SrokTech](https://sroktech.com)**.
