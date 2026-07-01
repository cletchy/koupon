# Koupon — Family Pilot 
(https://cletchy.github.io/koupon)

A small, just-for-fun app for sharing a play currency called **koupon (KP)** among family. Each phone keeps its own balance, and you pay each other in person with a QR code (or a copy-paste code). There is no server and nothing leaves your phone — it runs on the honour system, for fun, not for real money.

## Files in this folder

- **`index.html`** — the app. A single, self-contained file. This is all you need to run it. (Named `index.html` so GitHub Pages serves it automatically at the site root.)
- **`README.md`** — this guide.
- **`koupon-requirements-brief.md`** and **`koupon-ledger-design.md`** — design blueprints for a *future real-money version*. Not needed to run the app; kept in case the pilot takes off.

## Running it

**Simplest way (works anywhere, no setup):** open `index.html` on each family member's iPhone — email it to yourself, or open it from the Files app — and tap **Add to Home Screen** so it's easy to reopen. On first run, pick a handle (e.g. `@tania`) and you start with 100 KP.

**To pay someone:** tap **Send**, enter the amount, and show them the QR. They tap **Receive** and scan it — or, if scanning isn't available, you tap **Copy code**, share that text with them (any way you like), and they paste it into the **Receive** box. The KP moves from your phone to theirs.

**For camera scanning to work,** the app needs to be opened over an `https://` link (an Apple rule). If you just open the file directly, the camera stays off — but the **paste-a-code** method works everywhere, so the app is fully usable either way. If you want tap-and-scan, put this one file on any free static host (e.g. GitHub Pages or a Netlify drop) and open that link on each phone. No data goes to the host; it only serves the page.

## Roles

**Banker.** One person sets their role to **Banker** during setup (or anyone can — it just unlocks the Banker tab). The banker issues KP: the starting 100, the monthly +5, or any custom amount. They create a code and the family member scans/pastes it to receive it.

**Resetting a member's account.** Only the banker can do this, and only via the Banker tab (members don't see this option). The banker picks a handle and a target balance, creates a **reset code**, and the member scans/pastes it on their own phone. That clears the member's balance back to the target amount and wipes their transaction history — their handle, role, and rewards list are untouched. (A full wipe of everything, including handle, is still a self-service option under that person's own **More → Reset everything**.)

**Rewards.** The banker adds rewards (a name and a KP cost) on the **Rewards** tab. To claim one, a family member taps **Redeem**, which creates a code that sends the KP back to the banker — who then gives them the reward in real life.

## Good to know

- **Back up now and then.** Phones can clear browser storage after long disuse, which would wipe a balance. Use **More → Copy my backup** occasionally and keep the text somewhere safe; **Restore** pastes it back.
- **It's honour-system.** Balances live only on each phone with no central record, so it relies on everyone playing fair — which is the point for a family game. (The blueprints describe what a tamper-proof, real-money version would take.)
- **No internet needed for a payment.** The transfer itself is just a QR/code between two phones. Internet is only used to load the page and, optionally, the camera scanner.
