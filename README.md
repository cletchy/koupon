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

**Resets and restores are banker-only.** Members have no self-service reset on their phone at all — there's no "erase everything" button in Settings anymore. Only the banker can fix an account, in one of two ways, both from the Banker tab:

- **Reset a member.** The banker picks a handle and a target balance, creates a **reset code**, and the member scans/pastes it on their own phone. That clears the member's balance back to the target amount and wipes their history — handle, role, and rewards stay.
- **Restore a member's backup.** A backup code is copied to a member's clipboard automatically right before every transaction (send, receive, or redeem) and stashed under **More → Copy backup from before my last transaction** as a fallback. If a member wants a transaction undone, they send that code to the banker, who pastes it into **Restore a member's backup** to generate a restore code. The member scans/pastes it on their own Receive tab and their account rolls back to exactly that pre-transaction snapshot — balance, history, everything.

**Rewards.** The banker adds rewards (a name and a KP cost) on the **Rewards** tab. To claim one, a family member taps **Redeem**, which creates a code that sends the KP back to the banker — who then gives them the reward in real life.

## Good to know

- **A backup is copied automatically before every transaction.** No need to remember to do this — it happens silently on your clipboard right as you send, receive, or redeem. If you ever need something undone, that's the code to send your banker (or grab it again from **More → Copy backup from before my last transaction**).
- **`More → Copy my backup`** grabs a fresh snapshot any time, useful before switching phones. There's no matching self-service "Restore" anymore — all restores go through the banker (see Roles above), by design.
- **It's honour-system.** Balances live only on each phone with no central record, so it relies on everyone playing fair — which is the point for a family game. (The blueprints describe what a tamper-proof, real-money version would take.)
- **No internet needed for a payment.** The transfer itself is just a QR/code between two phones. Internet is only used to load the page and, optionally, the camera scanner.
