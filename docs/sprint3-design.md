# Sprint 3 design: Waiting on them, You said you would, Later

Designed on Opus, Nov 3, 2026. Built on Sonnet. Branch `sprint/3` from `sprint/2`, PR base `sprint/2` (one release).

## Principles (why these rules)
- **Precision over recall.** A wrong item on Home costs more than a missed one. Each feature gets a rules pass, then an Apple Intelligence veto when it is available. The AI can only remove an item, never add one.
- **What you owe comes first.** Waiting on you, then You said you would, then To do. Waiting on them is a quiet watch list and sits low on Home, collapsed.
- **Gmail is unchanged.** No new Gmail actions or scopes. Later is local only: Gmail snooze is a label change, and label changes are not approved. Waiting on them may read thread metadata (read-only `threads.get`). Nudge opens a draft the owner sends himself.
- **Every dismissal is local and undoable.** The toast pattern and wording match Done.
- **Copy:** plain, short, no em-dashes. Rose stays for Waiting on you only. The new sections use ink, secondary and blue.

## Home order (All)
1. Waiting on you (rose, unchanged)
2. **You said you would** (new, up to 3 cards, then "See all")
3. To do (unchanged; items back from Later go first)
4. Notes to self
5. People
6. **Waiting on them** (new, one collapsed row: `WAITING ON THEM 3 ›`, which opens a list)
7. Organizations
8. Earlier

Items you put off with Later leave every Home section until they are due.

---

## 1. You said you would

### Source
Your sent mail (`sentByMe`, already loaded: 90 days, up to 60 messages), the author's own words only (`ReplySignals.authoredText`).

### Rules (all must hold)
1. **It is a commitment.** The sentence matches the pattern below. This replaces the loose `promisePhrases` list in `PersonProfile`.
2. **It is not a question,** does not contain " if " or start with "If", and does not contain "let me know".
3. **The recipient is someone else.** At least one To address is not yours (`TriageContext.isMine` / `otherAddresses`) and is not a no-reply address (`SenderSignals` no-reply fragments).
4. **It is not closed.** It is closed when there is a later message from you in the same thread, a later message from them in the same thread (existing behavior, kept for precision), or you tapped Done or Not a promise.
5. **Age:** Home shows it from 0 to 14 days old. The person page keeps it until 30 days (`promiseWindow`, unchanged).
6. **AI veto (when available):** a second on-device check on the sentence. If it says this is not a commitment, the item is dropped. The verdict is cached by message id.
7. **One per sent message:** the first matching sentence only.

### Commitment pattern
Normalize quotes first (`ReplySignals.normalizeQuotes`), lowercase, then match:

```
\b(i'll|i will|i'm going to|i am going to|let me)\s+(also\s+|just\s+|try to\s+|go ahead and\s+)?
(send|get you|get back to you|get it|call|follow up|check|look into|look at|find|forward|share|review|sign|pay|
schedule|book|set up|put together|draft|update you|confirm|ask|reach out|circle back|text|email|write up|bring|
drop off|pick up|order|fix|submit|file|handle|take care of|loop you in|let you know)\b
```

- "let me" counts only with check, look into, look at, find or ask. "Let me know" is excluded by rule 2.
- Dropped from today's list: "i can send" (an offer, not a promise), and bare "i'll " and "i will " (they matched "I'll be out Friday" and "I'll see you there").

### Examples that must pass (commitments)
- I'll send the signed form tonight.
- I will call the school tomorrow.
- Let me check with Sarah and get back to you.
- I'll follow up with the vendor on Monday.
- I'm going to put together the budget this week.
- I'll get back to you by Friday.
- I'll forward you the invoice.
- I'll take care of the registration.
- I'll let you know once I hear from them.
- I'll try to send it before the game.
- Let me look into the billing issue.
- I'll pick up the jerseys Saturday.

### Examples that must not pass
- I'll be out of the office Friday.
- I'll see you at practice.
- I'll talk to you soon.
- Let me know if you need anything.
- If you want, I'll send the slides. (conditional offer)
- I can send it if that helps.
- Will you send the form? (a question)
- I'll be there at 6.
- I will be traveling next week.
- I'll have to think about it.
- Thanks, I'll take a look when I get a chance. (no specific verb from the list; "take a look" is deliberately left out)
- I'll probably be late.

These 24 go in a new fixture, `promise-corpus.json`, with a scorecard test. **Floors:** precision 100% on this set, recall at least 90%.

### AI veto
- Uses FoundationModels, like `AppleIntelligenceSummarizer`: a `@Generable struct CommitmentCheck { var isCommitment: Bool }`.
- Instructions: "The sentence is from an email the user sent. Answer true only if the user commits to doing a specific thing for the recipient later. Answer false for pleasantries, plans about where the user will be, offers that depend on the recipient, and anything already done."
- For Waiting on them, the same session uses a second field, `asksRecipient: Bool`: "true only if the email asks the recipient to answer or do something."
- Cache: `MailCache.commitmentVerdicts: [String: Bool]?`, optional so older caches decode. Key `"commit-" + messageID` or `"ask-" + messageID`.
- When the model is unavailable, the rules alone decide.

### Copy
- Section title: `YOU SAID YOU WOULD` and the count.
- Card:
  - Line 1, the sentence in quotes: `"I'll send the signed form tonight."`
  - Line 2 (secondary): `To Dana · 3 days ago`. With several recipients: `To Dana and 2 others · 3 days ago`.
  - Actions: **Done**, **Reply**, then a `…` menu with **Not a promise** and **Open in Gmail**.
- Toasts: `Marked done` and `Not a promise`, each with Undo.
- The person page keeps "You owe them:" in its short version, now driven by the tighter rule.

### Storage
`lovely.promises.closed.<accountKey>`: a set of sent message ids (Done or Not a promise). Per account, local.

---

## 2. Waiting on them

### Rules (all must hold)
1. **You asked.** `ReplySignals.askSentence(in:)` finds an ask in your sent message. Courtesy rules apply as today.
2. **Direct, small audience.** 1 to 3 To recipients, none of them yours and none no-reply. Cc is ignored, and an ask sent with a Cc still counts.
3. **No answer yet.** No message from anyone other than you in that thread after your ask.
   - First check the loaded inbox and sent mail by `threadId`.
   - If nothing is loaded for the thread, confirm with a read-only `threads.get` (format=metadata, metadataHeaders=From, Date). That covers replies you archived.
   - At most 20 thread checks per load (10 quota units each, 200 total). Results are cached by thread id until the next load.
4. **Old enough to matter, not stale:** 3 to 21 days since you sent it. Before 3 days it's too early to nudge. After 21 days it stays only on the person page.
5. **AI veto (when available):** `asksRecipient` must be true.
6. **One per thread:** your latest ask in the thread.
7. **Not dismissed** with Got it.

### Copy
- Home row (collapsed): `WAITING ON THEM 3 ›`. Hidden when the count is 0. It opens a list screen titled "Waiting on them".
- List row:
  - `Dana Reyes` plus the age on the right (`5 days`).
  - Line 2 (secondary), your ask in quotes: `"Can you send the roster by Friday?"`
- Row actions: **Nudge** and **Got it**.
- **Nudge** opens the existing draft-reply sheet with this text: `Hi Dana, checking on this when you have a minute. Thanks, Graham`. Use the sender's first name (`Person.firstName`) and the owner's first name. The owner edits it and sends from Gmail. Lovely sends nothing.
- **Got it** toast: `Removed from Waiting on them` with Undo.
- The person page gains an open item with `theirs: false` styling: `You asked 5 days ago`.

### Storage
`lovely.waitingOnThem.dismissed.<accountKey>`: a set of sent message ids.

### Code
- A new protocol method on `GmailInboxClient`: `threadSenders(threadID:) async throws -> [(from: String, date: Date)]`.
- GmailService implements it with GET `threads/{id}?format=metadata&metadataHeaders=From&metadataHeaders=Date`. It is read-only, and the privacy guard needs no change.
- Fake clients in tests return fixtures.

---

## 3. Later (local snooze)

### Behavior
- Later hides a message from every Home section until a time you pick. It is still unread in Gmail and still found by Search and on the person page, tagged `Later · Tue 8 AM`.
- When the time comes, it returns at the top of To do with a small tag, `Back from Later`, on the next load or when the app comes to the foreground.
- If you read it in Gmail or trash it meanwhile, it simply leaves, as today.
- Waiting on you and To do items can both be put off. Waiting on them and You said you would use Got it and Done instead.
- No notification this sprint. Sprint 4's morning brief will say what came back.

### Options
Pure logic in `LaterSchedule.options(now:calendar:) -> [LaterOption]`, tested with a fixed calendar:

| Title | Time | Shown when |
|---|---|---|
| This evening | Today 6 PM | before 5 PM |
| Tomorrow | Tomorrow 8 AM | always |
| This weekend | Saturday 9 AM | Monday to Thursday |
| Next week | Next Monday 8 AM | always |

All times are local and use `Calendar.current`. Show at most 3 options plus "Pick a time…". The picker is a date picker sheet with a minimum of 1 hour from now.

### Where
- NextUpCard: a clock button (`clock`) between Done and Reply.
- Email action bar: a clock button between Done and Trash.
- Row short swipe left: **Later** (blue), next to Hide.
- The menu title reads `Later`, and the options read as above.

### Copy
- Toast: `Later: tomorrow 8 AM` with Undo.
- Return tag (caption, blue): `Back from Later`.
- The Settings > Rules section lists them under `Later (2)`, each with **Bring back now**.

### Storage
`lovely.later.<accountKey>`: `[messageID: Date]`. Entries for messages no longer loaded or unread are pruned on each load.

---

## Tests (Sonnet writes, CI runs)
- `PromiseRulesTests`: the 24 corpus examples (the floors above), the closed-by-later-reply rule, the no-reply recipient rule, the own-address rule, and the 14/30-day windows.
- `WaitingOnThemTests`: the 3-day and 21-day edges, more than 3 recipients excluded, Cc'd you not required, a reply in the loaded inbox closes it, a reply found only via `threadSenders` closes it, the 20-check cap, one per thread.
- `LaterScheduleTests`: options at Mon 9 AM, Thu 5:30 PM, Sat 10 AM and Sun 11 PM; it returns on time; it is pruned when read.
- `HomeDigestTests`: the new order, Later items excluded and then first in To do with the tag, the Waiting on them count.
- The AI veto is behind a protocol, so tests inject a fake veto (for example, always false) and check that the veto only removes items.
- The existing scorecard floors must still hold.
- Screenshots (`DesignScreenshotTests`, fictional data):
  - Home with You said you would and Waiting on them.
  - The Waiting on them list.
  - The Later menu.
  - To do with `Back from Later`.

## Build order (Sonnet)
1. `PromiseRules` (pure) and the fixture. Swap `PersonProfile.promiseSentence` to use it.
2. `LaterSchedule` (pure), store state and the UI hooks.
3. `WaitingOnThem` (pure, with injected thread lookups), `threadSenders` in GmailService and the fakes.
4. The AI veto protocol, the FoundationModels implementation and the cache field.
5. Home sections, the list screen, copy, toasts.
6. Docs, the PR (base `sprint/2`), screenshots from CI.

## Owner decisions (defaults used; say if you want different)
- Waiting on them starts at 3 days and drops at 21.
- You said you would stays on Home for 14 days.
- No phone notification for Later until Sprint 4.
