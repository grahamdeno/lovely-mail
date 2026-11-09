# Reelmail: calm-feed redesign

## Approved product direction
Personal Gmail first; mobile-first native experience initially. Reduce junk and overload before polishing newsletters. Present worthwhile mail as compact summaries, connections, and one unified chronological timeline per person. Future multi-user support matters, but do not build unnecessary infrastructure before validating the personal experience.

## Visual direction
Replace the current visual treatment rather than preserving its layouts. Start with warm ivory #F7F6F2, white #FFFFFF, ink #202827, slate #626C69, deep teal #176B63, burnt amber #956018, and dividers #E4E8E3. These are proposed tokens, subject to contrast and device review. Support larger text, accessibility labels, and light/dark appearances. Avoid decorative per-email artwork and full-screen paging. Icon concept: an ivory folded-ribbon lowercase r on deep teal; not yet a finished or cleared mark.

## Navigation and screens
- Home: compact variable-height cards; Needs you, Updates, Reading; accessible Filtered review entry. Sender, meaningful change, and requested action take priority over unread counts.
- People: active relationship list and a unified timeline with dates, topic markers, explicit group participants, and expandable originals. Do not present incomplete history as complete.
- Search: searchable source mail and people, with clear coverage limits.
- Settings: account connection, privacy, demo mode, and diagnostics.
- Filtered review: explain decisions, allow correction and undo. Distinguish unwanted mail from wanted newsletters.

## Trust requirements
No Gmail changes in this milestone. Demo mode is explicit. Summaries must link to source messages. Generated claims and open requests must not be presented as verified facts without supporting mail. Do not label simple local hiding as Gmail Archive or as Snooze without a persisted return time. Do not infer identities solely from matching names.

## Milestone A: reviewable design slice
Implement Home, person timeline, and Filtered review using deterministic fictional mail. Preserve useful integration code. Include long text, missing photos, larger text, empty states, summary failures, sensitive mail, group mail, and uncertain classifications. Clearly label demo data. Filtering UI must not pretend a learned classifier exists. Tests and simulator screenshots are required before calling the slice validated; runtime validation remains pending when unavailable. Do not automatically merge or distribute.

## Milestone B: trustworthy live triage
Verify personal Gmail sign-in in a distributed build. Add persistent real-message storage, bounded paginated import with coverage status, incoming/sent history, and persistent reversible filtering corrections. Explicit sender rules may use feedback initially; do not claim trained personalization before it exists. Separate action-needed from reply-needed. Never silently fall back to fictional mail.

## Current status (Nov 1, 2026)
- Approved compact design is on testflight (merge d0f86da); uploaded as build 1002, which runs in sample mode (no client ID).
- Branch fix/gmail-release-config (PR #3), awaiting the Google iOS client ID for com.grahamdeno.reelmail:
  - TestFlight workflow injects the client ID from Config/Release.xcconfig, refuses unconfigured uploads unless demo_build is requested, and verifies the archived Info.plist.
  - Live import: account address from users/me/profile; Primary-tab inbox only (up to 120, paginated); sent mail from the last 90 days (up to 60); outgoing marked by address, never by display name; incremental refresh skips known messages.
  - Bulk detection from Gmail category labels, List-Unsubscribe/List-Id, Precedence and address shape. Reply detection ignores quoted text, signatures and link footers.
  - Feed priority: Waiting on you, People, Coming up, Updates, Reading. A reply from you newer than the ask moves it from Waiting to People; it is never hidden. Rules (Reading, Filtered) win over everything.
  - On-device cache per account (Application Support, complete file protection, excluded from backup): mail, summaries, hidden and seen state. Relaunch is instant; summaries no longer change between launches. Cleared on disconnect.
  - Session expiry (401, or refresh rejected) shows a Reconnect prompt; loaded mail stays.
  - UI: Home rows are full width; Draft reply on rows, source and conversation; Hide (local) replaces Archive/Snooze; Source, Search, Profile, Draft reply, New and Summary Lab use the calm palette. Old dark screens removed.

## Session fixes from first phone test (Nov 9, 2026, build 1028)
- Ask field moved out of the scroll area into the bottom bar, in its own view: the keyboard pushes it up as it grows, and typing redraws only the field (the lag and lost letters came from redrawing the whole email on every keystroke). While typing, the bar shows only the field; Return means Go.
- New session action `trash`: "delete", "trash", "junk" and similar work instantly with no model, and every engine can answer `trash`. It uses the Trash approved 2026-11-01 (app-wide 10-second Undo, Gmail keeps it 30 days). An engine saying "delete" still only reaches Trash.
- Lovely remembers senders he trashed in a session (exact address, per account) and offers Move to Trash first next time; putting one away forgets it.
- An engine's proposal replaces the main button instead of appearing twice.
- Session "More" (the ... button): Always put away in <category> (Gmail filter: exact address, skips the inbox, files new mail; also moves and marks read the sender's inbox mail now), Screen out this sender (Gmail filter to Lovely/Screened Out plus Lovely's own filter), and Move to Trash. Each is a preview button; filters are removable in Settings > Gmail filters.
- Screened Out > Decline now also makes the Gmail filter, so a declined sender's future mail skips the inbox in Gmail too.
- Not done: a rule for "trash these only when nothing is unusual" (it remembers the sender; it does not judge each email yet). Pending: device check on the next TestFlight build.

## Claude engine fix (Nov 9, 2026, build 1029 test)
- Opus 5.5 returned 400 for forced tool_choice. Claude requests (session and forms) now use tool_choice auto plus a system line asking for the tool; parsing also accepts the JSON written as text. Works on Sonnet, Haiku and Opus. Quick commands gained "file it away".
- Home: "N done today" now opens a Done today list (the messages done, put away or filed today, newest first) instead of To do. Lovely saves the ids with the daily count.

## Lag fix (Nov 9, 2026, build 1030 test)
- Apple Intelligence summaries were applied one at a time after launch; each one rebuilt triage for all mail and redrew every screen. Now applied in batches of 25 (or every 20 seconds), one change to `posts` per batch.
- `sessionCandidates` and `backlogCandidates` (read by Home on every redraw) are cached until mail, hidden or Later changes.
- Pending: device check. If lag remains, profile with Instruments on a Mac (SwiftUI and Time Profiler) during typing.

## Keep 2 weeks and per-row choices (Nov 9, 2026)
- New: Keep 2 weeks, then Trash. Lovely/Short-term label, out of the inbox, read. After 14 days Home shows "N short-term emails past 14 days · Review" (checked every 6 hours, IDs only) and the list moves them to Trash with one tap. Never trashed without his tap. Also in Settings, the drawer grid, the ⋯ sheet ("Always keep 2 weeks" makes a Gmail filter).
- Quick ones and Newsletters: each row has a swipeable strip (category ▾, 2 weeks, Archive, Trash, Unread); the bottom button does the whole page in one tap ("Put away all", "Archive all" or "Do all").
- Lovely remembers each sender's choice (SenderFateMemory, exact address, per account) and starts that sender's rows there next time.
- Owner approved (Nov 9): expired short-term mail moves to Trash automatically on the 6-hour check, with Undo; setting in Settings > Short-term mail (on by default). Recorded in CLAUDE.md.

## Launch (Nov 9, 2026)
- Signed in with saved mail: FeedStore applies the cache in init, so the first frame is your mail (the sample "Connect Gmail" page no longer flashes for ~2 seconds).
- Otherwise a splash (icon's l and dot, "lovely" wordmark, "Mail from your people.") shows until Lovely knows what to show (`hasStarted`), then fades.
- The iPhone launch screen (Config/Info.plist UILaunchScreen) uses LaunchBackground (app background, light/dark) and LaunchMark (the icon's l and dot, light/dark), so opening never shows black.

## Text someone about an email (Nov 9, 2026)
- Email ⋯ > "Text someone about this": pick a person (Apple's contact picker, no Contacts permission; then the last 5 people texted, most recent first), an editable draft (sender, subject, on-device summary, first date, "Want to talk about it?"; sensitive mail gets sender and subject only), "Text <name>" opens Apple's Messages sheet. Lovely never sends; the owner taps Send. Recipients stay on this phone.
- Next: offer it from the session (⋯) and as a quick command ("text Sarah about this").

## Undo and network (Nov 9, 2026)
- One Undo bar everywhere (newest, "+N more"); outside the session it used to stack every pending action full screen.
- A batch page's Trash rows share one Undo and move after the 10 seconds, like put away.
- Gmail requests retry twice on a dropped connection (NetworkRetry), after "The network connection was lost" when many changes reached Gmail at once.

## Home order and Notes thread (Nov 9, 2026)
- Home, in order: Today card (brief + session in one: "8 to go through · 1 waiting on you · 2 dates this week", one button; heading opens the brief), Waiting on you, Coming up this week inline (3, then See all), You said you would, To do, Notes to self (one row), Waiting on them, Kids · Energy · Money tiles on one line, Organizations, Earlier.
- Off Home: People (People tab), New senders (Settings > New senders; first-time senders already come up in the session).
- Notes to self is a text thread (Route.notes): notes as blue bubbles, his messages blue, Lovely gray. Tap a note to focus it; action strip: Done (Lovely/Notes, out of inbox, read; preview button), Bring back tomorrow (Later), Trash (test notes offered first), Open. Lovely answers with the chosen engine (health notes stay on Apple), suggestions appear as buttons. Thread kept on the phone (NoteThreadStore, per account, 200 messages).
- UI audit job 6 now opens New senders from Settings.

## Glance cards (Nov 9, 2026)
- Under To do and Notes, Home shows glance cards in a 2-column grid (HomeGlance, pure): Coming up (next date, "Thu 6 PM"), Bills ("2 due", next payee and day; a payment problem is an amber warning card first), Kids (newest kid and subject), Energy ("$4.29/day", change vs last month), Older mail (Earlier count), Organizations. Sorted by urgency; a card with nothing to say is left out.
- One color per kind (GlanceStyle): Coming up airmail blue, Money green, Kids amber, Energy teal, the rest muted; soft 12% wash with the big fact in full color. Rose stays for Waiting on you.
- Replaced: the inline Coming up list, the Kids/Energy/Money tiles, the Organizations chips and the Earlier row.
- Next: use the same category colors on session drawer chips.

## Opening animation (Nov 9, 2026)
- Cold start only, about 1.8 s, tap to skip: the icon's l writes itself in one stroke (path from Design/Brand/icon-layer-l.svg), the dot hops off the end, lands with a squash and a rubbery spring, then "lovely" and "Mail from your people." fade in. Continues from the still launch screen (same crop as LaunchMark). Mail loads underneath.
- Off with Reduce Motion, and in Settings > Appearance > Opening animation. All in `Features/Home/LaunchAnimation.swift`; to remove, delete the file and its one overlay line in ReelmailApp.swift. UI audits pass `-lovely.launchAnimation NO`.
- Contact photos are zoomed 14% inside the avatar so photos with baked-in white corners (initials images) fill the shape.

## Home as Today steps (design D, chosen Nov 9, 2026)
- Home top: "Today" with up to three steps (TodayPlan, pure): Answer <name> (or N people), Go through N emails, a date today, Pay <bill> due within 4 days. Only the first open step is lit and has the button; steps check off by themselves when their reason is gone; the day's steps are saved per account (TodayPlanStore) so finished ones stay checked, and new ones join while fewer than three are open. "Today ›" opens the brief.
- Below: "When you have a minute" chips (To do, Waiting on you, dates this week, Notes, Bills, Kids, Energy, You said you would, Waiting on them, older, Clear older mail, All cards). "All cards" opens the glance cards (Route.glance).
- Removed from Home: Waiting rows, Next up, the glance grid, the Today card.
- Coming up ignores "today" with no time (Tamara's "post your kit today" showed as an event).
- UI audit jobs that tap Next up (home.nextup.*) need updating to the new Home; not done yet.

## Known limits
- Google consent screen is in Testing: sign-in expires every 7 days; only test users can sign in.
- Summaries use Apple Intelligence when available (iPhone 15 Pro or newer); otherwise subject/first-sentence excerpts labeled as such.
- "Waiting on you" relies on reply detection; a reply that only promises a follow-up clears the wait. Resolution tracking beyond that is not implemented.
- Read state comes from Gmail. Since 2026-11-02 Done marks a message read in Gmail (owner approved); opening a message never does.
- Hidden mail and rules are per phone, not synced.

## Next implementation task
After the client ID lands and a configured build is approved: verify on device sign-in, inbox and sent load, refresh, relaunch from cache, 7-day reconnect. Then: reply chips (short suggested answers), "remind me if no reply", and a review of real-mail bulk detection misses.

## Empty Primary import (found on first real-device run, build 1003)
- Symptom: sign-in worked and the import finished, but the feed showed "No mail loaded yet."
- Likely cause: `in:inbox category:primary` returned nothing for this account (for example inbox tabs turned off). Not confirmed from device logs.
- Change: the import now falls back to the inbox without Promotions/Social/Updates/Forums, then to the whole inbox. The empty state now says Gmail connected but returned no inbox mail, with the sent count.
- Still unverified on a device until the next TestFlight build is installed.

## Trustworthy "Waiting on you" (after the first real-inbox run, build 1004)
First real run showed 23 waiting, including a portal notification, a do-not-reply school notice and a note from the owner's other address.

Rules now (FeedTriage.assess, all must hold):
- A person wrote it: not bulk/list mail, not a system address, no do-not-reply or portal wording.
- Not from you: your account, any address on your sent mail, or your display name.
- A direct ask in the author's own words (quoted text, signatures and link lines ignored).
- Apple Intelligence, when it ran, agrees a reply is needed. It can veto; it cannot add.
- You have not replied in the thread since.
- Sent to you directly: not a cc, not a group of more than 6.
- Under 14 days old. Older asks move to People with the reason shown.
- You have not marked the message, or the sender, as not waiting.

Every message carries a plain-language reason (shown on waiting rows, in the long-press menu and on the open message).
Corrections ("Not waiting on me", "Never for <sender>") are stored locally per account and can be undone.

Home layout: a List with no buttons on rows. Tap opens; swipe right to reply; swipe left for Not waiting or Hide;
long-press for everything else. Filter pills scroll edge to edge. Loading shows in the header subtitle.

Next steps:
- Check the waiting count and reasons on the real inbox; tune machine phrases from misses.
- Learn from corrections beyond the exact sender (for example, a domain that is always a portal).
- Reference class for receipts and travel; daily summary.

## Notes to self, Trash, speed and pinned bars (build after 1005)
- **Identity is the account address only.** A display name never marks mail as yours (an earlier rule did, and hid a message the owner sent from his iCloud address).
- **Notes to self.** The owner declares other addresses of his in Profile (or from a message: "This is another address of mine"). Mail from them lands in the Notes to self section and filter, never in Waiting on you. The app only asks when a display name matches; the owner decides.
- **Waiting asks.** Plain requests without a question mark count ("if you could give me some help", "email me back", "call me", "please send").
- **Trash (owner approved 2026-11-01).** Scope is now `gmail.modify`. Only action: move one message to Trash, and back on Undo (`users.messages.trash` / `untrash`). Swipe left: a short swipe shows Hide (and Not waiting); a full swipe moves to Trash with a 6 second Undo bar. Old sign-ins hold only the read scope; the first Trash attempt shows "Reconnect and allow it".
  - Owner step in Google Cloud: Data Access > add `https://www.googleapis.com/auth/gmail.modify` to the consent screen, then Reconnect in Lovely.
  - CI privacy guard now forbids send/compose/full-access scope, permanent delete, batch modify and label endpoints, and allows `gmail.modify` only in GmailConfig.swift.
- **Speed.** Tab switches were slow because every screen draw re-ran text rules over all messages. FeedStore now builds its derived data (triage, people, conversations) once per change.
- **Pinned bars.** Home filter pills, People title and search, and Search title and field stay in place while the list scrolls. The wordmark was removed from Home.

Shipped as build 1006 (merge ec68a78). Same-address self mail is also a note to self.

## Sorting scorecard and tuning (after 1006)
- **Corpus.** `App/ReelmailTests/Fixtures/sorting-corpus.json`: 105 fictional, labeled messages (79 tune, 26 holdout), each with the section it belongs in. `SortingScorecardTests` scores the rules and prints `SCORECARD` lines in the CI log (precision and recall per section, plus each miss with its reason). Floors: tune accuracy 95%; Waiting precision 95% and recall 85%; every other section 90% precision and recall (whole corpus). The holdout was written by the same author at the same time, so it checks overfitting but is not independent of the author's blind spots. Real-inbox review is the independent check.
- **Baseline before tuning** (local mirror of the rules): tune 66/79, holdout 18/26.
- **Rule changes**, each from a tune-set miss:
  - Courtesy and rhetoric are not asks: "Let me know if you have any questions / need anything", "Feel free to…", "Don't hesitate…", "If anything comes up", "Can you believe…", "Who knew…".
  - More polite asks count: "hoping you could", "was hoping you", "would love your", "would appreciate", "could use your".
  - Mail you sent yourself is a note before any other check, so a newsletter or receipt you forwarded to yourself is a note.
  - Booking systems are automated: "Reply C to confirm", "Reply Y to confirm or N to cancel". Codes ("verification code", "your code is") are automated.
  - Automated mail that names a weekday, "tomorrow" or a numeric date (11/19) is Coming up, as month-day dates already were.
  - Shipping and delivery notices stay in Updates even with a date. Bulk marketing ("shop now", "% off", "limited time", "promo code", "sitewide") goes to Reading.
- **Known holdout misses, deliberately not tuned:** "Remind me what the wifi password is" (an imperative ask with no ask phrase), an "out for delivery" notice from a plain-looking tracking address, and a recipe newsletter whose only list signal is "You are receiving this email because you signed up".
- **Review sorting** (Profile > Review sorting): the 60 newest messages, each with Right or "Belongs in…". Verdicts are stored per account on the phone (message ids and section numbers only) and never change sorting. Share summary sends counts and each miss's rule reason with the sender's name and address replaced; subjects are added only if the owner turns that on, and never for private messages.
- **Live test mail.** Eleven tagged messages, subjects [LT-01] to [LT-11], were sent from the owner's Gmail to itself on 2026-11-02 with his approval to test Notes to self. The owner has since removed them.

Next steps:
- Owner reviews 30 to 60 real messages in Review sorting and shares the summary; add each real miss as a fictional corpus case, then tune.
- Real-inbox check of Notes to self, swipe-to-Trash and Reconnect on build 1006 (not device-verified yet).
- Consider a "reply chips" pass and the Waiting resolution gap listed under Known limits.

## Gmail per-user rate limit (found on build 1008, Nov 2, 2026)
- The 403 after reconnecting was never a permission problem. Build 1008 showed Google's reason: RATE_LIMIT_EXCEEDED, "Units per minute per user". The project's per-user quota is now 6,000 units a minute (Google lists the previous value as 15,000). A fresh load with no cache (about 180 messages) went over it, and one refused message discarded the whole load, so Home showed nothing.
- Fix: a refused request waits 20 s, then 40 s, and retries; messages download 4 at a time; a message still refused is skipped and fetched on the next refresh, so everything that loaded is kept and cached.
- Next: if first loads stay slow, fetch sent mail with format=metadata, or raise the quota in Google Cloud (Gmail API > Quotas & System Limits).

## Real-inbox review and UI pass (after 1010, Nov 2, 2026)
- Claude read the owner's recent inbox through the Gmail connector (read-only) and compared Lovely's rules with its own judgment. Only patterns were kept; every corpus case is fictional. Corpus is now 120 cases (88 tune, 32 holdout).
- The account has no Primary tab results for `category:primary`, so Lovely loads the inbox without Promotions/Social/Updates/Forums (the second fallback). Gmail still labels messages CATEGORY_PERSONAL/UPDATES, which drive `bulk`.
- Fixes: forwarded messages end the author's words; blind-copy blasts are never Waiting and list under Organizations; Gmail addresses compare without dots and +tags; more system senders (invoice@, ebill@, confirmation@, reminders@, machine ids with long digit runs); auto-replies and schedulers are automated; receipts and finished services stay in Updates.
- Owner's calls: a business asking you to act on its site (eSign, complete a form, pay) is Waiting on you; a bare forward from his wife is People.
- Known holdout misses (untuned): an imperative ask with no ask phrase, an out-of-office reply that names a weekday (goes to Coming up), a delivery notice from a plain tracking address, a newsletter with only "you are receiving this".
- UI: dark mode (palette follows the iPhone), People tab People / Organizations / All, filter pills fade before the profile button.
- Owner step: add graham.denoyer@ipta.com in Profile > Your other addresses.

## Home digest and person page (owner approved the mockup, Nov 2, 2026)
- Home "All" is now a digest (`HomeDigest`, pure): Waiting on you (full rows), Notes to self (recent), New (unread, last two weeks), People (people, last two weeks), Organizations (automated mail and blind-copy lists, one button per sender name with a count), and Earlier (everything older than two weeks, one row that opens a list). Pills: All, Waiting, Notes to self, People, Organizations.
- Rows outside Waiting are compact: one line of preview; organizations show "Name · Section".
- Person page header (`PersonProfile`, pure): a blunt short version (emails traded since when, recent topics, your usual reply time, what is open), three numbers, open items both ways (their asks in Waiting, and your own "I'll…" promises from the last 30 days that they have not answered since), and recent topics (cleaned subjects).
- The short version is rule-based from loaded mail. An Apple Intelligence version is a possible next step; it would only rephrase these facts.
- Next: tune organization grouping (several addresses per company, e.g. two Fidelity senders, currently group by display name); "New" depends on Gmail's unread flag.

## Organizations by company, logos and Contacts photos (after 1011)
- Organizations group by company domain (`OrganizationKey`): mail.fidelity.com and shareholderdocs.fidelity.com are one group. Shared sending services (Gmail, Hide My Email relay, newsletter, form and school/app platforms) group by display name. The group name is the most common display name. Owner overrides: "Merge" on an organization page, "Split this sender out" per sender; saved per account in the triage rules (`organizationOverrides`).
- Organization page: logo, name, domain, short version, three numbers (emails, last 30 days, need you), Needs you, mail by section, and Senders (each address with its count and per-sender rules).
- Logos: fetched from the company's own site (apple-touch-icon, then favicon), cached in Caches, failures retried after a week; never for people, shared domains or fictional domains. Profile toggle "Company logos" (on by default).
- People photos: from Contacts only, matched by email on the phone, opt in from Profile (system permission prompt). Never fetched from the internet: matching people by name online is unreliable and would publish who emails you.
- Home has no filter chip row any more (owner, Nov 2): the top shows the date, a search button and the account button; each digest section title ("WAITING ON YOU · 2 ›") opens that section's full list.
- People tab has no switch (owner, Nov 2): one list, people first, then an "ORGANIZATIONS · N ›" section showing the five most recent (all matches while searching); the title opens the full organization list.
- Neon theme (owner, Nov 2): Profile > Appearance offers Automatic, Light, Dark, Neon. Neon is a third palette in CalmStyle (midnight violet ground, electric cyan for anything tappable with dark text on it, hot pink for Waiting) plus a pink-to-cyan gel line under the top bar.

## People screen fixes (after 1012, Nov 2, 2026)
- Person or organization: a sender not plainly automated is a person if you've written to them, writes from a personal mailbox (gmail and the like) without a company word in the name, or has a two-to-four word capitalized name with no company word ("Group", "Reserve", "Recreation", "Services"...). Otherwise an organization. Rule: `PersonSignals`.
- Previews hide only real secrets (codes, passwords, keys, account numbers). Apple Intelligence's own "sensitive" guess no longer hides mail.
- Forwards read "You forwarded: <subject>" in list rows.
- Same full name from two addresses is one person; the person page lists "Also <address>" with "Not the same person" (saved per account).
- This year's dates drop the year.

## Unread is the to-do (after 1013, Nov 2, 2026)
- Owner: "I used my unread status as a todo list. Unread means I wasn't ready to act on it yet." Build 1013 hid it: unread mail older than two weeks folded into Earlier, and opening a message in Lovely marked it read on the phone.
- Fixes: unread never folds into Earlier; opening never marks read; the old local "seen" set is ignored. Every refresh re-reads Gmail's unread list (`is:unread` + the inbox query, up to 300) and loads every unread message however old, so the to-do matches Gmail.
- Home "To do · N": the oldest unread is a Next up card (sender, what it is, "Unread 3 weeks", Done, Reply, Trash); the next four follow as compact rows with their age; "N more unread" and the title open the whole list, oldest first. After 30 days the card asks "Still need this?". The title shows "3 done today" (count kept on the phone, resets daily). No streaks or mascots (owner rejected the gamified Neon mockups the same night).
- Done (owner approved 2026-11-02): marks the message read in Gmail (`messages.modify`, removing UNREAD only) with a 6 second Undo that marks it unread again. Swipe right, the long-press menu, the Next up card and the open email all offer Done. If Gmail refuses, the message stays on the to-do and the reason shows. CI allows `modify` only in GmailService and only the UNREAD label.
- "St. asked 7 days ago": first names keep titles and articles whole ("St. Andrews Reserve", "Dr. Patel", "The Rink").
- Pending: device check of Done on the real inbox; screenshots come from CI.
- Build 1014 on the real inbox showed "To do 0": all 17 unread messages were in the Updates and Promotions tabs, none in Primary, and the unread list used the Primary query. Fix: the unread list is `is:unread in:inbox`, every tab. Read mail still comes from Primary only.


## Email screen redesign (owner, Nov 3, 2026)
- Owner: "The UI here has a lot to be asked for." The old screen was wider than the phone (the fixed-size button row pushed text off both edges), links and phone numbers weren't tappable, two large "Not waiting" buttons outweighed the email, a summary repeated short mail, and a footnote explained the buttons.
- Now: sender row (tap for the conversation), subject, "Oct 26 · 8 days ago", To/Cc only when someone besides you is on it (full lists then, so group mail keeps recipients); one line "Waiting on you: <their ask>" with a small Not waiting; the email with tappable web, email, phone and street addresses (detected on the phone, `EmailPresentation`); "In short" only for bodies over 600 characters. Bottom bar: Reply, Done (unread only), Trash, and "…" (Open in Gmail, conversation, sender rules, Hide). Title is the sender. Trash from here offers Undo on Home.
- Pending: device check; screenshots 11-13 come from CI.

## Sprint 1 UI (Nov 3, 2026)
- Settings replaces the account menu: the avatar on Home (36 pt, thin ring, 44 pt hit area, label "Settings") pushes `Route.settings`. The magnifying-glass button is gone from Home; the Search tab stays. `AppTab` is now Search, People, Home (the unused Profile and New cases were removed; `NewMessageView` stays in the project, unreferenced).
- Profile became Settings (`Features/Settings/SettingsView.swift`), same controls and privacy text, regrouped: Account (mail source, reconnect notice, Connect/Reconnect, a quiet Disconnect Gmail at the bottom), Your other addresses, Appearance, Pictures, Rules (rules card, Review filtered senders, Show hidden mail), Testing (one row, "Testing tools": Review sorting and Summary Lab), About (On-device AI card and a row, "How Lovely handles your mail", with the privacy paragraph).
- People: an "Organizations · N ›" row with up to four logos sits under the search field (hidden while searching). The bottom Organizations section shows three rows. The organization list is A to Z with its own search (name and domain). People search also matches organization domains.
- Next up card: Done and Reply always show their words; the stale note ("Still need this?") is secondary text, not rose (rose is Waiting on you only).
- Person timeline: the Draft reply bar has an opaque full-width backing; topic chips never truncate (the row scrolls sideways). The person header is unchanged.
- Screenshots 14-Settings and 15-People-orgs-row come from CI.
- Pending: device checks of all of the above (Done label on device, Settings back button and large title, bar backing over long conversations, chip scrolling). Nothing here has run on a phone yet.

## Sprint 1 sorting (Nov 3, 2026)
- Audit of the real inbox: sections agreed 92 to 95%, but Waiting on you ran about 73% precision and 78% recall at arrival. Causes: quoted text (the owner's own sentences) read as asks, courtesy lines with curly apostrophes, calendar and group-notice mail.
- **Quote and forward stripping** (`ReplySignals.authoredText`): the author's words end at an Outlook header block (`From:` followed within three lines by `Sent:`, `Date:`, `To:` or `Subject:`, however few lines came before), a line of 10+ underscores, `On ... wrote:` (also when Gmail wraps `wrote:`), "<Name> reacted to your message", and the existing forward markers. Summaries read `ReplySignals.summaryBody` (quotes and signatures removed, links kept so newsletters still categorize); under about 40 authored characters the whole body is used. Apple Intelligence is told to address the reader as "you".
- **Phrases:** curly quotes are straightened before matching. New courtesy: "any additional/further/other questions", "feel welcome to", "let me know if you need/there's/there is anything (else)". New machine phrases: "this is a group email", "please reply to sender only"; subjects starting Accepted:, Declined:, Tentative:, New time proposed:, Invitation: are machine mail. System local parts add admin, sender, assistance, policy, claims.
- **Names and previews:** address-only senders read "DFAS SmartDocs" / "Pisa Recreation" (generic local parts such as noreply use the domain's main label, "Infinitecampus"); "Last, First" shows as "First Last"; single quotes trimmed; initials split on spaces, hyphens and dots; row previews no longer end at "Ms." or "J." (three words minimum) and Apple Intelligence blurbs show as written; "temporary password will come in a separate email" no longer hides a preview, while `sk-` keys and 32+ character letter-and-digit tokens do.
- **Unchanged on purpose:** automated eSign/pay/complete mail stays in To do; the 14-day window; Waiting group-size rules.
- **New corpus cases (all tune, fictional):** `fp-outlook-quote`, `fp-reaction`, `tp-outlook-ask`, `c-additional-questions`, `c-curly-hesitate`, `m-group-email`, `m-calendar-accepted`. Corpus is 127 cases (95 tune, 32 holdout). `PersonNameTests` covers the name, preview, secret and stripping rules.
- **SCORECARD before (sprint/1, CI):** tune 88/88, holdout 28/32, all 116/120; Waiting (all) precision 100%, recall 97%.
- **SCORECARD after (PR 19, CI):** tune 95/95, holdout 28/32, all 123/127; Waiting (all) precision 100%, recall 97%. 134 tests, 0 failures. Holdout misses unchanged (w25, u17, r13, u24).
- **Side effect to watch:** an address-built name such as "DFAS SmartDocs" is two capitalized words, so People vs Organizations may treat it as a person; the 32+ token rule can match long tracking ids. A test fixture sender called `sender@` became a system address, so the test now uses `pal@`.

## Sprint 2 (Nov 3, 2026)
- Search tab: People and Organizations groups (best five each) above Mail. Every word of the query must match somewhere (name, address, subject, summary, body), in any order. Rules live in `MailSearch`.
- Reading: Gmail's Promotions tab (`CATEGORY_PROMOTIONS`) sends mail to Reading even with no marketing words (`Email.promotionalMark`, optional so older caches decode). A `.newsletter` category now needs list signals (`email.isAutomated`); a person's mail that mentions a newsletter is no longer filed as one.
- Stub bodies: when the text/plain part is under 200 characters and the HTML has more, the stripped HTML is used (`GmailMessageParser.preferred`).
- Plain asks added: "i need the", "remind me", "keep me posted", "let us know", "see if you have/had", "touch base". "Let us know if you have any questions" stays a courtesy.
- Refresh errors: `RefreshProblem` gives a short plain message (offline, slow down, Gmail trouble, other), says loaded mail is unchanged, and Home shows Try again. No demo mail is substituted.
- Corpus: 7 new cases (p-ask-*, p-courtesy-let-us-know, r-promo-no-keywords, r-newsletter-ai-only). Sprint2Tests covers the rest.
- Not verified locally (no Xcode here): compile and tests run in CI only. Screenshots and on-device checks are pending.
- Still open: Waiting on them / You said you would (Sprint 3, design first), Later/snooze, holdout misses w25, u17, r13, u24 (w25 "Remind me" may now pass), structured dates, group reply-all, morning brief.

## Sprint 3 (Nov 3, 2026)
Design: docs/sprint3-design.md. Stacked on Sprint 2 (PR #22); ships in one release.
- **You said you would** (Home, up to 3 cards, title opens all): `PromiseRules`. Strict verb pattern, no questions or "if" offers, real recipient, 0 to 14 days, closed by any later message in the thread. Done and Not a promise are local, with Undo. 24-sentence `promise-corpus.json`: 100% precision, 90% recall floor.
- **Waiting on them** (one quiet row on Home, list screen with Nudge and Got it): `WaitingOnThem`. Your ask, 1 to 3 real recipients, 3 to 21 days old, no answer in loaded mail. Threads with no loaded inbox mail are confirmed with a read-only `threads.get` (metadata only, 20 per refresh); unconfirmed threads stay out. Nudge opens a draft; Lovely never sends.
- **Later** (clock button on the To do card and email bar, short swipe, list in Settings): local only. Gmail is untouched, so the mail stays unread there. Returns at the top of To do with "Back from Later". `LaterSchedule` is pure and tested with a fixed calendar.
- **AI veto** (`CommitmentVeto`): on-device model may remove an item the rules found, never add one. No opinion leaves the rules in charge. Verdicts cached in `MailCache.verdicts` (optional).
- **Gmail:** no new actions or scopes. The only new call is read-only `threadSenders`.
- **Not done / next:** the "Later" tag on Search and the person page, an open item for Waiting on them on the person page, a Later phone notification (Sprint 4 morning brief). CI is the only compile check so far; no screenshots or device check yet.

## Sprint 4 (Nov 3, 2026)
Design: docs/sprint4-design.md. Stacked on Sprint 3 (PR #23); ships in one release.
- **Dates:** `MailDates` (pure) reads dates and times from the subject and the author's own words, resolved from the day the mail was sent, within 120 days, skipping receipts and quoted text. The email screen shows the first date with Add to Calendar and a "+N more" menu. Home has a quiet "Coming up · N this week" row that opens a list grouped Today, Tomorrow, This week, Later. Organization chips read "Rink · Sun 9 PM" when a date is in the next 7 days.
- **Add to Calendar:** Apple's Add Event sheet (`EKEventEditViewController`). No calendar permission and no usage-description key; Lovely never reads the calendar. Title is the cleaned subject (60 characters at most), notes are "From <sender> in Lovely." and never the body, location is the first street address on the phone's data detector.
- **Reply all:** `ReplyRecipients` (pure). Sender first, then the original To, then Cc; your addresses and repeats removed. Offered only when someone besides you and the sender is on the mail, never for organization mail. Draft sheet has a Reply | Reply all control and a "To … · Cc …" line; the "…" menu has Reply all; group messages show "With Sam, Lee and 2 others" in the conversation. The compose link gained an optional `cc`. Lovely still never sends.
- **Morning brief:** off until switched on (Settings, or a one-time Home card after the first Done). Local notification at 7:30 AM by default, counts only unless "Show names in the brief" is on, skipped when empty. Rebuilt after each refresh and when the app goes to the background; a background refresh task (`com.grahamdeno.reelmail.morning`) asks iOS to wake the app about an hour earlier. iOS decides whether it runs. Info.plist gained `UIBackgroundModes: fetch` and `BGTaskSchedulerPermittedIdentifiers`. No notification actions.
- **Gmail:** no new actions, scopes or credential changes (the Keychain already uses AfterFirstUnlockThisDeviceOnly).
- **Not done / next:** the date row only uses the first date for Add to Calendar's default; no calendar read, so no conflict check. The brief cannot run if iOS never grants background time (it then shows what was loaded last). Owner device check of notifications, the Add Event sheet and Reply all in Gmail is pending. CI is the only compile check; screenshots 19 to 23 come from CI.

- **Shipped:** Sprints 2, 3 and 4 merged to testflight together on Nov 3, 2026 as build 1017.

## Sprint 5 (Nov 3, 2026)
Design: docs/sprint5-design.md. Based on testflight (build 1017). A trust pass before the first device check.
- **Auto-replies** (`AutoReply`): by header (`Auto-Submitted: auto-replied`, `X-Autoreply`, `X-Autorespond`), subject prefix (Automatic reply, Out of office, OOO, Away) or two body phrases. They sort to Updates ("Automatic reply"), never close Waiting on them or You said you would (inbox mail and the read-only thread lookup both skip them), and yield no dates. `Auto-Submitted: auto-generated` is left alone on purpose: it is a system notice, not a reply (design said "anything but no"; this is narrower).
- **Delivery notices** (`DeliveryNotice`): a delivery phrase plus an automated signal or a shipping sender word (tracking, shipping, orders, ...) goes to Updates ("Delivery update") and yields no dates. A person writing "it was delivered, thanks" stays with People.
- **Newsletters:** bulk mail with a list footer ("You are receiving this email because...") is Reading even when it names days, unless it is school, travel or plans mail. This fixes holdout r13 (its category was never Newsletter, so the Newsletter rule never ran).
- **Dates:** `dates-corpus.json` (30 fictional sentences, every date each should yield) with precision 95% and recall 85% floors. Rule changes: skip forwarded and quoted header lines (Sent:, From:, On ... wrote:), skip offer sentences (50% off, sale), number pairs after Version, page, step and similar, and a weekday written before its own date ("Thursday, Nov 12") is one date, not two. Coming up shows one entry per conversation, from its newest message with a date ahead.
- **Sprint 3 leftovers:** a "Later · tomorrow 9 AM" tag on mail you put off, wherever it still shows (Search, organization and person lists, conversation bubbles); a "You asked 5 days ago" row with Nudge and Got it at the top of a person's page.
- **Testing tools > Morning brief:** shows the next brief as it would read now (or that it would be skipped) and sends a test in 5 seconds under its own id. It does not turn the brief on.
- **Gmail:** no new actions or scopes. The thread lookup still reads metadata only; it now also asks for the Subject, Auto-Submitted, X-Autoreply and X-Autorespond headers.
- **Measurement:** 8 new fictional holdout cases (`h5-*`) were committed first. SCORECARD before and after are in the PR. The three holdouts fixed by looking at them (u17, r13, u24) moved to the tuning set.
- **Not done / next:** device check of build 1017 and this sprint; Google verification path (needs a separate Google Cloud project; the owner presses Publish and Submit).

## Sprint 6 (design, Nov 4, 2026)
Design: docs/sprint6-design.md. Insights from mail, all on the iPhone: a full-page morning brief at a learned time (Kids, Money, Energy), accounts and bills ledger with a payment-problem alarm, Sense plus Duke energy page with one rule-based suggestion a month, water cost per household, per-child school digest with chunked newsletter summaries, cards walk-through with chat behind an owner switch, learned rules, and handoff prompts for Grok or Claude (filters and forwarding stay with the owner's agent). Wider Gmail permissions approved Nov 4 (labels, filters, forwarding, send) behind preview-and-tap guardrails; handoff prompts only for non-Gmail tasks. Tier 2 cloud designed, not built.
- **Built (Nov 4, 2026, on branch sprint/6-design, PR #26; CI result and device validation recorded in the PR):** steps 1 to 9 of the build order. Insight store with 12-month metadata-first read; Energy, Money (with payment-problem alert, announced once per bill), Kids, brief page with learned time (9:30 weekdays, 10:00 weekends, optional 7 PM check), cards walk-through, chat walk-through behind Settings, Testing tools, Chat walk-through (Remove rules made in chat); Gmail actions with guardrails; Shoebox rule; New senders (Screened Out); Send on Draft reply; one-click unsubscribe; handoff prompts (Grok default, Claude).
- **Not done / next:** Opus review before ship (redaction, health exclusion, alarm wording, every send path); Google Cloud Data Access: tick the three new scopes, then Reconnect in Settings; confirm the Shoebox forwarding address once in Gmail; device validation and screenshots; Tier 2 cloud stays designed, not built; measurement floors on real mail not yet run.

### Sprint 6 follow-up (Nov 4, 2026, build 1019 tested on device)
- Verified on device: four permissions granted (Google shows three boxes; send is folded into mail access), a reply sent from Lovely arrived, Kids looks right.
- Fixed on branch `fix/forwarding-status`: "Ask Gmail to verify" removed. Gmail's forwardingAddresses.create is Workspace-only (HTTP 403 on personal accounts). Forwarding addresses now show Gmail's own status by a read-only GET; privacy_guard blocks any non-GET to that endpoint.
- Lag reported on device (scrolling, swipes, tab bar). Likely causes found by reading the code: the 12-month insight backfill changed the observed store once per message, and Home rebuilt digest, Coming up (date parsing over every message, once per organization chip), promises, waiting-on-them, new senders and kid matches on every redraw. Fixed on the same branch: backfill publishes every 100 messages; those lists are cached until their inputs change or the minute turns. Not yet measured on device.
- Disconnect no longer deletes what you typed (households, kids, forwarding addresses, Shoebox). Mail-derived data is still deleted.
- iCloud backup (key-value store) of those typed settings, on by default, toggle in Settings. Needs the iCloud entitlement to survive signing: the TestFlight archive is now ad-hoc signed (an unsigned archive drops entitlements on export), with checks in the archive and a `dry_run` input that exports without uploading. Not verified on device.
- Delete, remove, decline, clear and disconnect buttons are rose-red (`role: .destructive`; CalmActionStyle honors it).
- "Send to Shoebox" in an email's "…" menu when a Shoebox address is set and allowed; preview, 10-second Undo, health mail excluded.

### Build 1025 feedback (Nov 7, 2026)
- Tab switching much smoother after the Home caching fix.
- Trash showed no Undo when used outside Home (the Undo bar lived only in Home). Fixed on `fix/trash-undo`: every Trash, from any screen, shows the app-wide Undo bar for 10 seconds; Undo takes it out of Gmail's Trash. No "are you sure" prompt, by the owner's choice.
- Mark as done (read) still offers Undo only on Home.


### UI audit harness (Nov 8, 2026, on `fix/trash-undo`)
Built so a model can walk the real app the way the owner does, with screenshots as evidence. Nothing here ships to users.
- **Fixture mode** (`-uiTestFixtures`, Debug builds only, `App/Reelmail/Fixtures/UITestFixtures.swift`): fictional inbox (utility bill, failed payment, Sense report, kid mail for two children, a renewal, two newsletters with one-click unsubscribe, a first-time sender, a health message, a group thread, mail from me), a fake `GmailInboxClient`, and a fake transport for `GmailActions` that records every request and answers success. Shoebox address and allowlist are pre-set; Settings, households and kids are reset at each launch. Error launches: `-uiTestExpired`, `-uiTestNoPermission`, `-uiTestOffline`, `-uiTestEmpty`, `-uiTestSignedOut`. `-uiTestAppearance light|dark|neon` sets the app's appearance.
- **Release safety**: the file is wrapped in `#if DEBUG`; `scripts/privacy_guard.py` fails if fixture names appear outside `#if DEBUG` or if the fixture file opens a network connection (selftest covers both); `testflight.yml` also scans the archived binary with `strings` before export.
- **Tests** (`App/ReelmailUITests`, scheme `ReelmailUIAudit`, not part of the `Reelmail` scheme so the normal unit run stays fast): `AuditJobs` (10 jobs; jobs 1, 4 and 10 also run in dark, Neon, largest text and the four error states), `AuditCrawler`, `AuditSmoothness` (launch, Home scrolling, tab switching).
- **Workflow**: `.github/workflows/ui-audit.yml`, run by hand (`workflow_dispatch`); until the file is on the default branch GitHub cannot dispatch it, so adding the label `ui-audit` to a pull request starts the same run. It writes `audit-summary.json`, every screenshot as `NN-job-sNN-step-condition.png`, and prints the summary and reduced-size light-mode screenshots into the job log because artifact downloads can be blocked.
- **Known limits**: the clock is not frozen (the app calls `Date()` in about 70 places); fixture mail is dated relative to launch instead. Simulator smoothness numbers show relative problems, not a phone's frame rate. Nothing here touches Google sign-in, Face ID, real notifications or the iCloud account.
- **Next**: Opus reviews the screenshots and `audit-summary.json`, scores each job, and lists the top fixes; Sonnet fixes them and ships with PR #28 when the owner says "ship". Mark as done still offers Undo only on Home.
- **Opus review of audit run 2 (Nov 8)**: 9 of 10 jobs finish unaided; 189 of 196 checks passed. Ranked fixes: (1) Households footer wrongly says data is deleted on Disconnect; (2) Decline shows no result and has no Undo; (3) Next up starts behind the tab bar (owner to choose: Next up first, cap Waiting on you at 2, or padding); (4) unify Done's toast with the app-wide Undo bar, and add Undo to Done in an open email; (5) reply sheet loading wording, starter grammar, Undo keeps the typed reply, person page "send in Gmail" copy; (6) largest text breaks tab labels and Next up buttons; (7) label sample mail on first-launch Home with a Connect button; (8) plain wording on open email, Kids reasons, empty inbox; (9) 44-point targets and caption/amber contrast; (10) More menu grouping, Settings title, Disconnect confirm. Audit run 3 (crawler fixed) was running when this was written.
- **Audit fixes shipped with PR #28 (Nov 8)**: honest Households footer (backed up to iCloud, kept on Disconnect); Decline held 10 seconds with Undo and gone from the list at once; Home shows two Waiting on you rows plus "See all N" so Next up is on the first screen; every Home undo (Done, Not waiting, Later, promises) uses the one app-wide Undo bar, and Done in an open email now has Undo; reply sheet shows Send from the first frame, starter text keeps capitals and drops "?.", an undone or refused reply comes back when you tap Reply; icon-only tab bar and Next up buttons at accessibility text sizes, and the Undo bar clears the taller tab bar; sample-mail card with Connect on first-launch Home; plain wording for automated mail, Kids reasons and the empty inbox; Disconnect asks once; caption grey one step darker; "Share with an AI assistant".
- Audit run 3 (pre-fix app): 201 of 201 checks, crawler 0 crashes. Run 4 (fixes): every fix visible in screenshots; jobs 3 and 5 failed only because the test could not find mail behind the new "See all" (test fixed in 07a8ed3, not yet re-run).
- **Next**: re-run ui-audit once to confirm jobs 3 and 5; owner checks the phone checklist on the TestFlight build. Crawler "no way back" findings are tab switches and the keyboard (expected); "does nothing" findings are Appearance taps (colour-only change) and re-tapping the current tab. Open idea: re-tapping the current tab could scroll to the top.

### TestFlight check after PR #28 (Nov 8, 2026)
Owner ran the 7-step phone checklist: all passed (Next up on first screen, one Undo bar for Done in Home and in an email, Trash Undo, Decline held with Undo, reply text kept after Undo, Disconnect confirm with households and kids kept, iCloud footer).
Next round:
- Remaining slight tap and navigation delay (most lag was Low Power Mode). Profile Home: it likely rebuilds the whole list after every tap.
- Send in the reply sheet should look faded until the starter text loads (it is disabled but looks active).
- "Your other addresses" are per account and not in iCloud backup; while disconnected Settings shows the empty sample list, which looks like data loss. Back them up with SettingsSync and keep showing them while disconnected.
- Nov 8 evening, owner: filtered senders kept showing on Home and never appeared in Settings > Review filtered senders. Fixed on `next/after-1026`: the review lists every filter rule (not only loaded mail) with Restore; Filter shows the Undo bar; Kids and New senders now respect filters (they read all mail before); "Filter everything from <domain>" on an organization page covers every address and subdomain at that company (never for public providers like gmail.com); after filtering, Lovely offers a real Gmail filter (owner approved Nov 8): preview, then new mail skips the inbox into `Lovely/Filtered` and the loaded messages from that sender move there. Nothing is deleted; remove it in Settings > Gmail filters. Send in the reply sheet now looks faded until it can be tapped.

## Sprint 7: Inbox session (design approved Nov 8, 2026)
Design: docs/sprint7-design.md. The owner works through unread mail in conversation; each decision becomes a Gmail action and mail is put away (read, drawer label, out of the inbox). Claude understands replies and drafts; rules, drawer memory and Apple Intelligence do routine work.
- **Step 1, session engine (branch `feat/inbox-session`):** pure rules in `App/Reelmail/Session/`: `Drawer`/`DrawerChoice`, `DrawerMemory` (address, then company domain; never public or shared sending domains), `DrawerGuesser` (rules, kids from Settings > Kids), `SessionPlanner` (one at a time, quick, reading; batch exclusions; order; estimate), `SessionProgress`. Tests: `SessionEngineTests`. No UI and no Gmail calls yet.
- **Step 2, session screens:** `Features/Session/`: Home card "Go through your inbox", start, one item per screen (one main button: the suggestion), drawer grid, reply with Send and put away, quick batch with drawer chips and one confirm, newsletters with Keep, wrap-up. Put away and send are held 10 seconds with one Undo; Gmail refusals bring the item back to the session. `GmailActions.archive` (remove INBOX only). `SessionConfirm.swift` makes the ConfirmedAction (privacy guard updated).
- **Step 3, engines:** `Session/Engines/`: `SessionCommand` (one schema, validator, instant quick commands), `SessionPlaybook` (model-neutral tuning, learned examples), `EngineSettings`/`EngineUsage`/`EngineRouter`, `AppleSessionEngine` (@Generable), `CloudEngines` (Anthropic Messages API, xAI Chat Completions; both forced to one tool), `SessionHandoff` (app link, web link, copy; `[Lovely] H-xxxx` report subject), `EngineScorecard`. Settings > Inbox session > Conversation engine (Apple only default, keys, models, compare, weekly calls and cost, scorecard). Item screen: "Or say what to do" with proposals (two in compare mode).
- **Step 4, web forms in Lovely:** the handoff sheet offers "Do it here in Lovely" when the email has a link and a cloud key is set. `WebFormView` opens the site in a browser panel (sign-ins persist); "Fill this page" reads the page's fields (`FormScripts.extract`), the engine proposes values (`FormFiller`, Claude or Grok), `FormFillValidator` keeps only listed, non-sensitive fields with matching options, and the values are filled and outlined in blue. Passwords, codes, card, account and Social Security numbers are never filled. Lovely never clicks or submits. Settings > Conversation engine > Your details for forms (name, email, phone, address, this phone only).
- **Also:** Apple Intelligence drawer suggestions for routine mail the rules could not place (a suggestion only, never batched); UI audit job 11 walks a whole session.
- **Backlog mode:** "Clear older mail" (Home when nothing new is waiting, and the session's start and wrap-up screens) runs the same session over read mail still in the inbox, oldest first, 50 at a time. Read mail from people and notes to self may go in a batch there; everything else on the never-in-a-batch list still gets its own turn. Only loaded mail is covered (the newest 120 inbox messages plus all unread); after a page is put away, the next refresh loads older mail for the next page.
- **Audit (Nov 9, 59b13da):** job 11 passes in light, dark and large text. One known flake: job 10 large text, the Disconnect confirmation (failed in light and Neon the run before).
- **Categories and tags (Nov 9):** ten categories replace the drawers (`Drawer`: money, home, kids, health, work, projects, orders, travel, personal, accounts; old names decode). `MailTagger` adds tags from fixed lists: type, topic per category, property (Settings > Households: active only, Home mail or a linked sender domain, never a shipping address), person (kids, only in kids, health, money, travel and personal mail), `Lovely/Taxes/<year>` for tax documents (year in the text, else last year for Jan to Apr mail, else this year). Put away files the category and its tags in one Gmail call (`GmailActions.file(labelIDs:)`). Item screen shows tag chips (tap one to leave it off); batch rows show tags; changing a category keeps only type, person and tax tags.
- **Found in your mail (Settings > Households and kids):** `Discovery` offers children (parent of, student, Name's report card, first name plus the owner's last name, in school and care mail) and properties (street addresses in mortgage, utility, lease, insurance and closing mail; sale wording marks one as past), each with how many emails, to add or dismiss. Nothing is added on its own.
- **Clean up old login emails (Settings, Gmail only):** lists account notices older than 90 days or a year, then one tap moves them to Trash after the 10-second Undo. Never runs on its own.
- **Not done yet:** device check of everything in Sprint 7; first real scorecard runs per engine.
