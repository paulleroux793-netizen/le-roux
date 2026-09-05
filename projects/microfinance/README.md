# Microfinance — Feasibility & Capital Allocation

Scoping project for a South African lending business. This directory holds the
decision material only; no application code has been written yet, and none
should be until the go/no-go gates below are cleared.

> **Separate business, separate repo.** This lives under `projects/` in the
> receptionist repo purely so the analysis is version-controlled alongside the
> session that produced it. Before any implementation starts, it must move to
> its own repository — a regulated lender shares no code, no database, and no
> deployment surface with a dental practice.

## Contents

| File | What it is |
|---|---|
| `loan-book-model.html` | Interactive unit-economics model. Four lending models, live assumptions, benchmarked against an S&P 500 hurdle |

Published model: https://claude.ai/code/artifact/c4eacb06-db5e-4040-b347-5638488282d2

---

## The question this answers

Not "can a loan book make money" — it can. The question is whether it makes
enough to beat the alternative use of the same rand, given that the alternative
is liquid, requires no staff, and carries no regulator.

### The hurdle

| Component | Value | Source |
|---|---|---|
| S&P 500 long-run nominal return (USD) | 10.0% | Long-run historical |
| Rand depreciation vs USD | 4.5% / yr | Long-run historical drift |
| **Index return in rand terms** | **14.95%** | Compounded, not added |
| Illiquidity & concentration premium | +10.0% | Judgement |
| **Hurdle rate** | **≈24.9%** | What a private book must clear |

A loan book returning 18% is not a good business. It is a worse index fund with
staff, a regulator, and no exit.

---

## Findings at R3m deployed

Computed by the model at its default assumptions. Every figure is an input you
can move.

| Rank | Model | Net ROC | Verdict |
|---|---|---|---|
| 1 | Payroll-deduction consumer | **29.3%** | Clears the hurdle |
| 2 | SME invoice & working capital | 13.0% | Below hurdle |
| 3 | Asset-backed lending | 10.7% | Below hurdle |
| 4 | Short-term unsecured | −5.3% | Loses money |

### Three things drive the whole result

**1. Fixed compliance cost is the binding constraint, not credit risk.**
Being a registered credit provider costs roughly R273k a year before a single
loan is written — NCR renewal, audited financials, credit bureau access, legal,
loan management software, payment rails. At a R1m book that is 27% of capital
consumed by overhead, and *nothing* clears the hurdle. At R3m it is 9%. The
model reports a **minimum viable book of ≈R2.03m** for the strongest strategy.

Below roughly R2m, this is not a business regardless of how well you lend.

**2. Return must be measured on capital-months, not principal advanced.**
An amortising loan returns capital progressively; a 1-month loan redeploys the
same rand ten times a year. Measuring return against face value understates
short-dated books badly and overstates long-dated ones. The model builds an
exact amortisation schedule and sums the outstanding balance month by month.

This is why asset-backed lending ranks poorly: 30-month terms mean capital turns
0.4× a year. At a R1m–R5m book you could fund roughly twenty deals and then have
no liquidity for two and a half years.

**3. Short-term unsecured is a cost-to-serve problem, not a yield problem.**
At 5% per month it has the highest headline yield of the four and still loses
money, because R250 of origination cost and a 12% default rate on a R4 000 loan
overwhelm R725 of gross revenue. It becomes viable only if origination is
automated to near-zero marginal cost and defaults are held down by debit-order
collection. Every rand automated out of cost-to-serve drops straight to net.

---

## Recommendation: sequence, don't spread

R1m–R5m cannot fund four books. Spread four ways it buys ~R250k–R1.25m per book
— too thin to generate statistically meaningful credit performance in any of
them, while paying four sets of fixed cost.

| Phase | Action | Gate to the next phase |
|---|---|---|
| **0** | NCR registration, attorney sign-off, credit policy, bureau contracts | Registration granted |
| **1** | Payroll-deduction only. Two or three employer partners. Full book ≥ R2m | 12 months of data with actual PD ≤ 8% |
| **2** | Add SME invoice finance, priced contractually under the juristic-person exemption | Loss experience confirms LGD ≤ 40% |
| **3** | Short-term unsecured, but only once origination is fully automated | Cost-to-serve < R150/loan |
| **—** | Asset-backed | Not at this capital level |

Phase 1 is a **sales problem before it is a lending problem**. The economics
depend entirely on deduction at source, which depends on employer relationships.
Secure two employers before deploying capital, not after.

---

## Regulatory map

Registration is mandatory for every credit provider regardless of book size —
the R500 000 threshold was removed in 2016.

| Ceiling | Formula | At repo 7.00% |
|---|---|---|
| Unsecured credit | (repo × 2.2) + 20% | 35.4% p.a. |
| Other credit agreements | (repo × 2.2) + 10% | 25.4% p.a. |
| Credit facilities | (repo × 2.2) + 10% | 25.4% p.a. |
| Mortgage agreements | (repo × 2.2) + 5% | 20.4% p.a. |
| Short-term credit | 5%/month first loan, 3% thereafter | ≤ R8 000 over ≤ 6 months |
| Initiation fee | R165 + 10% above R1 000 | R1 050 cap, excl VAT |
| Monthly service fee | Flat | R60/month, excl VAT |

### The juristic-person exemption is the largest structural lever available

Under section 4(1) of the National Credit Act, a credit agreement falls outside
the Act entirely where the borrower is a juristic person whose asset value or
annual turnover meets or exceeds **R1 million**. Section 4(1)(b) extends this to
large agreements (principal ≥ R250 000) with smaller juristic persons.

That removes rate caps, fee caps, and the prescribed affordability assessment
from SME lending to established businesses. It is why the SME model is priced
contractually at 3%/month rather than at a statutory ceiling, and it is the
single biggest reason to prefer business lending over consumer lending on a
regulatory-cost basis.

### Verify before committing capital

- **The rate-cap formula is contested in public sources.** Practitioner
  commentary splits between `(repo × 2.2) + 20%` and `repo + 21%` for unsecured
  credit — roughly seven percentage points of gross yield. The model uses the
  multiplier form and exposes it as an input. Confirm against the Government
  Gazette.
- **Not modelled, each one real:** the *in duplum* rule capping accrued interest
  and fees at outstanding principal on default; reckless-lending exposure under
  ss.80–83, which can void an agreement entirely; FICA obligations as an
  accountable institution; POPIA; mandatory credit bureau reporting; Debt
  Collectors Act registration for in-house collections.

This is a commercial model, not legal advice. The licensing path needs sign-off
from a credit-regulatory attorney before a rand goes out.

---

## Assumptions register

| Assumption | Value | Confidence | How to verify |
|---|---|---|---|
| SARB repo rate | 7.00% (Aug 2026) | High | resbank.co.za |
| Prime | 10.50% | High | Repo + 3.5% by convention |
| NCA unsecured ceiling formula | (repo × 2.2) + 20% | **Low — sources conflict** | Government Gazette |
| Juristic-person exemption threshold | R1 000 000 | High | NCA s.4(1) |
| NCR application fee | R550 + R250/branch | Medium | NCR directly |
| Fixed annual compliance cost | R273 000 | **Low — estimate** | Quote each line item |
| Payroll-deduction PD | 6% | Medium | Employer-specific |
| Short-term unsecured PD | 12% | Medium | Sector data: ~15% repeat, ~30% first-time |

The two low-confidence items — the rate formula and the fixed cost stack — are
also two of the three largest drivers of the result. Both are cheap to verify
and should be settled before any further work.
