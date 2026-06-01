# RI Network Speed

**A real-time network speed monitor for iPhone and Apple Watch, built entirely with SwiftUI.**

RI Network Speed reads live byte counters directly from the system's network interfaces and turns them into a clean, always-up-to-date dashboard — no third-party SDKs, no background servers.

---

## Features

### Live Speed Dashboard
- Real-time download and upload speeds, updated every 0.5 s (configurable)
- Separate readouts for Wi-Fi (`en0`) and Cellular (`pdp_ip0`)
- Smooth Catmull-Rom spline chart rendered entirely on the GPU via SwiftUI `Canvas` + `drawingGroup()` — no scroll jank
- Connection details: IP address, Wi-Fi RSSI, and live latency

### Speed Test
- Full download → upload pipeline powered by Cloudflare's public speed endpoints
- Adaptive file size: a 1 MB probe measures your line speed first, then selects a download target (10 MB – 200 MB) and upload target (5 MB – 100 MB) for an accurate ~10 s test
- Rolling 2-second average window for smooth, jitter-free speed readings
- Persistent history (last 10 results) stored in `UserDefaults`

### Ping Monitor
- Continuous latency and packet-loss tracking with a live graph

### Data Usage
- Per-session and today's cumulative usage for Wi-Fi and Cellular
- Exportable PDF reports

### Live Activity & Dynamic Island
- Real-time download/upload speeds shown in the Dynamic Island and Lock Screen
- A dedicated 1 Hz ActivityKit timer prevents stale updates without overwhelming the system
- Push-token support for server-side updates; falls back to local-only if unavailable
- Graceful background handling: the app requests a background task on suspension and tears down cleanly after a 25 s grace period

### Home Screen Widgets
- Small and medium WidgetKit widgets reading speeds from a shared `UserDefaults` App Group
- Auto-refreshes every 15 minutes; the main app triggers an early reload whenever speeds change

### Apple Watch Companion
- Glanceable speed readout on the watch face
- Digital Crown switches between Download and Upload views with haptic feedback
- Shows today's Wi-Fi and Cellular data usage
- Tap to bring the iPhone app to the foreground via WatchConnectivity

### Smart Notifications
- Alerts for speed drops below a configurable threshold
- Alerts for speed peaks above a configurable threshold
- Disconnect / reconnect notifications

---

## Architecture

```
rinetworkspeed/          ← iOS app target
├── NetworkStats.swift       Core monitor: reads getifaddrs(3), drives Live Activity
├── SpeedTestManager.swift   Adaptive speed test pipeline (ping → download → upload)
├── PingMonitor.swift        Continuous latency tracking
├── DataUsageMonitor.swift   Cumulative byte counters per interface
├── WiFiInfoManager.swift    SSID, RSSI, IP helpers
├── NotificationManager.swift Speed-drop / peak / disconnect alerts
├── WatchConnectivityManager.swift  Pushes live speeds to the watch
├── PurchaseManager.swift    StoreKit subscription management
└── Views/                   SwiftUI screens

NetworkWidget/           ← WidgetKit extension
NetworkSpeedWatch/       ← watchOS companion app
```

**Data flow**

```
getifaddrs(3) → NetworkStatsMonitor (0.5 Hz)
    ├─► SwiftUI views (Combine / @Published)
    ├─► UserDefaults App Group → WidgetKit extension
    ├─► ActivityKit (1 Hz dedicated timer)
    └─► WatchConnectivity → watchOS app
```

---

## Requirements

| Component | Minimum |
|-----------|---------|
| iOS       | 16.1    |
| watchOS   | 9.0     |
| Xcode     | 15.0    |
| Swift     | 5.9     |

Live Activities and Dynamic Island require a device running **iOS 16.2+**.

---

## Getting Started

```bash
git clone https://github.com/erayideall/rinetworkspeed.git
cd rinetworkspeed
open rinetworkspeed.xcodeproj
```

1. Select your development team in **Signing & Capabilities** for all three targets (`rinetworkspeed`, `NetworkWidget`, `NetworkSpeedWatch`).
2. Update the App Group identifier (`group.com.rinetworkspeed`) in the entitlements files if you use a different bundle-ID prefix.
3. Build and run on a real device — the simulator does not expose live network interface counters.

> **Note:** The speed test uses Cloudflare's public endpoints (`speed.cloudflare.com`). No API key is required.

---

## Privacy

RI Network Speed reads **only local system counters** (`getifaddrs`) and makes outbound connections solely for:
- Latency measurement (TCP connect to `8.8.8.8:53`)
- Speed tests initiated explicitly by the user (`speed.cloudflare.com`)

No analytics, no tracking, no data leaves the device without user action.

---

## Pro Features & Paywall

The freemium layer is implemented with a `ProGateModifier` view modifier and a `PurchaseManager` (StoreKit). Gated features include: Speed Test, Ping Monitor, Widgets & Live Activity, Apple Watch, Smart Notifications, History Reports, and Data Limit alerts.

To build and test without a paid subscription, set `PurchaseManager.shared.isPro = true` in `rinetworkspeedApp.swift` during development.

---

## Contributing

Pull requests are welcome. Please open an issue first to discuss major changes.

1. Fork the repo and create a feature branch.
2. Follow the existing SwiftUI / Combine patterns — no third-party dependencies.
3. Test on a physical device before submitting.

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

*Created by [Eray Koçer](https://github.com/erayideall)*
