# Koupon — Family App
(https://cletchy.github.io/koupon)

A small, just-for-fun app for sharing a play currency called **koupon (KP)** among family. Balances live on a shared backend (Supabase), so every phone sees the same numbers instantly — no more copying codes or scanning QR to move KP around. Still honour-system economically (no real money involved), just no longer fragile to a single phone's local storage.

> **Earlier version:** this app used to be a fully offline, single-device pilot (QR/paste-code transfers, `localStorage` only). That version is retired — see git history if you ever need it back. `koupon-lightweight-schema.sql` in this folder is the Postgres schema for the current backend.

## Files in this folder

- **`index.html`** — the app. A single, self-contained file that talks to Supabase. This is all you need to run it. (Named `index.html` so GitHub Pages serves it automatically at the site root.)
- **`koupon-lightweight-schema.sql`** — the database schema (tables + functions) this app runs against. Only needed if you're standing up a new Supabase project from scratch.
- **`koupon-migration-2-issuer-role.sql`**, **`koupon-migration-3-weekly-drip.sql`**, **`koupon-migration-4-zero-start.sql`** — in-place database changes applied after the original schema, in order. Only needed if you're updating an existing Supabase project rather than starting fresh.
- **`README.md`** — this guide.
- **`koupon-requirements-brief.md`** and **`koupon-ledger-design.md`** — design blueprints for a *heavier, real-money-grade version* (double-entry ledger, escrow, phone-OTP auth). Not what's running today; kept in case KP ever needs to carry real value and that rigour becomes necessary.

## Running it

Open `index.html` on each family member's iPhone — email it to yourself, or open it from the Files app — and tap **Add to Home Screen** so it's easy to reopen. No camera permission or `https://` hosting requirement anymore (that was only ever needed for QR scanning, which is gone).

**First time on a phone:** pick a handle (e.g. `@tania`) and a PIN, and tap **Create new account**. You'll land at 0 KP — ask a banker to issue your starting balance from the **Banker** tab. If you already have an account (made on another phone, or the family banker made it for you), just enter your handle and PIN and tap **Log in** instead — your balance and history come with you to any device.

**To pay someone:** tap **Send**, type their handle and an amount, hit **Send**. It's instant — nothing to show or scan.

## Roles

**Banker.** Assigned by an issuer, not chosen at account creation. New accounts start at 0 KP — the banker issues each member's first 100 KP by hand from the **Banker** tab, plus any custom top-up. (The +5 weekly bonus pays everyone automatically and doesn't need the banker.) No code exchange.

**Fixing an account is banker-only,** two ways, both from the Banker tab:

- **Reset a member.** Sets a member's balance to a chosen number directly. History isn't erased — a "reset" entry is logged alongside everything else, so there's always a record of what changed and why.
- **Undo a transaction.** Look up any member's recent activity and reverse one specific entry. This replaces the old backup-code/restore-QR workaround entirely — since the server keeps the full log permanently, "undo" is just picking the bad entry and reversing it. Nothing to copy, nothing that can get lost.

**Rewards.** The banker adds rewards (a name and a KP cost) on the **Rewards** tab, visible to everyone. A family member taps **Redeem**, which debits their balance immediately — they then collect the reward from the banker in person.

## Good to know

- **PIN, not a password.** Each account has a short PIN (4-6 digits) chosen at creation, checked server-side on every action. It's there so one phone can't act as someone else's handle — not meant to withstand real attacks, just honest mistakes and impersonation, appropriate for a trusted-family app.
- **Balances sync automatically.** Home refreshes on a short timer while you're on it, plus a manual **Refresh** button, so activity from other phones shows up without you doing anything.
- **Data lives on Supabase now, not on your phone.** Losing or replacing a phone just means logging in again elsewhere with the same handle and PIN — nothing to back up or restore manually.
- **Not audited/tamper-proof.** Balances are plain integer columns, not a double-entry ledger — fine for a family game, not the rigour of `koupon-ledger-design.md`. Revisit that blueprint if KP ever needs to be trustworthy at a level beyond "we trust each other."
