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

## Current status
- Read-only static audit completed in conversation; no local compile or runtime verification performed.
- Redesign branch created from testflight at 44ede596bba75a3ea477125882207ff0eadba0db.
- App source subtree hashes matched scaffold at audit time.
- Existing live retrieval is limited to a default 30 inbox messages; complete sent/archived history and learned junk reduction are not implemented in the inspected pipeline.
- Design slice not yet implemented.

## Next implementation task
Inspect existing design tokens, router, root navigation, sample data, and dependent views. Implement the design slice in a scoped PR with tests, without changing Gmail scopes or triggering TestFlight distribution. Report actual build results and unresolved limitations.
