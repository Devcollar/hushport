# HushPort beta release checklist

Use this for `v0.1.0-beta.1` (first public beta).

## Prerequisites (one-time)

### Apple Developer

- [ ] **Developer ID Application** certificate (Mac DMG — not the same as “Apple Development”)
  - [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) → **+** → **Developer ID Application**
  - Download and double-click to install in Keychain
- [ ] App ID `com.devcollar.hushport` registered (iOS)
- [ ] App ID `com.devcollar.hushport.mac` registered (Mac helper app)
- [ ] App ID `com.devcollar.hushport.audio` registered (HAL plugin)

### App Store Connect (iOS TestFlight)

- [ ] New app: **HushPort**, bundle ID `com.devcollar.hushport`
- [ ] Privacy policy URL: `https://devcollar.github.io/hushport/privacy.html`
- [ ] Category: Utilities (or Entertainment)

---

## Part A — Mac DMG (`v0.1.0-beta.1`)

### 1. Version numbers (Xcode)

Target **HushPortMacApp** and **HushPortAudioPlugin**:

- **Marketing Version:** `0.1.0`
- **Build:** `1` (increment for each upload)

### 2. Archive

1. Open `HushPort.xcodeproj`
2. Scheme: **HushPortMacApp** → **Any Mac**
3. **Product → Archive** (Release)
4. In Organizer → **Distribute App** → **Direct Distribution** (or “Copy App” / Developer ID)
5. Sign with **Developer ID Application** (team Devcollar)

### 3. Export app

Export to a folder, e.g. `~/Desktop/HushPort-0.1.0-beta.1/`

You should get `HushPort.app`.

### 4. Notarize

```sh
# Zip for notarytool (Apple expects a zip or dmg)
ditto -c -k --keepParent HushPort.app HushPort.zip

xcrun notarytool submit HushPort.zip \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id V2HN22942W \
  --password "APP-SPECIFIC-PASSWORD" \
  --wait

# After Accepted:
xcrun stapler staple HushPort.app
```

Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.

Or run `./Scripts/release-mac.sh 0.1.0-beta.1` (requires `brew install create-dmg`).

### 6. Notarize DMG (recommended)

```sh
xcrun notarytool submit HushPort-0.1.0-beta.1.dmg \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id V2HN22942W \
  --password "APP-SPECIFIC-PASSWORD" \
  --wait

xcrun stapler staple HushPort-0.1.0-beta.1.dmg
```

### 7. GitHub Release

1. [github.com/Devcollar/hushport/releases/new](https://github.com/Devcollar/hushport/releases/new)
2. Tag: `v0.1.0-beta.1`
3. Title: `HushPort 0.1.0 beta 1 (Mac)`
4. Attach the **stapled DMG**
5. Release notes (minimum):

```markdown
## Mac beta — first public build

**Requirements:** macOS 14+, same Wi‑Fi as your iPhone.

1. Open the DMG and drag **HushPort** to Applications.
2. Open HushPort from Applications (approve in Privacy & Security if prompted).
3. Click **Install or Update HushPort Audio** → restart Mac.
4. Set **System Settings → Sound → Output → HushPort**.
5. Pair iPhone via QR code.

iPhone: TestFlight link coming soon — build from source until then.

Known: manual iPhone IP may be needed after Wi‑Fi changes. See [install guide](https://devcollar.github.io/hushport/install.html).
```

### 8. Smoke test (clean Mac if possible)

- [ ] DMG opens, app launches without Gatekeeper block
- [ ] HAL install + restart works
- [ ] HushPort appears in Sound output
- [ ] Stream works with iPhone (Xcode or TestFlight build)

---

## Part B — iOS TestFlight

### 1. Version numbers

Target **HushPortIOSApp**:

- **Marketing Version:** `0.1.0`
- **Build:** `1`

### 2. Archive & upload

1. Scheme: **HushPortIOSApp** → your **iPhone** or **Any iOS Device**
2. **Product → Archive**
3. Organizer → **Distribute App** → **App Store Connect** → Upload
4. Wait for processing in App Store Connect (often 5–30 min)

### 3. TestFlight setup

1. App Store Connect → **HushPort** → **TestFlight**
2. Fill **Beta App Description** and **What to Test**
3. **Export Compliance:** typically “No” for custom encryption (local UDP audio only — confirm with your legal comfort)
4. **External Testing** → create group → add build → submit for Beta App Review (first external build)
5. Enable **Public Link** when approved

### 4. Update website (after link works)

- `docs/index.html` — replace “TestFlight soon” with the public link
- `docs/install.md` — paste the TestFlight URL

---

## Part C — Friend beta (before Reddit/HN)

- [ ] 5–10 people install Mac DMG + TestFlight
- [ ] Collect issues via [GitHub Issues](https://github.com/Devcollar/hushport/issues/new/choose)
- [ ] Fix top 2–3 install/stream blockers → `v0.1.0-beta.2` if needed

---

## Quick commands

```sh
# Verify signing identity (need Developer ID for Mac release)
security find-identity -v -p codesigning

# Verify staple
xcrun stapler validate HushPort.app
```
