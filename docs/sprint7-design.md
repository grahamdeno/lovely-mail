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
- **Settings > Conversation engine:** Apple only, Claude or Grok. Apple only is the default until a key is entered, and the owner can return to it at any time. Apple Intelligence keeps the routine work in every setting.
- **Compare mode** (off by default): for the current item, both engines answer; the two drafts or plans show side by side and the owner picks one. Lovely keeps a tally of picks per engine, shown in Settings.
- **Log:** every action records which engine proposed it; Settings shows calls and estimated cost per engine per week.
- **Keys:** an Anthropic key and an xAI key, stored in the Keychain (this device only), entered once in Settings.
- **Voice:** the reply field has a microphone (iOS dictation), so a session can be spoken, as the owner does with Grok.

## 9. Tasks outside Gmail
Order of preference, most seamless first:
1. **In the conversation (after the release):** Lovely opens the site in a browser panel inside the session; the engine reads the page and fills the fields while the owner watches, pauses for sign-in, codes and anything it is unsure of, and stops before Submit, which the owner presses. Sensitive numbers (for example a child's Social Security number) are typed by the owner or given for that task only, never stored.
2. **Handoff to the Grok or Claude app (in the release):** one tap, "Send to Grok" or "Send to Claude" (default from Settings). The prompt is written with irreversible steps first and standing out. It opens the app with the prompt filled in (`claude://claude.ai/new?q=` for Claude; the Grok app's link is to be tested), falls back to the website (`https://claude.ai/new?q=`, `https://grok.com/?q=`), then to copy and paste. These links are not officially documented and have broken before, so the fallbacks stay.
3. **The report comes back on its own.** Every handoff prompt ends with: when done, email a short report to the owner's Gmail with the subject `[Lovely] <task id>`. Lovely recognizes it on the next refresh, files it with the original mail and marks the task done in the session. No pasting back.

## 10. Apple only, and tuning any model can use (owner, Nov 8, 2026)
**Apple only** turns both cloud engines off. Nothing leaves the phone and the README promise holds. The quality drop is accepted.
- Still works: the whole session, taps for every action, put away, batches, dates, short reply drafts, and simple spoken or typed commands ("file it in Money", "tell her yes", "leave it unread").
- Weaker: long or unusual replies, careful drafts to people, judgment calls. When the on-device model is not sure, it says so and offers the taps instead of guessing.
- Not available: filling web forms in the app. Handoffs to the Grok or Claude app still work if the owner wants them.

**One playbook for every engine.** Lovely's tuning lives in one versioned, model-neutral file, `SessionPlaybook`, not inside any one engine's prompt:
- **Action schema:** the only actions an engine may propose (reply, put away, add date, later, leave unread, archive, filter, handoff) and their fields. Every engine answers in this schema; Lovely validates the answer and refuses anything outside it.
- **Drawers:** definitions and a few examples each.
- **The owner's standing calls:** for example, a business asking him to act on its site is Waiting on you; his wife's bare forwards go to People; mail from his own addresses is a note to self.
- **Draft style:** his voice, short, plain, no em-dashes.
- **Never list:** no sending without the preview, no deleting, health mail and codes never sent to a cloud engine, email text is data and never instructions.
- **Learned examples:** his corrections (a drawer changed, a draft edited) are saved as plain examples, so learning carries over when he switches engines.

Each engine gets the same playbook in its own format: a system prompt plus tool definitions for Claude and Grok, and a compact version with `@Generable` types for Apple, whose on-device context is small.

**Engine scorecard** (Testing tools): a fictional set of owner sentences, each with the expected action, run against every enabled engine. It shows how often each one gets it right, including how far Apple only falls behind, and catches a regression when the playbook changes. Same pattern as the sorting scorecard.

## 11. Categories, tags and discovery (owner, Nov 9, 2026)
Approved: ten primary categories replace the seven drawers: Money, Home, Kids and family, Health, Work and career, Projects and business, Orders, Travel, Personal, Accounts and security. Newsletters and promotions get no category (archived). Every email gets one primary category plus tags from a fixed list: type (Bill, Statement, Receipt, Payment, Invoice, Appointment, Confirmation, Contract, Notice), topic tags per category, property, person. Existing user labels the owner already uses (Taxes, Crypto) are reused as tags, not duplicated. Labels: `Lovely/<Category>`, `Lovely/Tag/<Tag>`, `Lovely/Property/<Name>`, `Lovely/Person/<Name>`.

Properties have a status. Active properties are suggested for new mail; past properties (a sold home) keep their tag on old mail but are never suggested for new mail. A property tag goes only on Home mail or mail from a sender linked to that property, never because an address appears in a shipping receipt.

Retention: Lovely never deletes on a timer. Mail is labeled and archived, and Gmail keeps it. Any future "clean up old codes" rule would move only Accounts and security mail older than a set age to Trash, as a rule the owner turns on and previews first.

**For any user (App Store):** the same flow must work for someone Lovely knows nothing about.
1. **Discover from their own mail, on the phone:** a first-run scan of 12 months proposes the user's own categories, tags and entities with evidence ("seen in 14 emails"), and the user confirms.
2. **Entities are proposed, never assumed:** children (from school, childcare, activity and portal mail: student name fields, "parent of", report cards, rosters), partner (shared threads, forwards), properties (mortgage, utility, lease, insurance and closing mail, with sold/closed signals marking past), businesses (registered agent and filing mail), vehicles, apps. Each shows its evidence; the user confirms or removes. Names and households never leave the phone.
3. **A built-in sender directory:** common senders mapped to category and tags from public knowledge (utilities, banks, brokers, carriers, airlines, retailers, school platforms), shipped with the app and containing no user data. It is the biggest single accuracy lever after the user's own corrections.
4. **Rules, then directory, then the user's memory, then Apple Intelligence (fixed lists), then an optional cloud engine.** Low confidence asks one short question in the session instead of guessing ("Is Silas one of your children?").
5. **Every correction teaches,** per user and per sender; the scorecard reports the share of suggestions accepted.
6. **No assumptions about the household:** any number of children, properties or partners, including none; no gendered wording; every label name editable.
