# Health Insights (iOS)

A private, on-device iOS app that turns **Apple Health, Oura and Withings** data
into insights that aren't directly measured — **heart health**, **cardiovascular
(heart-attack/stroke) risk**, and **blood pressure** — using *validated clinical
models* rather than a black box, and Apple's **on-device Foundation model** to
summarise it in plain language. Extensible by design so new devices and insights
plug in cleanly.

> ℹ️ This is the **Foundation MVP**: Apple Health is live end-to-end with one
> fully-wired validated insight (cardiovascular risk) plus a heart-health score
> and blood-pressure logging. Oura/Withings are scaffolded through the same
> extension point and activate once the OAuth backend is configured.

## What's here

```
HealthInsights.xcodeproj    # open this in Xcode 16+
project.yml                 # XcodeGen spec (regenerate the project if needed)
Support/                    # Info.plist + HealthKit entitlements
InsightKit/                 # pure-Swift core (clinical math) + unit tests
HealthInsights/             # SwiftUI app (App, DesignSystem, Core, Features)
backend/                    # optional OAuth helper (only for a Withings redirect quirk)
docs/ARCHITECTURE.md        # how it all fits together
```

## Run it

**Requirements:** a Mac with **Xcode 16+**, and an iPhone (HealthKit needs a real
device, or a simulator with seeded Health data). Deployment target **iOS 18**;
the on-device summary uses Apple Intelligence on **iOS 26+** and falls back to a
template elsewhere.

```bash
open HealthInsights.xcodeproj
# Select the HealthInsights scheme → your device → Run.
```

If the committed project ever fails to open, regenerate it:

```bash
brew install xcodegen
xcodegen generate
```

## Test the clinical core (no Xcode required)

```bash
cd InsightKit
swift test
```

These tests pin the SCORE2 and ASCVD implementations to the worked examples in
their source papers, so a transcription error breaks the build.

## Enabling Oura & Withings

Do it **inside the app** — no backend, no code. Open **Settings ▸ Integrations ▸
Oura** (or Withings) and follow the built-in, plain-language guide: you create a
free developer app on the provider's site, copy the redirect address the app
shows you, paste your Client ID + Secret, and tap **Save & Connect**. Credentials
are stored in the iPhone Keychain and the whole OAuth flow runs on-device. The
same setup is also offered as an optional, skippable step during onboarding.

The [`backend/`](backend/README.md) folder is **optional** and only relevant if
Withings rejects the custom-scheme redirect (see its README).

## Medical disclaimer

For information and self-tracking only — **not a medical device**, not a
diagnosis, and not a substitute for professional medical advice. Consult a
clinician for health decisions and seek emergency care for acute symptoms.
