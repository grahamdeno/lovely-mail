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

## Known limits
- Google consent screen is in Testing: sign-in expires every 7 days; only test users can sign in.
- Summaries use Apple Intelligence when available (iPhone 15 Pro or newer); otherwise subject/first-sentence excerpts labeled as such.
- "Waiting on you" relies on reply detection; a reply that only promises a follow-up clears the wait. Resolution tracking beyond that is not implemented.
- Read state is local; Gmail unread labels are not changed.
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
- **Live test mail.** Eleven tagged messages, subjects [LT-01] to [LT-11], were sent from the owner's Gmail to itself on 2026-11-02 with his approval. Because they come from his own address they test Notes to self only. They should be moved to Trash once he confirms the test is done.

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
