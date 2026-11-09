# Lovely brand

**Name:** Lovely (home screen). **App Store name:** Lovely Mail. **Bundle ID stays** `com.grahamdeno.reelmail`
(the Google OAuth client and App Store Connect record are tied to it; users never see it).

**Subtitle (App Store and under the logo):** Get through your email, calmly. (30 characters; chosen Nov 9, 2026. Replaces "Mail from your people.")

**Positioning (keep for all marketing, the website and videos; small tweaks are fine):**
> Lovely turns your Gmail into a short list of next steps, walks you through each decision one at a time, and files everything neatly behind you.

**What it is:** not an inbox but a workflow. Gmail is the filing cabinet; Lovely is the desk where you deal with mail. Competitors sell "AI handles your inbox for you"; Lovely helps you get through it yourself, one decision at a time, and finish. Keep "Gmail" out of the subtitle (trademark); use it descriptively in the description and keywords ("works with Gmail").

**Intent:** "lovely to hear from you," as you would say about a letter from a friend. The airmail palette keeps it about correspondence, not romance: no pink or red as a main color.

## Palette: Airmail

| Token (`CalmStyle`) | Name | Hex | Use |
|---|---|---|---|
| `background` | Letter paper | `#FBF8F4` | App background, icon background |
| `ink` | Ink | `#25222A` | Text |
| `secondary` | Muted | `#6D6870` | Secondary text (5.1:1 on paper) |
| `blue` | Airmail blue | `#2E58C8` | Everything you can tap (5.9:1 on paper) |
| `rose` | Postmark rose | `#D2546E` | "Waiting on you" graphics only: avatar ring, icon dot |
| `roseInk` | Postmark rose, text | `#B8405A` | "Waiting on you" labels (5.1:1 on paper) |
| (derived) | Blue wash | blue at 8% | Avatar tiles, quiet buttons |
| `divider` | | `#ECE6E2` | Row dividers |
| `bubble` | | `#EFEBE8` | Incoming message bubbles |

Dark icon variant: background `#1E1B22`, hand `#86A2F0`, dot `#E77A91`.

## Rules
1. Rose means one thing: someone is waiting on you. Nothing else is rose.
2. Blue is everything you can tap.
3. The italic wordmark ("lovely", system serif italic) appears at the top of Home only. The rest of the app uses the system font.
4. The app stays light-only for now.

## Icon (Liquid Glass)
- `App/Reelmail/AppIcon.icon` is an Icon Composer bundle (iOS 26 Liquid Glass): letter-paper fill, two glass layers (the handwritten l, written in one stroke, in blue; the dot where the pen lifts, in rose), specular highlights, neutral shadow. Dark and tinted appearances are defined in `icon.json`; clear mode is derived by the system.
- Layers are white-on-transparent 1024 PNGs in `AppIcon.icon/Assets/`; color comes from the layer fill so the system can recolor them for dark and tinted modes.
- Masters: `icon-layer-l.svg`, `icon-layer-dot.svg` (layer art), `icon-flat.svg` / `icon-flat-1024.png` (flat reference for the App Store listing, website and social).
- To adjust glass effects, open `AppIcon.icon` in Icon Composer (ships with Xcode 26) on a Mac. Not required to build.
