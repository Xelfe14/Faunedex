# 🌿 Flaunedex

Two things in one app, sharing a design language, a store and a single Gemini key.

**Faune & Flore** is a personal Pokédex for European wildlife. Photograph a plant or animal in the
field, and Google **Gemini** identifies it and writes a readable French card (a *spécificité* + a
*fun fact*). Each find joins a growing, map-backed, filterable collection, and photographing a
species **anywhere** unlocks it across **every European country in its natural range**.

**Cuisine** is a recipe bank. Ask Gemini for a dish and get it back with a real photograph, its
ingredients, and step-by-step instructions, with every amount in grams, millilitres and degrees
Celsius. Then make it yours: add your own notes, delete what you do not want, rescale it for a
different table, or rewrite the whole thing as free text.

Native SwiftUI · SwiftData + iCloud · offline-first · French throughout.

---

## Repository layout

```
Flaunedex/
├─ Core/                     Swift package "FlaunedexCore" — all the framework-independent
│  ├─ Sources/FlaunedexCore/   logic (Gemini schema + prompt, GBIF taxonomy/distribution,
│  │   ├─ Domain/              enrichment clients, the assembler, and the whole
│  │   ├─ Gemini/             recipe engine: units, schema, free-text round trip).
│  │   ├─ GBIF/               Unit-tested on macOS.
│  │   ├─ Enrichment/
│  │   ├─ Cuisine/            Recipe units, prompt + schema, text format, dish photos
│  │   ├─ Media/              EXIF GPS tagging, and the GPS-free copy sent to Gemini
│  │   └─ Networking/
│  └─ Tests/FlaunedexCoreTests/  199 tests, run with `swift test` (no Xcode needed)
├─ App/                      The iOS app (SwiftUI, SwiftData, AVFoundation, MapKit, CloudKit)
│  ├─ FlaunedexApp.swift
│  ├─ Persistence/           SwiftData models (Species, Sighting, Recipe)
│  ├─ Services/              Camera, location, geocoding, keychain, scan queue, recipe store
│  └─ Features/              The screens, with Features/Cuisine/ for the recipe side
├─ project.yml               XcodeGen project definition
├─ App/Info.plist, App/Flaunedex.entitlements, App/PrivacyInfo.xcprivacy
├─ .github/workflows/ci.yml  Core tests + app builds on Xcode 26, on every push
└─ README.md
```

**Why the split?** Everything correctness-critical and bug-prone (the country-unlock rule, the
GBIF animal-group edge cases, the JSON schemas and parsers) lives in `FlaunedexCore`, which compiles
and **tests on macOS without Xcode**. The Apple-framework code lives in `App/`, which needs Xcode.

---

## Prerequisites

- **A Mac with full Xcode 26 or later** — not just the Command Line Tools. Needed to build the iOS
  app, and App Store Connect has refused uploads built with older Xcode versions since April 2026.
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

That seeds four species and three recipes, all with live Wikimedia images.

Add `-previewSpeciesDetail` or `-previewRecipeDetail` to open a card directly, or
`-previewScreen <faune|flore|carte|journal|stats|decouvertes|reglages|recettes|demander>`
to jump to any screen. Set these under **Product → Scheme → Edit Scheme → Arguments** to
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
   candidates for review. What is sent, inline as base64, is a copy of the capture: a JPEG at most
   1600 px on its long edge, turned upright, and stripped of all metadata, so the GPS stays on the
   phone.
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

## How a recipe works (one ask)

1. **Gemini** (same model, same key) returns a structured recipe: title, servings, times, ingredients,
   numbered steps, a chef's tip, allergens, and tags.
2. **Units are metric by construction.** The `unit` field in the response schema is an `enum`
   containing only g, kg, ml, cl, l and the French spoons, so a cup or an ounce is not a discouraged
   answer, it is an invalid one the API will not emit. Anything that still slips through in prose
   (a Fahrenheit oven temperature, a pasted "2 cups") is converted before it is ever stored.
3. **Photograph** — French Wikipedia is searched for the dish, English as a fallback, and the lead
   image is taken with its Commons licence and credited on the card. It is a real photograph of the
   real dish, not an image a model invented, and it is cached on disk so the recipe still shows it
   in a kitchen with no signal.
4. **Then it is yours.** Add your own notes, delete ingredients or steps, drag them into a different
   order, rescale for a different number of people, or rewrite the whole recipe as free text. The
   text round trips: what you type parses straight back into the structured recipe, and the card
   stops crediting the model.

Rescaling rounds the way a kitchen does: counted things (apples, pastry sheets) become whole
numbers, spoons round to halves, and weights and volumes get cookbook rounding. Cooking times are
never scaled, because doubling a batch does not double its baking time.

---

## Data credits & safety

Data from **GBIF** (CC BY), **Wikidata** (CC0), **Wikimedia Commons** (per-image CC/PD — attribution
shown on each card), **IUCN Red List** (non-commercial), and **Xeno-canto** (per-recording CC).
Identification is by Google Gemini and **can be wrong** — the app never gives edibility advice, and
toxicity notes always carry a caution. Contributing your sightings to iNaturalist (which feeds GBIF)
is planned for a future version.

---

## Status

- ✅ `FlaunedexCore` — **199 passing tests** (`cd Core && swift test`), including a real EXIF-GPS
  round-trip, the GPS-free upload copy, the natural-range unlock rules, the recipe text round trip,
  and both pipelines driven end to end over a scripted transport (so the wiring, the error statuses
  and the graceful degradations are exercised without an API key).
- ✅ Builds with **Xcode 26** (the iOS 26 SDK App Store Connect requires) on every push, in GitHub
  Actions: the Core tests, a Release build for iPhone (what an archive compiles) and a Debug build
  for the simulator, with no compiler warnings. The Release bundle is checked for its privacy
  manifest, SDK, device family and background modes.
- ✅ Live endpoint checks, off by default so the suite works on a train:
  `FLAUNEDEX_LIVE=1 swift test --filter LiveEndpointTests`.
- ✅ iOS app — launches, and every screen has been verified running in the iOS 18.5 simulator:
  Faune/Flore dex, species card, map, journal, stats, Découvertes, settings. Nobody has looked at
  it yet as built with the iOS 26 SDK, which restyles tab bars, navigation bars and sheets by itself.
- ✅ All v1 features implemented: offline scan queue, animal subgroups, stats + achievements,
  new-species celebration, rarity badges, birdsong, nearby suggestions, nature journal, and the
  low-confidence review flow.
- ✅ Cuisine: recipe bank with search, your own tags, favourites and hand ordering; ask Gemini for a
  dish or a variation of one you have; real dish photographs with attribution; per-recipe notes;
  swipe-delete and drag-reorder of ingredients and steps; rescaling; and full free-text editing.
- ✅ Verified live: Wikipedia/Commons image lookup, GBIF nearby suggestions, and batched Wikidata
  French-name resolution all exercised against the real APIs from the running app.
- ⏳ Not yet done: run on a **real iPhone** (the camera and CoreLocation can't be exercised in the
  simulator), a first **real Gemini call** (identification and recipes are tested up to the wire,
  never against the live API), and the account-holder steps in [DEPLOYMENT.md](DEPLOYMENT.md) —
  Xcode 26 on the Mac, Apple Developer enrolment, the iCloud container, **deploying the CloudKit
  schema to Production**, and TestFlight. iNaturalist sharing remains the planned v2.

### Known limitations

- The camera path (AVFoundation capture + GPS injection) compiles and its GPS logic is unit-tested,
  but it can only be exercised on a physical device.
- SwiftUI's `Map` has no built-in clustering; `SightingsMapView` is isolated so an `MKMapView`
  wrapper can replace it if pin counts grow.
- CloudKit sync needs the paid account and a Production schema deploy before TestFlight — see
  [DEPLOYMENT.md](DEPLOYMENT.md). Until then the app runs local-only and says so in Réglages
  rather than failing.
