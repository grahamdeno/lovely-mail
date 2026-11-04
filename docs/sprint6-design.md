# Sprint 6 design: insights from mail

Designed on Opus, Nov 4, 2026. Build on Sonnet. Branch `sprint/6` from `testflight`. Ships as one release.

Mockups the owner reviewed: the "Lovely Insights" artifact (placement, insight screens, cards vs chat, cloud switch).

Lovely stops being only a sorter. It reads the mail that is really data (statements, bills, school notices, energy reports) and tells you what changed and what to do. Everything in this sprint runs on the iPhone.

## Owner decisions (Nov 4, 2026)
1. **Placement:** the morning brief becomes a full page, opened from its notification and from Home. No new tab this sprint.
2. **Brief time:** learned from when the owner actually uses mail, not fixed at 7:30.
3. **Insight order on screen:** Kids, Money, Energy. All three ship together.
4. **Walk-through:** cards by default. Chat exists behind an owner switch in Testing tools, easy to turn off.
5. **Handoff prompts:** when the phone can't do a task, Lovely writes a prompt for an outside agent. Grok is the default agent; Claude is the other choice. The owner can switch to compare.
6. **Health mail:** appointment dates only, into Coming up. Nothing else from health mail is read for insights or put in a prompt.
7. **Household heads-up:** Lovely drafts a text and opens it in Messages. The owner presses Send.
8. **Sense mail:** hidden from Home once the Energy page covers it (local only; Gmail untouched).
9. **Two households:** Home (the house, where Sense is) and the Apartment (the owner's son's apartment, rent and utilities paid by the owner through March 2027). Every bill and energy item belongs to one of them.
10. **Kids to Shoebox:** a summary that suggests forwarding becomes a standing rule, handed off to an agent (see section 7).

## Gmail stance (unchanged)
- No new scopes, no new Gmail actions. Lovely still only reads, moves to Trash and toggles UNREAD.
- The CI privacy guard is unchanged and must still pass.
- Gmail filters and forwarding are done by the owner's chosen agent from a handoff prompt, never by Lovely.

## Public repo rule for this sprint
This repo is public. The owner's real institutions, amounts, addresses and family names stay out of code, tests, fixtures and docs. Parsers match on sender domains and email formats, which are public. Household names, children and service addresses are entered by the owner in Settings and stored on the phone.

---

## 1. Insight pipeline

### History
- First load after update: backfill 12 months, **metadata first** (`format=metadata`: From, Subject, Date, List-Unsubscribe), paged and throttled by the existing rate-limit handling.
- Bodies are fetched only for messages a known parser claims (section 2) and for school mail (section 4). Expected: a few hundred bodies, not thousands.
- Progress shows on the brief page as "Reading your last 12 months · 40%". Insights fill in as they arrive.
- Incremental after that: each refresh parses new mail only.

### Store
- `InsightStore` (new, persisted beside `MailCache`, Codable, optional fields so older caches decode).
- Entity types: `Account`, `Bill`, `Payment`, `EnergyReading`, `SchoolItem`, `Appointment` (date and place only), `Renewal`.
- Every entity keeps `sourceMessageID` so each insight links back to its email. No insight is shown without a source.
- Account numbers: last four digits at most, ever. Activation codes, full account numbers and passwords are dropped at parse time.

### Extractors, in order
1. **Known-format parsers** (pure Swift, deterministic, tested on fictional fixtures). One per sender format in section 2.
2. **Apple Intelligence fallback** for unknown senders that look like bills or statements: a `@Generable` struct (sketch below), temperature 0.2, body capped at 2,500 characters. Its output is a suggestion: it is shown with "Found by Apple Intelligence" and never raises an alarm on its own.
3. **No cloud.** Tier 2 is designed in section 9, not built.

```swift
@Generable
struct BillFacts {
    @Guide(description: "The company that sent the bill, as written in the email.")
    var payee: String
    @Guide(description: "Total amount due in US dollars, or 0 if none is stated.")
    var amountDue: Double
    @Guide(description: "Due date exactly as written, empty if none.")
    var dueDate: String
    @Guide(description: "True if the email says a payment failed, was returned or the service will be suspended.")
    var paymentProblem: Bool
}
```

## 2. Money

### Accounts ledger
- An account is an institution plus a kind (brokerage, IRA, retirement plan, bank, mortgage, retiree pay, child account), keyed by sender domain and kind words in the subject.
- Shows: name, kind, last statement date, and a rose dot when the latest mail asks you to act (subjects with "Take action", "Action needed", "Action required", or a deadline in the authored text).
- "I've handled it" clears the dot locally until the next action mail from that account.
- "Add to To do" puts the source email at the top of To do (local, like Later).
- Insight line when an account is asking: "<Institution> has sent N notices asking you to act on <topic>." No financial advice beyond a plain sentence of what such notices usually mean.

### Bills
- Parsers return payee, amount, due date, paid/unpaid and household.
- **Payment problem alarm:** phrases such as "problem receiving your payment", "payment was returned", "suspension has started", "past due". This is the one insight allowed to notify outside the brief, as a normal notification with the payee and nothing else.
- Paid confirmations close the matching bill (same payee, amount within $1, within 45 days).
- Trend per payee: last 12 amounts, shown as a small bar row.

### Renewals
- "Will renew", "will be charged ... in N days", "trial ends" → a Renewal with a date. Shows in the brief 3 days before.

### Households
- Settings › Households: two by default, Home and Apartment, each with an optional end date ("Apartment until Mar 2027").
- The owner assigns a payee to a household once (long-press › "This bill is for…"). Lovely remembers it by sender domain and service address line.
- After an end date, that household's bills move to "Ended" and stop appearing in the brief.

## 3. Energy and water (Home)

### Sources
| Source | Fields parsed | Notes |
|---|---|---|
| Sense monthly snapshot | month, kWh used, kWh produced, $/day, change vs last month, peak day, top 3 devices with $ | Fixed format; parse labels, not positions |
| Duke usage alert | cost to date, cycle start, as-of date, cycle end | Mid-cycle warning |
| Duke payment confirmation | amount, date posted | The real billed total |
| Duke program offers | program name and credit amount, if present | Feeds the suggestion rule |
| CFPUA statement | amount due, due date | Water and sewer cost only; no gallons in the email |
| Apartment utility statement | line items (water, sewer, trash, fees), total, due date | Apartment household |

### Energy page
- Headline: this month's $/day and the change vs last month.
- Bars: monthly $/day for the last 12 months from Sense.
- Top devices with $.
- **Real-bill check:** when a Duke payment exists for the same period, show "Sense estimated $X; Duke billed $Y." Taxes and fees explain the gap; Lovely says so in one line.
- **One suggestion per month**, picked by rule, never invented:
  - Top device is a water heater or AC, and a Duke mail in the last 12 months offers a program for that device → "Duke offers up to $N in credits for enrolling your <device>." with Open latest Duke email.
  - Top device is a water heater, no program mail → "A lower water heater setting is the usual first step. Next month's snapshot will show whether it moved."
  - Spend up more than 25% vs the same month last year → "Up N% from last <month>." with the top device that grew most.
  - Otherwise no suggestion. Silence beats filler.
- **Water** (a section on the same page): monthly cost per household, 12 bars, due dates. No usage claims.

### Sense mail on Home
- Once one snapshot has been parsed, mail from the Sense snapshot sender skips Home and appears only via Energy (local rule, shown in Rules, removable). Gmail is untouched.

## 4. Kids

### Setup (Settings › Kids)
- The owner adds each child: first name, school email address (optional), school name (optional). Nothing is inferred from names alone (existing trust rule).
- Mail belongs to a child when: it is from or to the child's school address; or it is school mail (district domain, Infinite Campus sender, school payment platform) and names the child; or the owner assigns it.
- Unassigned school mail goes to a "School" group.

### Per-child page
- Coming up: dated items from that child's mail (`MailDates`), one per conversation.
- From teachers: messages from a person at the district domain.
- Newsletters in short: see below.
- Done items: forms or permissions the owner already sent (found in Sent mail to the school or child's address).

### Newsletter summaries on the phone
- Long newsletters exceed what the on-device model reads at once. Split the authored text into chunks of at most 2,500 characters on paragraph boundaries.
- Each chunk → `@Generable struct NewsletterItems { var items: [Item] }` with title, one-sentence gist, date as written, and whether it asks a parent to act.
- Merge, drop duplicates, keep at most 5 items, dated and action items first.
- Shown as "3 items, 1 with a date. Nothing asks you to act." with the list behind a tap.

### Shoebox rule suggestion
- When the owner forwards school mail of the same kind to the Shoebox address twice, or taps "Send to Shoebox" on a newsletter summary, Lovely offers **Make this a Shoebox rule**.
- That writes a handoff prompt (section 7) that creates a Gmail filter and forwards the last 10 days of matching mail.

## 5. Morning brief

### Timing
- Default **9:30 AM weekdays, 10:00 AM weekends** (owner's sent mail peaks 9 to 11 AM; almost nothing before 8).
- **Learned time:** Lovely records, on the phone only, the time of the first app open each day and each Done. After 10 days of data, the brief fires 15 minutes before the median first open, clamped to 7:00 to 11:00, weekdays and weekends separately.
- Settings shows "Brief at 9:15 AM (learned)" with a fixed-time override.
- **Evening walk-through nudge:** optional, off by default, 7:00 PM. "12 unread to go through." Opens the walk-through.
- Existing rules stay: off until switched on, counts only unless names are on, skipped when empty.

### Brief page
Order: Today line, Kids, Money, Energy, Coming up. Each section shows at most 3 items and "See all". A section with nothing new is hidden.

## 6. Walk-through: cards, and chat for the owner

### Cards (default)
- "Go through" from the To do header. One card per unread message, oldest first.
- Card: sender, one-line summary, why line, **Suggested** action, buttons Done, Trash, Later, Keep, and the suggestion's own button when it has one (e.g. "Text <household member>"; tests use fictional names).
- Suggestions come from existing rules plus: delivery slip → household heads-up; school form → Coming up; account asking → Add to To do.

### Chat (owner switch)
- Settings › Testing tools › **Chat walk-through**. Off by default.
- Same queue and same actions as cards. Turns are short; the on-device model writes the one-line summary and parses replies like "trash both", "keep, and text her", "from now on trash these".
- "From now on" creates a rule (section 8) tagged `source: chat`, shown back for confirmation before it is saved.
- **Rollback:** the switch off returns to cards immediately. Chat stores only its rules. Testing tools › "Remove rules made in chat" deletes every rule tagged `source: chat`, with Undo.
- Anything chat can't do on the phone (research, filters, forwarding, signups) → it offers a handoff prompt instead of attempting it.

## 7. Handoff prompts

### Agent setting
- Settings › Agent: **Grok** (default) or **Claude**. Both stay available.
- Every handoff sheet shows two buttons, **Copy for Grok** and **Copy for Claude**, so the owner can run the same task on both and compare. The default agent's button is first.
- The prompt text is the same for both; only a one-line header differs ("You have computer and Gmail access…").
- Lovely copies to the clipboard and offers the share sheet. It does not open or control the other app.

### Prompt format (every prompt)
1. **IRREVERSIBLE STEPS (confirm before each):** listed first, numbered, in capitals. E.g. "FORWARD these 6 emails", "CREATE this Gmail filter".
2. Goal in one sentence.
3. Exact inputs (sender addresses, subjects, dates, the forwarding address).
4. Steps.
5. Stop conditions: stop before any submit, payment, ID number, or publishing step and ask the owner.
6. "When done, send a report: what you did, what you skipped and why, links."

### Redaction
- Account numbers, codes, street addresses and health content are removed before the prompt is built. The sheet shows the prompt in full before Copy.

### First prompt types
- Shoebox rule (filter + forward last 10 days).
- Research question from chat ("do my kids qualify for …").
- Unsubscribe on a site that needs a login.

## 8. Rules memory
One representation for all learned rules, local, editable in Settings › Rules.

```swift
struct LearnedRule: Codable, Identifiable {
    enum Match: Codable { case senderDomain(String), senderAddress(String), subjectContains([String]), category(String) }
    enum Action: Codable { case section(String), hideFromHome, trashAfterDays(Int), keepUntilDelivered, assignHousehold(String), assignChild(String) }
    var id: UUID
    var matches: [Match]        // all must match
    var exceptions: [Match]     // any match skips the rule
    var action: Action
    var source: Source          // .settings, .longPress, .chat
    var created: Date
    var note: String            // the owner's words, e.g. "build notices to Trash, keep App Review"
}
```
- `trashAfterDays` is local only (moves to Trash through the approved Trash action, with the usual Undo on next open). It applies only after the owner confirms the rule.

## 9. Tier 2 (designed, not built)
- `protocol LanguageModelProvider { func respond<T: Generable>(_ prompt: Prompt, as: T.Type) async throws -> T }` with Apple, Anthropic and xAI implementations later.
- Switch off by default; per-request sheet shows the exact payload; never-send list (health, codes, account numbers, private-marked mail); weekly log.
- The README promise ("email text is never sent to any server") stays true until the owner turns this on in a later sprint, and the README changes in that same PR.

## 10. Messages heads-up
- `MFMessageComposeViewController` with a drafted body and no recipient preset unless the owner chose one before. The owner presses Send. No Gmail sending.

## 11. Health mail
- Appointment confirmations (sender and subject patterns for scheduling systems) → date, time and place into Coming up, titled "Appointment".
- No body text from health senders is summarized, parsed for amounts, shown in insights, or put in a prompt. Health invoices are excluded from Bills.

## 12. Measurement
- New fictional fixture sets, committed before rules change: `sense-fixtures`, `duke-fixtures`, `utility-fixtures`, `statement-fixtures`, `school-fixtures`, `handoff-fixtures`.
- Floors: parsers 100% on their fixtures; payment-problem alarm precision 100%, recall ≥ 95%; account "asking you to act" precision ≥ 95%; newsletter item extraction is scored by hand on device (on-device model is not available in CI).
- Existing sorting and dates floors must not drop.
- Handoff prompts: snapshot tests that the irreversible block comes first and redaction removed every planted secret.

## 13. Build order (one release)
1. InsightStore, history backfill, Households and Kids settings.
2. Energy (Sense, Duke, water parsers, page, suggestion rules).
3. Money (accounts, bills, alarm, renewals).
4. Kids (assignment, per-child page, newsletter chunks, Shoebox suggestion).
5. Brief page and learned timing.
6. Cards walk-through, chat behind the switch, LearnedRule.
7. Handoff prompts and the agent setting.

Steps 1 to 7 on Sonnet. A review pass on Opus before ship for data safety (redaction, health exclusion, alarm wording).

## 14. Open items
- Duke mail stops after June 2026 in the owner's inbox. If Duke moved to paper or its app, the real-bill check is idle until Duke mail resumes.
- The apartment household ends March 2027; confirm then whether to delete its history or keep it under Ended.
- Whether a fourth "Life" tab is worth it after a month of using the brief page.
