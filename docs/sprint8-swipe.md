# Sprint 8: card moves in the inbox session

Owner direction, Nov 10, 2026. Borrow Shoebox's Today moves (grahamdeno/Shoebox, `App/Shoebox/Today/TodayView.swift`) for the inbox session. One email per screen, full height, moved with the thumb.

## The moves
| Move | Does | Gmail change |
|---|---|---|
| Flick up (100 pt) | Skip for now. Stays unread, comes back next session. | None |
| Pull down (160 pt) | Put away: the screen's filing action. | Yes, on release past the line (approved Nov 10, see below) |
| Swipe left (sideways, 1.5x wider than tall) | Shows Move to Trash beside the email. | Only on a tap of that word, never the swipe |
| Tap | Opens the email. | None |

- Feel copied from Shoebox: follows the finger 1:1 for 40 pt, then half speed; a tick when a line is crossed; springs back short of it; direction settles once per drag.
- One shared Undo bar, 10 seconds, as today.
- Swipe right is left alone (the system back swipe lives at that edge).

## Pull down names its target
The gesture is the confirmation, so it must say what it will do before it does it.
- As the pull starts, the bottom object shows the destination in words: "Put away in Money", "Archive", "Keep 2 weeks".
- Crossing the line locks it in (tick, the words firm up). Letting go short of the line does nothing.
- Reply-suggested email: pull down still means handled, and puts it away in its drawer.
- No drawer known: the pull reads "Choose a drawer" and releasing opens the drawer grid. Nothing is filed.
- Sender remembered for Trash: pull down still puts away; Trash stays behind the left swipe and its tap.
- Health mail and Ask Lovely rules are unchanged.

## The screen (owner picks, Nov 10, 2026; mockup Design/mockups/sprint8-moves.html)
- Each email is a full white screen (dark: near black), no card, no photo, no colored ground. Lots of white space.
- Top: sender line. Middle: one big fact (amount, day, time) with a short label. Then one Liquid Glass panel: subject, summary, drawer and tags, Open, and the Ask Lovely field with the blue up button inside it.
- Beside the dot: Archive (left) and ⋯ (right; Keep 2 weeks moves into ⋯).
- No main button by default. VoiceOver actions mirror the three moves; a Settings switch can show the button.

## The dot
- The logo's blue, a gel ball about 148 pt across, centered at the bottom, about half off screen. Never a perfect circle: an uneven wobble at rest.
- Grows and leans toward the thumb as the email is pulled toward it. Gulps the email and wobbles like gel as it settles. Tap it and it jiggles. No ripple rings, no color change.
- The next email rises out of it.

## Choosing a drawer
- When no drawer is known, letting go past the line springs a glass box up out of the dot: the email's sender, subject and summary on top for reference, then the most likely drawers (with a short reason), then the other drawers. One tap puts it away; Not now puts the email back.

## Safety (approved by the owner in chat, Nov 10, 2026)
- Pull down past the line makes the same ConfirmedAction the session's main button makes, in `Features/Session/SessionConfirm.swift`, only after the destination has been shown on screen during the pull. The 10-second Undo applies.
- Only filing (put away, archive, Keep 2 weeks). Never Trash, send, filters or rules by gesture.
- `scripts/privacy_guard.py` already limits ConfirmedAction to SessionConfirm.swift; the gesture goes through it, so the guard needs no new exception.

## Build order (Sonnet)
1. `SessionCardGesture` (pure state: direction, thresholds, resisted offset) with unit tests.
2. Wire flick up and swipe-left Trash first (no new Gmail path).
3. Pull down through SessionConfirm, with the destination label.
4. The bottom object and its animation, behind Reduce Motion.
5. UI audit job for the three moves.
