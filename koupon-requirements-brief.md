# Koupon — Requirements Brief (real-money blueprint)

**Status:** Blueprint — shelved for now (rev. 3)
**Date:** 29 June 2026 · updated 30 June 2026
**Owner:** Tania

> **Which version is this?** There are two tracks. The **live build** is a just-for-fun family pilot — the app in `koupon-pilot.html` (see `README.md`): honour-system, in-person QR transfers, no server, no real value. **This document and `koupon-ledger-design.md` describe the other track: a real-money version**, kept as the blueprint to build from if the pilot takes off and you decide to make KP genuinely valuable. None of it is needed to run the pilot; it is retained on purpose.

**Purpose:** Single source of truth for the real-money design decisions. It states what that version would be, the constraints that must not be crossed, and the questions still open. It is intentionally short and decision-focused, not a specification.

---

## 1. Product summary

Koupon is a mobile app built around a custom, closed-loop currency called *koupon* (KP). It is a peer-to-peer activity economy: users perform activities for one another, charge each other in KP, and settle on completion. The issuer governs the money supply and a reward list against which users redeem KP.

Every user starts with a fixed 100 KP. The issuer adds 5 KP to each account every month. KP moves between users as they complete paid activities, and flows back to the issuer when users redeem it for rewards — so the loop is closed and KP never leaves the system.

The product is for real users from its first release (a working MVP), not a throwaway prototype.

---

## 2. Hard constraints

These define the product's legal and economic character. They are not to be crossed without a deliberate, documented decision, because crossing any of them changes the regulatory picture materially.

- **No buy-in.** Users never purchase KP with money. KP enters a user's hands only via the starting grant, the monthly allocation, or payment from another user.
- **No cash-out.** Users can never convert KP back into money.
- **Single minter.** Only the issuer creates or allocates KP supply. No user or merchant can increase the total in circulation.
- **One balance per user.** A user holds a single KP balance. The starting grant, monthly allocation, and activity payments are all the same KP.
- **Closed loop.** KP cycles issuer → users → issuer. It is never destroyed and never leaves the system.

Holding the first two lines keeps KP in promotional territory rather than stored-value or money-transmission regulation. This is the most valuable constraint set in the product and should be protected deliberately as it grows.

---

## 3. Money supply and the KP lifecycle

KP follows one closed cycle:

1. **Grant.** A new, verified account receives a fixed 100 KP.
2. **Allocation (drip).** The issuer adds 5 KP to every account each month, unconditionally.
3. **Circulation.** Users charge each other for activities and settle in KP on completion. This only moves KP sideways — the total is unchanged.
4. **Redemption.** A user spends KP against the reward list. The KP returns to the issuer's treasury (it is not burned). The reward itself is fulfilled by the issuer or a merchant.
5. **Recycling.** Returned KP is held by the issuer and re-used to fund future monthly allocations.

**Supply governance — recommended rule:** fund the monthly drip from returned KP first, and mint fresh KP only for the shortfall. This keeps circulating supply stable and self-balancing. Minting the drip fresh while redemptions also return KP to the treasury would inflate total supply over time. Issuance rate versus reward pricing is the central ongoing lever and should be monitored from day one.

The **grand prize** (amount and mechanism still to be determined) acts as a large, deliberate sink for users who accumulate high balances.

---

## 4. Actors and boundaries

### Issuer (you)
The central authority and supply governor. Grants the starting 100 KP, runs the monthly allocation, owns the reward list with final authority over it, fulfils or reimburses rewards, and holds the treasury of returned KP. Carries the liability represented by KP in circulation.

### User
Holds a single KP balance. Starts with 100 KP, receives 5 KP monthly, performs and pays for activities with other users via `@handle`, and redeems KP against the reward list. Cannot mint or cash out.

### Merchant
A verified business that supplies items to the reward list and is reimbursed by the issuer (out-of-band, in fiat or credit) for each reward a user redeems. The issuer outranks merchants in curating the list. **Merchants do not hold KP balances:** redeemed KP returns to the issuer, and the merchant holds only a reimbursement claim per fulfilled reward. *(Interpretation to confirm.)*

A merchant **can**: list rewards (subject to issuer approval), view its fulfilled-redemption history, and receive settlement statements. A merchant **cannot**: mint or hold KP, transact KP with users directly, set reward terms outside issuer rules, or convert KP to cash.

---

## 5. Core mechanics

**Starting grant.** 100 KP on account creation, after identity verification.

**Monthly allocation.** +5 KP to every account each month, unconditional. (Identity verification at onboarding is the control point against farming, since the drip itself is not gated.)

**Activities (peer-to-peer, with escrow).** A user agrees to perform an activity for another at an agreed KP price. The payer's KP is held in escrow when the activity is agreed and released to the performer when completion is confirmed. Escrow requires a completion-confirmation step and a path for disputes (to be designed).

**Redemption.** A user picks an amount/item from the reward list; that KP returns to the issuer's treasury and the reward is fulfilled by the issuer or the supplying merchant.

**Reward list.** Jointly stocked by the issuer and merchants, with the issuer holding final authority. Includes a grand prize (TBD).

**Identity / auth.** Phone-number OTP recommended as the backbone, because the unconditional drip and 100 KP grant make every account a real, redeemable cost — so sybil resistance matters more than onboarding speed. Apple/Google sign-in may be offered alongside, tied to a verified phone before an account can earn, transact, or redeem.

**Platform / app form.** Cross-platform native via **React Native + Expo**, launching **iPhone-first**. Chosen over iPhone-only native because the app is transactional (balances, lists, forms, push) rather than graphics- or compute-heavy, so native offers no real advantage here — while a cross-platform codebase keeps Android a low-cost option the network-effect model will likely need. Chosen over Flutter because the builder is undecided/likely hired: React Native has the largest talent pool and shares JS/TS with the backend and a future web admin. **All money logic stays server-side; the app is a thin, untrusted client** that calls an API and never computes or trusts a balance on-device.

**Deployment (family pilot).** The first deployment is a private family pilot, optimised for near-zero cost and ops — **not** a public launch. Backend on **Supabase free tier** (managed Postgres), chosen because the ledger's invariants rely on Postgres atomic transactions, constraints, and row locks, and Supabase includes phone-OTP auth. The six money operations run as **server-side database functions**, with **row-level security** so a phone can only read its own balance and call controlled operations — never write the ledger directly (preserving the thin-client rule). App distributed to family iPhones via **Expo Go** (free) or **TestFlight** ($99/yr Apple Developer account) — no App Store listing. "Private" here means one authoritative managed backend all phones defer to; it does **not** mean peer-to-peer sync between phones, which would break single-source-of-truth and reintroduce double-spend. Going public later is a plan upgrade on the same project, not a migration.

---

## 6. Phasing

**Phase 1 — the core economy (users + issuer).** Auth and identity; the append-only ledger (one balance per user, immutable transaction log); the 100 KP grant; the monthly allocation with treasury recycling; peer-to-peer activities with escrow and completion confirmation; and reward-list redemption fulfilled by the issuer. This is a complete, usable economy and exercises the two hardest primitives — a correct ledger and escrow — without merchant complexity.

**Phase 2 — merchants and the grand prize.** Merchant onboarding and verification; merchant-supplied rewards with the reimbursement/settlement ledger and statements; and the grand-prize mechanism. This carries most of the financial-integrity risk, so it follows once the core economy is proven.

---

## 7. Risk notes

**Sybil / farming.** The unconditional drip plus the 100 KP grant make every account a direct, redeemable payout. Strong identity at onboarding is economic protection, not polish — this is why phone-based verification gates account creation.

**Escrow disputes.** Holding KP between agreement and completion introduces a dispute surface (work contested, non-delivery, abandonment). The MVP needs a defined resolution path, even a simple manual-arbitration one.

**Reward pricing vs. issuance.** If rewards are priced too high relative to 5 KP/month, balances stagnate and activity stalls; too low, and KP drains faster than it accrues. This balance must be actively tuned.

**Merchant–reward collusion (Phase 2).** Faked redemptions of merchant rewards extract real reimbursement money. Requires verifiable redemption proof, limits, and an audit trail.

---

## 8. Open questions (parked for the architecture phase)

These are deliberately undecided and must not be silently assumed during design:

- **Grand prize mechanism.** Fixed high price, periodic raffle, auction, or something else? Amount TBD.
- **Dispute resolution for escrowed activities.** Manual arbitration by the issuer, mutual-confirmation timeout, or a fuller dispute flow?
- **Reward pricing strategy.** How reward costs are set and adjusted relative to the issuance rate.
- **Merchant KP balances.** Confirm merchants hold no KP