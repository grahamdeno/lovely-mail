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
