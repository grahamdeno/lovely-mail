# Reelmail

**Email, reeled.** A native iPhone app that turns your Gmail inbox into a calm, social-style feed:
a white header with the people waiting on you, a lens carousel (Today's brief, Needs you, Coming up,
People, Money, Catch up later), and a vertical reel of posts written on device by Apple Intelligence.

## Privacy stance

- **Read-only.** The only Google scope requested is `gmail.readonly`. There is no code that sends,
  drafts, deletes or changes mail, and CI fails if a send scope or endpoint shows up in `App/`.
- **On-device AI.** Summaries and reply drafts use Apple's Foundation Models framework on the
  iPhone. Email text is never sent to any server, including ours (there isn't one).
- **Never sends.** "Draft reply" offers **Copy** and **Open in Gmail** only. You press Send in Gmail.
- **No secrets in the repo.** The Google client ID comes from `Config/Local.xcconfig`, which is
  gitignored. OAuth tokens live in the Keychain, this device only. Email bodies are never logged.
- **Hide is local.** Hiding a message only affects the app. Changing Gmail would need `gmail.modify`,
  which is intentionally not requested.

## What's here

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. iOS 26, SwiftUI, bundle id `com.grahamdeno.reelmail`. |
| `App/Reelmail/Design` | Tokens (`RM`): palette, nested radii (outer = inner + padding), rounded-square avatars, the rolling tab bar. |
| `App/Reelmail/Features` | Home (header, lens carousel, reel), Open email, Draft reply sheet, Connection profile, DM-style thread, People, Search, New, Profile, **Summary Lab**. |
| `App/Reelmail/Summarizer` | `EmailSummarizer` protocol, `AppleIntelligenceSummarizer` (`@Generable PostSummary`), `FallbackSummarizer` (heuristics), reply drafters. |
| `App/Reelmail/Gmail` | Read-only `GmailService`: ASWebAuthenticationSession + PKCE, Keychain tokens, list/get `format=full`, plain-text parsing. |
| `App/Reelmail/Photos` | `PhotoProvider` with local placeholder gradients + SF Symbols. |
| `App/Reelmail/Model` | Models, `FeedStore`, lenses and chips, ~20 fake sample emails. |
| `App/ReelmailTests` | Fallback summarizer, radius math, tab bar, sample data, Gmail parsing/PKCE/scope tests. |
| `.github/workflows/build.yml` | Simulator build + unit tests on `macos-26`, unsigned. |
| `.github/workflows/testflight.yml` | Archive + upload to TestFlight (push to `testflight` branch, or manual). |

### Design tokens

White header `#F2F2F0`, graphite sheet `#15171A`, surface `#22252A`, hairline `#33373D`,
secondary text `#959BA3`, ink `#15171A`. Violet `#8B7CFF` (text on light `#7361E2`) means
**needs reply** and nothing else. No glow. Radii: button 8, card 16, sheet 24, active tab 12,
tab bar 18; avatars are rounded squares at 25% of their size. SF Pro throughout.

## Run it

```sh
brew install xcodegen
xcodegen generate
open Reelmail.xcodeproj
```

Without a Google client ID the app runs in **sample mode** with fake emails, which is all you need for
the design and the Summary Lab.

### Summary Lab (the on-device test)

Profile → **Summary Lab**. It shows whether Apple Intelligence is available, runs the summarizer over
the 20 sample emails (or text you paste), and shows each headline/blurb/category/needs-reply result
with its latency in ms, plus average, median and slowest. Switch Engine to compare Apple Intelligence
against the fallback. Requires an iPhone 15 Pro or newer with Apple Intelligence turned on; the
simulator and older phones fall back to the heuristic summarizer.

### Connecting Gmail

1. Create an **iOS** OAuth client in Google Cloud Console for bundle id `com.grahamdeno.reelmail`
   with the Gmail API enabled. While the consent screen is in Testing, your Gmail address must be a
   test user, and Google expires the sign-in after 7 days (reconnect in Profile).
2. Local builds: `cp Config/Local.xcconfig.example Config/Local.xcconfig` and paste the client ID.
3. TestFlight builds: put the same client ID in `Config/Release.xcconfig` (tracked; iOS client IDs are
   public by design). The workflow copies it into the build, refuses to upload if it is empty or
   malformed, and checks the archived app's Info.plist before upload.
4. Profile → Connect Gmail.

## What Graham needs to do

- [ ] App ID + App Store Connect app record for `com.grahamdeno.reelmail` (done for TestFlight, if the
      `testflight` workflow is green).
- [ ] Repo secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` for the TestFlight workflow.
- [ ] Create a Google **iOS** OAuth client for `com.grahamdeno.reelmail`; its ID goes in
      `Config/Release.xcconfig` (TestFlight) and optionally `Config/Local.xcconfig` (local builds).
- [ ] Test on an **iPhone 15 Pro or newer with Apple Intelligence on**, then run the Summary Lab.

## TestFlight

`testflight.yml` archives with automatic signing via the App Store Connect API key, numbers the build
`1000 + run number`, and uploads it. It runs on every push to the `testflight` branch (and manually once
it's on `main`). It never submits for review. Gmail must be configured (see above); a sample-mail demo
build is only possible as a manual run with `demo_build` checked.
