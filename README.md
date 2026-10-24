# 🌿 Flaunedex

Three apps in one, sharing a design language, a store and a single Gemini key. A bar across the top
of every screen switches between them in one tap, each in its own colour (green, paprika, blue), with
Réglages behind the gear at its end. Each app has its own tab bar, and stays as it was left when you
switch away and back.

**Faune & Flore** is a personal Pokédex for European wildlife. Photograph a plant or animal in the
field, and Google **Gemini** identifies it and writes a readable French card (a *spécificité* + a
*fun fact*). Each find joins a growing, map-backed, filterable collection, and photographing a
species **anywhere** unlocks it across **every European country in its natural range**.

**Cuisine** is a recipe bank. Ask Gemini for a dish and get it back with a real photograph, its
ingredients, and step-by-step instructions, with every amount in grams, millilitres and degrees
Celsius. Then make it yours: add your own notes, delete what you do not want, rescale it for a
different table, or rewrite the whole thing as free text.

**Saisons**, inside Cuisine, is the year as a fresque: every fruit and vegetable ADEME tracks, twelve
months across, coloured by where it comes from each month seen from Paris (France, Southern Europe,
or far away). Every recipe shows its carbon footprint, flags the ingredients that are out of season,
and can ask Gemini for a lower-impact version. Asking for a recipe cooks with the season by default.

**Savoirs** is a deck of knowledge cards. Ask Gemini about anything ("pourquoi le ciel est bleu", "la
bataille de Marignan", "sérendipité") and get a card back: the sentence to remember, a short
explanation, the points to retain, a review question with its answer, and a picture and link from
Wikipedia. A word always comes with its definition and its etymology. Or write the card yourself.
Cards are shelved in categories you name, decorate and order yourself, and come back as flashcards on
a spaced-repetition schedule.

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
│  │   ├─ Cuisine/            Recipe units, prompt + schema, text format, dish photos,
│  │   │   ├─ Saisons/          the seasonal calendar (generated from ADEME data)
│  │   │   └─ Impact/           ingredient matching and recipe carbon footprints
│  │   ├─ Savoirs/            Knowledge card schema + prompt, parser, review scheduler
│  │   ├─ Media/              EXIF GPS tagging, and the GPS-free copy sent to Gemini
│  │   └─ Networking/
│  └─ Tests/FlaunedexCoreTests/  249 tests, run with `swift test` (no Xcode needed)
├─ App/                      The iOS app (SwiftUI, SwiftData, AVFoundation, MapKit, CloudKit)
│  ├─ FlaunedexApp.swift
│  ├─ Persistence/           SwiftData models (Species, Sighting, Recipe, KnowledgeCard)
│  ├─ Services/              Camera, location, geocoding, keychain, scan queue, recipe and card stores
│  └─ Features/              The screens: home and tab bars, then Features/Cuisine/ and Features/Savoirs/
├─ project.yml               XcodeGen project definition
├─ Config/Signing.xcconfig   Reads your Team ID from Config/Team.xcconfig (not committed)
├─ update.sh                 Pull, keep the signing team, regenerate: the one command to update
├─ App/Info.plist, App/Flaunedex.entitlements, App/PrivacyInfo.xcprivacy
├─ Tools/food-data/          Regenerates the seasonal and footprint tables from ADEME's datasets
├─ .github/workflows/ci.yml  Core tests + app builds on Xcode 26, on every push
└─ README.md
```

**Why the split?** Everything correctness-critical and bug-prone (the country-unlock rule, the
GBIF animal-group edge cases, the JSON schemas and parsers) lives in `FlaunedexCore`, which compiles
and **tests on macOS without Xcode**. The Apple-framework code lives in `App/`, which needs Xcode.

---

## Prerequisites

- **A Mac with full Xcode** — not just the Command Line Tools. Any version that supports your
  iPhone's iOS works for installing from Xcode; only App Store Connect uploads (TestFlight) need
  Xcode 26 or later.
- **XcodeGen** to generate the `.xcodeproj`: `brew install xcodegen`
- **A paid Apple Developer account** ($99/yr) — for iCloud backup and year-long installs (a free
  Apple ID works too, with 7-day installs and no iCloud). Enrol on the web at
  <https://developer.apple.com/account>.
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

That seeds four species, three recipes and four knowledge cards, with live Wikimedia images.

Add `-previewSpeciesDetail` or `-previewRecipeDetail` to open a card directly, or `-previewScreen`
with one of `nature cuisine savoirs reviser pastille` (the whole app, switcher included) or `faune
flore carte sans-position journal stats decouvertes reglages demander saisons produit impact fiches
fiche apprendre rubriques nouvelle-rubrique` (one screen) to jump to it. Set these under **Product → Scheme → Edit Scheme → Arguments** to
use them from Xcode. They are compiled out of Release builds.

In Xcode:
1. Select the **Flaunedex** target → **Signing & Capabilities** → pick your Team; Xcode provisions
   automatically. `./update.sh` then saves that team to `Config/Team.xcconfig`, so regenerating the
   project never loses it. Confirm the **iCloud → CloudKit** capability is present with container
   `iCloud.com.taddeocarpinelli.flaunedex` (rename the container + bundle id to your own if you like —
   change them in `project.yml`, `App/Info.plist`, and `App/Flaunedex.entitlements` together).
2. Run on the **Simulator** to click through the UI (simulate a location via **Features → Location**).
   The camera only works on a **real device**.
3. Launch on your iPhone, tap the gear at the top right (**Réglages**), paste your Gemini key, then
   use **Capturer** in Faune & Flore.

> **iOS version:** the project targets **iOS 17** for broad compatibility. The plan documents the
> iOS 26 APIs (`MKReverseGeocodingRequest`, `BGContinuedProcessingTask`) you can adopt later — each is
> already isolated behind a small abstraction (`ReverseGeocoder`, the scan queue).

---

## Putting it on your iPhone

The app is for one person on one phone (an iPhone XS on iOS 18), so it is installed straight from
Xcode: plug the phone in, turn on Developer Mode, press Run. With the paid account an install lasts a
year and iCloud backs the data up. Step by step, including the first real scan and recipe request,
in [DEPLOYMENT.md](DEPLOYMENT.md). TestFlight is described there too, as an option.

To install a newer version later: `./update.sh` in the repository, then Run again in Xcode with the
iPhone selected. Reinstalling over the app keeps everything it holds.

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

The shutter never waits. The GPS warms up while the camera is open and the photo takes the latest
fix; if there is none yet, the photo is saved at once and the position is attached when the GPS finds
it. The app then goes back to the tab you came from, and a pill above the tab bar follows the
identification to its result: open the species, choose between candidates, or retry. A photo that
still has no position is counted above the map, with a picker to place it by hand.

Offline, the capture is saved immediately and the whole pipeline runs later when the network returns
(`NWPathMonitor`-driven queue).

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

## How a knowledge card works (one ask)

1. **Gemini** (same model, same key) returns a structured card: title, one of your categories, the one
   sentence to remember (for a word, its definition), the etymology, an explanation in short
   paragraphs, three to five points to retain, a review question and its answer, an optional
   anecdote, and the title of the matching French Wikipedia article. The etymology is required when
   the subject is a word or an expression to define (a single word, "définition de…", "que veut
   dire…", a quoted expression), and given for other subjects when it sheds light on the meaning. The prompt forbids invented dates, figures and quotations, and asks for uncertainty to be
   stated rather than settled. Two depths: *l'essentiel* (about 120 words) or *approfondi* (about 350).
2. **Picture and link** come from that Wikipedia article, through the same lookup as dish photos, with
   the Commons licence credited. The article is the card's "en savoir plus", never its claimed source.
3. **Then it is yours**: rewrite any field, add notes, star it, move it to another category from its
   chip, or ask Gemini to amend it ("plus simple", "ajoute l'étymologie"). A card edited by hand stops
   crediting the model.
4. **Categories are yours too.** A new collection starts with eleven (Sciences, Histoire…); rename
   them, change their icon, reorder them, delete them (their cards move to Divers) or add your own,
   from **Gérer les rubriques** under the cards or from any category picker. Gemini is offered your
   categories by name, as a closed list, so a card always lands on one of your shelves. Cards point to
   a category by a stable key, so renaming one moves nothing.
5. **Review** is a Leitner schedule: *Je sais* moves a card to the next box (1, 3, 7, 14, 30, 60, then
   120 days), *Facile* skips one, *À revoir* sends it back to the start and brings it back at the end
   of the same session. Due dates fall at the start of a day, so a card reviewed at 23:00 is due the
   morning it is scheduled for. Free practice runs through every card without touching the schedule.

---

## Seasons and carbon footprint

1. **The calendar is ADEME's.** Impact CO2's 76 fruits and vegetables give the months each is
   harvested in France and its footprint in kg CO₂e per kg (Agribalyse 3.2). On top of that, curated
   by hand and shown as indicative: when Spain, Italy, Portugal or Greece supply each item, which items
   only reach Paris from far away, and where they come from. Each month of each item is French,
   Southern European, a far import, or out of season, in that order of preference.
2. **A recipe's footprint is computed from its ingredient list.** Each line is matched to a known food
   by whole words, longest name first, so "pommes de terre" is a potato and "lait de coco" is not milk.
   Fresh produce uses the calendar's figure; everything else (meat, dairy, pasta, oil, condiments) uses
   Agribalyse 3.2, 154 foods in all. Amounts are already metric; counted things use a typical piece
   weight. What has no data, or no knowable weight, is listed as not evaluated rather than guessed.
3. **It is put into perspective** against ADEME's reference meals (vegan 0.54, vegetarian 0.85,
   chicken 1.46, beef 4.97 kg CO₂e per meal) and a petrol car's kilometre (0.142 kg).
4. **Gemini cooks with the season**: a recipe request carries this month's French and Southern
   European produce, and the "lower-impact version" request names the heaviest ingredients so the
   model knows what to replace. That version is saved as a new recipe, beside the original.

The tables are generated by `python3 Tools/food-data/build_food_data.py` from the live datasets; it
fails if a curated entry points at something the datasets no longer contain.

---

## Data credits & safety

Data from **GBIF** (CC BY), **Wikidata** (CC0), **Wikimedia Commons** (per-image CC/PD — attribution
shown on each card), **IUCN Red List** (non-commercial), **Xeno-canto** (per-recording CC), and
**ADEME** — Impact CO2 and Agribalyse 3.2 — for seasons and carbon footprints (Licence Ouverte 2.0).
Identification, recipes and knowledge cards are by Google Gemini and **can be wrong** — the app never gives edibility advice, and
toxicity notes always carry a caution. Contributing your sightings to iNaturalist (which feeds GBIF)
is planned for a future version.

---

## Status

- ✅ `FlaunedexCore` — **249 passing tests** (`cd Core && swift test`), including a real EXIF-GPS
  round-trip, the GPS-free upload copy, the natural-range unlock rules, the recipe text round trip,
  the season statuses and ingredient footprints, the knowledge card parser and the review schedule,
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
- ✅ Saisons: the seasonal fresque with month, shelf and name filters; a card per fruit and vegetable
  with its season, footprint and the recipes that use it; season pictograms and a carbon footprint on
  every recipe; seasonal cooking by default; and lower-impact versions. Seen running in the iOS 26
  simulator through CI's screenshots (an artifact on every run); not yet on the iPhone.
- ✅ Three apps in one: the coloured app switcher on every screen, the three tab bars, and Savoirs (cards from Gemini or by
  hand, themes, search, favourites, editing, Gemini amendments, flashcard review with a due-count
  badge). Built on Xcode 16.4 and 26 and seen in CI's screenshots; not yet on the iPhone.
- ✅ Verified live: Wikipedia/Commons image lookup, GBIF nearby suggestions, and batched Wikidata
  French-name resolution all exercised against the real APIs from the running app.
- ⏳ Not yet done: run on a **real iPhone** (the camera and CoreLocation can't be exercised in the
  simulator), a first **real Gemini call** (identification and recipes are tested up to the wire,
  never against the live API), the Saisons and Savoirs screens on the iPhone itself, and the account-holder steps in
  [DEPLOYMENT.md](DEPLOYMENT.md) — Apple Developer enrolment, signing, Developer Mode and the install
  from Xcode. iNaturalist sharing remains the planned v2.

### Known limitations

- The camera path (AVFoundation capture + GPS injection) compiles and its GPS logic is unit-tested,
  but it can only be exercised on a physical device.
- SwiftUI's `Map` has no built-in clustering; `SightingsMapView` is isolated so an `MKMapView`
  wrapper can replace it if pin counts grow.
- CloudKit sync needs the paid account (and, only for TestFlight, a Production schema deploy) — see
  [DEPLOYMENT.md](DEPLOYMENT.md). Without it the app runs local-only and says so in Réglages
  rather than failing.
- Southern Europe months are curated by hand and indicative; only the French calendar is ADEME's.
  Agribalyse has no figure for some common ingredients (champignons de Paris, câpres), which recipes
  list as not evaluated. Home cooking energy is not counted.
