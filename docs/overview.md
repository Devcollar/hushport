# HushPort — Overview

## What is HushPort?

**HushPort** lets you hear your Mac's audio through earphones connected to your iPhone — over local Wi‑Fi, with no cloud.

Use cases:

- Mac speakers are off; you want private listening on AirPods or wired earphones
- You're at a desk with a Mac but prefer phone earbuds
- You want Mac system audio (YouTube, calls, music) on your phone without cables between the devices

**Pair once, then stream.** The Mac captures system audio, sends it to the iPhone, and the iPhone plays it in real time.

---

## How it works (user perspective)

### One-time setup

1. **Mac** — Open HushPort, show the QR code and 6-digit pairing code
2. **iPhone** — Scan the QR code (or enter code + Mac IP manually)
3. **Mac** — Install the **HushPort Audio** HAL plugin, restart if needed
4. **macOS** — Set **System Settings → Sound → Output → HushPort**

### Daily use

1. **iPhone** — Open HushPort → **Start Listening** (auto-starts when paired)
2. **Mac** — **Stream Mac audio** (menu bar or main window)
3. Audio plays on the iPhone (speaker or earphones)

### Controls

| Control | Where | What it does |
|--------|--------|----------------|
| Stream / Stop | Mac | Start or stop sending audio |
| Mute | Mac | Sends silence; iPhone keeps connection |
| Start / Stop Listening | iPhone | Open or close the UDP receiver |
| Forget pairing | Either | Clears trust; pair again with QR |

Both devices must be on the **same Wi‑Fi** (not guest/isolated networks). If auto-discovery fails, enter the iPhone's IP manually on the Mac (shown in the iPhone app as **This iPhone: …**).

---

## Architecture overview

HushPort is a **two-app system** plus a **Mac audio driver**:

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS (Sender)                          │
│                                                                 │
│  System Audio ──► HushPort HAL Plugin ──► Ring Buffer           │
│                         │                                       │
│                         ▼                                       │
│              SharedAudioCapture (read PCM)                      │
│                         │                                       │
│                         ▼                                       │
│              MacSessionController (5ms pacing)                  │
│                         │                                       │
│                         ▼                                       │
│              UDPAudioSender ──────────────┐                     │
│              ControlChannelSender (ping) ─┼──► Wi‑Fi LAN        │
└───────────────────────────────────────────┼─────────────────────┘
                                            │
┌───────────────────────────────────────────┼─────────────────────┐
│                        iOS (Receiver)     ▼                     │
│                                                                 │
│              UDPAudioReceiver (port 49200) ◄── UDP audio          │
│              ControlChannelReceiver (49201) ◄── control msgs      │
│                         │                                       │
│                         ▼                                       │
│              AdaptivePlaybackBuffer (jitter + prebuffer)        │
│                         │                                       │
│                         ▼                                       │
│              IOSAudioPlaybackEngine (AVAudioEngine)             │
│                         │                                       │
│                         ▼                                       │
│                   iPhone speaker / earphones                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technical deep dive

### Platforms and modules

| Component | Target | Role |
|-----------|--------|------|
| `HushPortMac` | macOS 14+ | Sender UI, menu bar, session control |
| `HushPortIOS` | iOS | Receiver UI, playback |
| `HushPortCore` | Shared Swift | Protocol, networking, buffering, pairing |
| `HushPortAudioPlugin` | macOS HAL | Virtual audio output device |
| `HushPortRingBuffer` | C | Lock-free ring buffer between HAL and app |

**Bundle IDs**

- iOS: `com.devcollar.hushport`
- macOS: `com.devcollar.hushport.mac`
- HAL plugin: `com.devcollar.hushport.audio`

---

### Audio capture (Mac)

1. **HAL plugin** (`HushPortAudioPlugin`) registers as a Core Audio output device named "HushPort".
2. When macOS routes audio to HushPort, the driver writes **interleaved stereo float32** into a **shared ring buffer** (`HushPortSharedAudio`).
3. **`SharedAudioCapture`** reads 240 frames per packet, converts float32 → **int16 PCM**, and passes payloads to the send loop.
4. If a read misses briefly, the sender **repeats the last good packet** instead of sending silence.

**Audio format**

| Parameter | Value |
|-----------|--------|
| Sample rate | 48 kHz |
| Channels | Stereo (2) |
| Bit depth | 16-bit signed PCM |
| Frames per packet | 240 |
| Packet duration | **5 ms** |
| Payload size | **960 bytes** per packet |

---

### Network transport

**Protocol:** Custom framed UDP (not RTP).

**Ports**

| Port | Purpose |
|------|---------|
| `49200` | Audio stream |
| `49201` | Control channel (pairing, ping/pong, mute) |

**Discovery:** Bonjour service `_hushport._udp` — iPhone advertises while listening; Mac browses for nearby receivers.

**Audio packet format** (`AudioPacket`, magic `PHSD`):

- 28-byte header: magic, version, stream ID, sequence number, capture timestamp, payload length
- Payload: 960 bytes PCM

**Sending (Mac):** `NWConnection` UDP to iPhone IP:49200. The send loop is **clock-paced at 5 ms per packet** (~200 packets/sec).

**Receiving (iPhone):** `NWListener` on UDP 49200; each datagram is handled as an incoming connection by the receiver.

**Control messages:** JSON over UDP (`ControlMessage`) — `pairRequest`, `pairAccept`, `ping`, `pong`, `mute`, `unmute`, `unpair`. Pings carry each device's current LAN IP for address refresh after Wi‑Fi changes.

**Target resolution:** Mac picks iPhone IP via Bonjour resolve → ping/pong verify → saved paired address → manual IP.

---

### Playback pipeline (iPhone)

1. **`UDPAudioReceiver`** ingests packets into an async stream.
2. **`AdaptivePlaybackBuffer`**:
   - **Prebuffer:** ~12 packets (~60 ms) before playback starts
   - **Jitter buffer:** ordered by sequence; handles reorder, duplicates, gaps
   - **Packet-loss concealment:** repeat last good packet up to 3×, then skip gap
   - **Latency trim:** if backlog stays high for 3+ seconds, drop oldest packets to limit drift on long sessions
3. **`IOSAudioPlaybackEngine`**:
   - `AVAudioSession` category `.playback`
   - `AVAudioEngine` + `AVAudioPlayerNode`
   - int16 → float32 conversion, sequential buffer scheduling
   - Dynamic schedule-ahead (8–18 buffers) based on queue depth

**Background:** iOS `audio` background mode keeps playback alive when the app is backgrounded.

---

### Pairing and trust

1. Mac generates a **6-digit code** and **QR** (`hushport://pair?...` via `PairingPayload`).
2. iPhone scans QR → sends `pairRequest` to Mac control port.
3. Mac checks code → `pairAccept` / `pairReject`.
4. Both sides store a **`TrustedDevice`** (UUID, name, network address) in `UserDefaults`.
5. Reconnect uses saved trust + Bonjour + ping/pong; no QR needed after first pair.

**Security today:** Local network only, no encryption on the wire (planned for a future milestone). Suited for trusted home Wi‑Fi.

---

### Resilience features

| Feature | Behavior |
|---------|----------|
| Wi‑Fi change | iPhone restarts listener; Mac reconnects with fresh IP |
| Stale IP | Bonjour + ping/pong + explicit IP in control messages |
| Mini dropouts | Jitter buffer + PLC (concealment) |
| Long-session drift | Latency trim + adaptive schedule-ahead |
| Mac mute | Sends silence packets; connection stays up |

---

### Mac app UX

- **Menu bar app** with stream / mute / disconnect
- **Main window:** pairing, discovery status, manual IP, packet counter, audio plugin installer
- **Test tone:** 440 Hz sine for debugging without system audio routing

---

### Build and development

```bash
swift test
open HushPort.xcodeproj
```

Schemes: `HushPortMacApp`, `HushPortIOSApp`. The HAL plugin is embedded in the Mac app and installed to `/Library/Audio/Plug-Ins/HAL/`.

**Permissions**

- iPhone: Camera (QR), Local Network (Bonjour), Background Audio
- Mac: Network client/server (no sandbox in debug)

---

### Current limitations

- **No encryption** on audio or control traffic
- **LAN only** — same Wi‑Fi; guest/isolated networks often block device-to-device traffic
- **Latency** — typically ~60–150 ms depending on Wi‑Fi; can creep on very long sessions (mitigated by trimming)
- **System audio** requires HushPort selected as Mac output — per-app routing is not supported
- **Not App Store distributed yet** — requires Xcode install / notarization for wider distribution

**Planned:** Encrypted sessions, on-screen latency display, stronger long-session sync, notarized distribution.

---

## License

Source is publicly available for inspection under a [proprietary license](../LICENSE). Copyright © 2026 Devcollar Private Limited.

---

### One-line pitch

> **HushPort turns your iPhone into a wireless speaker for your Mac** — pair over Wi‑Fi, route Mac system audio through a virtual output device, stream low-latency PCM over UDP, and listen on your phone.
