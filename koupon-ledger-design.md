# Koupon — Ledger & Escrow Design (real-money blueprint)

**Status:** Blueprint — shelved for now
**Date:** 29 June 2026 · updated 30 June 2026
**Owner:** Tania

> **Which version is this?** This is the money model for the **real-money version** of Koupon, not the live build. The live build is a just-for-fun family pilot (`koupon-pilot.html`, see `README.md`) that is honour-system and needs none of this. Keep this document as the blueprint to build from if the pilot succeeds and you decide to make KP genuinely valuable — at that point this rigour becomes necessary.

**Scope:** The server-side money model — how KP is stored, moved, and held in escrow, and the rules that must never be violated. It is deliberately concrete enough to build from, but stops short of API and framework detail.

---

## 1. Core model: a double-entry, append-only ledger

KP is tracked with a **double-entry ledger**: every movement is recorded as a set of entries that sum to zero, posted against accounts. Balances are **derived** from entries, never edited directly.

This model is chosen deliberately because it makes the system's guarantees structural rather than hopeful:

- **Conservation is automatic.** Because every transaction's entries sum to zero, KP can never be created or destroyed except through an explicit mint. You cannot accidentally lose or invent KP.
- **It is auditable.** Every balance is the sum of an immutable history. You can always answer "why is this balance what it is?"
- **It is correctable without rewriting history.** Entries are never updated or deleted; a mistake is fixed with a new compensating transaction. The trail stays intact.

The ledger is **append-only**. A cached `balances` table is maintained in lockstep for fast reads, but it is a derived convenience — the entries are the source of truth, and a reconciliation job periodically asserts that the cache still equals the sum of entries.

**KP units are whole integers.** No fractional KP, no floating-point arithmetic anywhere in the money path. (Floats and money do not mix; this prevents rounding errors entirely.) *Decision to confirm: KP has no sub-units.*

---

## 2. Accounts

Every balance in the system lives in an account. There are four account types:

| Account | Count | Purpose |
|---|---|---|
| `USER` | one per user | A user's spendable KP balance. |
| `ISSUER_TREASURY` | singleton | Holds KP returned by redemptions; the preferred source for the monthly drip. |
| `MINT` | singleton | The source of newly created supply. Its balance is the negative of all KP ever minted. |
| `ESCROW` | singleton | Holds KP locked in in-flight activities. Per-activity amounts are tracked via the activity record, not separate accounts. |

Merchants have **no KP account** — consistent with the brief, they are reimbursed in fiat in Phase 2 and never hold KP.

The sum of all account balances is always exactly zero. Equivalently: `users + escrow + treasury = total minted` (the negative of the MINT balance).

---

## 3. Transaction types

Every state change to money is one of these. Each is atomic — all its entries commit together or none do.

| Type | Movement (debit → credit) | Trigger | Notes |
|---|---|---|---|
| `GRANT` | `MINT → USER` (100 KP) | New verified account | One per user, ever. |
| `DRIP` | `TREASURY → USER`, shortfall `MINT → USER` (5 KP) | Monthly, per account | Funded from treasury first; mint only the shortfall. One per user per period. |
| `ESCROW_HOLD` | `USER(payer) → ESCROW` (price P) | Activity agreed | Requires payer balance ≥ P. |
| `ESCROW_RELEASE` | `ESCROW → USER(performer)` (P) | Completion confirmed | Exactly once per activity. |
| `ESCROW_REFUND` | `ESCROW → USER(payer)` (P) | Cancellation / dispute resolved for payer | Exactly once per activity; mutually exclusive with RELEASE. |
| `REDEMPTION` | `USER → TREASURY` (amount R) | User claims a reward | KP returns to issuer; reward fulfilled off-ledger. |

There is no merchant transaction in Phase 1. Reward fulfilment and (Phase 2) merchant reimbursement are tracked off the KP ledger.

---

## 4. Invariants — the rules that must always hold

These are the contract. Each is enforced both in application logic and, where possible, by a database constraint. If any can be violated, the design is wrong.

1. **Zero-sum.** Every transaction's entries sum to zero. (Conservation.)
2. **No negative user balances.** A `USER` account can never go below zero. (Escrow holds and redemptions check funds first, under a row lock.)
3. **Mint is issuer-only.** Entries touching `MINT` occur only within `GRANT` and `DRIP`. No other path creates supply.
4. **One grant per user.** A user receives exactly one `GRANT`, ever.
5. **One drip per user per period.** A unique `(user, period)` key makes double-crediting the monthly allocation impossible, even if the job re-runs.
6. **Escrow resolves exactly once.** An activity's escrow can be either released or refunded, once — never both, never twice.
7. **Escrow conservation.** The `ESCROW` balance always equals the sum of held amounts of all activities currently in an escrowed state.
8. **Append-only.** Ledger entries are immutable. Corrections are new compensating transactions, never edits or deletes.
9. **Idempotency.** Every transaction carries a unique operation key; replaying it is a no-op, not a duplicate.
10. **Atomicity.** All entries of a transaction (and the matching balance-cache updates) commit in a single database transaction or not at all.

---

## 5. Activity & escrow state machine

An activity is a service one user (the **performer**) does for another (the **payer**), at an agreed price P. KP is held in escrow from agreement until the outcome is settled, so neither side can be cheated by the other acting first.

```
            agree (ESCROW_HOLD)
   OFFERED ────────────────────────▶ AGREED
      │                                 │
      │ decline                         │ performer marks done
      ▼                                 ▼
  CANCELLED                         COMPLETED
  (no escrow)                           │
                          ┌─────────────┼──────────────┐
              payer confirms │       dispute            │ timeout (T days, no action)
            (ESCROW_RELEASE) │   (escrow frozen)        │ auto-confirm (ESCROW_RELEASE)
                          ▼             ▼                ▼
                       CLOSED        DISPUTED         CLOSED
                      (released)        │            (released)
                                  issuer arbitrates
                                   ┌────┴────┐
                                   ▼         ▼
                              CLOSED       CLOSED
                            (released)   (refunded, ESCROW_REFUND)
```

State summary:

- **OFFERED** — terms proposed; no KP moved. Either party can walk away (→ CANCELLED) with no ledger effect.
- **AGREED** — both accept; `ESCROW_HOLD` locks P from the payer. The activity now owns that escrow. From here the activity can also be **cancelled** — by mutual agreement, or by a performer no-show timeout — which triggers `ESCROW_REFUND` back to the payer. (Without this, an abandoned activity would trap the payer's KP in escrow forever.)
- **COMPLETED** — performer marks the work done. KP still held.
- **CLOSED (released)** — payer confirms, or a timeout auto-confirms; `ESCROW_RELEASE` pays the performer.
- **DISPUTED** — payer contests; escrow is frozen pending issuer arbitration, which resolves to release (performer) or `ESCROW_REFUND` (payer).
- **CANCELLED / refunded** — escrow, if any, returns to the payer.

**Two defaults proposed here, both flagged for your confirmation:**

- **Auto-confirm timeout (T).** If the payer neither confirms nor disputes within T days of completion, the system auto-confirms and releases to the performer. Without this, a payer could grief a performer by simply never confirming, trapping their own KP and the performer's payment forever. *Default proposed: 7 days.*
- **Performer no-show timeout.** If an activity sits in AGREED with no completion for some window, it can be cancelled and the escrow refunded to the payer, so an abandoned job doesn't lock funds indefinitely. *Default proposed: 14 days.*
- **Dispute resolution = issuer arbitration.** For the MVP, a disputed activity is decided manually by the issuer. A fuller automated flow can come later. (This is one of the brief's parked questions; manual is the safe MVP answer.)

---

## 6. Data model (Phase 1)

Tables, with the columns that matter for integrity:

- **`users`** — `id`, `handle` (unique), `phone_verified`, `created_at`.
- **`accounts`** — `id`, `type` (USER/TREASURY/MINT/ESCROW), `owner_user_id` (null for singletons), `created_at`.
- **`transactions`** — `id`, `type`, `idempotency_key` (unique), `metadata` (e.g. activity_id, reward_id), `created_at`.
- **`ledger_entries`** — `id`, `transaction_id`, `account_id`, `amount` (signed BIGINT), `created_at`. *Append-only.* Sum of `amount` per `transaction_id` = 0.
- **`balances`** — `account_id`, `balance` (BIGINT). Derived cache, updated inside the same DB transaction as the entries.
- **`activities`** — `id`, `payer_id`, `performer_id`, `price`, `state`, `escrow_transaction_id`, `completed_at`, `resolved_at`, dispute fields.
- **`redemptions`** — `id`, `user_id`, `reward_id`, `amount`, `transaction_id`, `fulfilment_status`, `fulfilled_by`.
- **`drip_runs`** — `user_id`, `period` (e.g. `2026-07`), `transaction_id`. Unique `(user_id, period)`.

---

## 7. Concurrency & integrity

- **Money writes are serialized per account.** Holding escrow or redeeming locks the payer's account row (or uses an equivalent serializable boundary) so two concurrent spends can't both pass the balance check and overdraw. This is the classic double-spend guard.
- **Integer amounts only**, stored as BIGINT. No floats touch KP.
- **Idempotency keys** on every transaction make client retries and job re-runs safe.
- **Reconciliation job** periodically asserts, for every account, that the cached balance equals the summed entries, and that the global sum is zero. Any drift is an alarm, not a silent error.

---

## 8. Decisions made here (confirm) and open questions

Decided in this doc, pending your nod:
- KP is integer-only, no sub-units.
- Single `ESCROW` holding account, with per-activity amounts tracked on the activity record.
- Escrow auto-confirm after **7 days** of payer inaction.
- Disputes resolved by **manual issuer arbitration** for the MVP.
- The payer (service requester) funds escrow; the performer is paid on release.

Still open (from the brief, not blocking the backend build):
- Grand-prize mechanism and amount.
- Reward pricing strategy relative to the issuance rate.
- Offline support for redemption / activity confirmation.
- Launch scale (affects infrastructure sizing, not the model).

---

## 9. Next step

With this model agreed, the first code is the **backend ledger service**: the schema above, the six transaction types as atomic operations, the invariants enforced in code, and a test suite that tries to violate each invariant and proves it can't. The activity state machine sits on top of the escrow transactions. Only once that is green does the API surface — and then the React Native app — become worth building.
