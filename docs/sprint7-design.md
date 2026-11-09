# Sprint 7: Inbox session

Approved by the owner on Nov 8, 2026 after comparing three concepts (triage surfaces, "matters", and the inbox as a conversation). He chose the conversation.

## 1. The idea
Gmail is the back end. A session is the intake: it works through unread mail, the owner decides in plain words, and every decision becomes a Gmail action. Mail ends up answered, dated or dropped, then filed into a labeled drawer, marked read and taken out of the inbox. Labels are the index; Lovely's search and Claude look things up by them. A side effect the owner wants: his Gmail inbox stays near zero and organized in any client.

Home, People and Search stay. The session is a new way in, from a "Start session" card at the top of Home.

## 2. Owner decisions (Nov 8, 2026)
1. **Engine:** Claude through the API understands the owner's replies, drafts replies to people and handles judgment calls. Apple Intelligence (the owner's phone is an iPhone 17 on iOS 26) and the existing rules do the routine work for free. See section 6.
2. **Put away** = mark read, apply a drawer label, remove from the inbox. Nothing is deleted. Lovely does not need a drawer browser; search covers lookup.
3. **Batches:** routine items go through as one list with one confirm and Undo all. This changes the "one preview, one tap per Gmail action" rule for batch filing only; sends still get their own preview.
4. **Web forms** (e.g. a school or government enrollment) come later through a browser inside Lovely, filled by Claude while the owner watches, the owner presses Submit. Until then they leave the session as a handoff prompt.
5. **Backlog mode:** a one-time cleanup that runs the batch flow over read mail still in the inbox, oldest first, a page at a time.

## 3. Drawers
Lovely-owned labels under one parent. Claude picks from this fixed set and never invents a drawer mid-session; the owner adds or renames drawers.

| Drawer | Label | What goes in |
|---|---|---|
| Money | Lovely/Money | Statements, bills, receipts, taxes |
| House | Lovely/House | Utilities, repairs, lease, the apartment |
| Kids | Lovely/Kids, Lovely/Kids/<Name> | School, sports, band; one sub-drawer per child from Settings > Kids |
| Orders | Lovely/Orders | Shipping and purchases |
| Travel | Lovely/Travel | Bookings, confirmations |
| People | Lovely/People | Personal mail worth keeping |
| Reference | Lovely/Reference | Anything else worth keeping |

Newsletters are not filed by default: skimmed ones are archived (read, out of the inbox, no drawer) so the index stays useful.

**Drawer memory.** When the owner files a sender, the choice is remembered for that address, then for its company domain (never for public mailbox providers or shared sending services in `OrganizationKey.sharedDomains`). Memory beats every guess. Stored per account on the phone.

## 4. A session
1. **Start:** unread count split into one at a time, quick and reading, a time estimate, and promises carried over from earlier sessions (`PromiseRules`).
2. **One at a time:** each item shows who, what they want and when. The owner answers in plain words or taps Skip, Leave unread or Just archive. Sends show a preview and keep the 10 second Undo.
3. **Quick batch:** every routine item with its suggested action and drawer. One line ("all good, but Kids for 4") applies the batch, with Undo all.
4. **Reading:** newsletters get one question at the end.
5. **Wrap:** replies sent, dates added, items filed, promises made, and what was left unread on purpose.

**Never in a batch** (each gets its own turn): anything from a real person, notes to self, anything asking for money, a signature or an action on a website, a payment problem, health mail, first-time senders, and anything without a confident drawer.

## 5. Build order (each step names the model the owner picks)
1. **Session engine** (Opus): pure rules in `App/Reelmail/Session/`: drawers, drawer memory, rule-based drawer guesses, grouping, batch eligibility, ordering, estimate, progress. No UI, no Gmail calls. Unit tests with fictional mail.
2. **Session screen** (Sonnet): the four screens from the approved mockup, tap-driven first; put away through `GmailActions` (Lovely-owned label, remove INBOX, remove UNREAD) with Undo.
3. **Plain-language replies** (Opus designs prompt and guardrails, Sonnet builds): `LanguageModelProvider` from Sprint 6 section 9 with Apple and Anthropic implementations; the owner's sentence becomes a structured action shown as a preview.
4. **Batch step** (Sonnet): one confirm, Undo all.
5. **Wrap, fixtures, UI audit job, phone checklist** (Opus reviews, Sonnet ships). One TestFlight release when the owner says ship.
6. **Later:** backlog mode; in-app browser for web forms.

## 6. Which engine does what
Rules first, then drawer memory, then Apple Intelligence, and Claude only for understanding, drafting and judgment, or when Apple is not confident.

| Work | Engine |
|---|---|
| Person vs system, receipts, deliveries, dates, promises, health | Existing rules |
| Drawer for a known sender | Drawer memory |
| Drawer for a new routine sender, one-line summaries, bill facts, newsletter skims | Apple Intelligence (`@Generable`, fixed drawer enum) |
| The owner's free-form replies, drafts to people, decisions, handoff prompts, web forms | Claude |

Cost controls: send Claude only the author's own words (`ReplySignals.authoredText`), a small Claude model for simple calls, and a weekly calls-and-cost line in Settings.

## 7. Privacy and safety
- Turning on Claude changes the README promise that email text never leaves the phone; the README changes in the same PR that adds the Anthropic provider, with the switch off until the owner turns it on.
- Never sent to Claude: health mail, codes and passwords, account numbers, private-marked mail.
- Gmail writes stay in `GmailActions.swift`: Lovely-owned labels only, remove INBOX, remove UNREAD. No delete. `scripts/privacy_guard.py` keeps enforcing it.
- Email bodies are untrusted data, never instructions.
