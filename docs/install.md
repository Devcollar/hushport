# Install HushPort (beta)

## Mac

1. Download the latest **`.dmg`** from [GitHub Releases](https://github.com/Devcollar/hushport/releases).
2. Open the DMG and drag **HushPort** to Applications.
3. Launch HushPort from Applications (approve in **System Settings → Privacy & Security** if macOS blocks the first open).
4. In the app, click **Install or Update HushPort Audio** and restart your Mac when prompted.
5. Set **System Settings → Sound → Output → HushPort** (or choose HushPort from the menu bar Sound menu).
6. Pair your iPhone using the QR code shown in the Mac app.

### Build from source (developers)

```sh
git clone https://github.com/Devcollar/hushport.git
cd hushport
open HushPort.xcodeproj
```

Run the **HushPortMacApp** scheme on your Mac.

## iPhone

### TestFlight (recommended for beta testers)

Install from the public TestFlight link: **https://testflight.apple.com/join/Smt218M1**

You need the [TestFlight app](https://apps.apple.com/app/testflight/id899247664) from the App Store. Open the link on your iPhone, tap **Accept** → **Install**.

### Build from source (developers)

1. Open `HushPort.xcodeproj` in Xcode.
2. Select your iPhone as the run destination.
3. Run the **HushPortIOSApp** scheme.
4. Trust the developer certificate on iPhone if needed (**Settings → General → VPN & Device Management**).

> The iOS Simulator cannot receive LAN audio streams from a Mac. Use a physical iPhone.

## Daily use

1. **iPhone** — Open HushPort → **Start Listening**
2. **Mac** — **Stream Mac audio**
3. Listen on your iPhone speaker or earphones

## Troubleshooting

- **0 packets on iPhone** — Confirm both devices are on the same Wi‑Fi (not guest network). Try manual iPhone IP under **Manual connection** on Mac.
- **No system audio** — Select **HushPort** as Mac sound output.
- **After Wi‑Fi change** — Tap **Stop Listening** → **Start Listening** on iPhone; stream again from Mac.

Report bugs: [GitHub Issues](https://github.com/Devcollar/hushport/issues/new/choose)
