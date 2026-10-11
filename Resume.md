# Flaunedex: Project Resume

> Paste-me-first context file for future conversations. Updated 2026-09-29. It reflects master at
> `4488a11` **plus the uncommitted Savoirs work** built on 2026-09-24 (see §11). When something
> here conflicts with the code, the code wins.

---

## 1. What the project is

**Flaunedex** is a personal, French-language iOS app for one user (Taddeo), not an App Store
product. It holds **three worlds** that share one SwiftData store and one design language; each
world's "Plus" tab switches to the others.

- **Faune & Flore**: a **Pokédex for real European flora and fauna**. The user photographs a plant,
  animal, bird, or insect *from within the app*; the photo goes to **Google Gemini**, which
  identifies the species and writes a readable French card (a *spécificité* paragraph + a *fun
  fact* paragraph, modeled on a Gemini output the user liked). Each identified species becomes a
  numbered card ("N° 004") in a growing, filterable, map-backed personal collection.
- **Cuisine** (added 2026-09-03): a recipe bank. Ask Gemini for a dish, get it back with a real
  Wikipedia photograph, metric amounts and steps, then take it over: notes, edits, rescaling,
  free-text rewrite. See §6.
- **Savoirs** (built 2026-09-24): flash cards in folders and sub-folders. Each card has a recto and
  a verso written in a rich-text editor (formatting, links, pictures). Revision sessions deal a
  random hand from any folder, and mastered cards rest for growing periods. No network needed.
  See §7.

**Business goal:** a joyful private companion. For Faune & Flore, success = it runs on his iPhone,
identifies correctly in the field, works offline in the mountains, and makes every walk feel like
collecting.

**The signature rule of Faune & Flore (user's own design):** photographing a species **anywhere**
unlocks it for **every European country in its natural range** (native + established
populations). Introduced-only countries are stored separately and tagged, never counted as core
unlock. So one photo of a red fox in France lights it up in the Italy view too, marked "présent,
vu ailleurs" vs "vu ici".

## 2. Confirmed product decisions (from the user)

**Whole app**
- **SwiftUI native**, built with Xcode on this Mac. No cross-platform framework.
- Distribution to the iPhone via **paid Apple Developer account ($99/yr) + TestFlight internal testing**.
- All UI text and all generated content in **French**.

**Faune & Flore**
- Dex **fills as you scan**: starts empty, no pre-loaded catalog. Species names shown FR + EN + scientific.
- v1 features (all built): offline scan queue · animal subgroups · stats + achievements ·
  new-species celebration · rarity/conservation badges · birdsong playback · Découvertes (nearby
  species) · nature journal · low-confidence review flow.
- v2 (designed-for, not built): "Partager sur iNaturalist" citizen-science sharing.

**Cuisine**
- Amounts are **always metric** (g, kg, ml, cl, l, French spoons, °C), enforced by the response
  schema's unit enum rather than by asking the model.
- A recipe the cook has edited stops being credited to the model ("Modifiée par vous"). The cook's
  notes are never rewritten by a variation request.
- Dish photographs are real (Wikipedia/Commons, credited on the card), never generated.

**Savoirs** (rules confirmed 2026-09-24)
- **Maîtrisée** rests a card 30 days, doubling on each consecutive Maîtrisée (60, 120, 240),
  capped at 365. A card that comes back and is **not** mastered again becomes fresh, exactly as if
  never mastered.
- **Retirer** is an archive, not a deletion: the card leaves every session until restored
  ("Remettre"), and in a session an "Annuler" button follows for 6 s. Permanent deletion is a
  separate, confirmed action (swipe left in a folder, or on the card's page).
- **Suivante** is the neutral "next" (on a returning mastered card it triggers the reset above).
- "Fully random" means a **shuffled deck**, not independent draws (why: §7).
- **Recto shows first.** A per-session "Commencer par le verso" switch drills the other direction
  with the same cards (the user's "I always see the verso" meant the front).
- When a folder runs dry: a shorter session, then "Dossier maîtrisé ! Prochaine carte le <date>"
  with a "Réviser quand même" button.

**Open question (since 2026-09-23):** the user asked for "two new full sections: cooking and
knowledge" and will describe cooking later. Knowledge became Savoirs. Since Cuisine already exists,
it is **unanswered whether "cooking" extends Cuisine or is a new world**. He once misread this
question as being about Knowledge, so ask it plainly.

## 3. Architecture & strategy

**The one structural decision that shaped everything: the Core/App split.**

- `Core/` is a Swift package (**FlaunedexCore**, tools version 6.0, so Swift 6 strict concurrency)
  holding every piece of correctness-critical, framework-independent logic: Gemini
  request/schema/prompt, GBIF taxonomy + distribution, all enrichment parsers, EXIF GPS, nearby
  ranking, the recipe engine, and the Savoirs rules (mastery calendar, deck dealing, rich-text
  document + codec, folder tree, picture downscaling). It compiles and runs its **271 tests on
  macOS with only Command Line Tools**, no Xcode needed.
- `App/` is the SwiftUI iOS target (camera, GPS, SwiftData, MapKit, UIKit text editing, screens),
  in Swift 5 language mode. It consumes Core and needs Xcode 16.4 / the iOS 18.5 SDK to build.
- The `.xcodeproj` is **generated by XcodeGen** from [project.yml](project.yml) and gitignored:
  run `xcodegen generate` after any file add/remove.
- **Three worlds, one shell** ([RootTabView.swift](App/Features/RootTabView.swift)): `AppSection`
  (line 12; title, symbol, tint, subtitle per world) is persisted in `@AppStorage("appSection")`
  (line 57). Each world is its own `TabView`: `NatureTabs` (199: Faune, Flore, Capturer, Carte,
  Plus), `CuisineTabs` (266: Recettes, Demander, Plus), `KnowledgeTabs` (306: Dossiers, Réviser,
  Plus). Every "Plus" tab carries `WorldSwitchSection` (343).

**Other standing strategies:**

- **Verified-research foundation.** Every external fact (Gemini model id, GBIF endpoints,
  licensing, TestFlight cadence) came from a 2026 research + adversarial-verification pass. The plan
  file that held the dossier (`~/.claude/plans/hello-we-are-going-zazzy-wren.md`) **no longer
  exists**; its key outcomes: model `gemini-3.6-flash` with `thinking_level` escalation; GBIF
  occurrence **facet** (not `/distributions`) as the presence source; Wikidata P1843 for FR/EN
  names; IUCN v4 with Wikidata P141 fallback; Xeno-canto v3.
- **Offline-first capture.** The shutter never touches the network: photo + GPS are saved
  synchronously as a `Sighting` with a pending status, and the whole identify/enrich pipeline runs
  later when `Connectivity` ([App/Services/Connectivity.swift](App/Services/Connectivity.swift))
  reports the network back.
- **Graceful degradation everywhere.** Storage opens CloudKit → local-only → in-memory instead of
  crashing ([App/Persistence/Persistence.swift](App/Persistence/Persistence.swift)); enrichment is
  best-effort per source; French names fall back Wikidata → GBIF vernacular → English → scientific;
  a failing dish-photo lookup costs the photo, never the recipe.
- **Pure rules, provable in tests** (Savoirs): randomness enters as a `RandomNumberGenerator`
  (seeded SplitMix64 in tests) and dates through an explicit `Calendar` (Europe/Paris in tests),
  so the deck's fairness and every rest date are tested, daylight saving included.
- **Debug preview arguments** (compiled out of Release) make every screen inspectable without an
  API key or a walk outside: `-seedSampleData` (seeds each world independently, only while it is
  empty), `-previewSpeciesDetail`, `-previewRecipeDetail`, `-previewScreen <route>` for any screen
  of the three worlds, plus `-previewFolder <nom>` and `-previewVersoFirst` for Savoirs. Route table
  at [README.md:103](README.md:103); routing in `previewDestination`
  ([RootTabView.swift:151](App/Features/RootTabView.swift:151)); seeds in
  [SampleData.swift](App/Persistence/SampleData.swift) (`seed` 19, `seedRecipes` 77,
  `seedKnowledge` 243).
- **Safety stance:** AI identification is never presented as food-safety advice; every toxicity
  note renders under a hard disclaimer (`toxicityWarning`,
  [SpeciesDetailView.swift:117](App/Features/SpeciesDetailView.swift:117)). Media attribution
  (Commons artist/license, Xeno-canto recordist, dish photos) is stored on the model and rendered
  on every card.

## 4. Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI, iOS 17 deployment target (SDK on this Mac is iOS 18.5: **never** reach for iOS 26 APIs) |
| Rich text (Savoirs) | UIKit `UITextView` in a `UIViewRepresentable`, because SwiftUI's `TextEditor` on this SDK only edits a plain `String`; documents stored as versioned JSON |
| Persistence | SwiftData + CloudKit private DB (`.automatic`), CloudKit-safe models: all optional/defaulted, no unique constraints, optional relationships, cascade deletes; card pictures via `@Attribute(.externalStorage)` |
| Camera | AVFoundation custom capture; GPS injected via ImageIO in Core |
| Pictures (Savoirs) | ImageIO downscale in Core: longest side ≤1600 px, JPEG 0.8, metadata and GPS stripped |
| Location | CoreLocation one-shot fix at shutter; CLGeocoder deferred reverse geocode |
| Map | SwiftUI `Map` + `Marker` (no clustering yet, isolated behind `SightingsMapView`) |
| AI | Gemini `generateContent`, structured JSON via `responseSchema`, French system prompts (species and recipes) |
| Biodiversity data | GBIF (taxonomy, distribution, nearby), Wikidata (names, IUCN fallback), Wikipedia/Commons (image + license), IUCN v4, Xeno-canto v3 |
| Dish photos | French Wikipedia search with English fallback, Commons licence, cached on disk |
| Secrets | User-pasted keys in the device Keychain ([App/Services/KeychainStore.swift](App/Services/KeychainStore.swift)); nothing in the repo |
| Project gen | XcodeGen ([project.yml](project.yml)); tests via `swift test` in `Core/` |

## 5. Faune & Flore: the scan pipeline (what happens on one photo)

Orchestrated by [App/Services/ScanCoordinator.swift](App/Services/ScanCoordinator.swift)
(`enqueueCapture` line 31, `processQueue` line 52, `retryIdentification` line 91) calling
[Core/Sources/FlaunedexCore/SpeciesIdentificationPipeline.swift](Core/Sources/FlaunedexCore/SpeciesIdentificationPipeline.swift)
(`Outcome` line 33):

1. **Capture**: photo + CLLocation at shutter; EXIF GPS injected
   ([CameraModel.swift:127](App/Services/CameraModel.swift:127) via
   [Core/Sources/FlaunedexCore/Media/ExifGPS.swift](Core/Sources/FlaunedexCore/Media/ExifGPS.swift),
   round-trip tested); saved to disk via PhotoStore; `Sighting` row created immediately.
2. **Identify**: Gemini structured JSON: names, family, realm, animal group, spécificité, fun fact,
   season, toxicity, similar species, confidence + candidates. Schema and prompt in
   [Core/Sources/FlaunedexCore/Gemini/GeminiSchema.swift](Core/Sources/FlaunedexCore/Gemini/GeminiSchema.swift)
   (schema line 31, French system prompt line 89, review-hint instruction line 124).
3. **Canonicalize**: GBIF `species/match` → `speciesKey`, family, kingdom → realm + animal subgroup
   via the lookup table in
   [Core/Sources/FlaunedexCore/GBIF/AnimalGroupClassifier.swift](Core/Sources/FlaunedexCore/GBIF/AnimalGroupClassifier.swift)
   (GBIF has no `Reptilia` class; fish need a `phylum == Chordata` fallback). A hesitant
   identification routes to review without any GBIF request.
4. **Distribution**: occurrence facet by country + `/distributions` establishmentMeans, combined by
   the rule documented at
   [DistributionPipeline.swift:6](Core/Sources/FlaunedexCore/GBIF/DistributionPipeline.swift:6):
   range = (wild presence ∪ explicitly-native) − introduced-only, intersected with the European
   whitelist in [EuropeanCountries.swift](Core/Sources/FlaunedexCore/GBIF/EuropeanCountries.swift).
5. **Enrich** (best-effort, parallel-ish): Wikipedia image + FR article link, Commons license,
   Wikidata FR/EN names + P141 status, IUCN v4, Xeno-canto song. Assembled by
   [SpeciesAssembler.swift](Core/Sources/FlaunedexCore/Enrichment/SpeciesAssembler.swift) into a
   `SpeciesRecord`.
6. **Persist**: new species ⇒ dex number assigned
   ([ScanCoordinator.swift:170](App/Services/ScanCoordinator.swift:170), `nextDexNumber` line 183)
   and the "Nouvelle espèce !" celebration fires; known species ⇒ quiet new sighting. Low
   confidence ⇒ `needsReview` status and the candidates land in the journal's review sheet.
7. **Geocode, on its own schedule** (fix `74f4cf3`): the country lookup drains separately from
   identification ([ScanCoordinator.swift:46](App/Services/ScanCoordinator.swift:46), `geocode` line
   76) with its own counter (`geocodeAttempts`, [Models.swift:106](App/Persistence/Models.swift:106);
   retried while `needsGeocoding`, line 139, i.e. under 5 attempts). Before, one failed geocode
   during identification left the sighting without a country forever, silently breaking "vu ici"
   and "pays visités".

Same commit: `LocationProvider` is main-actor confined and a new request settles the pending one
(Découvertes re-requests on every realm change); `CameraModel`'s continuation sits behind a lock;
Découvertes fetches its species records concurrently. Both pipelines (species and recipe) are
driven end to end over a scripted transport in
[StubTransportTests.swift](Core/Tests/FlaunedexCoreTests/StubTransportTests.swift) (`4488a11`).

## 6. Cuisine: how a recipe works

**Flow:** [RecipeAskView](App/Features/Cuisine/RecipeAskView.swift) → `RecipeStore.generate`
([RecipeStore.swift:53](App/Services/RecipeStore.swift:53)) →
[RecipeGenerationService](Core/Sources/FlaunedexCore/Cuisine/RecipeGenerationService.swift)
(`requestBody` 35, `parseResponse` 98) → `RecipeDraft.normalized`
([Recipe.swift:244](Core/Sources/FlaunedexCore/Cuisine/Recipe.swift:244)) → `Recipe.apply`
([Models.swift:289](App/Persistence/Models.swift:289)) → photo via `RecipeStore.attachPhoto` (209)
and [DishPhotoService](Core/Sources/FlaunedexCore/Cuisine/DishPhotoService.swift) (`photo(for:)`
116), bytes cached on disk by PhotoStore (one instance per kind of image).

- **Metric by construction:** the schema's `unit` enum is `MetricUnit.allCases`
  ([RecipeSchema.swift:41](Core/Sources/FlaunedexCore/Cuisine/RecipeSchema.swift:41); enum at
  [MetricUnit.swift:15](Core/Sources/FlaunedexCore/Cuisine/MetricUnit.swift:15)), so the API cannot
  emit a cup. Prose that slips through is converted: `MetricConversion.toMetric` (161),
  `normalizeTemperatures(in:)` (199) for °F inside steps.
- **Variations** start from the stored recipe: `RecipeStore.revise` (81) with
  `RecipeSchema.revisionInstruction` (149). `Recipe.apply` keeps the cook's layer (notes,
  favourite, tags, order, photo).
- **Free-text round trip:** `RecipeTextFormat.render` (70) / `parse` (148) in
  [RecipeTextFormat.swift](Core/Sources/FlaunedexCore/Cuisine/RecipeTextFormat.swift);
  `RecipeStore.applyFreeText` (116) marks the recipe edited (`markEdited` 252), shown as "Modifiée
  par vous" ([Models.swift:224](App/Persistence/Models.swift:224)).
- **Rescaling:** `RecipeDraft.scaled(toServings:)`
  ([Recipe.swift:302](Core/Sources/FlaunedexCore/Cuisine/Recipe.swift:302)) with
  `MetricConversion.cookingRounded` (178): counted items whole, spoons to halves, cookbook
  rounding for weights and volumes, cooking times never scaled.
- **Organisation:** own tags, favourites, hand order (`sortIndex`, `persistOrder` 194), search
  across titles, ingredients and notes, course filters.
- **Screens** in [App/Features/Cuisine/](App/Features/Cuisine/): `RecipesView` (the bank),
  `RecipeDetailView` (the card; `RecipeVariationSheet` 406), `RecipeTextEditorView` (free text
  with a live parse counter), `RecipeAskView`, `RecipeComponents` (image, source badge,
  `TagEditor`, and the `FlowRow` layout at line 144 that Savoirs reuses).
- **Tests:** CuisineUnitsTests (25), RecipeGenerationTests (25), RecipeTextFormatTests (38), plus
  the recipe cases in StubTransportTests and LiveEndpointTests.

## 7. Savoirs: how the flash cards work

**The rules, in Core** ([Core/Sources/FlaunedexCore/Savoirs/](Core/Sources/FlaunedexCore/Savoirs/)):
- [MasteryRule.swift](Core/Sources/FlaunedexCore/Savoirs/MasteryRule.swift): `restDays(forLevel:)`
  (47: 0, 30, 60, 120, 240, then 365); `afterMastered` (72: when due, level + 1; when mastered
  early, still resting, via "Réviser quand même", the level stays (at least 1) and the rest
  restarts); `afterNotMastered` (81: back to fresh); `firstDayBack` (93: midnight at the start of
  the return day, by Calendar arithmetic, so the announced date is exact across daylight saving).
- [DeckDealer.swift](Core/Sources/FlaunedexCore/Savoirs/DeckDealer.swift): `dealable` (67)
  excludes resting and retired cards; `deal` (95) groups the pool by `timesDealt`, takes the
  least-dealt tier first, shuffles uniformly within each tier, then shuffles the chosen hand;
  `status` (76) returns a `DeckStatus` whose `isMastered` (45) triggers "Dossier maîtrisé".
- **Why a deck:** with 100 cards and 20 per session, independent draws leave about 33 cards unseen
  after 5 sessions and need about 24 sessions on average to show every card once. The deck shows
  all 100 in exactly 5 (tested, plus a chi-square test over 100,000 deals).
- [FolderTree.swift](Core/Sources/FlaunedexCore/Savoirs/FolderTree.swift): `subtree` (26),
  `canMove` (44: refuses moving a folder into its own subtree), `path`, `depth`; all loop-safe.

**Cards and their text:**
- Each side is a versioned JSON `RichDocument`
  ([RichDocument.swift](Core/Sources/FlaunedexCore/Savoirs/RichDocument.swift): types lines 14 to
  114, `normalized` 155, `trimmed` 216, `isShort` 276, `RichLink.normalized` 297, Codable 329,
  `jsonData` 344, `from(jsonData:)` 352). Paragraphs carry a style (body, heading, bullet, quote),
  runs carry a format (bold, italic, underline, strikethrough, 6 colours, link), pictures are blocks
  referring to a `KnowledgeImage` by id. Links allow http, https, mailto and tel (bare hosts get
  https; `javascript:` and `file:` refused). Unknown block types, styles or colours degrade
  instead of failing.
- [RichTextCodec.swift](Core/Sources/FlaunedexCore/Savoirs/RichTextCodec.swift) converts document
  ⇄ `NSAttributedString` using **semantic** keys (`fl.bold`, `fl.color`, `fl.paragraph`,
  `fl.image`, …, line 12; links use the "NSLink" key UIKit reads): `attributedString(from:)` 58,
  `document(from:)` 115 (total: never fails on foreign content), `setFormat` 195. Contract:
  document → attributed string → document returns the normalized document, tested on 400 random
  documents.
- The **look** is recomputed from the meaning by
  [RichTextStyle.swift](App/Features/Savoirs/RichText/RichTextStyle.swift): Dynamic Type sizes,
  hanging-indent bullets, and `CardImageAttachment` (193) sizing pictures for TextKit 1 and 2.
- **Editor** [RichTextEditor.swift](App/Features/Savoirs/RichText/RichTextEditor.swift):
  `RichUITextView` (17: pasting pictures), `RichTextEditorModel` (56: Return continues a list,
  Return on an empty bullet ends it, Backspace leaves a bullet; `shouldChangeTextIn` 166,
  `textViewDidChange` 207, `repairParagraphs` 578 restores the paragraph invariants after every
  edit, `registerUndo` 563), `RichTextToolbar` (747: UIKit toolbar in the keyboard's
  `inputAccessoryView`).
- **Display** [RichTextDisplay.swift](App/Features/Savoirs/RichText/RichTextDisplay.swift):
  `CardFaceTextView` (36) centres short content vertically; a tap on a link (checked against the
  character's drawn rectangle) opens it, any other tap turns the card.

**Pictures:** `PendingImage.prepare` ([KnowledgeStore.swift:23](App/Services/KnowledgeStore.swift:23))
→ `ImageDownscaler.downscale`
([ImageDownscaler.swift:33](Core/Sources/FlaunedexCore/Media/ImageDownscaler.swift:33): longest side
≤1600 px, never upscaled, EXIF orientation applied, transparency flattened onto white, JPEG 0.8,
all metadata incl. GPS stripped) → `KnowledgeImage.data` (external storage). `saveCard` (142)
deletes pictures no longer referenced and drops references to missing ones (`keepingImages` 176);
decoded pictures are cached (`image(for:in:)` 264); a picture not yet synced shows a placeholder.

**Store, session and screens:**
- [KnowledgeStore.swift](App/Services/KnowledgeStore.swift) (`@MainActor @Observable`): folders
  (create 80, `move` 100 guarded by `canMove`, delete 108 cascading), cards (`saveCard` 142,
  retire/restore 189/194, `resetMastery` 200), deck (`deal` 214; `record` 229: every verdict adds
  one to `timesDealt`, then Maîtrisée → `afterMastered`, Suivante → `afterNotMastered`, Retirer →
  `retiredAt`, returning a `VerdictUndo` for `undo` 250). `KnowledgeIndex` (286): subtree card
  lists, counts, "A › B" path labels, outline, French return dates.
- [ReviewViews.swift](App/Features/Savoirs/ReviewViews.swift): `ReviewSetupView` (54: folder, count
  presets below the available count plus "Toutes (N)", the verso switch at 220, `start` 136),
  `ReviewSessionView` (277: verdict buttons 377 to 379, `judge` 436, undo toast 401),
  `SessionSummaryView` (483: tiles, "Dossier maîtrisé !", "Réviser quand même" dealing resting cards).
- [FoldersView.swift](App/Features/Savoirs/FoldersView.swift) (`FolderContentView` 7: sub-folders,
  cards, search; swipe a card right to retire or restore, left to delete after confirmation),
  [FolderEditing.swift](App/Features/Savoirs/FolderEditing.swift)
  (`FolderPickerView` 6, `FolderEditorSheet` 87: 30 emojis, 10 colours, parent picker),
  [CardEditorView.swift](App/Features/Savoirs/CardEditorView.swift) (12: recto and verso editors
  kept alive in layers, photo library, camera via `CameraPicker` 282, links, "Enregistrer et en
  créer une autre", discard confirmation, `save` 263),
  [CardDetailView.swift](App/Features/Savoirs/CardDetailView.swift) (flip, facts, retire/restore,
  "Oublier la maîtrise", delete), [SavoirsComponents.swift](App/Features/Savoirs/SavoirsComponents.swift)
  (`FlipCard`/`FlipFace` 12/28: an `Animatable` modifier hiding each face past 90°; `ConfettiBurst`
  125 on each Maîtrisée; folder badges, deck pills, state badges).
- **Tests:** SavoirsMasteryTests (10, including the user's own example dates and a daylight-saving
  change), SavoirsDeckTests (14), SavoirsFolderTreeTests (6), RichDocumentTests (21),
  RichTextCodecTests (18), ImageDownscalerTests (8); helpers in SavoirsTestSupport.

## 8. Data model

Six SwiftData models, all registered at [Persistence.swift:52](App/Persistence/Persistence.swift:52).

In [App/Persistence/Models.swift](App/Persistence/Models.swift):
- **`Species`** (line 12): the dex card: `gbifKey` (join key), names, family, realm, animalGroup,
  `rangeCountries` / `nativeCountries` / `introducedCountries`, conservation status, reference image
  + attribution, audio + attribution, French texts, `seasonMonths`, `dexNumber` (line 59),
  `isNotable` rarity flag (line 84), optional `sightings` relationship.
- **`Sighting`** (line 94): one observation: photo path, lat/lon/accuracy, timestamp, `countryISO`
  (deferred geocode, `geocodeAttempts` line 106), `status` (pendingIdentification /
  pendingGeocoding / complete / failed / needsReview), `retryCount`, `geminiCandidatesJSON`.
- **`Recipe`** (line 158): title, servings, times, `ingredients` / `steps` (Codable arrays of Core
  types), chef's tip, allergens, tags, the cook's `notes` (181), `isFavorite` (184), `sortIndex`
  (186), `originalPrompt` (209), source generated vs edited (220 to 238), photo fields.

In [App/Persistence/KnowledgeModels.swift](App/Persistence/KnowledgeModels.swift):
- **`KnowledgeFolder`** (line 21): name, emoji, `FolderColor` (line 8), `sortIndex`, `parent`,
  cascading `children` and `cards`.
- **`KnowledgeCard`** (line 80): `rectoData` / `versoData` (RichDocument JSON) plus plain-text
  copies for search and previews; deck state `masteryLevel`, `restUntil`, `timesDealt`,
  `retiredAt`; `mastery` (130) and `deckEntry` (145) bridge to Core; cascading `images`.
- **`KnowledgeImage`** (line 159): picture bytes with `@Attribute(.externalStorage)` (161), pixel
  size, owning card.

Unlock semantics: a species is "collected" in country X iff it has ≥1 sighting **and**
`rangeCountries` contains X. Countries with an actual sighting show "vu ici".

CloudKit record types to deploy: `CD_Species`, `CD_Sighting`, `CD_Recipe`, `CD_KnowledgeFolder`,
`CD_KnowledgeCard`, `CD_KnowledgeImage`.

## 9. Design system

[App/Design/Theme.swift](App/Design/Theme.swift): warm field-guide identity: parchment canvas /
deep-forest dark mode, **amber accent for Faune, leaf-green for Flore**, gold "treasure" for rarity
and celebrations, rounded display type, card surfaces, and the monospaced `DexNumber` badge. One
tint per world, applied on each world's `TabView`: `brand` forest green (line 12), `cuisine`
terracotta (32), `knowledge` indigo ink (36); `folder(_:)` (41) maps the ten folder colours.
Shared components (RemoteImage, ConservationBadge, Chip, AttributionLabel, NewSpeciesCelebration,
EmptyStateView with a `tint` parameter) live in [App/Features/Components.swift](App/Features/Components.swift).
The app icon (leaf + paw on forest gradient) is a generated 1024px PNG in
`App/Assets.xcassets/AppIcon.appiconset/`.

---

## 10. Codebase Guide

### Root
- **[project.yml](project.yml)**: XcodeGen definition: targets, bundle id
  `com.taddeocarpinelli.flaunedex`, iOS 17 target, entitlements hookup, empty `DEVELOPMENT_TEAM`.
- **[README.md](README.md)**: build/run instructions, the "How ... works" walkthroughs for all three
  worlds, status; debug launch args from line 86.
- **[DEPLOYMENT.md](DEPLOYMENT.md)**: the account-holder runbook (see Next steps).
- **`.gitignore`**: excludes the generated `Flaunedex.xcodeproj/`, `Core/.build/`, DerivedData.
- **Resume.md**: this file (untracked).

### Core/Sources/FlaunedexCore: platform-independent logic (271 tests)
- **[FlaunedexConfig.swift](Core/Sources/FlaunedexCore/FlaunedexConfig.swift)**: central config: Gemini model id (`gemini-3.6-flash`), API base URLs, User-Agent.
- **[SpeciesIdentificationPipeline.swift](Core/Sources/FlaunedexCore/SpeciesIdentificationPipeline.swift)**: orchestrates identify → canonicalize → distribution → enrich; returns an `Outcome` with either a full `SpeciesRecord` or review candidates.
- **Domain/**
  - **[Realm.swift](Core/Sources/FlaunedexCore/Domain/Realm.swift)**: plant / animal / fungus enum mapped from GBIF kingdom.
  - **[AnimalGroup.swift](Core/Sources/FlaunedexCore/Domain/AnimalGroup.swift)**: bird/mammal/insect/… enum with French labels.
  - **[TaxonMatch.swift](Core/Sources/FlaunedexCore/Domain/TaxonMatch.swift)**: canonical taxon (key, name, higher taxonomy, vernacular) from GBIF.
  - **[GeminiIdentification.swift](Core/Sources/FlaunedexCore/Domain/GeminiIdentification.swift)**: decoded Gemini answer incl. confidence + `Candidate` list.
  - **[SpeciesRecord.swift](Core/Sources/FlaunedexCore/Domain/SpeciesRecord.swift)**: the fully-assembled species (what the app persists from).
  - **[Enrichment.swift](Core/Sources/FlaunedexCore/Domain/Enrichment.swift)**: enrichment value types: VernacularNames, image/audio attribution, distribution result.
- **Gemini/**
  - **[GeminiSchema.swift](Core/Sources/FlaunedexCore/Gemini/GeminiSchema.swift)**: the `responseSchema` JSON, the French system prompt, the user instruction, and the review-hint sentence.
  - **[GeminiIdentificationService.swift](Core/Sources/FlaunedexCore/Gemini/GeminiIdentificationService.swift)**: builds the ordered `generateContent` request (inline base64 image, `thinking_level`, hint threading) and parses the response.
- **GBIF/**
  - **[GBIFEndpoints.swift](Core/Sources/FlaunedexCore/GBIF/GBIFEndpoints.swift)**: URL builders: `species/match`, occurrence country facet, `/distributions`, vernacular names; the wild-presence `basisOfRecord` filter list.
  - **[GBIFResponses.swift](Core/Sources/FlaunedexCore/GBIF/GBIFResponses.swift)**: all GBIF DTOs/parsers: match, facet counts, `species/{key}` record, distributions, vernaculars.
  - **[GBIFService.swift](Core/Sources/FlaunedexCore/GBIF/GBIFService.swift)**: async façade over endpoints + parsers.
  - **[AnimalGroupClassifier.swift](Core/Sources/FlaunedexCore/GBIF/AnimalGroupClassifier.swift)**: class→group table + reptile-order and Chordata-fish fallbacks.
  - **[DistributionPipeline.swift](Core/Sources/FlaunedexCore/GBIF/DistributionPipeline.swift)**: implements the natural-range rule (native ∪ wild-presence − introduced-only).
  - **[EuropeanCountries.swift](Core/Sources/FlaunedexCore/GBIF/EuropeanCountries.swift)**: the ISO alpha-2 European whitelist + French country names.
  - **[NearbyService.swift](Core/Sources/FlaunedexCore/GBIF/NearbyService.swift)**: Découvertes: geoDistance facet by speciesKey (`speciesFacet` line 60, `seasonWindow` line 100), pure ranking (line 118), batched FR-name resolution with GBIF fallback (`frenchNames` line 202, records fetched concurrently), first-letter display casing (`displayName` line 20).
- **Enrichment/**
  - **[WikipediaClient.swift](Core/Sources/FlaunedexCore/Enrichment/WikipediaClient.swift)**: Action API: lead image + FR langlink (endpoint validated live).
  - **[CommonsClient.swift](Core/Sources/FlaunedexCore/Enrichment/CommonsClient.swift)**: imageinfo/extmetadata → artist, license, source page (handles missing fields).
  - **[WikidataClient.swift](Core/Sources/FlaunedexCore/Enrichment/WikidataClient.swift)**: SPARQL: single-taxon FR/EN names + P141 IUCN fallback; batched FR-names query for lists (from line 88).
  - **[IUCNClient.swift](Core/Sources/FlaunedexCore/Enrichment/IUCNClient.swift)**: Red List v4 (Bearer token) → category code.
  - **[XenoCantoClient.swift](Core/Sources/FlaunedexCore/Enrichment/XenoCantoClient.swift)**: v3 recordings query → best song + recordist attribution.
  - **[SpeciesAssembler.swift](Core/Sources/FlaunedexCore/Enrichment/SpeciesAssembler.swift)**: merges Gemini + GBIF + enrichment into one `SpeciesRecord` with name-cascade rules.
- **Cuisine/** (see §6)
  - **[MetricUnit.swift](Core/Sources/FlaunedexCore/Cuisine/MetricUnit.swift)**: the unit enum, conversions to metric, °F → °C in prose, cooking rounding, French number and duration formatting.
  - **[Recipe.swift](Core/Sources/FlaunedexCore/Cuisine/Recipe.swift)**: `RecipeDraft`, ingredient, step, course, difficulty; normalisation and scaling.
  - **[RecipeSchema.swift](Core/Sources/FlaunedexCore/Cuisine/RecipeSchema.swift)**: response schema, French system prompt, user and variation instructions, `RecipeRequest`.
  - **[RecipeGenerationService.swift](Core/Sources/FlaunedexCore/Cuisine/RecipeGenerationService.swift)**: builds the Gemini request and parses the recipe.
  - **[RecipeTextFormat.swift](Core/Sources/FlaunedexCore/Cuisine/RecipeTextFormat.swift)**: the free-text render/parse round trip.
  - **[DishPhotoService.swift](Core/Sources/FlaunedexCore/Cuisine/DishPhotoService.swift)**: Wikipedia search (FR then EN) → lead image + Commons credit.
- **Savoirs/** (see §7): MasteryRule, DeckDealer, RichDocument, RichTextCodec, FolderTree.
- **Media/**
  - **[ExifGPS.swift](Core/Sources/FlaunedexCore/Media/ExifGPS.swift)**: ImageIO GPS write/read on image bytes (AVFoundation does not embed GPS itself).
  - **[ImageDownscaler.swift](Core/Sources/FlaunedexCore/Media/ImageDownscaler.swift)**: Savoirs picture shrinking (see §7).
- **Networking/**
  - **[HTTPClient.swift](Core/Sources/FlaunedexCore/Networking/HTTPClient.swift)**: tiny async GET/POST protocol + URLSession impl (User-Agent, error mapping); everything is injectable for tests.
  - **[JSONValue.swift](Core/Sources/FlaunedexCore/Networking/JSONValue.swift)**: order-preserving JSON builder (Gemini needs `propertyOrdering`-stable bodies).

### Core/Tests/FlaunedexCoreTests: one file per subsystem
- **Faune & Flore:** Domain, AnimalGroupClassifier, DistributionPipeline (the unlock rule),
  EuropeanCountries, GBIFResponses, EnrichmentParsers (all five sources), Gemini (request shape,
  schema, hint), ExifGPS (real JPEG round-trip incl. hemispheres), SpeciesAssembler (cascades),
  NearbyService (ranking, season clamps, URLs, batched names, display casing).
- **Both pipelines:** StubTransportTests (16: end to end over a scripted transport, error statuses,
  graceful degradations); LiveEndpointTests (4, skipped unless `FLAUNEDEX_LIVE=1`).
- **Cuisine:** CuisineUnitsTests, RecipeGenerationTests, RecipeTextFormatTests.
- **Savoirs:** SavoirsMasteryTests, SavoirsDeckTests, SavoirsFolderTreeTests, RichDocumentTests,
  RichTextCodecTests (incl. 4 on replacement formatting), ImageDownscalerTests; SavoirsTestSupport
  holds the seeded SplitMix64 generator and the Paris calendar helpers.

### App: the iOS target
- **[FlaunedexApp.swift](App/FlaunedexApp.swift)**: entry point; opens storage via Persistence, injects `storageMode` env key, seeds sample data in Debug.
- **Design/[Theme.swift](App/Design/Theme.swift)**: palette, per-world tints, folder colours, metrics, type, `cardSurface`/`canvasBackground` modifiers, `DexNumber`.
- **Persistence/**
  - **[Models.swift](App/Persistence/Models.swift)**: `Species`, `Sighting`, `Recipe` (CloudKit-safe).
  - **[KnowledgeModels.swift](App/Persistence/KnowledgeModels.swift)**: `KnowledgeFolder`, `KnowledgeCard`, `KnowledgeImage`, `FolderColor`, `CardSide`.
  - **[Persistence.swift](App/Persistence/Persistence.swift)**: CloudKit → local → in-memory fallback + honest `StorageMode` (checks the iCloud ubiquity token); the six-model schema.
  - **[SampleData.swift](App/Persistence/SampleData.swift)**: Debug-only seed, per world and only while that world is empty: 4 real species with live Wikimedia images (incl. the two plants from the original brief), 3 recipes, and 22 cards in 9 folders (3 resting, 1 retired, 1 back for confirmation, 3 flags drawn in code).
- **Services/**
  - **[APIKeys.swift](App/Services/APIKeys.swift)**: observable key store (Gemini required; IUCN, Xeno-canto optional) backed by Keychain.
  - **[KeychainStore.swift](App/Services/KeychainStore.swift)**: minimal Security-framework wrapper.
  - **[CameraModel.swift](App/Services/CameraModel.swift)**: AVFoundation session + capture; injects GPS via Core's ExifGPS at line 127.
  - **[LocationProvider.swift](App/Services/LocationProvider.swift)**: one-shot CLLocation with timeout, main-actor confined.
  - **[ReverseGeocoder.swift](App/Services/ReverseGeocoder.swift)**: coordinate → ISO country (deferred, online-only).
  - **[PhotoStore.swift](App/Services/PhotoStore.swift)**: photos on disk under Application Support, one instance per kind (sightings, recipes), relative paths in the DB.
  - **[Connectivity.swift](App/Services/Connectivity.swift)**: NWPathMonitor → `isOnline` + a tick that triggers queue drains.
  - **[ScanCoordinator.swift](App/Services/ScanCoordinator.swift)**: the Faune & Flore brain: queue, retries, species upsert, dex numbering, celebration trigger, review retry, separate geocode drain.
  - **[RecipeStore.swift](App/Services/RecipeStore.swift)**: the Cuisine store (see §6).
  - **[KnowledgeStore.swift](App/Services/KnowledgeStore.swift)**: the Savoirs store and `KnowledgeIndex` (see §7).
- **Features/** (screens)
  - **[RootTabView.swift](App/Features/RootTabView.swift)**: the world switch (`AppSection`), the three tab shells, the world-switch rows, the celebration overlay, debug preview routing (line 151) and `PreviewSessionHost` (392, deals a preview session once).
  - **[DexView.swift](App/Features/DexView.swift)**: per-realm grid, search, Groupe/Famille/Pays filter menus, `DexCard`.
  - **[SpeciesDetailView.swift](App/Features/SpeciesDetailView.swift)**: the star card: hero images, chips, toxicity, spécificité/fun-fact, season, birdsong, range countries (vu ici / vu ailleurs), sightings mini-map, Wikipedia link, attribution.
  - **[CaptureView.swift](App/Features/CaptureView.swift)**: live camera, banners (no key / offline / pending count), shutter with flash + haptic.
  - **[SightingsMapView.swift](App/Features/SightingsMapView.swift)**: all-sightings map, realm-tinted leaf/paw markers.
  - **[DiscoverView.swift](App/Features/DiscoverView.swift)**: Découvertes: realm segment, radius slider, ranked nearby list.
  - **[JournalView.swift](App/Features/JournalView.swift)**: day-grouped timeline; taps open species or the review sheet.
  - **[ReviewSheet.swift](App/Features/ReviewSheet.swift)**: low-confidence flow: pick a candidate (re-asks Gemini with the hint) or re-analyse deeper.
  - **[StatsView.swift](App/Features/StatsView.swift)**: headline count, tiles (incl. pays visités vs pays couverts), family bars, achievements.
  - **[SettingsView.swift](App/Features/SettingsView.swift)**: storage-mode status row, API keys, data credits + safety note.
  - **[Components.swift](App/Features/Components.swift)**: shared visual components (see §9).
  - **[Cuisine/](App/Features/Cuisine/)**: the recipe screens (see §6).
  - **[Savoirs/](App/Features/Savoirs/)** and **Savoirs/RichText/**: the flash-card screens and the rich-text editor (see §7).
- **[Info.plist](App/Info.plist)**: FR usage strings, `CFBundleExecutable` (hand-written plists must declare it), `ITSAppUsesNonExemptEncryption=false`.
- **[Flaunedex.entitlements](App/Flaunedex.entitlements)**: CloudKit container `iCloud.com.taddeocarpinelli.flaunedex`.

---

## 11. Where we are (precise, 2026-09-29)

**Done and verified:**
- Core: **271 tests: 267 pass and the 4 live-endpoint tests are skipped by default** (rerun
  2026-09-29 with the scratch-path command in §13).
- App: builds for the iOS 18.5 simulator with 0 errors and 0 warnings in App sources
  (2026-09-24), with
  `xcodebuild -project Flaunedex.xcodeproj -scheme Flaunedex -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build CODE_SIGNING_ALLOWED=NO`;
  installs and runs on the iPhone 16 simulator, **zero crashes**.
- Faune & Flore: every screen verified running, several by driving the UI live (taps/swipes in the
  simulator panel): dex grids, full species card incl. the range-country unlock display, journal,
  stats, settings, map pins, Découvertes. Verified **against live APIs** from the running app:
  Wikipedia image+langlink lookup, GBIF nearby facet (real alpine species from a simulated
  Chamonix GPS), batched Wikidata FR names (found its partial coverage → built the GBIF fallback;
  result all-French incl. "Épicéa" and "Sorbier des oiseleurs" from the fallback).
- Cuisine: every screen verified running in the simulator by hand (bank, filters, card, free-text
  editor, rescaling, tags, swipe-delete, hand ordering, ask screen); live dish-photo lookup
  verified ("Shakshuka aux poivrons" resolves to the Chakchouka article).
- Savoirs, verified in the simulator on 2026-09-24:
  - home counts (22 cards: 18 to revise, 3 resting, 1 retired, checked by hand) and the "À confirmer" badge;
  - card detail with the 3D flip, bullets and italics;
  - a session with random deal, pictures, Maîtrisée, and Retirer + Annuler (the database showed the card restored);
  - "Dossier maîtrisé ! Prochaine carte le 24 octobre" (24 Sep + 30 days);
  - the editor: toolbar, list behaviour, save and reopen, a link opening Safari;
  - a library photo stored as a 1600 × 1200 JPEG of about 0.9 MB with no GPS, shown on its card.
- Robustness fixes landed: no-crash storage fallback + honest iCloud status; review flow for
  uncertain IDs; EXIF GPS proven by round-trip test; the lost-country and concurrency fixes of
  `74f4cf3` (§5).
- Git: master at `4488a11`, 6 commits: `5570bf2` initial build, `2acb494` CloudKit resilience +
  French Découvertes, `afb3c9d` README fix, `74f4cf3` sighting country + concurrency, `f8539a5`
  Cuisine, `4488a11` end-to-end pipeline tests. Cuisine was built on branch
  `claude/project-context-review-9761da` and fast-forwarded into master on 2026-09-24.
  **All the Savoirs work is uncommitted**: new `App/Features/Savoirs/`,
  `App/Persistence/KnowledgeModels.swift`, `App/Services/KnowledgeStore.swift`,
  `Core/Sources/FlaunedexCore/Savoirs/`, `Core/Sources/FlaunedexCore/Media/ImageDownscaler.swift`
  and 7 test files; modified Theme, Components, RootTabView, Persistence, SampleData, README and
  DEPLOYMENT. This file is untracked. There is **no git remote**.

**Not done:**
1. **Nothing has run on a real iPhone.** The camera and real CoreLocation cannot be exercised in the
   simulator, and neither can the camera button of the Savoirs card editor.
2. **No real Gemini call has ever been made** (no key on this Mac). The identification and recipe
   paths are tested against recorded payloads and a scripted transport only.
3. **No Apple Developer account exists on this Mac** (0 signing identities, no provisioning
   profiles). Everything in DEPLOYMENT.md is blocked, so CloudKit sync, card pictures included, is
   untested and the schema exists nowhere yet.

## 12. Next steps, in order

**0. Waiting on Taddeo:**
- Whether to **commit the Savoirs work** (never committed without his go-ahead).
- The **cooking-section question** (§2): extend Cuisine, or a new world? Then his description, and
  a brief with proposals back to him before building, as was done for Savoirs.

**A. Account-holder steps (user only, cannot be automated; runbook = [DEPLOYMENT.md](DEPLOYMENT.md)):**
1. Enrol + sign into Xcode, pick the team: [DEPLOYMENT.md:13](DEPLOYMENT.md) §1. Optionally paste
   the Team ID into `DEVELOPMENT_TEAM` in [project.yml](project.yml) (line 17) so XcodeGen keeps it.
2. Add the iCloud/CloudKit capability + container: §2 (line 31).
3. Run signed with an iCloud account and create all **six** record types (a sighting, a recipe, and
   a knowledge card **with a picture**, or simply `-seedSampleData`): §3 (line 38). The in-app check
   is the Réglages "Sauvegarde" row: it must say "Sauvegarde iCloud active".
4. **Deploy schema to Production in the CloudKit Console**: §4 (line 56). Repeat after any model change.
5. Archive → App Store Connect → TestFlight internal: §5 (line 71). Rebuild every ~80 days
   (builds expire at 90); bump `CURRENT_PROJECT_VERSION` in [project.yml](project.yml) (line 13).

**B. First on-device session (assistant + user together, after A1):**
- Build to the physical iPhone, walk the real flow: Réglages → paste Gemini key → Capturer → real
  photo → verify identification, dex entry, celebration, journal, map pin, EXIF GPS in the photo.
- Test offline: airplane mode → capture → reconnect → queue drains
  ([ScanCoordinator.swift:52](App/Services/ScanCoordinator.swift:52)).
- Test the review flow with a deliberately ambiguous photo.
- Cuisine: ask for a real recipe (the first real recipe call) and check its photo.
- Savoirs: add a picture with the camera, then check it is upright and stored without GPS.

**C. Housekeeping (small, each needs Taddeo's OK):**
- Delete the redundant worktree `.claude/worktrees/project-context-review-9761da` and its branch
  (same commit as master, nothing uncommitted).
- Add a git remote: today the only copies are this Mac and iCloud.
- Move the repo out of the iCloud-synced Desktop (e.g. `~/Developer`), which has broken builds (§13).

**D. Post-device polish backlog (nice-to-have, not blocking):**
- Proper `Localizable.xcstrings` catalog (French strings are currently hardcoded inline: works, but
  not localizable).
- Map clustering via an `MKMapView` wrapper if pin counts grow
  ([SightingsMapView.swift](App/Features/SightingsMapView.swift) is isolated for exactly this swap).
- Per-sighting notes UI (the model field exists on `Sighting`), share-a-card image export,
  `BGProcessingTask` opportunistic background drains.

**E. v2:** iNaturalist sharing (designed-for, not built; the plan file that described it no longer exists).

## 13. Gotchas learned the hard way (do not re-learn)

**Build and tooling**
- This Mac: Xcode 16.4 / iOS 18.5 SDK / iPhone 16 simulator. Deployment target is **iOS 17**; iOS
  26 APIs are *future* adoptions only.
- Hand-written [App/Info.plist](App/Info.plist) must declare `CFBundleExecutable`; without it,
  simulator install fails with a misleading "Please try again later".
- **The repo lives on the iCloud-synced Desktop.** `swift test` has failed with "input file ... was
  modified during the build" and with I/O error 60 reading `Core/.build/description.json`. Working
  fix: `cd Core && swift test --scratch-path <session scratchpad>/core-build`, which keeps build
  products out of iCloud.
- The simulator screenshot tool often returns the frame from before the last action: take two.
- `file` calls the app's stored JPEG pictures "TIFF"; the magic bytes (`ffd8 ffe0 … JFIF`) and
  `sips` say JPEG, so trust those. The app's store is readable with sqlite3 at the simulator app
  container's `Library/Application Support/default.store`.

**Data and APIs**
- AVFoundation does **not** embed GPS EXIF: that is why
  [ExifGPS.swift](Core/Sources/FlaunedexCore/Media/ExifGPS.swift) exists and is round-trip tested.
- GBIF backbone: no `Reptilia` class; `class` is null for many bony fish → classifier table +
  Chordata fallback are mandatory, unit-tested in
  [AnimalGroupClassifierTests.swift](Core/Tests/FlaunedexCoreTests/AnimalGroupClassifierTests.swift).
- GBIF `/distributions` is far too incomplete to drive presence: the occurrence facet is the source.
- Wikidata P1843 French coverage is partial (measured 3/5) → always keep the GBIF vernacular fallback.
- SwiftData creates a CloudKit container even when sync is impossible → gate any "iCloud active"
  claim on `ubiquityIdentityToken` ([Persistence.swift](App/Persistence/Persistence.swift)).
- Every launch logs CoreData "Could not materialize Objective-C class named Array" for plain Swift
  array attributes: benign, the data persists (verified). Do not "fix" it.

**SwiftUI and UIKit (met while building Savoirs)**
- SwiftUI's `TextEditor` on the iOS 18.5 SDK only takes a plain `String`: rich text needs the UIKit
  wrapper.
- **Autocorrection strips custom attributes.** UITextView's system replacements (autocorrection
  re-inserting the word under a newly placed cursor, typing over a selection) ignore
  `typingAttributes` and drop custom `fl.*` attributes, which silently lost bold on save. Fixed
  with `pendingReplacement` + `RichTextCodec.setFormat`
  ([RichTextEditor.swift:196](App/Features/Savoirs/RichText/RichTextEditor.swift:196)), 4 tests. If
  formatting vanishes again, log the ranges in `shouldChangeTextIn` first.
- `NSAttributedString.Key.link` does not exist in plain Foundation (Core has no UIKit): Core
  declares `.flLink` with the raw value "NSLink", the key UIKit reads.
- **One tap handler per area.** A SwiftUI tap on the whole card face plus the text view's own tap
  turned the card twice; the SwiftUI tap now covers only the header strip
  ([SavoirsComponents.swift:79](App/Features/Savoirs/SavoirsComponents.swift:79)).
- A `.tint` placed before `.toolbar` inside a NavigationStack does not reach the navigation bar's
  buttons: put it on the NavigationStack itself (done for both editor sheets and the debug routes).
- A `Label` inside a `List` reserves an icon column, opening a gap in small pills: use an `HStack`.
- UndoManager closures under Swift 6 checking: register through a helper that runs
  `MainActor.assumeIsolated` with an `@unchecked Sendable` wrapper (`registerUndo`, RichTextEditor
  line 563; `SavedText` line 883).
- A debug preview must deal its session once, in `@State` (`PreviewSessionHost`), or every render
  re-deals.

**Memory:** session memory for this project lives at
`~/.claude/projects/-Users-taddeocarpinelli-Desktop-Mugi-the-inventor-Code-Flaunedex/memory/`; older
notes remain under `-Users-taddeocarpinelli-Desktop-Flaunedex` (the repo's previous location).
