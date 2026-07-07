# Koupon — Reward List v1 (KP pricing)

**Status:** Draft, first pass — pricing model, not final
**Date:** 6 July 2026
**Owner:** Tania

---

## 1. Basis for pricing

Reward prices are pegged to one benchmark: **~1,000 KP = a year of earnings for a moderately active member.**

That figure is built from two pieces:

- **Guaranteed income** — the weekly +5 KP drip, steady-state: 5 × 52 = **260 KP/year**. This is the only number the pilot actually guarantees; every member gets it whether or not they trade.
- **Assumed activity income** — since no transaction history exists yet, I've assumed a moderately active member also completes roughly one small paid activity a week at ~15 KP average, i.e. **~780 KP/year** from peer-to-peer work.

260 + 780 ≈ 1,040, rounded to **1,000 KP/year**. This is a placeholder, not a measurement — it should be replaced with the real average once the pilot has a few months of activity data behind it. Everything below scales off it, so revisiting this one number re-prices the whole list.

The one-off 100 KP start grant is excluded from the benchmark since it's not recurring.

---

## 2. Vote results

| Reward | Votes | Share |
|---|---|---|
| Claude subscription | 4 | 28% |
| Laptop | 3 | 21% |
| PlayStation | 2 | 14% |
| Sport clothing of choice | 2 | 14% |
| Perfume of choice | 2 | 14% |
| Streaming service gift card | 1 | 7% |
| Apple Watch | 0 | 0% |
| iPhone upgrade | 0 | 0% |
| Drone | 0 | 0% |

Apple Watch, iPhone upgrade, and Drone drew zero votes — excluded from v1 below rather than forced in. See note at the end on one possible use for them.

---

## 3. Reward list — KP prices

Prices are scaled from rough real-world cost against the 1,000 KP/year benchmark (Laptop anchors near a full year; everything else scales proportionally). Treat the underlying dollar figures as ballpark, not quoted prices — the ratios are the point, not the exact numbers.

| Reward | Approx. real-world value | KP price | ≈ time to earn* |
|---|---|---|---|
| Claude subscription (1 month) | $20 | **25 KP** | ~1.5 weeks |
| Streaming service gift card | $25 | **30 KP** | ~2 weeks |
| Sport clothing of choice | $80 | **90 KP** | ~1 month |
| Perfume of choice | $100 | **110 KP** | ~5–6 weeks |
| PlayStation | $500 | **550 KP** | ~6.5 months |
| Laptop | $900 | **1,000 KP** | ~1 year |

*At the ~1,000 KP/year assumed earning rate above.

---

## 4. Notes

- **Highest-voted ≠ highest-priced.** Claude subscription topped the vote and is the cheapest item on the list — consistent with people voting for what's actually attainable rather than what's most valuable in the abstract. Worth watching whether that pattern holds as more rewards get added.
- **Laptop and PlayStation are stretch items** by design — a full year (or more) of saving with zero redemptions elsewhere. If early redemption data shows nobody's reaching them, that's a signal to either lower the price or accept they're meant to be rare.
- **Apple Watch / iPhone upgrade / Drone (0 votes)** are natural candidates for the **grand prize** the project brief still has as an open question — priced well above the annual benchmark (e.g. 2,000+ KP) as a deliberate high-end sink, rather than added to the regular list where they'd currently be dead weight.
- This whole list assumes redemption returns KP to the issuer treasury, per the existing design (Section 3 of the requirements brief) — nothing here changes that mechanic, only the prices.

---

## 5. Open follow-up

Revisit the 1,000 KP/year benchmark once real activity data exists — the 780 KP "assumed activity income" half of it is a guess with no pilot data behind it yet.
