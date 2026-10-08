# Mettre Flaunedex sur l'iPhone

Everything in this file requires **signing in with your Apple ID**, so these are
the steps only you can perform. The app itself is ready — nothing here is a code
change.

Current state of this Mac: **no Apple Developer account is signed into Xcode**
(`security find-identity -v -p codesigning` reports 0 identities and there are no
provisioning profiles). Step 1 is therefore the blocker for everything else.

---

## 0. Xcode 26 or later

Since **28 April 2026**, App Store Connect refuses uploads built with anything
older than Xcode 26 and the iOS 26 SDK, TestFlight included. This app was last
built locally for the iOS 18.5 simulator, the newest one Xcode 16.4 ships, so
check which Xcode that Mac has before archiving.

1. `xcodebuild -version` must print **Xcode 26** or later.
2. If not, update Xcode. Any 26.x release is accepted: Xcode 26.0 to 26.3 run on
   macOS Sequoia 15.6 or later, and Xcode 26.4.1 onwards needs macOS Tahoe 26.2.
   Older releases are at <https://developer.apple.com/download/all/>.

GitHub Actions already builds every push with Xcode 26
(`.github/workflows/ci.yml`), so a green run there means the code itself is
ready; this step is only about the Mac you archive from.

## 1. Apple Developer Program — $99/year

Required, and not optional here: **both** CloudKit and TestFlight need the paid
program. A free Apple ID cannot provision an iCloud container.

1. Enrol at <https://developer.apple.com/programs/enroll/> (Apple ID + 2FA).
   Individual enrolment is usually instant, occasionally 24–48 h.
2. In Xcode: **Settings → Accounts → +** and sign in with that Apple ID.
3. Open `Flaunedex.xcodeproj` → target **Flaunedex** → **Signing & Capabilities**
   → tick *Automatically manage signing* and pick your Team.

After this, `security find-identity -v -p codesigning` should list an
*Apple Development* identity.

> The project sets `DEVELOPMENT_TEAM: ""` in `project.yml`. Once you know your
> 10-character Team ID you can paste it there so `xcodegen generate` keeps the
> setting; otherwise just re-pick the team in Xcode after regenerating.

## 2. Create the iCloud container

The entitlements file already asks for `iCloud.com.taddeocarpinelli.flaunedex`.

1. **Signing & Capabilities → + Capability → iCloud**, tick **CloudKit**.
2. In the containers list, tick (or create) `iCloud.com.taddeocarpinelli.flaunedex`.
3. Leave **Push Notifications** and **Background Modes → Remote notifications** on
   when they appear. They come from the entitlements and `Info.plist`, and are how
   CloudKit tells the app about changes made on another device.

## 3. Populate the Development schema

CloudKit builds its schema from what the app actually saves — it starts empty.

1. Sign the **simulator or device** into an iCloud account
   (Réglages → *Se connecter à l'iPhone*).
2. Run the app from Xcode.
3. In **Réglages** inside the app, confirm it now reads **"Sauvegarde iCloud
   active"**. If it says *"iCloud non connecté"*, the device isn't signed in and
   nothing will sync.
4. Capture at least one sighting **and save at least one recipe** (or run with
   `-seedSampleData`, which creates both) so that all three record types get
   created: `CD_Species`, `CD_Sighting` and `CD_Recipe`.

Do this on the **iPhone**, with your Gemini key pasted into Réglages, and make
the sighting a real scan and the recipe a real request. The camera only works on
a device, and these are the first two Gemini calls the app will ever make
against the real API: everything around them is tested, the calls themselves
are not. If a scan fails, that is the place to look before uploading anything.

## 4. Deploy the schema to Production ⚠️

**This is the step that silently breaks TestFlight if skipped.** TestFlight and
App Store builds talk to the **Production** CloudKit environment; a schema that
only exists in Development simply isn't there for them.

1. Open <https://icloud.developer.apple.com/dashboard/>.
2. Select the container `iCloud.com.taddeocarpinelli.flaunedex`.
3. **Schema → Indexes / Record Types** — check `CD_Species`, `CD_Sighting` and
   `CD_Recipe` are listed under *Development*.
4. Click **Deploy Schema Changes…** → review → **Deploy to Production**.

Re-do this **any time the SwiftData models change** (new field, new entity).

## 5. TestFlight

Internal testing needs **no App Review**.

1. Create the app record in App Store Connect (same bundle id).
2. Xcode → **Product → Archive** → **Distribute App → App Store Connect →
   Upload**.
3. In App Store Connect → **TestFlight** → add yourself to **Internal Testers**.
4. Install TestFlight on the iPhone, signed in with the same Apple ID.

Processing takes minutes to about an hour.

### Keep it alive

- **TestFlight builds expire 90 days after upload.** Re-upload (bumping
  `CURRENT_PROJECT_VERSION`) about every 80 days. Set a reminder.
- The $99 membership renews annually; if it lapses, distribution stops.

`ITSAppUsesNonExemptEncryption` is already set to `false` in `App/Info.plist`, so
you won't be blocked by the export-compliance question.

---

## Sanity checks

| Check | Where |
|---|---|
| Xcode new enough to upload | `xcodebuild -version` → 26 or later |
| Code builds with Xcode 26 | GitHub → **Actions** → latest *CI* run is green |
| Signing identity exists | `security find-identity -v -p codesigning` |
| iCloud actually syncing | app → **Réglages** → *Sauvegarde* row |
| Schema deployed | CloudKit Console → Schema → **Production** tab |
| Build not expired | App Store Connect → TestFlight |

If the app ever shows **"iCloud non connecté"** or **"Stockage local
uniquement"**, it is still fully usable — sightings are saved on the device and
simply aren't backed up. The app no longer crashes when CloudKit is unavailable.
