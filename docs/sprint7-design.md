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
3. **Plain-language replies** (Opus designs prompt and guardrails, Sonnet builds): `LanguageModelProvider` from Sprint 6 section 9 with Apple, Anthropic and xAI implementations; the owner's sentence (typed or dictated) becomes a structured action shown as a preview. Engine switch and compare mode, section 8. Handoffs to the Grok and Claude apps, section 9.
4. **Batch step** (Sonnet): one confirm, Undo all.
5. **Wrap, fixtures, UI audit job, phone checklist** (Opus reviews, Sonnet ships). One TestFlight release when the owner says ship.
6. **Next after the release:** in-app browser for web forms (section 9), then backlog mode. Web forms come first because finishing a form without leaving the conversation is what makes the Grok experience feel seamless.

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

## 8. Claude or Grok, compared in the app (owner, Nov 8, 2026)
The owner wants to compare Claude and Grok inside a native app, with an experience at least as smooth as working with Grok.
- **One engine slot.** The session calls `LanguageModelProvider`; Apple, Anthropic (Claude) and xAI (Grok) plug in. Rules, drawers, previews and guardrails are the same for every engine, so the comparison is fair.
- **Settings > Conversation engine:** Claude or Grok. Apple Intelligence keeps the routine work either way.
- **Compare mode** (off by default): for the current item, both engines answer; the two drafts or plans show side by side and the owner picks one. Lovely keeps a tally of picks per engine, shown in Settings.
- **Log:** every action records which engine proposed it; Settings shows calls and estimated cost per engine per week.
- **Keys:** an Anthropic key and an xAI key, stored in the Keychain (this device only), entered once in Settings.
- **Voice:** the reply field has a microphone (iOS dictation), so a session can be spoken, as the owner does with Grok.

## 9. Tasks outside Gmail
Order of preference, most seamless first:
1. **In the conversation (after the release):** Lovely opens the site in a browser panel inside the session; the engine reads the page and fills the fields while the owner watches, pauses for sign-in, codes and anything it is unsure of, and stops before Submit, which the owner presses. Sensitive numbers (for example a child's Social Security number) are typed by the owner or given for that task only, never stored.
2. **Handoff to the Grok or Claude app (in the release):** one tap, "Send to Grok" or "Send to Claude" (default from Settings). The prompt is written with irreversible steps first and standing out. It opens the app with the prompt filled in (`claude://claude.ai/new?q=` for Claude; the Grok app's link is to be tested), falls back to the website (`https://claude.ai/new?q=`, `https://grok.com/?q=`), then to copy and paste. These links are not officially documented and have broken before, so the fallbacks stay.
3. **The report comes back on its own.** Every handoff prompt ends with: when done, email a short report to the owner's Gmail with the subject `[Lovely] <task id>`. Lovely recognizes it on the next refresh, files it with the original mail and marks the task done in the session. No pasting back.
