# Sprint 5 design: trust pass before the first device check

Designed on Opus, Nov 3, 2026. Built on Sonnet. Branch `sprint/5` from `testflight` (build 1017 = Sprints 2 to 4).

Sprints 2 to 4 added a lot of new reading (promises, waiting, dates, the brief), all checked only by CI. Sprint 5 adds no big feature. It removes the wrong answers most likely to show up on your phone, finishes the Sprint 3 leftovers, and gives you a way to see the morning brief without waiting for 7:30.

## Owner decisions (defaults below; say if you want different)
1. **Auto-replies ("Out of office", "Automatic reply") go to Updates.** They never count as an answer: they do not close Waiting on them or You said you would, and their dates ("back Monday") never show in Coming up.
2. **Delivery notices ("Out for delivery") go to Updates,** not To do and not Coming up.
3. **Coming up shows one entry per conversation,** using the latest message, so a reminder chain about one game shows once.
4. **"Send a test brief" lives in Testing tools,** not in the everyday Settings.
5. **The test set stays honest.** Holdout cases fixed by looking at them move to the tuning set, and new holdout cases are written and committed before any rule changes.

No new Gmail actions, scopes or credential changes. Nothing is sent.

---

## 1. Auto-replies (holdout u24)

### Detection (pure, `AutoReply.isAutoReply(email:)`)
Any one of:
- **Header** `Auto-Submitted` with a value other than `no` (RFC 3834), or `X-Autoreply`, or `X-Autorespond`. The parser reads these from headers Gmail already returns with the message; no new request.
- **Subject** starting with: `Automatic reply:`, `Auto:`, `Autoreply:`, `Auto-reply:`, `Out of office`, `Out of the office`, `OOO:`, `Away:` (case-insensitive, after Re:/Fwd: are removed).
- **Body**, within the author's own words, matching two or more of: `out of the office`, `out of office`, `limited access to email`, `limited access to my email`, `I am currently away`, `I'm currently away`, `will respond when I return`, `respond to your email when I return`, `return on`, `back in the office`.

### Effects
- **Sorting:** section Updates, with the why line `Automatic reply`.
- **Waiting on them** and **You said you would:** an auto-reply in the thread is not an answer and does not close the item.
- **Thread lookups** (`threadSenders`, read-only `threads.get` with `format=metadata`): add `Subject` and `Auto-Submitted` to `metadataHeaders`. Still metadata only. `ThreadSender` gains `isAutoReply`. Check that the CI privacy guard still passes; if the guard pins the header list, update the allowlist in the same commit and say so in the PR.
- **Coming up:** auto-replies yield no dates.

## 2. Delivery notices (holdout u17)
- **Phrases** (subject or authored body): `out for delivery`, `has shipped`, `has been shipped`, `was delivered`, `has been delivered`, `delivery attempt`, `arriving today`, `arriving tomorrow`, `tracking number`, `track your package`, `track your order`.
- **Sender local parts:** `tracking`, `shipment`, `shipments`, `shipping`, `delivery`, `deliveries`, `orders`, `order-update`.
- A phrase **plus** either an automated signal or one of those local parts → Updates, why line `Delivery update`.
- A person writing "it was delivered" stays with People (no automated signal, no shipping address).

## 3. Newsletter with only "you are receiving this" (holdout r13)
- `you are receiving this` is already a footer phrase, so the miss is elsewhere. Likely the day words ("This week", "30 minutes") send it to Dated first.
- **Builder:** run the scorecard, read r13's assessment, and fix the order so a list footer plus bulk outranks a mentioned day. Record the actual cause in the PR. Do not add a phrase list for this one case.

## 4. Honest measurement
Order matters:
1. **First commit:** add 8 new holdout cases (fictional, written without looking at the rules):
   - 2 auto-replies (one with only the header-style subject, one Outlook "Automatic reply:"),
   - 2 delivery notices (one from a plain `notifications@` address that should still be Updates by phrase plus bulk, one from a person saying "the box was delivered, thanks" that should stay People),
   - 2 newsletters (one with a weekday in the subject),
   - 2 real asks that mention a day (should stay Waiting).
2. **Record SCORECARD before** from CI.
3. **Then** change the rules, and move u17, r13, u24 (and w25 if it already passes) from holdout to tune, since they were fixed by looking at them.
4. **Record SCORECARD after.** The floors are unchanged. The PR reports both runs.

## 5. Coming up accuracy
### `dates-corpus.json` (new) and `ComingUpCorpusTests`
30 fictional sentences, each with the sent day and the expected result (a date and time, or none):
- **Should find:** "Practice moved to Thursday 6-8 PM.", "Forms due 11/14.", "See you tomorrow at noon.", "Dinner Sat, Nov 21 at 7.", and similar.
- **Should not find:**
  - "50% off, 1/2 price today only." (`price`, `off`)
  - "3/4 of the team voted."
  - "Open 24/7."
  - "On Mon, Nov 2, 2026 at 9:00 AM Dana wrote:" (quoted header)
  - "Sent: Monday, November 2, 2026 9:14 AM" (Outlook forward header)
  - "I am out of the office until Monday."
  - "Posted Oct 30." (past)
  - "Version 2/3 of the draft."
- **Floor:** precision ≥ 95%, recall ≥ 85%. The 30 sentences are a tuning set, so the PR also lists any sentence that needed a rule change.

### Rule changes
- Add `price`, `off`, `of the`, `version`, `draft`, `page` to the numeric-date deny list. Reject `24/7`.
- Lines that start with `Sent:`, `Date:`, `From:`, or look like `On <date> ... wrote:` are dropped before dates are read (they are header lines, not plans).
- Auto-replies yield nothing (section 1).

### One entry per conversation
- `ComingUp.entries` keeps one entry per `threadId`, from the newest message with a date ahead.

## 6. Sprint 3 leftovers
- **Later tag** on Search results and on the person page message list: the same small `Later · Thu` caption the Settings list uses. Tapping the row opens the mail as today.
- **Waiting on them on the person page:** when you have an open ask to this person, a quiet row under the header: `You asked 5 days ago` with **Nudge** and **Got it**, reusing `WaitingOnThemListView`'s actions and Undo.

## 7. See the brief without waiting
- **Testing tools > Morning brief:**
  - **Preview:** shows the title and body of tomorrow's brief from the mail loaded now, or `Tomorrow's brief would be skipped: nothing to say.`
  - **Send a test brief:** asks for notification permission if needed, then schedules the same content 5 seconds out under a separate identifier (`lovely.morning.test`). It does not replace or turn on the real brief.
- Both use `FeedStore.morningBrief(at:showNames:)` with the saved names setting.

---

## Tests (Sonnet writes, CI runs)
- **`AutoReplyTests`:**
  - each subject prefix,
  - the header,
  - two body phrases needed (one alone is not enough),
  - a person's "I'll be out of the office Friday, can you cover?" is not an auto-reply and stays Waiting,
  - an auto-reply does not close Waiting on them,
  - an auto-reply does not close a promise.
- **`DeliveryTests`:** phrase plus automated signal is Updates; a person's "it was delivered, thanks" stays People.
- **`ComingUpCorpusTests`:** the floors above. Plus one-entry-per-thread.
- **Scorecard:** before and after, as in section 4.
- **Screenshots** (fictional): Search with a Later tag, person page with the Waiting on them row, Testing tools brief preview.

## Build order (Sonnet)
1. The 8 new holdout cases, committed alone. Push, record SCORECARD before.
2. `AutoReply` (pure), parser headers, sorting, Waiting on them and promise closing, thread lookup headers, and tests.
3. Delivery notices and the r13 fix. Move the fixed holdouts to tune.
4. `dates-corpus.json`, the date rule changes, header-line stripping, one per thread, and tests.
5. Later tag, person page Waiting on them row.
6. Testing tools brief preview and test send.
7. Docs (`docs/calm-feed.md`), PR against `testflight` with both scorecards, screenshots. Do not merge.

## Out of scope
- Reading your calendar or checking conflicts.
- Notification actions.
- New Gmail actions or scopes.
- Google verification (its own path, separate from sprints).
