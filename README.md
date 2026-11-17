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
- iOS does not give apps the Wi-Fi signal strength (RSSI) or frequency band. A one-time shortcut ("RiNetwork Wi-Fi Signal", built from Shortcuts' "Get Network Details") reads RSSI, noise, channel, Wi-Fi standard, link rates and BSSID on request and hands them back through `rinetworkspeed://wifi-signal?…`; the Wi-Fi details then show signal, SNR, band and access point changes

### Speed Test
- Full ping → download → upload pipeline powered by Cloudflare's public speed endpoints
- Time-boxed phases (10 s download, 8 s upload) with parallel streams; the first 2 s are excluded so TCP slow start does not drag the result down
- Every result is kept (no cap) in a JSON file, with connection type, Wi-Fi name, provider and jitter
- History screen with a trend chart, averages and filters by connection type and time range
- A 0–100 score, a letter grade and a plain summary of what the connection handles (4K streaming, video calls, gaming…); the share card and PDF use the same grading
- Latency under load (bufferbloat): latency is also measured on a separate connection while the download and upload run, and graded A–F by how much it rises over idle latency
- The provider name comes from `speed.cloudflare.com/meta`, the same service the test uses

### Ping Monitor
- Continuous latency, jitter and packet-loss tracking with a live graph
- Latency is the TCP handshake time to port 443 of the chosen host (one network round trip, no TLS or server time)
- On Wi-Fi the router is pinged at the same time and drawn as a second line; a "Wi-Fi or Provider?" section says whether a problem starts on the Wi-Fi or beyond the router (the troubleshooter uses the same check)

### Data Usage
- Today's, weekly and monthly usage for Wi-Fi and Cellular
- Cellular data limit tied to a monthly billing period with a configurable reset day
- Exportable PDF reports

### Internet Plan and ISP Report
- Test History shows the median speed by time of day and points out a large evening drop (a sign of congestion); the ISP report includes it
- Cellular tests record the radio technology (5G, 4G…) and, with location access, an approximate place (about 100 m) for a personal coverage map that stays on the device
- Enter the speeds your provider advertises (Settings → Internet Plan)
- Test History compares results with the plan (average share of the plan, tests reaching 80 %)
- A printable PDF report for complaints to your provider, built from the tests shown with the current filters

### Per-Network History
- Each test records the Wi-Fi name (with location access), so Test History lists every network with its own averages and can filter by network

### Network Tools
- **Troubleshooter:** checks the network, router, DNS, internet access (including hotel and café login pages) and latency, then explains the first problem in plain language
- **IP Scanner** remembers the devices on each network and marks devices that were not there in the previous scan. Besides the port sweep it identifies devices from what they announce: Bonjour service names and TXT records (model, and the MAC address on AirPlay devices), NetBIOS node status (Windows and Samba name and MAC), UPnP descriptions and web page titles, which also finds devices with no open port. iOS hides MAC addresses, so other devices are matched by name or last IP address. The Network Map uses the same identification
- **Wi-Fi Survey:** name rooms, run a speed test in each and see the best and weakest spots
- **Hidden Camera Check:** scans the Wi-Fi network for video stream (RTSP) and camera-maker ports, ONVIF discovery answers and devices that announce themselves as cameras, and explains what it can't see
- **Wi-Fi Safety:** encryption type, interception of secure connections (certificates not from a public root), DNS redirection of non-existent names, other visible devices and a different router under a known network name (evil twin)
- **DNS Benchmark:** compares the router/provider DNS with Cloudflare, Google, Quad9, AdGuard and OpenDNS, and sets the fastest public one up as encrypted DNS (DNS over HTTPS) with `NEDNSSettingsManager`
- **NAT Type:** STUN mapping behaviour (Open/Moderate or Strict, as consoles call it), carrier-grade NAT and double NAT
- **Streaming & Gaming:** plays Apple's public HLS test stream for 20 seconds (start-up time, buffering, quality reached) and measures latency to cloud regions where many game servers run
- **Wi-Fi Heatmap:** add a photo of a floor plan (or use a blank grid), tap where you stand and the app pings the router, optionally runs a 3-second download and reads the Wi-Fi signal there; the plan is coloured between the spots (router quality, download or signal), and with the router marked it suggests where a mesh point could go
- **Modem & Line:** reads the router over UPnP IGD (SSDP discovery with the multicast entitlement): DSL line rate, WAN address with a carrier-grade NAT / double NAT note, uptime, traffic counters and UPnP port mappings, and compares plan, line rate and recent Wi-Fi tests to say whether the line or the home network limits the speed. The last DSL reading also appears in the ISP report
- **Traceroute:** a real TTL-based trace (ICMP echo on an unprivileged ICMP socket) that keeps measuring loss and latency at every hop, shows each hop's network operator (ASN) and says where lasting loss starts: the Wi-Fi, the provider's access network, the provider or beyond it
- **Subnet Calculator** and **Wake-on-LAN** (uses Apple's multicast networking entitlement; see below)
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
├── GatewayResolver.swift    Default gateway from the kernel routing table
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
4. Wake-on-LAN sends a UDP broadcast, which iOS only allows with the `com.apple.developer.networking.multicast` entitlement. Apple granted it to this account on 2026-11-17 and it is declared in `rinetworkspeed/rinetworkspeed.entitlements`. If you build under another team, request it from Apple and enable it for your App ID, or remove the key; without it the tool explains that the broadcast was blocked.

> **Note:** The speed test uses Cloudflare's public endpoints (`speed.cloudflare.com`). No API key is required.

---

## Privacy

RI Network Speed has no analytics, no tracking and no backend of its own. Usage counters and test history stay on the device. It does make these network requests:

- **Speed tests** to `speed.cloudflare.com`, when you start a test.
- **Ping** TCP connections to the host you choose in the Ping Monitor (default `1.1.1.1`).
- **Provider name** from `speed.cloudflare.com/meta` during a speed test, to label the result in history.
- **Troubleshooter** loads Apple's connectivity test page (`www.apple.com/library/test/success.html`), looks up `www.apple.com` and opens TCP connections to your router and `1.1.1.1`.
- **Public IP and ISP lookup** to `api.ipify.org` and `ipapi.co` when the Speed Test screen opens and location permission is granted (for the Wi-Fi details section). These services receive your public IP address, as every web request does, and return your public IP and provider name.

Network tools (port scanner, traceroute, DNS lookup, SSL checker) contact the hosts you enter; WHOIS lookups go through `who-dat.as93.net`; traceroute looks up the network operator of each public hop address with Team Cymru's IP-to-ASN DNS service, queried through `cloudflare-dns.com`; the IP scanner and network map only probe your local network. Device identification only talks to devices on the local network (Bonjour, SSDP, NetBIOS on UDP 137 and their web pages). The DNS benchmark sends lookups to the public resolvers listed above, NAT Type sends STUN requests to `stun.l.google.com` and `stun.cloudflare.com`, Wi-Fi Safety opens HTTPS connections to apple.com, google.com and cloudflare.com, and Streaming & Gaming loads Apple's public test stream and connects to Amazon Web Services endpoints. Modem & Line talks only to the router (SSDP multicast and HTTP on the local network; `NSAllowsLocalNetworking` permits the plain-HTTP requests).

Tools that reach devices on your network (IP scanner, network map, troubleshooter) trigger the iOS Local Network permission prompt.

The app and the widget extension each ship a `PrivacyInfo.xcprivacy` manifest declaring the required-reason APIs they use (UserDefaults, system boot time).

---

## Pro Features & Paywall

> **During development every Pro feature is open to everyone** (`PurchaseManager.unlocksProForEveryone = true`). Set it to `false` before the App Store release.

The freemium layer is implemented with `ProFeature`, a `proGated(feature:)` view modifier, `ProLockedCard` and a `PurchaseManager` (StoreKit 2).

| Free | Pro |
|------|-----|
| Speed test and live speed | Widgets and Live Activity |
| Data usage (today, week, month) | Unlimited test history with trends, filters and per-network averages |
| The latest tests on the speed test screen | PDF usage report and ISP report |
| Ping Monitor | 24-hour and 7-day graphs |
| Connection troubleshooter | Advanced network tools (modem & line, NAT type, streaming & gaming, hidden camera check, Wi-Fi safety, DNS benchmark, IP scanner, network map, Wi-Fi survey, Wi-Fi heatmap, traceroute, port scanner, DNS, SSL, Whois, subnet calculator, Wake-on-LAN) |
| Notifications | Data limit alerts |

Tapping a locked feature opens the paywall with that feature listed first. The annual plan shows its saving against twelve monthly payments, and its free trial when the product has an introductory offer the user is eligible for (configured in App Store Connect). Widgets show an upgrade message to free users.

After a successful, good speed test (grade C or better) the app may ask for an App Store rating: only after three successful tests, at most once per app version and at least 120 days apart (`ReviewPromptPolicy`).

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
