# RI Network Speed

**A real-time network speed monitor for iPhone, built entirely with SwiftUI.**

RI Network Speed reads live byte counters directly from the system's network interfaces and turns them into a clean, always-up-to-date dashboard — no third-party SDKs, no backend of its own.

---

## Features

### Live Speed Dashboard
- Real-time download and upload speeds, updated every second (0.5 s, 1 s or 2 s in Settings)
- Separate readouts for Wi-Fi (`en0`) and Cellular (`pdp_ip0`)
- Smooth chart rendered entirely on the GPU via SwiftUI `Canvas` + `drawingGroup()` — no scroll jank
- Graph tab covers 60 s to 30 min from memory, and 24 h / 7 days from per-minute summaries saved on disk (only the time the app was open, since iOS does not allow background measurement)
- Connection details: IP address, gateway, DNS, Wi-Fi name and security type
- iOS does not give apps the Wi-Fi signal strength (RSSI) or frequency band, so the app does not show them

### Speed Test
- Full ping → download → upload pipeline powered by Cloudflare's public speed endpoints
- Time-boxed phases (10 s download, 8 s upload) with parallel streams; the first 2 s are excluded so TCP slow start does not drag the result down
- Every result is kept (no cap) in a JSON file, with connection type, Wi-Fi name, provider and jitter
- History screen with a trend chart, averages and filters by connection type and time range
- A 0–100 score, a letter grade and a plain summary of what the connection handles (4K streaming, video calls, gaming…); the share card and PDF use the same grading
- The provider name comes from `speed.cloudflare.com/meta`, the same service the test uses

### Ping Monitor
- Continuous latency, jitter and packet-loss tracking with a live graph
- Latency is the TCP handshake time to port 443 of the chosen host (one network round trip, no TLS or server time)

### Data Usage
- Today's, weekly and monthly usage for Wi-Fi and Cellular
- Cellular data limit tied to a monthly billing period with a configurable reset day
- Exportable PDF reports

### Internet Plan and ISP Report
- Enter the speeds your provider advertises (Settings → Internet Plan)
- Test History compares results with the plan (average share of the plan, tests reaching 80 %)
- A printable PDF report for complaints to your provider, built from the tests shown with the current filters

### Per-Network History
- Each test records the Wi-Fi name (with location access), so Test History lists every network with its own averages and can filter by network

### Network Tools
- **Troubleshooter:** checks the network, router, DNS, internet access (including hotel and café login pages) and latency, then explains the first problem in plain language
- **IP Scanner** remembers the devices on each network and marks devices that were not there in the previous scan. iOS hides MAC addresses, so devices are matched by name or last IP address
- **Wi-Fi Survey:** name rooms, run a speed test in each and see the best and weakest spots
- **Subnet Calculator** and **Wake-on-LAN** (sending the packet needs Apple's multicast networking entitlement; see below)
- Favorite hosts for Ping, Traceroute, Port Scanner, DNS, SSL and Whois, and a share button on every tool to share or copy its results as text

### Accessibility, Languages and Appearance
- Every text scales with Dynamic Type; side-by-side cards stack at accessibility sizes
- VoiceOver labels for the speed cards, gauge, charts and results
- English and Turkish via String Catalogs (`Localizable`, `InfoPlist`, `AppShortcuts` and the widget's catalog), including Siri phrases
- System, light or dark appearance (Settings → General); flat colors only, no gradients

### Live Activity & Dynamic Island
- Real-time download/upload speeds shown in the Dynamic Island and Lock Screen
- A dedicated 1 Hz ActivityKit timer prevents stale updates without overwhelming the system
- Push-token support for server-side updates; falls back to local-only if unavailable
- Graceful background handling: the app requests a background task on suspension and tears down cleanly after a 25 s grace period

### Widgets and Control
- **Speed widget:** small and medium Home Screen sizes (also in StandBy), plus circular, rectangular and inline Lock Screen sizes, showing the last speed test
- **Data Usage widget:** cellular usage against the monthly limit as a ring or bar, or today's usage when no limit is set
- Both read a shared `UserDefaults` App Group and follow the light or dark appearance
- Widgets cannot measure live; the app reloads them after every speed test and when it goes to the background
- A "Start Speed Test" control for Control Center, the Lock Screen and the Action button
- Tapping the widget or the control opens the app and starts a test (`rinetworkspeed://speedtest`)

### Notifications
- Disconnect alerts
- Speed drop alerts when a speed test is less than half of your recent typical result
- Speed peak alerts above a configurable threshold
- Cellular data limit warnings, once per billing period
- Notification actions open the relevant screen (Usage, Graph or a new speed test)
- iOS does not let the app run continuously in the background, so live alerts fire only while the app is open or shortly after it is backgrounded

---

## Architecture

```
rinetworkspeed/          ← iOS app target
├── NetworkStats.swift       Core monitor: reads getifaddrs(3), drives Live Activity
├── SpeedTestManager.swift   Adaptive speed test pipeline (ping → download → upload)
├── PingMonitor.swift        Continuous latency tracking
├── DataUsageMonitor.swift   Cumulative byte counters per interface
├── WiFiInfoManager.swift    SSID, security type, IP helpers
├── NotificationManager.swift Disconnect / speed / data limit alerts and action routing
├── AppRouter.swift          Deep links, widget and notification navigation
├── WidgetSharedStore.swift  Values shared with the widget extension
├── SpeedTestHistoryStore.swift  Unlimited speed test history (JSON file)
├── SpeedTestScoring.swift   Score, grade and use-case summary
├── SpeedHistoryArchive.swift  Per-minute live speed summaries for 24 h / 7 days
├── ConnectionContext.swift  Connection type, Wi-Fi name and provider for a test
├── InternetPlan.swift       Advertised plan and comparison with results
├── ISPReportGenerator.swift Printable ISP report PDF
└── NetworkTools/            Troubleshooter, scanners, survey, subnet calculator, Wake-on-LAN…
├── PurchaseManager.swift    StoreKit subscription management
└── *View.swift              SwiftUI screens

NetworkWidget/           ← WidgetKit extension (status widget, control, Live Activity)
NetworkSpeedWatch/       ← planned watchOS app, not part of the build (see its README)
```

**Data flow**

```
getifaddrs(3) → NetworkStatsMonitor (1 Hz by default)
    ├─► SwiftUI views (Combine / @Published)
    └─► ActivityKit (1 Hz dedicated timer)

SpeedTestManager / DataUsageMonitor → UserDefaults App Group → WidgetKit extension
```

---

## Requirements

| Component | Minimum |
|-----------|---------|
| iOS       | 18.0    |
| Xcode     | 26.0    |
| Swift     | 5 language mode |

The Liquid Glass tab bar behaviour is used on iOS 26 and later; earlier versions fall back to a material tab bar.

---

## Getting Started

```bash
git clone https://github.com/erayideall/rinetworkspeed.git
cd rinetworkspeed
open rinetworkspeed.xcodeproj
```

1. Select your development team in **Signing & Capabilities** for both targets (`rinetworkspeed`, `NetworkWidgetExtension`).
2. Update the App Group identifier (`group.rinetworkspeedapp`) in both entitlements files and in `WidgetSharedStore.swift` / `NetworkStatusWidget.swift` if you use a different bundle-ID prefix.
3. Build and run on a real device — the simulator does not expose live network interface counters.
4. Wake-on-LAN sends a UDP broadcast, which iOS only allows once Apple grants the `com.apple.developer.networking.multicast` entitlement. Request it from Apple, then add it to `rinetworkspeed.entitlements`; until then the tool explains that the broadcast was blocked.

> **Note:** The speed test uses Cloudflare's public endpoints (`speed.cloudflare.com`). No API key is required.

---

## Privacy

RI Network Speed has no analytics, no tracking and no backend of its own. Usage counters and test history stay on the device. It does make these network requests:

- **Speed tests** to `speed.cloudflare.com`, when you start a test.
- **Ping** TCP connections to the host you choose in the Ping Monitor (default `1.1.1.1`).
- **Provider name** from `speed.cloudflare.com/meta` during a speed test, to label the result in history.
- **Troubleshooter** loads Apple's connectivity test page (`www.apple.com/library/test/success.html`), looks up `www.apple.com` and opens TCP connections to your router and `1.1.1.1`.
- **Public IP and ISP lookup** to `api.ipify.org` and `ipapi.co` when the Speed Test screen opens and location permission is granted (for the Wi-Fi details section). These services receive your public IP address, as every web request does, and return your public IP and provider name.

Network tools (port scanner, traceroute, DNS lookup, SSL checker) contact the hosts you enter; WHOIS lookups go through `who-dat.as93.net`; the IP scanner and network map only probe your local network.

Tools that reach devices on your network (IP scanner, network map, troubleshooter) trigger the iOS Local Network permission prompt.

The app and the widget extension each ship a `PrivacyInfo.xcprivacy` manifest declaring the required-reason APIs they use (UserDefaults, system boot time).

---

## Pro Features & Paywall

The freemium layer is implemented with a `ProGateModifier` view modifier and a `PurchaseManager` (StoreKit 2). Gated features include: Speed Test, Ping Monitor, Widgets & Live Activity, Smart Notifications, History Reports, and Data Limit alerts.

To work on gated screens without a purchase in a Debug build, add `-forceProAccess YES` to the scheme's launch arguments. Release builds always use the real StoreKit entitlements. To test purchases, use a StoreKit configuration file with the product IDs from `PurchaseManager.swift`.

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
