# 12 — Financial Model

The working model is `VPS-Financial-Model.xlsx` at the repo root. Ten sheets, 536 live formulas, all inputs editable. This document explains how to use it and what it revealed.

**I am not a licensed financial advisor.** This is a calculation tool with structure and formulas, not advice. Every default cost figure is an **indicative placeholder** from my training data (cutoff May 2026), varying enormously by region, vendor, and market conditions. Replace all of them with real quotes and have an accountant review the result.

---

## 12.1 The headline finding

Run with the default placeholder costs and a conventional budget-VPS price list (ARPU $28.55, plans from $8 to $115/mo), the model says:

| | 3 nodes | 5 nodes | 10 nodes |
|---|---|---|---|
| Total startup cost | $112,448 | $158,741 | $255,995 |
| Fully-loaded monthly cost | $6,038 | $6,734 | $10,214 |
| Sellable VM capacity (after N+1) | 118 | 238 | 535 |
| Break-even VMs (fully loaded) | **222** | **248** | 376 |
| Break-even as % of sellable capacity | **188%** | **104%** | **70%** |
| Monthly profit at 75% utilisation | **−$3,632** | **−$1,889** | +$688 |
| **Required ARPU to break even** | **$71.65** | **$39.68** | **$26.75** |
| Current ARPU | $28.55 | $28.55 | $28.55 |

**A 3-node cluster at budget-VPS pricing cannot break even.** Break-even needs 222 VMs; the cluster can only sell 118. Even filled completely, it loses money. The required ARPU is $71.65 against $28.55 charged — a 151% price increase.

This is not a modelling artefact. It is arithmetic, and it is the single most important output of this whole exercise.

### Why this happens

Fixed costs do not scale down. Whether you run 3 nodes or 30, you pay for: two transit providers, cross-connects, DDoS scrubbing, LIR membership, accounting, insurance, a backup server, two switches, two routers, and a monitoring host. At 3 nodes those fixed costs are spread across 118 sellable VMs. At 10 nodes, across 535.

The fixed-cost base is roughly $4,400/month before you own a single sellable VM. That is $37/month per VM at 3 nodes and $8/month per VM at 10 nodes.

### What this means practically

Four viable responses, in order of how much I would recommend them:

**1. Price at a premium and mean it.** This is what the strategy sections have been arguing throughout: you cannot beat Hetzner and DigitalOcean on price because their fixed costs are spread across hundreds of thousands of VMs. The model quantifies exactly how badly you lose that fight. At 3 nodes you need roughly $70 ARPU — which is a business/managed VPS product with real support, not a $6 budget VPS. Position accordingly.

**2. Cut the fixed-cost base deliberately.** Levers, with what each costs you:
- Refurbished prior-generation hardware — roughly halves capex and therefore depreciation. Costs you warranty and firmware support lifetime
- Blackhole-only DDoS posture instead of scrubbing — saves ~$700/mo. Costs you the ability to keep an attacked customer online, and must be disclosed in your SLA
- Lower-cost colo market — can be a 2× difference. Costs you latency to premium markets
- Single transit provider at launch — saves substantially. Costs you real redundancy, and I would not do this

**3. Increase density — but move all three levers together.**

I initially suggested "double the RAM to 1 TB" as the high-leverage fix. **That advice was wrong, and the model shows why.** In the baseline configuration the two constraints are almost exactly tied:

| Resource | VMs/node |
|---|---|
| RAM (512 GB) | 59.5 |
| vCPU (128 threads @ 3.5×) | 114.9 |
| **Disk (6 × 7.68 TB, safety 0.60)** | **59.1 ← binds** |

Doubling RAM to 1 TB raises the RAM bound to 125.1 — and changes sellable capacity by **0.0%**, because disk still binds at 59.1. You would spend real money for no additional revenue.

The lesson generalises: **when two constraints are nearly tied, relieving one alone buys you nothing.** Always check the second-tightest constraint before spending.

The configuration that actually works moves RAM, disk, and price together — see the `Viable Config` sheet in the workbook, and §12.9 below.

**4. Start smaller than a 3-node owned cluster.** Launch on leased dedicated servers, prove demand and pricing, then buy hardware. Trades margin for dramatically reduced capital risk. For a first-time provider this is often the right call, and the model lets you compare.

**What I would not recommend:** launching a 3-node cluster at budget pricing and hoping volume fixes it. The model says volume cannot fix it, because capacity runs out before break-even.

---

## 12.2 How to use the workbook

### Sheet by sheet

| Sheet | Purpose |
|---|---|
| **README** | Legend and instructions |
| **Assumptions** | Every input. Edit blue and yellow cells only. Start here |
| **Capacity** | Plan mix → VMs per node. Identifies the binding resource |
| **Startup Costs** | One-time capex and setup, by cluster size |
| **Monthly Opex** | Recurring cost, by cluster size |
| **Revenue & Pricing** | Capacity → sellable VMs → net revenue |
| **Break-Even** | Break-even VM count, margin, payback, and the ARPU sensitivity block |
| **Scenarios** | 3 / 5 / 10 side by side, plus qualitative differences |
| **Cash Flow 24mo** | Monthly cash position with an editable ramp |
| **Viable Config** | The corrected multi-lever scenario, and why single-lever fixes fail |

### Colour convention

Blue text and yellow fill are inputs you edit. Black is a formula. Green is a cross-sheet link. Do not overwrite black or green cells.

### The order to work through it

1. **Assumptions sheet: replace every cost figure with a real quote.** Nothing else matters until you do this. The ones that move the answer most: node cost, colo, transit, IPv4, and DDoS.
2. **Capacity sheet: set your actual plan mix.** Weights must sum to 100%. Watch which resource binds — it tells you what to buy more of.
3. **Break-Even sheet: read the sensitivity block.** "Required ARPU to break even at target util" is the number that decides whether your business model works.
4. **Cash Flow sheet: set a realistic ramp.** The default is deliberately conservative: zero VMs for three months, then slow growth. Founders systematically over-forecast this.
5. **Read "Peak cash requirement"** on the Cash Flow sheet. That is the capital you must actually have.

---

## 12.3 Revenue model

### What you sell

| Revenue line | Notes |
|---|---|
| VPS subscriptions | The core. Monthly or annual, annual at a discount |
| Additional IPv4 | High margin, and it improves your IPv4 economics |
| Backup add-on | Extended retention beyond the included nightly |
| Managed services | The highest-margin line and your best differentiation against hyperscalers |
| Bandwidth overage | Only if you meter it; many providers do not |
| Snapshots / extra storage | Modest |

**Annual prepayment is a cash-flow tool, not free money.** It solves the runway problem the model exposes — but you must recognise it as deferred revenue and not spend it. A 15–20% discount for annual is standard.

### Pricing strategy

The model's conclusion is the strategy: **premium positioning is not a preference, it is a requirement at small scale.**

Differentiate on something a hyperscaler structurally cannot match:

| Differentiator | Why it can command a premium |
|---|---|
| Real human support with technical depth | Hyperscalers cannot afford this per-customer |
| Jurisdiction and data residency | A hard requirement for some customers, not a preference |
| A specific niche (game hosting, compliance, an industry vertical) | Specialised knowledge and configuration |
| Hardware nobody else offers | High-clock CPUs, huge RAM, specific GPUs |
| Local presence and language | Genuinely valuable in underserved markets |

Practical pricing guidance:

- Price the entry tier to be *credible*, not cheapest. Being 3× Hetzner on a $5 plan looks absurd; being 2× on a $30 business plan with real support is defensible
- **Publish your resource limits** — IOPS, bandwidth, CPU. Customers respect published limits and resent undisclosed throttling
- Charge for IPv4 as an add-on; include a free IPv6 `/64`
- Do not discount below the model's break-even ARPU to win a customer. You are buying revenue at a loss and it does not become profitable at volume

---

## 12.4 Cost structure

### Startup cost shape (3 nodes, default placeholders)

| Category | Approximate share |
|---|---|
| Compute nodes | ~37% |
| Other hardware (PBS, switches, routers, spares, monitoring) | ~32% |
| IPv4 acquisition | ~10% |
| Legal, formation, LIR sign-up | ~7% |
| Colo and cross-connect setup | ~4% |
| Contingency (12%) | ~11% |

**Do not set contingency below 10%.** The line items you have not thought of are real and consistent.

### Monthly cost shape

Roughly 77% infrastructure (colo, transit, cross-connects, IPv4, DDoS), 9% software and services, 14% business overhead — before any labour cost.

**Two lines founders consistently underestimate:** cross-connects (recurring, several needed) and IPv4 (often the largest single COGS item).

### Depreciation

Hardware is depreciated over 48 months. This is non-cash but you **must** reserve for it, because in year four you need to replace it. The model's "fully-loaded" break-even includes depreciation and the "cash" break-even does not — the gap between them is the trap. A business that breaks even on cash but not fully-loaded is quietly consuming its own hardware.

---

## 12.5 Break-even analysis

Two numbers, and the difference matters:

**Cash break-even** — covers cash costs. You are not losing money this month.

**Fully-loaded break-even** — covers cash costs plus depreciation. You are actually sustainable.

The rule from the Phase 2 document: **fully-loaded break-even should be below 60% of sellable capacity.** Above that, any churn puts you underwater and you can never comfortably fill the cluster. At the default assumptions the 3-node scenario is at 188% — the model is telling you the configuration is not viable, loudly.

### The most useful output in the workbook

The **required-ARPU sensitivity block** on the Break-Even sheet. It inverts the question from "will this work?" to "what would have to be true for this to work?" — which is a much more actionable question. It gives you the price you need at target utilisation and the absolute floor at 100% capacity.

---

## 12.6 Cash flow — the thing that actually kills companies

The 24-month sheet exists because break-even analysis hides a timing problem: **capex is spent in month 1 and revenue arrives over 24 months.**

With the default conservative ramp (zero VMs for 3 months, then growing), peak cash requirement is roughly **$160,000** for the 3-node scenario — considerably more than the $112,448 startup cost, because you fund operating losses throughout the ramp.

Three rules from this:

1. **Model 18 months of runway, not 6.** Revenue ramps slower than every founder expects.
2. **The ramp assumption is the most consequential input in the whole model.** Be pessimistic. Halve your instinct.
3. **Peak cash requirement, not startup cost, is the capital you need.** They are different numbers and the second one is much larger.

---

## 12.7 Scenario comparison, including what the numbers do not show

| Aspect | 3 nodes | 5 nodes | 10 nodes |
|---|---|---|---|
| Ceph self-healing | **No** | Yes | Yes |
| Rolling maintenance | Degraded | Clean | Clean |
| Ceph safety factor | 60% | 70% | 75% |
| Defensible SLA | 99.5–99.9% | 99.9–99.95% | 99.95% |
| Break-even % of capacity | 188% | 104% | 70% |
| Rack failure domains | No | No | Possible |

**The 3 → 4 node step is qualitative, not quantitative.** With three nodes and `size=3`, Ceph cannot rebuild a lost replica because there is no fourth host to put it on. Node 4 introduces self-healing; node 5 gives clean rolling maintenance. This changes the *availability category*, which changes what SLA you can honestly sell.

Order node 4 at 55% raw utilisation. Hardware lead time plus rebalance time means "when full" is already too late.

---

## 12.9 A configuration that does work

The `Viable Config` sheet models the corrected fix. Changes from baseline:

| Lever | Baseline | Viable | Why |
|---|---|---|---|
| Platform | Current-gen, $14,000 | Prior-gen/refurb, $16,000 | Costs *more* despite being refurbished, because the drives are larger |
| RAM per node | 512 GB | 1,024 GB | Necessary but not sufficient alone |
| Drives | 6 × 7.68 TB | 6 × **15.36 TB** | **The lever that actually unblocks density** |
| Thin provisioning | 1.0× | 1.5× | Sold vs actual consumption. Must be monitored |
| Switches | $12,000 new | $5,000 refurb | Established market; verify firmware access |
| Pricing | ARPU $28.55 | ARPU **$63.70** | Premium positioning, ~2.2× |
| DDoS scrubbing | Kept | **Kept** | Deliberately retained — see below |

Result:

| | Baseline (3 nodes) | Viable (3 nodes) | Change |
|---|---|---|---|
| VMs per node | 59.1 | **114.9** | +94% |
| Sellable capacity | 118 | **230** | +94% |
| Total startup cost | $112,448 | **$107,968** | −4% |
| Fully-loaded cost/month | $6,038 | $5,955 | −1% |
| Break-even VMs | 222 | **98** | −56% |
| **Break-even % of capacity** | **188%** | **43%** | comfortably under the 60% rule |
| Monthly profit at 75% util | −$3,632 | **+$4,484** | viable |
| Payback | never | **24 months** | |

At 5 nodes: 24% break-even, $14,191/month profit, 10-month payback.

### Three caveats on this configuration

**DDoS scrubbing is deliberately retained.** Dropping it saves ~$700/month and would improve these numbers further. It is a legitimate launch posture — blackhole-only means an attacked customer goes offline while everyone else survives — but it must be disclosed in your SLA exclusions and explained in your AUP. I would not cut it silently to make a spreadsheet look better.

**Thin provisioning at 1.5× is an assumption, not a fact.** It says customers use two-thirds of the disk they buy. Track actual consumption against sold capacity and alert at 70% of *real* capacity. Above 2× you are gambling with a resource you cannot reclaim quickly.

**Premium pricing at $63.70 ARPU requires a product that justifies it.** $34/month for 2 vCPU / 4 GB is roughly 2× DigitalOcean and considerably more than Hetzner. That is defensible with real human support, a jurisdiction customers need, or a niche — and indefensible without one. The pricing lever and the positioning work are the same decision.

## 12.8 What to do with all this

The model's job is to make you confront the arithmetic before you spend $112,000. Concretely:

1. Get real quotes and replace every placeholder
2. Read the required-ARPU figure
3. If it is far above what your market will pay, change the plan — pricing, positioning, density, or starting on leased hardware — **before** buying anything
4. Compute your peak cash requirement and confirm you actually have it
5. Have an accountant review the assumptions and the deferred-revenue treatment

If the numbers do not work, that is the model doing its job. It is much cheaper to discover it in a spreadsheet than in month fourteen.
