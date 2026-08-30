# HushPort

**Hear your Mac through your iPhone.** HushPort streams macOS system audio to your iPhone over local Wi‑Fi so you can listen on earphones — no cloud, no cables between the devices.

Your Mac. Your phone. Your earphones.

<table>
  <tr>
    <td width="50%" valign="top" align="center">
      <img src="docs/screenshots/mac-streaming.png" alt="HushPort Mac app streaming audio" width="100%" />
    </td>
    <td width="50%" valign="top" align="center">
      <img src="docs/screenshots/ios-streaming.png" alt="HushPort iOS app playing audio" width="70%" />
    </td>
  </tr>
</table>

---

## What it does

HushPort turns your iPhone into a wireless speaker for your Mac:

1. **Mac** captures system audio via a virtual output device (HushPort Audio).
2. **Mac** sends low-latency PCM audio to your iPhone over UDP on your LAN.
3. **iPhone** buffers and plays the stream on the built-in speaker or connected earphones.

Pair once with a QR code, then reconnect automatically on the same Wi‑Fi.

---

## Screenshots

### Pairing

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/mac-pairing-screen.png" alt="Mac pairing screen with QR code" width="100%" />
      <br /><sub><b>Mac</b> — QR code and 6-digit pairing code</sub>
    </td>
    <td width="50%" valign="top" align="center">
      <img src="docs/screenshots/ios-scan-qr.png" alt="iPhone scanning Mac QR code" width="70%" />
      <br /><sub><b>iPhone</b> — scan to pair securely</sub>
    </td>
  </tr>
</table>

### Ready to stream

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/screenshots/mac-device-paired.png" alt="Mac app after pairing" width="100%" />
      <br /><sub><b>Mac</b> — paired, Bonjour discovery, stream controls</sub>
    </td>
    <td width="50%" valign="top" align="center">
      <img src="docs/screenshots/ios-standby.png" alt="iPhone receiver on standby" width="70%" />
      <br /><sub><b>iPhone</b> — paired and ready; tap Start Listening</sub>
    </td>
  </tr>
</table>

### Streaming

<p align="center">
  <img src="docs/screenshots/macos-select-hushport-output.png" alt="macOS Sound menu with HushPort selected" width="70%" />
  <br /><sub>Select <b>HushPort</b> as the Mac audio output in the menu bar or System Settings</sub>
</p>

<p align="center">
  <img src="docs/screenshots/mac-streaming-details.png" alt="Mac app while streaming with packet counter" width="55%" />
  <br /><sub><b>Mac</b> — live stream status and packet counter</sub>
</p>

---

## Features

- **One-time pairing** — QR code or 6-digit code
- **Auto-reconnect** — saved trust + Bonjour discovery on relaunch
- **Menu bar controls** — stream, mute, disconnect from the Mac menu bar
- **Adaptive playback** — jitter buffer, packet-loss concealment, latency trim on iPhone
- **System audio capture** — Core Audio HAL virtual output (`HushPort Audio`)
- **Local network only** — UDP transport with sequenced packets; no cloud relay
- **Background playback** — iPhone keeps listening while the app is in the background
- **Manual fallback** — enter iPhone IP if Bonjour is blocked

---

## Quick start

### Requirements

- macOS 14+ (Apple Silicon or Intel)
- iOS 17+ (iPhone)
- Both devices on the **same Wi‑Fi** (not guest or client-isolated networks)
- Xcode 15+ to build from source

### First-time setup

1. Build and run **`HushPortMacApp`** on your Mac.
2. Build and run **`HushPortIOSApp`** on your iPhone.
3. On **Mac**, open HushPort and note the QR code under **Pair iPhone**.
4. On **iPhone**, scan the QR code (or use **Enter pairing details manually**).
5. On **Mac**, click **Install or Update HushPort Audio**, restart if prompted.
6. Set **System Settings → Sound → Output → HushPort** (or pick HushPort from the menu bar Sound menu).

### Daily use

1. Open **HushPort on iPhone** → tap **Start Listening** (auto-starts when paired).
2. On **Mac**, click **Stream Mac audio** (main window or menu bar).
3. Listen on your iPhone. Use **Mute** or **Stop** on the Mac when finished.

If discovery fails, enter the iPhone IP shown in the iOS app (**This iPhone: …**) under **Manual connection** on the Mac.

---

## How it works

| Layer | Details |
|-------|---------|
| **Audio** | 48 kHz stereo 16-bit PCM, 5 ms packets (960 bytes) |
| **Transport** | UDP port `49200` (audio), `49201` (control) |
| **Discovery** | Bonjour `_hushport._udp` |
| **Mac capture** | HAL plugin → shared ring buffer → paced send loop |
| **iPhone playback** | `AVAudioEngine` + adaptive jitter buffer |

For a full technical write-up, see **[docs/overview.md](docs/overview.md)**.

---

## Project structure

```
Sources/
  HushPortMac/          macOS sender app + menu bar
  HushPortIOS/          iOS receiver app
  HushPortCore/         Shared networking, protocol, buffering, pairing
  HushPortAudioPlugin/  Core Audio HAL virtual output
  HushPortRingBuffer/   C ring buffer between HAL and app
docs/
  overview.md           Architecture and protocol reference
  screenshots/          App screenshots
```

**Bundle IDs**

| Target | Bundle ID |
|--------|-----------|
| iOS | `com.devcollar.hushport` |
| macOS | `com.devcollar.hushport.mac` |
| HAL plugin | `com.devcollar.hushport.audio` |

---

## Development

```sh
swift test
open HushPort.xcodeproj
```

Run the **`HushPortMacApp`** scheme on your Mac and **`HushPortIOSApp`** on a physical iPhone (simulator cannot receive LAN audio streams from a Mac).

---

## Roadmap

- [ ] Encrypted audio and control sessions
- [ ] On-screen latency display
- [ ] Stronger long-session sync
- [ ] Notarized / App Store distribution

---

## Status

Early-stage project — built and tested on local Wi‑Fi. Expect rough edges on network changes, discovery, and very long sessions. Issues and contributions welcome once the repo is public.
