# 🌿 Flaunedex

Three worlds in one app, sharing a design language and one store. The first two also share a
single Gemini key; the third needs no network at all.

**Faune & Flore** is a personal Pokédex for European wildlife. Photograph a plant or animal in the
field, and Google **Gemini** identifies it and writes a readable French card (a *spécificité* + a
*fun fact*). Each find joins a growing, map-backed, filterable collection, and photographing a
species **anywhere** unlocks it across **every European country in its natural range**.

**Cuisine** is a recipe bank. Ask Gemini for a dish and get it back with a real photograph, its
ingredients, and step-by-step instructions, with every amount in grams, millilitres and degrees
Celsius. Then make it yours: add your own notes, delete what you do not want, rescale it for a
different table, or rewrite the whole thing as free text.

**Savoirs** is a deck of flash cards for anything worth keeping: vocabulary, quotes, dates, flags.
Cards live in folders and sub-folders, and each has a recto and a verso written like a short email,
with formatting, links and pictures. A revision session deals a random hand from any folder. Mark a
card *Maîtrisée* and it rests for a month, then longer each time you confirm it; retire it and it
leaves the rotation until you bring it back.

Native SwiftUI · SwiftData + iCloud · offline-first · French throughout.

---

## Repository layout

```
Flaunedex/
├─ Core/                     Swift package "FlaunedexCore": all the framework-independent
│  ├─ Sources/FlaunedexCore/   logic (Gemini schema + prompt, GBIF taxonomy/distribution,
│  │   ├─ Domain/              enrichment clients, the assembler, the recipe engine, and
│  │   ├─ Gemini/             the flash-card rules). Unit-tested on macOS.
│  │   ├─ GBIF/
│  │   ├─ Enrichment/
│  │   ├─ Cuisine/            Recipe units, prompt + schema, text format, dish photos
│  │   ├─ Savoirs/            Mastery rule, deck dealing, rich-text document + codec, folder tree
│  │   ├─ Media/              Picture shrinking (size cap, orientation, metadata stripping)
│  │   └─ Networking/
│  └─ Tests/FlaunedexCoreTests/  271 tests, run with `swift test` (no Xcode needed)
├─ App/                      The iOS app (SwiftUI, SwiftData, AVFoundation, MapKit, CloudKit)
│  ├─ FlaunedexApp.swift
│  ├─ Persistence/           SwiftData models (Species, Sighting, Recipe, KnowledgeFolder,
│  │                          KnowledgeCard, KnowledgeImage)
│  ├─ Services/              Camera, location, geocoding, keychain, scan queue, recipe and card stores
│  └─ Features/              The screens: Features/Cuisine/ for recipes, Features/Savoirs/ for cards
├─ project.yml               XcodeGen project definition
├─ App/Info.plist, App/Flaunedex.entitlements
└─ README.md
```

**Why the split?** Everything correctness-critical and bug-prone (the country-unlock rule, the
GBIF animal-group edge cases, the JSON schemas and parsers, the mastery calendar, the dealing rule,
the rich-text round trip) lives in `FlaunedexCore`, which compiles and **tests on macOS without
Xcode**. The Apple-framework code lives in `App/`, which needs Xcode.

---

## Prerequisites

- **A Mac with full Xcode** (App Store), not just the Command Line Tools. Needed to build the iOS app.
- **XcodeGen** to generate the `.xcodeproj`: `brew install xcodegen`
- **A paid Apple Developer account** ($99/yr), required because the app uses **CloudKit** (and for
  TestFlight). Enroll at <https://developer.apple.com/programs>.
- **A Google Gemini API key** (required for Faune & Flore and Cuisine; Savoirs needs none) from
  <https://aistudio.google.com/app/apikey>. Optional: an **IUCN Red List v4** token
  (<https://api.iucnredlist.org>) and a **Xeno-canto** key (<https://xeno-canto.org>) for richer
  conservation badges and bird songs. All keys are pasted into the app's **Réglages** screen and
  stored in the device Keychain. None are committed to the repo.

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

Debug builds accept a launch argument that fills every world with examples, so you can explore the
UI immediately:

```bash
xcrun simctl launch booted com.taddeocarpinelli.flaunedex -seedSampleData
```

That seeds four species and three recipes (with live Wikimedia images), and 22 knowledge cards in
nine folders. Among the cards, three are resting, one is retired, one is back for confirmation, and
three carry a picture. Each world is seeded only while it is empty, so relaunching never duplicates
anything.

Add `-previewSpeciesDetail` or `-previewRecipeDetail` to open a card directly, or
`-previewScreen <route>` to jump to any screen:

| World | Routes |
|---|---|
| Faune & Flore | `faune`, `flore`, `carte`, `journal`, `stats`, `decouvertes`, `reglages` |
| Cuisine | `recettes` (or `cuisine`), `demander` |
| Savoirs | `savoirs`, `dossier-savoir`, `reviser`, `session-savoirs`, `carte-savoir`, `editeur-savoir` |

The Savoirs routes accept `-previewFolder <nom>` to narrow them to one folder (for example
`-previewFolder Drapeaux`), and `session-savoirs` accepts `-previewVersoFirst`. Set these under
**Product → Scheme → Edit Scheme → Arguments** to use them from Xcode. They are compiled out of
Release builds.

In Xcode:
1. Select the **Flaunedex** target → **Signing & Capabilities** → pick your Team; Xcode provisions
   automatically. Confirm the **iCloud → CloudKit** capability is present with container
   `iCloud.com.taddeocarpinelli.flaunedex`. You can rename the container and bundle id to your own:
   change them in `project.yml`, `App/Info.plist`, and `App/Flaunedex.entitlements` together.
2. Run on the **Simulator** to click through the UI (simulate a location via **Features → Location**).
   The camera only works on a **real device**.
3. Launch on your iPhone, open **Réglages**, paste your Gemini key, then use **Capturer**.

> **iOS version:** the project targets **iOS 17** for broad compatibility. The plan documents the
> iOS 26 APIs (`MKReverseGeocodingRequest`, `BGContinuedProcessingTask`) you can adopt later. Each is
> already isolated behind a small abstraction (`ReverseGeocoder`, the scan queue).

---

## Putting it on your iPhone (TestFlight)

1. In App Store Connect, create the app record (matching the bundle id).
2. **Deploy the CloudKit schema to Production first** (CloudKit Dashboard → your container →
   *Deploy Schema Changes*). TestFlight/Release builds hit the **Production** environment; skipping
   this makes sync silently fail. The Savoirs models add three record types, listed in
   [DEPLOYMENT.md](DEPLOYMENT.md).
3. In Xcode: **Product → Archive → Distribute App → App Store Connect → Upload**.
4. In App Store Connect → TestFlight, add yourself to **Internal Testers** (no App Review needed).
   Install the **TestFlight** app on your iPhone with the same Apple ID.
5. **Rebuild roughly every 80 days**, because TestFlight builds expire at 90 (bump
   `CURRENT_PROJECT_VERSION` in `project.yml` each time). Set a calendar reminder.

`ITSAppUsesNonExemptEncryption` is already set to `NO` in `Info.plist`, so the build is testable
immediately.

---

## How identification works (one scan)

1. **Gemini** (`gemini-3.6-flash`, `thinking_level: low`, structured JSON) → French names, family,
   realm, animal group, *spécificité*, *fun fact*, season, toxicity note, and (when unsure)
   candidates for review. The capture is a JPEG, sent inline as base64.
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
3. **Photograph.** French Wikipedia is searched for the dish, English as a fallback, and the lead
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

## How a revision works (one session)

1. **Choose a folder and a number of cards.** A folder always includes everything below it, so
   *Langues* covers *Anglais* and *Italien*. Resting and retired cards do not count as available.
2. **Deal like a shuffled pack.** The cards dealt the fewest times go first. Among equals the choice
   is uniformly random, and the chosen hand is shuffled once more so its order says nothing. The
   effect: every card comes up once before any card comes up twice. With 100 cards and 20 per
   session, five sessions show all 100 exactly once.
3. **Turn the card.** The recto shows first. The *Commencer par le verso* switch reverses that for
   the session, which drills vocabulary in the other direction with the same cards. Tap to turn; a
   tap on a link opens the link instead.
4. **Judge it.**
   - **Maîtrisée**: the card rests for 30 days. Each time it comes back and is mastered again, the
     rest doubles (60, 120, 240), up to 365 days.
   - **Suivante**: the card stays in play. A card that had been mastered, and is not mastered again
     when it comes back, starts over exactly as if it had never been mastered.
   - **Retirer**: the card leaves every session until it is restored from its page. An *Annuler*
     button stays up for six seconds.
5. **When a folder runs dry**, the session is simply shorter, and the end screen says
   *Dossier maîtrisé ! Prochaine carte le 23 octobre*. *Réviser quand même* deals from the resting
   cards instead.

An example with dates. A card mastered on 23 September comes back on 23 October. Mastered again
that day, it rests 60 days, until 22 December. If on 22 December you tap *Suivante* instead, it is
an ordinary card again, and its next *Maîtrisée* gives 30 days, not 120.

A rest ends at midnight at the start of the announced day, counted in calendar days, so the date on
screen is exact even across a daylight-saving change. Mastering a card early (through *Réviser quand
même*) restarts its current rest without climbing to the next one.

---

## How a card is written and stored

- **The editor** wraps UIKit's text view, because SwiftUI's own editor only edits plain text on
  iOS 17 and 18. It offers headings, bullet lists and quotes; bold, italic, underline,
  strikethrough and six colours; links; and pictures from the library, the camera or the clipboard.
  Return continues a list, and Return on an empty bullet ends it.
- **Each side is saved as a small JSON document** (`RichDocument` in Core), not as HTML or RTF. It
  holds paragraphs with a style, runs of text with a format, and picture blocks that refer to a
  picture by its id. The format carries a version number, and anything unknown degrades instead of
  failing, so an older copy of the app can still open a card written by a newer one.
- **The conversion is tested, not trusted.** Turning a document into the text view's content and
  back is a pure function in Core. On 400 random documents it returns exactly the document it
  started from.
- **Pictures are shrunk before they are stored**: longest side at most 1600 pixels and never
  enlarged, turned upright, flattened onto white, re-encoded as JPEG, and stripped of every piece of
  metadata, GPS included. A detailed 1600 × 1200 photo takes about 0.9 MB. A picture that has not
  synced yet shows a placeholder instead of leaving a hole.
- **Links** accept web, mail and phone addresses. A bare `fr.wikipedia.org/…` gets `https://`
  added, and `javascript:` or file links are refused.

---

## Data credits & safety

Data from **GBIF** (CC BY), **Wikidata** (CC0), **Wikimedia Commons** (per-image CC/PD, attribution
shown on each card), **IUCN Red List** (non-commercial), and **Xeno-canto** (per-recording CC).
Identification is by Google Gemini and **can be wrong**: the app never gives edibility advice, and
toxicity notes always carry a caution. Contributing your sightings to iNaturalist (which feeds GBIF)
is planned for a future version.

---

## Status

- ✅ `FlaunedexCore`: **271 tests** (`cd Core && swift test`): 267 pass, and the 4 live endpoint
  checks below are skipped unless switched on. They include a real EXIF-GPS
  round trip, the natural-range unlock rules, the recipe text round trip, and both pipelines driven
  end to end over a scripted transport (so the wiring, the error statuses and the graceful
  degradations are exercised without an API key). For Savoirs they cover the mastery calendar
  across a daylight-saving change, the fairness of the deal (a chi-square test over 100,000 deals),
  the rich-text round trip, and the picture shrinker.
- ✅ Live endpoint checks, off by default so the suite works on a train:
  `FLAUNEDEX_LIVE=1 swift test --filter LiveEndpointTests`.
- ✅ iOS app: builds clean for the iOS 18.5 simulator, launches, and every screen has been
  verified running: Faune/Flore dex, species card, map, journal, stats, Découvertes, settings.
- ✅ All v1 features implemented: offline scan queue, animal subgroups, stats + achievements,
  new-species celebration, rarity badges, birdsong, nearby suggestions, nature journal, and the
  low-confidence review flow.
- ✅ Cuisine: recipe bank with search, your own tags, favourites and hand ordering; ask Gemini for a
  dish or a variation of one you have; real dish photographs with attribution; per-recipe notes;
  swipe-delete and drag-reorder of ingredients and steps; rescaling; and full free-text editing.
- ✅ Savoirs: folders and sub-folders with an emoji and a colour; recto/verso cards with rich text,
  links and pictures; revision sessions dealt from any folder; *Maîtrisée*, *Suivante* and
  *Retirer* with undo; and the growing rests. Verified running in the simulator, down to a photo
  picked from the library, stored at 1600 × 1200 with no GPS, and shown on its card.
- ✅ Verified live: Wikipedia/Commons image lookup, GBIF nearby suggestions, and batched Wikidata
  French-name resolution all exercised against the real APIs from the running app.
- ⏳ Not yet done: run on a **real iPhone** (the camera and CoreLocation can't be exercised in the
  simulator), and the account-holder steps in [DEPLOYMENT.md](DEPLOYMENT.md): Apple Developer
  enrolment, the iCloud container, **deploying the CloudKit schema to Production**, and TestFlight.
  iNaturalist sharing remains the planned v2.

### Known limitations

- The camera path (AVFoundation capture + GPS injection) compiles and its GPS logic is unit-tested,
  but it can only be exercised on a physical device. The same goes for the camera button in the
  card editor; the photo library and pasting work in the simulator.
- SwiftUI's `Map` has no built-in clustering; `SightingsMapView` is isolated so an `MKMapView`
  wrapper can replace it if pin counts grow.
- CloudKit sync needs the paid account and a Production schema deploy before TestFlight (see
  [DEPLOYMENT.md](DEPLOYMENT.md)). Until then the app runs local-only and says so in Réglages
  rather than failing.
- A card side is stored as one field. If the same side is edited on two devices before they sync,
  one version wins; the two edits are not merged.
