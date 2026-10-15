# Mettre Flaunedex sur l'iPhone

The app is for one person on one phone, an **iPhone XS on iOS 18**, so it is
installed straight from Xcode: no TestFlight, no App Store Connect, no review.
Everything here needs **your Apple ID**, so these are the steps only you can
perform. Nothing in this file is a code change.

The app needs **iOS 17 or later**. The XS stops at iOS 18, which is fine: CI
builds every push against an iOS 17 minimum, so nothing in the code needs
iOS 26. On iOS 18 the app looks the way it did in the simulator screenshots.

---

## 1. Apple Developer Program — $99/year

Strictly optional for a personal app, but worth it here:

| | Free Apple ID | Paid program |
|---|---|---|
| An install from Xcode lasts | **7 days**, then the app won't open until you reinstall | **1 year** |
| iCloud backup of your collection and recipes | No (the iPhone's own backup still includes it) | Yes |

The 7-day limit is the real cost for a field app: on a two-week trip it stops
opening halfway through. The data stays safe, but locked until you are back at
the Mac.

**Enrol on the web**, not in the Apple Developer app (which needs iOS 26):
<https://developer.apple.com/account> → sign in → **Enroll** → continue on the
web. Pay with a card in your own name, otherwise Apple asks for a copy of your
ID and approval takes longer.

## 2. Xcode

1. `xcodebuild -version`. Any Xcode that supports iOS 18 devices works: Xcode 16
   or 26. (The "Xcode 26 only" rule applies to App Store Connect uploads, which
   this route never makes.)
2. **Xcode → Settings → Accounts → +** and sign in with the Apple ID you enrolled.
3. In the repository: `xcodegen generate && open Flaunedex.xcodeproj`.
4. Target **Flaunedex** → **Signing & Capabilities** → tick *Automatically manage
   signing* and pick your Team. Leave **iCloud** (CloudKit, container
   `iCloud.com.taddeocarpinelli.flaunedex`), **Push Notifications** and
   **Background Modes → Remote notifications** on when they appear: they come from
   the entitlements and `Info.plist`, and are how iCloud keeps the data backed up.

> Once the team is picked, run `./update.sh` once: it saves the team to
> `Config/Team.xcconfig` (kept out of git), so regenerating the project never
> asks for it again.

> **Staying on the free Apple ID instead?** Free accounts cannot sign iCloud or
> push. Remove the three iCloud keys and `aps-environment` from
> `App/Flaunedex.entitlements` (or ask for a switch in `project.yml`); the app
> then runs local-only and says so in Réglages.

## 3. Install on the iPhone

1. Plug the iPhone into the Mac, unlock it, and tap **Trust**.
2. On the iPhone: **Réglages → Confidentialité et sécurité → Mode développeur** →
   on, then restart when asked. (The switch appears once Xcode has seen the phone.)
3. In Xcode, pick the iPhone as the run destination and press **Run** (⌘R). The
   destination is the box at the top centre of the window, right of
   *Flaunedex*. "iPhone 16" or "iPhone 16 Pro" there is a **simulator** on the Mac;
   your phone is listed under **iOS Device**, by its name. If it is greyed out,
   Xcode is still preparing it: wait for the progress bar at the top to finish.
4. The first launch may say the developer is not trusted: **Réglages → Général →
   VPN et gestion de l'appareil** → your Apple ID → **Faire confiance**.

## 4. First real use

These are the first calls the app will ever make for real, so do them before
relying on it in the field:

1. The gear at the top right of the home screen (**Réglages**) → paste your
   Gemini key. The one key serves the three apps.
2. Check the **Sauvegarde** row reads *Sauvegarde iCloud active*. *iCloud non
   connecté* means the iPhone isn't signed in to iCloud; the app still works, it
   just isn't backed up.
3. **Capturer**: photograph a plant or an animal. This is the first identification
   ever sent to Gemini.
4. **Cuisine → Demander**: ask for one recipe. This is the first recipe request.
5. **Savoirs → Apprendre**: ask for one card. This is the first card request.

If a scan, a recipe or a card fails, that is the thing to look at first.

## Install a new version

Whenever there is new code (a fix, a new screen), with the iPhone plugged in:

```bash
cd ~/Faunedex && ./update.sh
```

It closes Xcode, keeps your signing team, downloads the new code, rebuilds the
Xcode project and opens it again. Wait for *Resolving packages* at the top of
the window to finish, then: the iPhone as destination, and **Run** (⌘R). The
new version installs over the old one, and everything in the app (species,
recipes, cards, your Gemini key) stays.

**"Missing package product 'FlaunedexCore'"** means Xcode kept an old view of
the project. Run `./update.sh --clean`, which also empties Xcode's build cache
for the app. If it persists: **File → Packages → Reset Package Caches**. The
yellow *Update to recommended settings* warning is harmless; leave it.

The very first time, `update.sh` isn't on the Mac yet, so get it with
`cd ~/Faunedex && git pull` and then run `./update.sh`.

## Keep it alive

- **Once a year**, reinstall from Xcode (step 3) before the year runs out, and
  keep the $99 membership current. Set a reminder.
- iCloud data lives in CloudKit's **Development** environment, which is what
  installs from Xcode use. That is fine for a personal app; the Production deploy
  only matters for TestFlight or the App Store.

---

## Later: TestFlight (optional)

Only worth it to install without a cable, or to share the app with someone.

- Needs **Xcode 26 or later**: since 28 April 2026, App Store Connect refuses
  uploads built with older SDKs. Xcode 26.0 to 26.3 run on macOS Sequoia 15.6;
  26.4.1 onwards needs macOS Tahoe 26.2.
- Before the first upload, **deploy the CloudKit schema to Production**
  (<https://icloud.developer.apple.com/dashboard/> → container → *Deploy Schema
  Changes*, after `CD_Species`, `CD_Sighting`, `CD_Recipe` and `CD_KnowledgeCard`
  exist in Development). TestFlight builds talk to Production; skipping this silently
  breaks sync.
- Create the app in App Store Connect, then **Product → Archive → Distribute App →
  App Store Connect → Upload**, and add yourself as an internal tester.
- TestFlight builds expire after 90 days.

`ITSAppUsesNonExemptEncryption` is already `false` in `App/Info.plist`, and the
privacy manifest and opaque icon upload validation checks for are in place.

---

## Sanity checks

| Check | Where |
|---|---|
| Code builds | GitHub → **Actions** → latest *CI* run is green |
| Signing identity exists | `security find-identity -v -p codesigning` |
| iCloud actually syncing | app → **Réglages** → *Sauvegarde* row |
| Install not expired | app opens; reinstall from Xcode yearly |

If the app ever shows **"iCloud non connecté"** or **"Stockage local
uniquement"**, it is still fully usable — everything is saved on the device and
simply isn't backed up.
