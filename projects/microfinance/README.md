# Microfinance — Feasibility & Capital Allocation

Scoping project for a South African lending business with three profit engines:
a loan book, credit life insurance on those loans, and a funeral book. This
directory holds the decision material only; no application code has been written
yet, and none should be until the go/no-go gates below are cleared.

> **Separate business, separate repo.** This lives under `projects/` in the
> receptionist repo purely so the analysis is version-controlled alongside the
> session that produced it. Before any implementation starts, it must move to
> its own repository — a regulated lender and insurer shares no code, no
> database, and no deployment surface with a dental practice.

## Contents

| File | What it is |
|---|---|
| `loan-book-model.html` | Interactive model. Three profit engines, three ownership structures, live assumptions, benchmarked against an S&P 500 hurdle |

Published model: https://claude.ai/code/artifact/c4eacb06-db5e-4040-b347-5638488282d2

---

## The question this answers

Not "can a loan book make money" — it can. The question is whether the group
makes enough to beat the alternative use of the same rand, given that the
alternative is liquid, requires no staff, and carries no regulator.

### The hurdle

| Component | Value |
|---|---|
| S&P 500 long-run nominal return (USD) | 10.0% |
| Rand depreciation vs USD | 4.5% / yr |
| **Index return in rand terms** | **14.95%** (compounded, not added) |
| Illiquidity & concentration premium | +10.0% |
| **Hurdle rate** | **≈24.9%** |

---

## Headline finding

**The insurance is the business. The loan book is the distribution channel.**

At R3m deployed into payroll-deduction lending, through a microinsurance cell
captive, with 1 200 funeral policies in force:

| Engine | Annual profit | Capital consumed |
|---|---|---|
| Lending margin | R1.17m | R3.00m |
| Credit life | R90k | — |
| Funeral book | R556k | — |
| Fixed compliance cost | −R453k | — |
| **Group** | **R1.36m** | **R3.28m → 41.5% ROC** |

Lending alone returns 29.8%. The insurance engines add **11.7 points** while
consuming almost no capital, and they eliminate the minimum-book constraint
entirely — insurance income covers the fixed compliance base that previously
sank any book below ~R2m.

### Why credit life is so profitable, and why that is a warning

Credit life is capped at **R4.50 per R1 000 of the deferred amount**, with
prescribed minimum benefits for death, permanent and temporary disability, and
retrenchment. Market claims ratios ran **under 10%** — roughly R15bn of annual
premium against R1.5bn of claims — which is exactly what provoked the 2017 cap.

Two consequences follow, and both belong in the plan:

1. **Assume the R4.50 ceiling moves down, not up.** Do not build a business that
   only works at today's margin.
2. **Borrowers hold a statutory right to substitute their own policy** at any
   time. A high take-up assumption is a commercial assumption, not a given.

Credit life also has a second-order benefit most models miss: death, disability
and retrenchment claims settle the loan, so a share of what would have been a
write-off is recovered from the policy. The model reduces effective loss given
default accordingly — at the default assumptions, payroll LGD falls from 55% to
about 47%.

### Why the funeral book is the larger opportunity, and its single risk

Funeral cover is South Africa's largest insurance category by policy count, with
roughly **30 million policies in force** and **6.2 million sold in 2025**. It
consumes no lending capital, which is what lets it carry fixed cost the loan
book cannot.

Its economics live or die on one number. **Nearly a quarter of funeral policies
do not survive the first year, and a comparable share lapse before the first
premium is ever collected.** Acquisition cost is therefore incurred repeatedly
on the same customer.

This is the strategic case for attaching it to payroll-deduction lending: one
deduction instruction at source carries the loan, the credit life and the
funeral premium. That collapses both acquisition cost and lapse — the two
variables that destroy funeral books sold cold.

---

## Structure: who carries the risk

This is a capital decision before it is a risk decision, and it is close to
binary at a R1m–R5m budget.

| Structure | Capital | Group ROC | Verdict |
|---|---|---|---|
| **Microinsurance cell captive** | R250k floor, scaling with premium | **41.5%** | **Take this** |
| Intermediary only | Nil | 34.7% | Safe, but you give away the underwriting profit |
| Own microinsurance licence | **R4m floor** | 10.7% | Not viable at this capital level |

Your own licence is gated behind a minimum capital requirement of **15% of net
written premium, floored at R4 million** — which at a R1m–R5m budget would
consume the entire loan book and leave nothing to lend. A cell inside a licensed
microinsurer (Guardrisk, Centriq) gets the underwriting profit for **R250 000**,
with the provider supplying licence, actuarial and compliance for a share of
premium.

Commission economics also differ by product: credit life commission is capped at
**7.5%** (the 22.5% band was removed from 1 January 2019), while **funeral and
risk classes are not capped**.

---

## Lending models on their own merits

Computed at R3m, before insurance income.

| Rank | Model | Net ROC | Note |
|---|---|---|---|
| 1 | Payroll-deduction consumer | 29.8% | Clears the hurdle alone |
| 2 | SME invoice & working capital | 13.0% | No insurance attachment — pure lending play |
| 3 | Asset-backed lending | 10.7% | Capital locked 30 months |
| 4 | Short-term unsecured | −5.3% | Case rests on being a funnel, not a lender |

Three mechanics drive this ranking:

**Return is measured on capital-months, not principal advanced.** An amortising
loan returns capital progressively; a 1-month loan redeploys the same rand ten
times a year. The model builds an exact amortisation schedule and sums the
outstanding balance month by month. That same schedule gives the credit life
premium base directly, since premium accrues on the outstanding balance.

**Asset-backed fails on velocity, not credit quality.** 30-month terms mean
capital turns 0.4× a year.

**Short-term unsecured is a cost-to-serve problem, not a yield problem.** At 5%
per month it has the highest headline yield and still loses money: R250 of
origination cost and a 12% default rate on a R4 000 loan overwhelm R725 of gross
revenue. Automate origination below R150/loan and it inverts.

---

## Recommendation

| Phase | Action | Gate to the next phase |
|---|---|---|
| **0** | NCR registration, FAIS licence, cell captive mandate, attorney and actuarial sign-off | Registrations granted |
| **1** | Payroll-deduction lending with credit life attached. Two or three employer partners | 12 months with actual PD ≤ 8% and take-up ≥ 80% |
| **2** | Funeral book sold into the payroll base on the same deduction | Lapse ≤ 15% on the payroll-attached cohort |
| **3** | Funeral distribution beyond the loan book | Proven acquisition cost and lapse outside the base |
| **4** | SME invoice finance under the juristic-person exemption | Loss experience confirms LGD ≤ 40% |
| **—** | Asset-backed, own insurance licence | Not at this capital level |

Phase 1 remains **a sales problem before a lending problem** — the economics
depend on deduction at source, which depends on employer relationships. Secure
two employers before deploying capital, not after.

---

## Regulatory map

| Item | Rule | Limit |
|---|---|---|
| Unsecured credit | (repo × 2.2) + 20% | 35.4% p.a. at repo 7.00% |
| Other credit agreements | (repo × 2.2) + 10% | 25.4% p.a. |
| Short-term credit | 5%/month first loan, 3% after | ≤ R8 000 over ≤ 6 months |
| Initiation fee | R165 + 10% above R1 000 | R1 050 cap, excl VAT |
| Monthly service fee | Flat | R60/month, excl VAT |
| Juristic-person exemption | Turnover or assets ≥ R1m | NCA does not apply |
| NCR registration | Mandatory, every provider | R550 + R250/branch |
| Credit life premium | Per R1 000 of deferred amount | R4.50 (R2.00 mortgage) |
| Credit life commission | Where you carry no risk | 7.5% of premium |
| Funeral commission | Where you carry no risk | Not capped |
| Microinsurance cell captive | Cell in a licensed insurer | R250 000 capital |
| Own microinsurance licence | 15% of net written premium | R4m floor |

### The juristic-person exemption

Under section 4(1) of the National Credit Act, a credit agreement falls outside
the Act entirely where the borrower is a juristic person whose asset value or
annual turnover meets or exceeds **R1 million**. Section 4(1)(b) extends this to
large agreements (principal ≥ R250 000) with smaller juristic persons. That
removes rate caps, fee caps and the prescribed affordability assessment from SME
lending — but credit life does not attach to business lending either, so the SME
model is a pure lending play with no insurance upside.

### Not modelled, and each one real

The *in duplum* rule; reckless-lending exposure under ss.80–83, which can void an
agreement entirely; FICA; POPIA; mandatory credit bureau reporting; Debt
Collectors Act registration for in-house collections; FAIS licensing,
key-individual competency and representative supervision for selling any
insurance product; and Treating Customers Fairly conduct standards, which apply
with particular force to exactly these two products.

**Distribution is the largest omission.** The model charges acquisition and admin
per policy but carries no sales force, branch network, call centre or agent
commission structure. A book of several thousand funeral policies is a
distribution business before it is an underwriting one. Treat large policy counts
in the model as showing the shape of the opportunity, not a plan fundable at
those margins.

This is a commercial model, not legal or actuarial advice. The licensing path
needs sign-off from a credit-regulatory attorney, and the insurance pricing from
a qualified actuary, before a rand goes out.

---

## Assumptions register

| Assumption | Value | Confidence | How to verify |
|---|---|---|---|
| SARB repo rate | 7.00% (Aug 2026) | High | resbank.co.za |
| NCA unsecured ceiling formula | (repo × 2.2) + 20% | **Low — sources conflict** | Government Gazette |
| Juristic-person exemption | R1 000 000 | High | NCA s.4(1) |
| Credit life premium cap | R4.50 per R1 000 | High | Credit life regulations, 9 Aug 2017 |
| Microinsurer MCR | 15% of NWP, R4m floor | High | Insurance Act 2017 |
| Cell captive capital | R250 000 floor | Medium | Quote Guardrisk / Centriq directly |
| Cell fee | 6% of premium | **Low — estimate** | Quote directly |
| Fixed credit-provider cost | R273 000 / yr | **Low — estimate** | Quote each line item |
| Insurance compliance cost | R180 000 / yr (cell) | **Low — estimate** | Quote each line item |
| Credit life claims ratio | 22% | Medium | Market ran <10% pre-cap |
| Funeral claims ratio | 45% | Medium | Actuarial pricing required |
| Funeral lapse rate | 28% / yr | Medium | ~25% fail year one industry-wide |
| Payroll-deduction PD | 6% | Medium | Employer-specific |

The low-confidence items are concentrated in the **cost stack and the cell
terms** — not in the revenue lines. All are settled by three phone calls: a cell
captive provider, a credit-regulatory attorney, and an actuary. Do that before
any further work.
