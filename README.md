# 🌿 Flaunedex

A personal **Pokédex for European flora & fauna**. Photograph a plant or animal in the field, and
Google **Gemini** identifies it and writes a readable French card (a *spécificité* + a *fun fact*).
Each find joins a growing, map-backed, filterable collection — and photographing a species **anywhere**
unlocks it across **every European country in its natural range**.

Native SwiftUI · SwiftData + iCloud · offline-first.

---

## Repository layout

```
Flaunedex/
├─ Core/                     Swift package "FlaunedexCore" — all the framework-independent
│  ├─ Sources/FlaunedexCore/   logic (Gemini schema + prompt, GBIF taxonomy/distribution,
│  │   ├─ Domain/              enrichment clients, the assembler). Unit-tested on macOS.
│  │   ├─ Gemini/
│  │   ├─ GBIF/
│  │   ├─ Enrichment/
│  │   └─ Networking/
│  └─ Tests/FlaunedexCoreTests/  57 tests, run with `swift test` (no Xcode needed)
├─ App/                      The iOS app (SwiftUI, SwiftData, AVFoundation, MapKit, CloudKit)
│  ├─ FlaunedexApp.swift
│  ├─ Persistence/           SwiftData models (Species, Sighting)
│  ├─ Services/              Camera, location, geocoding, keychain, scan queue
│  └─ Features/              The screens (Dex, Capture, Detail, Map, Journal, Stats, Settings)
├─ project.yml               XcodeGen project definition
├─ App/Info.plist, App/Flaunedex.entitlements
└─ README.md
```

**Why the split?** Everything correctness-critical and bug-prone (the country-unlock rule, the
GBIF animal-group edge cases, the JSON schemas and parsers) lives in `FlaunedexCore`, which compiles
and **tests on macOS without Xcode**. The Apple-framework code lives in `App/`, which needs Xcode.

---

## Prerequisites

- **A Mac with full Xcode** (App Store) — not just the Command Line Tools. Needed to build the iOS app.
- **XcodeGen** to generate the `.xcodeproj`: `brew install xcodegen`
- **A paid Apple Developer account** ($99/yr) — required because the app uses **CloudKit** (and for
  TestFlight). Enroll at <https://developer.apple.com/programs>.
- **A Google Gemini API key** (required) from <https://aistudio.google.com/app/apikey>.
  Optional: an **IUCN Red List v4** token (<https://api.iucnredlist.org>) and a **Xeno-canto** key
  (<https://xeno-canto.org>) for richer conservation badges and bird songs. All keys are pasted into
  the app's **Réglages** screen and stored in the device Keychain — none are committed to the repo.

---

## Build & run

```bash
# 1. Run the core logic tests (works with only Command Line Tools installed)
cd Core && swift test

# 2. Generate the Xcode project
cd .. && xcodegen generate

# 3. Open it
open Flaunedex.xcodeproj
```

### Try it without an API key

Debug builds accept launch arguments that seed four real species (with live
Wikimedia images) so you can explore the UI immediately:

```bash
xcrun simctl launch booted com.taddeocarpinelli.flaunedex -seedSampleData
```

Add `-previewSpeciesDetail` to open a species card directly, or
`-previewScreen <faune|flore|carte|journal|stats|decouvertes|reglages>` to jump
to any screen. Set these under **Product → Scheme → Edit Scheme → Arguments** to
use them from Xcode. They are compiled out of Release builds.

In Xcode:
1. Select the **Flaunedex** target → **Signing & Capabilities** → pick your Team; Xcode provisions
   automatically. Confirm the **iCloud → CloudKit** capability is present with container
   `iCloud.com.taddeocarpinelli.flaunedex` (rename the container + bundle id to your own if you like —
   change them in `project.yml`, `App/Info.plist`, and `App/Flaunedex.entitlements` together).
2. Run on the **Simulator** to click through the UI (simulate a location via **Features → Location**).
   The camera only works on a **real device**.
3. Launch on your iPhone, open **Réglages**, paste your Gemini key, then use **Capturer**.

> **iOS version:** the project targets **iOS 17** for broad compatibility. The plan documents the
> iOS 26 APIs (`MKReverseGeocodingRequest`, `BGContinuedProcessingTask`) you can adopt later — each is
> already isolated behind a small abstraction (`ReverseGeocoder`, the scan queue).

---

## Putting it on your iPhone (TestFlight)

1. In App Store Connect, create the app record (matching the bundle id).
2. **Deploy the CloudKit schema to Production first** (CloudKit Dashboard → your container →
   *Deploy Schema Changes*). TestFlight/Release builds hit the **Production** environment; skipping
   this makes sync silently fail.
3. In Xcode: **Product → Archive → Distribute App → App Store Connect → Upload**.
4. In App Store Connect → TestFlight, add yourself to **Internal Testers** (no App Review needed).
   Install the **TestFlight** app on your iPhone with the same Apple ID.
5. **Rebuild roughly every 80 days** — TestFlight builds expire at 90 (bump `CURRENT_PROJECT_VERSION`
   in `project.yml` each time). Set a calendar reminder.

`ITSAppUsesNonExemptEncryption` is already set to `NO` in `Info.plist`, so the build is testable
immediately.

---

## How identification works (one scan)

1. **Gemini** (`gemini-3.6-flash`, `thinking_level: low`, structured JSON) → French names, family,
   realm, animal group, *spécificité*, *fun fact*, season, toxicity note, and — when unsure —
   candidates for review. iPhone HEIC photos are sent directly.
2. **GBIF** `species/match` → canonical taxon, family, kingdom → realm + animal sub-group.
3. **GBIF** occurrence facet + distributions → the **natural-range** country set (native + established,
   introduced-only countries tagged separately).
4. **Enrichment** (best-effort): Wikipedia (reference image **+ the article link**), Commons (license),
   Wikidata (FR/EN names + IUCN fallback), IUCN v4 (status), Xeno-canto (bird song).
5. Assembled into a `Species` and linked to your `Sighting`. New species → a "Nouvelle espèce !"
   celebration.

Offline, the capture is saved with its GPS immediately and the whole pipeline runs later when the
network returns (`NWPathMonitor`-driven queue).

---

## Data credits & safety

Data from **GBIF** (CC BY), **Wikidata** (CC0), **Wikimedia Commons** (per-image CC/PD — attribution
shown on each card), **IUCN Red List** (non-commercial), and **Xeno-canto** (per-recording CC).
Identification is by Google Gemini and **can be wrong** — the app never gives edibility advice, and
toxicity notes always carry a caution. Contributing your sightings to iNaturalist (which feeds GBIF)
is planned for a future version.

---

## Status

- ✅ `FlaunedexCore` — **86 passing tests** (`cd Core && swift test`), including a real EXIF-GPS
  round-trip and the natural-range unlock rules.
- ✅ iOS app — builds clean for the iOS 18.5 simulator, launches, and every screen has been
  verified running: Faune/Flore dex, species card, map, journal, stats, Découvertes, settings.
- ✅ All v1 features implemented: offline scan queue, animal subgroups, stats + achievements,
  new-species celebration, rarity badges, birdsong, nearby suggestions, nature journal, and the
  low-confidence review flow.
- ✅ Verified live: Wikipedia/Commons image lookup, GBIF nearby suggestions, and batched Wikidata
  French-name resolution all exercised against the real APIs from the running app.
- ⏳ Not yet done: run on a **real iPhone** (the camera and CoreLocation can't be exercised in the
  simulator), and the account-holder steps in [DEPLOYMENT.md](DEPLOYMENT.md) — Apple Developer
  enrolment, the iCloud container, **deploying the CloudKit schema to Production**, and TestFlight.
  iNaturalist sharing remains the planned v2.

### Known limitations

- The camera path (AVFoundation capture + GPS injection) compiles and its GPS logic is unit-tested,
  but it can only be exercised on a physical device.
- SwiftUI's `Map` has no built-in clustering; `SightingsMapView` is isolated so an `MKMapView`
  wrapper can replace it if pin counts grow.
- CloudKit sync needs the paid account and a Production schema deploy before TestFlight — see
  [DEPLOYMENT.md](DEPLOYMENT.md). Until then the app runs local-only and says so in Réglages
  rather than failing.
