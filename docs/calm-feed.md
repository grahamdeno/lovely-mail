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
- Approved compact design is on testflight (merge d0f86da, design head 2cb8bf1); uploaded as build 1002. That build has no Google client ID, so it runs in sample mode.
- Branch fix/gmail-release-config: TestFlight workflow now injects the client ID from Config/Release.xcconfig, refuses unconfigured uploads unless demo_build is requested, and verifies the archived Info.plist. Callback parsing extracted and tested; client ID validation tightened.
- Blocked on: a Google iOS OAuth client for com.grahamdeno.reelmail (none exists; the cos-mail-beta iOS client is bound to com.tangomike.cosmail).
- Live import limits unchanged: 30 inbox messages, no pagination, no sent/archived history, no outgoing direction, no account identity, filtering rules are demo-only.

## Next implementation task
After the client ID lands and a configured build is approved and uploaded: verify on device sign-in, inbox load, refresh, and relaunch. Then Milestone B: account identity, paginated import with coverage, sent history with outgoing direction, account-scoped filtering rules.
