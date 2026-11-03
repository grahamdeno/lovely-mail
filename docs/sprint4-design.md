# Sprint 4 design: dates and Calendar, reply all, morning brief

Designed on Opus, Nov 3, 2026. Built on Sonnet. Branch `sprint/4` from `sprint/3`, PR base `sprint/3` (one release).

## Owner decisions (defaults below; say if you want different)
1. **Calendar uses the system Add Event sheet, with no calendar permission.** On iOS 17 and later, Apple's event editor runs outside the app. Lovely never asks for calendar access and can never read your calendar. You tap Add in Apple's sheet. The alternative, write-only access for one-tap add, means a permission prompt for slightly less tapping. Recommended: no permission.
2. **Morning brief is off until you turn it on.** You turn it on from Settings, or from a one-time card on Home that you can dismiss for good.
3. **The lock screen shows counts only by default,** with no names or subjects: "2 waiting on you · 5 to do · 1 today". "Show names in the brief" is an opt-in switch.
4. **The brief comes at 7:30 AM** (changeable) and is skipped when there is nothing to say.
5. **Reply stays the default.** Reply all is one tap away whenever others are on the mail, and is never automatic.

No new Gmail actions or scopes. Nothing is sent. Notifications are local, built on the phone from mail already loaded.

---

## 1. Dates you can act on

### Today
- `EmailSummary.dates` holds strings like "Nov 7", with no time and no year.
- `MailKind.mentionsDay` only says that a day is mentioned.

### New: `MailDates` (pure)
`MailDates.extract(text:sent:calendar:) -> [MailDate]`, where a `MailDate` is:
- `start: Date`
- `hasTime: Bool`
- `phrase: String`, the words as written
- `sentence: String`, the sentence the date sits in

**Recognized forms**, resolved relative to the email's **sent date**, not today:

| Form | Example | Resolves to |
|---|---|---|
| Month and day, optional year | Nov 7, November 7th, Nov 7 2026 | That date; without a year, the next one on or after the sent date |
| Numeric m/d, optional year | 11/7, 11/7/26 | US month/day |
| Weekday | Sunday, this Sunday, next Tuesday | The first one after the sent date ("next" adds a week only when the same week would be the sent day) |
| Relative day | today, tonight, tomorrow | The sent date, or the sent date plus 1 |
| Time, attached to a nearby date in the same sentence | 9:00 PM, 9pm, 9 PM, noon, 14:30 | Sets `hasTime` |
| Range end | 6-8 PM | The start time only |

**Rules:**
- Keep only dates from the start of today through 120 days ahead.
- Skip mail where `MailKind.isReceipt` is true. Receipts name past days.
- Skip dates inside quoted replies, using `ReplySignals.authoredBody`.
- `nextDate`: the earliest kept date.
- `EmailSummary.dates` stays as is for display compatibility. The new `MailDate` list is computed, not cached. It is cheap.

### Where dates show
- **Email screen:** a row under the context line, `Sun, Nov 8 · 9 PM` (no time: `Sun, Nov 8`), with an **Add to Calendar** button. With several dates, it shows the first one and a `+2 more` menu that lists them.
- **Organization chips on Home:** "Rink · Coming up" becomes `Rink · Sun 9 PM` when a date exists in the next 7 days.
- **Home:** a quiet row after Waiting on them: `COMING UP · 2 THIS WEEK ›`. It counts mail with a date in the next 7 days and is hidden when the count is 0. It opens a list sorted by date, grouped `Today`, `Tomorrow`, `This week`, `Later`.

### Add to Calendar
- Presents `EKEventEditViewController` (EventKitUI) prefilled with:
  - **Title:** the cleaned subject (`FallbackSummarizer.cleanSubject`), at most 60 characters.
  - **Time:** start = `MailDate.start`. With a time, it lasts 1 hour. Without one, it is all-day.
  - **Location:** the first street address the data detector finds in the same email, if any.
  - **Notes:** `From <sender name> in Lovely.` Never the email body.
- The person taps Add or Cancel in Apple's sheet. Lovely does not read the result beyond whether it was added.
- **No `NSCalendars…UsageDescription` key** is added. The deployment target is iOS 26, so the permission-free editor is always available. If a build warning or a runtime prompt says otherwise, stop and ask the owner before adding a key.

---

## 2. Reply all (group mail)

### Today
- Reply drafts go only to the sender (`GmailCompose.appURL(to:subject:body:)`).
- The group's recipients are shown, but you can't reply to them.

### Rules (pure, in `ReplyRecipients`)
- **Reply:** To = sender.
- **Reply all:**
  - To = the sender plus the original To list, minus your addresses (`TriageContext.isMine` and other addresses).
  - Cc = the original Cc, minus yours and anyone already in To.
  - Order is kept and duplicates are removed case-insensitively. Your addresses never appear.
- **Offered when** anyone besides you and the sender is on To or Cc, the same test as `EmailPresentation.showsRecipients`.
- **Never offered** for organization mail (`store.isAutomated`), the same as Reply today.

### Where
- **Draft sheet:** a segmented control `Reply | Reply all` when offered. Reply is selected by default. The line under it shows who gets it: `To Dana · Cc Sam, Lee and 2 others`.
- **Email action bar:** `…` menu adds **Reply all** (opens the sheet with Reply all selected).
- **Thread view** (person page): a group message shows a caption, `With Sam, Lee and 2 others`. This keeps the group's identity on the person page (CLAUDE.md rule).

### Compose link
- `GmailCompose.appURL(to:cc:subject:body:)` and `webURL(to:cc:subject:body:)`, where `cc` is comma-separated and optional.
- Gmail's iOS scheme supports `cc`; the web form uses `cc` too.
- The privacy guard is unchanged: these build a compose link, the owner presses Send in Gmail, and the code still contains no send call.

---

## 3. Morning brief

### What it says
Built by pure `MorningBrief.make(digest:promises:waitingOnThem:comingUp:backFromLater:showNames:) -> MorningBrief?`.

- It returns `nil` when every count is 0. Quiet mornings get no notification.
- **Title:** `Good morning`.
- **Body,** in this order, keeping the first 3 parts with a count above 0, joined with ` · `:
  1. `2 waiting on you`
  2. `1 thing you said you would do` / `3 things you said you would do`
  3. `5 to do` (counts what is back from Later)
  4. `1 today` / `2 today` (Coming up with a date today)
  5. `1 back from Later` (only if parts 1 to 4 left room)
- **With Show names on,** part 1 becomes `Dana is waiting on you` / `Dana and Sam are waiting on you` / `Dana, Sam and 2 others are waiting on you`. Part 4 becomes `Today: Game 9 PM`, using the cleaned subject and at most 24 characters. The others stay counts.
- No em-dashes, no exclamation marks, no emoji.
- **Tapping it** opens Home. It is a plain local notification with no actions.

### When and how
- Each brief is a single local notification (`UNCalendarNotificationTrigger`, next brief time, not repeating), replaced every time it is rescheduled.
- **Rescheduled after every successful refresh,** and when the app goes to the background (`scenePhase == .background`). It is always computed from the mail loaded right then.
- **Background refresh:** register `BGAppRefreshTask` `com.grahamdeno.reelmail.morning`, requested for about 60 minutes before brief time. When iOS runs it:
  - refresh mail (the normal `load()`),
  - reschedule the brief,
  - request the next one.
- iOS decides whether it runs. When it doesn't, the brief uses what was loaded last. The text is counts, so it is never badly wrong, only possibly behind.
- **Keychain:** checked. `KeychainStore` already uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so background refresh can read the token. No change. **Do not change credential storage without owner approval** (CLAUDE.md).
- **Info.plist and project.yml:**
  - `UIBackgroundModes: [fetch]`
  - `BGTaskSchedulerPermittedIdentifiers: [com.grahamdeno.reelmail.morning]`
  - No other keys.

### Turning it on
- **Settings > Morning brief:**
  - A switch.
  - A time picker (default 7:30 AM).
  - The `Show names in the brief` switch, off by default. Its footnote: `Names can appear on your lock screen.`
- **The first time it is switched on,** the standard notification prompt appears (`.alert, .sound`). If it is declined, the switch turns off and shows `Notifications are off for Lovely. Turn them on in the Settings app.`
- **One-time Home card,** at the bottom of Home after the first day with a Done (`doneToday > 0`):
  - `Want a short morning brief? Counts only, at 7:30.` with **Turn on** and **No thanks**.
  - Either choice hides it for good (UserDefaults `lovely.briefOffer.seen`).
- Storage, per phone (not per account): `lovely.brief.enabled`, `lovely.brief.minutes` (minutes after midnight, default 450), `lovely.brief.names`.

### Sprint 3 tie-in
- Later items due before brief time count as `back from Later` in that morning's brief.
- Later still sends no notification of its own.

---

## Tests (Sonnet writes, CI runs)
- **`MailDatesTests`**, with a fixed calendar and sent date:
  - every form in the table,
  - a sent date on Saturday plus "Sunday" resolves to the next day,
  - "next Tuesday",
  - a year rollover (sent Dec 28, "Jan 3"),
  - times attach only within the same sentence,
  - receipts are skipped,
  - quoted text is skipped,
  - past and 120+ day dates are dropped.
- **`ReplyRecipientsTests`:**
  - you are removed from To and Cc, including another address of yours,
  - duplicates are removed,
  - the sender is first,
  - nothing is offered for 1:1 mail and organization mail,
  - the compose URL carries `cc` and is omitted when empty.
- **`MorningBriefTests`:**
  - nil when empty,
  - part order and the 3-part cap,
  - singular and plural,
  - the names variants (1, 2, 4 people),
  - the today subject is trimmed to 24 characters,
  - no em-dash (assert the text has no U+2014).
- **`ComingUpTests`:** the 7-day window, the grouping labels, and the org chip label.
- **Screenshots** (fictional data):
  - email with a date row,
  - Coming up list,
  - draft sheet with Reply all,
  - Settings Morning brief,
  - the Home brief offer card.

## Build order (Sonnet)
1. `MailDates` (pure) and tests.
2. The email-screen date row, the Add to Calendar wrapper (`UIViewControllerRepresentable` around `EKEventEditViewController`), the Coming up row and list, the org chip label.
3. `ReplyRecipients` (pure), the compose URL `cc`, the draft sheet control, the menu item, the thread caption.
4. `MorningBrief` (pure) and tests.
5. The scheduler (`UNUserNotificationCenter`), the BG task registration in `ReelmailApp`, the Settings section, the Home offer card, the project.yml keys.
6. Docs, the PR (base `sprint/3`), screenshots.

## Out of scope
- Reading your calendar.
- Notification actions (Done from the lock screen would change Gmail from outside the app; that needs its own approval).
- Snoozing via Gmail.
- A brief that summarizes message contents.
