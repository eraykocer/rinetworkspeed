# RI Network Speed — Improvement Roadmap

**Status: Phases 0–3 complete (2026-11-13); Phase 4 planned (2026-11-17).** Phases 0–3 are implemented. Scheduled speed tests were dropped by decision. Apple granted the multicast networking entitlement on 2026-11-17; it is declared in the app's entitlements, and Wake-on-LAN still has to be tested on a device.

Based on a full review of the codebase on 2026-11-12 (about 12k lines of Swift).

## Before release

- [ ] Set `PurchaseManager.unlocksProForEveryone` to `false`: since 2026-11-17 every Pro feature is open to everyone in all builds while the Phase 4 features are tested.
- [ ] Test Wake-on-LAN and the SSDP search of Modem & Line on a device with the multicast entitlement enabled for the App ID.
- [ ] Publish the "RiNetwork Wi-Fi Signal" shortcut to iCloud and set `WiFiSignalStore.shortcutShareURL`.
- [ ] Enable Network Extensions → DNS Settings for the App ID (Xcode: Signing & Capabilities), or remove the `networkextension` entitlement; the DNS Benchmark's encrypted DNS needs it.
- [ ] Verify Apple's HLS test stream URL in `VideoStreamProbe.streamURL`.

The foundation is solid: the speed test engine, the design system and the network tool set are in good shape. The main problem to solve before adding features is that the app promises several things it does not actually do. The plan is therefore split into four phases, and Phase 0 comes first.

## Phase 0 — Trust and correctness

Status: implemented on 2026-11-12. Decisions: 0.3 removed the Apple Watch promise (sources kept, not built), 0.4 added speed drop alerts and dropped the daily summary, 0.5 binds the limit to cellular usage in the billing period, 0.10 lowered the target to iOS 18.0.

| # | Problem | Where | Action |
|---|---|---|---|
| 0.1 | Wi-Fi signal strength (dBm) and frequency band are not measured. They are guessed from throughput (for example ≥120 → "-45 dBm, 6 GHz"). | [WiFiInfoManager.swift](rinetworkspeed/WiFiInfoManager.swift#L265-L298) | Remove the rows if real data is unavailable, or label them "Estimated quality". |
| 0.2 | The home screen widget was deleted. The Control widget is still the Xcode template ("Start Timer"). | [NetworkWidgetControl.swift](NetworkWidget/NetworkWidgetControl.swift) | Rewrite the widgets. Turn the Control into "Start speed test". |
| 0.3 | Apple Watch source files exist, but the Xcode project has no watch target. | [NetworkSpeedWatch/](NetworkSpeedWatch/) | Add the target, or remove the promise from onboarding and the paywall. |
| 0.4 | Onboarding promises "speed drop" and "daily data summary" notifications. Only disconnect, data limit and speed peak exist. | [OnboardingView.swift](rinetworkspeed/OnboardingView.swift#L600-L609) | Implement those notifications or correct the copy. |
| 0.5 | The data limit is set up as monthly (it has a reset day) but is compared against today's usage. | [DataUsageMonitor.swift](rinetworkspeed/DataUsageMonitor.swift#L190-L194) | Compute the billing-period total and bind the limit and progress bar to it. |
| 0.6 | Ping sends an HTTPS HEAD on a new session every time, so the TLS handshake inflates the value. | [PingMonitor.swift](rinetworkspeed/PingMonitor.swift#L112-L141) | Reuse the session or measure TCP connect time. Add jitter. |
| 0.7 | `proAccessForced = true`: everyone is Pro and the paywall never runs. | [PurchaseManager.swift](rinetworkspeed/PurchaseManager.swift#L24) | Turn it off before release. Remove the unused RevenueCat package. |
| 0.8 | Notification actions (Retry, Review Usage) are declared but never handled. | [NotificationManager.swift](rinetworkspeed/NotificationManager.swift) | Add a `didReceive` handler and route to the relevant tab. |
| 0.9 | The README says no data leaves the device, but ipify and ipapi.co are called. There is no `PrivacyInfo.xcprivacy`. | [WiFiInfoManager.swift](rinetworkspeed/WiFiInfoManager.swift#L314-L334) | Correct the privacy text and add the manifest. This can cause App Store review problems. |
| 0.10 | The README says iOS 16.1, but the project deployment target is iOS 26.4. | `project.pbxproj` | Lower the target unless this is deliberate; it narrows the audience considerably. |

## Phase 1 — User experience

Status: implemented on 2026-11-12, together with the removal of all decorative gradients (flat accent colors; only the speed gauge keeps its green-to-red scale).

- **Accessibility.** There are 270 fixed-size font usages against 2 Dynamic Type usages, and the main screens have no VoiceOver labels. This is the largest UX gap.
- **Localization.** There is no String Catalog. The UI is English with leftover Turkish strings ("puan", "Yenile", "Kapat"). Add `Localizable.xcstrings` with TR and EN.
- **Onboarding.** Five pages with two permission prompts back to back. Reduce to three pages and ask for location when the user first opens Wi-Fi details.
- **Speed test history.** Limited to 10 entries with no context. Store network type, SSID, ISP and jitter. Remove the cap and add a trend chart and filters.
- **Result explanation.** Next to the 0–100 score, add a plain summary such as "4K streaming ✓, video calls ✓, gaming ✗".
- **Graph.** Only the last 30 minutes are kept in memory. Persist samples to disk for daily and weekly history.
- **Light theme.** The app is locked to dark mode. The design system is already in place, so adding it is cheap.

## Phase 2 — New features (ordered by impact against effort)

Status: implemented on 2026-11-12, except scheduled speed tests, which were dropped by decision (the ISP report card was built without them). Wake-on-LAN needed Apple's multicast entitlement, which was granted on 2026-11-17.

1. **Widget family.** Small and medium home screen, Lock Screen and StandBy widgets showing the last test result and period usage.
2. **Scheduled speed tests and ISP report card.** Periodic tests, comparison against the advertised plan speed, and a PDF for ISP complaints. Builds on [PDFReportGenerator.swift](rinetworkspeed/PDFReportGenerator.swift).
3. **Connection troubleshooter.** One tap runs gateway → DNS → internet → latency and gives a plain-language diagnosis. Combines the existing tools.
4. **Per-network profiles.** Separate test history and averages per SSID ("Home" against "Office").
5. **New device alert.** Store IP scanner results and show when an unknown device joins the network.
6. **Room-by-room Wi-Fi survey.** Name rooms, run a test in each, and show the best and worst spots.
7. **Small tools.** Wake-on-LAN, subnet calculator, favorite hosts list, share and copy for tool output.

## Phase 3 — Growth and revenue

Status: implemented on 2026-11-13. Free: speed test, live speed, data usage, latest tests, Ping Monitor, troubleshooter and notifications. Pro: widgets and Live Activity, unlimited history, reports, 24-hour and 7-day graphs, advanced network tools and data limit alerts. 38 unit tests cover usage deltas, billing periods, scoring, plan comparison, the review prompt policy, subnet math and Wake-on-LAN packets.

- **Free and Pro split.** Even the speed test is Pro today. Make the speed test and live speed free. Move widgets, scheduled tests, unlimited history, PDF and advanced tools to Pro.
- **Paywall.** Add a free trial and emphasize the annual plan. When the user taps a locked feature, highlight that feature.
- **Review prompt.** Call `requestReview` after a successful test.
- **Tests.** The test targets are still the template (18 lines). Add unit tests for the `DataUsageMonitor` delta logic and the speed test math.

## Phase 4 — Hard, high-value features

Status: planned on 2026-11-17, not started. We go one step at a time: each step is built, tested on a device and reviewed before the next one starts. Assumptions marked **verify on device** are not confirmed yet; the first task of that step is a small spike that proves or rejects them.

### Step 4.0 — Foundation: read the real gateway

Status: builds without errors (2026-11-17); not yet tested on a device. Code: [GatewayResolver.swift](rinetworkspeed/GatewayResolver.swift), 10 unit tests in [GatewayResolverTests.swift](rinetworkspeedTests/GatewayResolverTests.swift)). Not yet built or tested on a device. Wi-Fi details, the troubleshooter, the network map and traceroute now use it and fall back to the old guess when the routing table cannot be read. The root `rinetworkspeed.entitlements` was removed; the OUI table was kept because NetBIOS (4.7) can return MAC addresses.

Several features below need the real default gateway. Today it is guessed:

| Where | Today |
|---|---|
| [WiFiInfoManager.swift](rinetworkspeed/WiFiInfoManager.swift#L206) | `inferredRouterIP` takes the first host of the subnet |
| [NetworkMapManager.swift](rinetworkspeed/NetworkTools/NetworkMapManager.swift#L131) | assumes `<subnet>.1` |
| [TracerouteView.swift](rinetworkspeed/NetworkTools/TracerouteView.swift#L107) | tries a fixed list (`192.168.1.1`, `10.0.0.1`…) |

All three are wrong on networks where the router is not the first address (for example `.254`).

- Read the default route from the routing table with `sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY)` (the `route.h` structs have to be declared by hand on iOS). **Verify on device.**
- One shared `GatewayResolver` used by Wi-Fi details, network map, traceroute and the troubleshooter; keep the inferred value only as a fallback.
- Cleanup found during the review: the OUI table in `NetworkMapManager` never runs because `macAddress` is always `nil` (iOS hides MAC addresses), and the root `rinetworkspeed.entitlements` uses a different App Group (`group.com.rinetworkspeed`) from the target's file (`group.rinetworkspeedapp`). Check whether it is still used and remove it if not.
- Done when: the gateway matches the router's real address on at least one network where it is not `.1`; unit tests cover the parser.

### Step 4.1 — Latency under load (bufferbloat)

Explains "100 Mbps but games and video calls lag".

Status: builds without errors (2026-11-17); not yet tested on a device. `LatencyProbe` in [SpeedTestManager.swift](rinetworkspeed/SpeedTestManager.swift) measures idle latency and, on its own connection, latency during each phase (probes every 0.2 s, warm-up excluded, median of at least 3). Results store `loadedLatencyDownload` / `loadedLatencyUpload`; `SpeedTestScore` adds the added latency, an A–F grade and a summary; gaming needs grade A or B and video calls less than 200 ms added (old results without the values are unaffected). The 0–100 score is unchanged so it stays comparable with earlier tests. Shown on the result screen and as an average in the ISP report; 9 unit tests (17 cases) in [LatencyUnderLoadTests.swift](rinetworkspeedTests/LatencyUnderLoadTests.swift). Still open: share card and history rows.

- While the download and upload phases run ([SpeedTestManager.swift](rinetworkspeed/SpeedTestManager.swift#L454)), send small latency probes on a separate connection that does not carry the transfer.
- Report idle, download-loaded and upload-loaded latency and an A–F bufferbloat grade. Use Apple's `networkQuality` RPM method (IETF "Responsiveness under Working Conditions" draft) as the reference for how probes are counted.
- Feed the grade into `SpeedTestScoring` (gaming and video calls), history, the share card and the ISP report. Store the new fields so old results still decode.
- Done when: on a saturated link loaded latency is clearly above idle latency, and the result is reproducible across runs.

### Step 4.2 — Wi-Fi or provider? Dual-target ping

Status: dual-target ping and diagnosis build without errors (2026-11-17); not yet tested on a device. The LAN throughput test below is not started. On Wi-Fi the Ping Monitor also probes the router (TCP connect to port 80, 443 or 53; a refused connection counts as a reply), draws it as a second line and shows a "Wi-Fi or Provider?" section. The rules live in [LatencyDiagnosis.swift](rinetworkspeed/LatencyDiagnosis.swift): router average over 30 ms, jitter over 20 ms or 3 % loss means Wi-Fi; otherwise internet jitter over 30 ms, 3 % loss or more than 150 ms added beyond the router means beyond the router. These thresholds are heuristics to be checked against real networks. The troubleshooter's latency step probes the router at the same time and uses the same rules for its advice. 9 unit tests in [LatencyDiagnosisTests.swift](rinetworkspeedTests/LatencyDiagnosisTests.swift).

- Ping Monitor pings the gateway (from 4.0) and an internet host at the same time, on one shared chart.
- Diagnosis rules: jitter or loss to the gateway points to Wi-Fi; a clean gateway with a bad internet target points to the provider. Show the conclusion in plain language and use it in the troubleshooter.
- Later in this step (optional): a LAN throughput test between two devices running the app (`NWListener` + Bonjour), so Wi-Fi speed can be measured without the internet in the way.

### Step 4.3 — Real traceroute and MTR

The current traceroute is not TTL-based: it probes guessed gateway addresses and fixed hosts over TCP.

Status: trace and MTR written on 2026-11-17, not yet built or tested on a device. [ICMPTracer.swift](rinetworkspeed/NetworkTools/ICMPTracer.swift) sends one ICMP echo per TTL each round and matches Time Exceeded and echo replies by sequence; [RouteAnalysis.swift](rinetworkspeed/NetworkTools/RouteAnalysis.swift) keeps per-hop statistics, classifies addresses, looks up the ASN (Team Cymru over Cloudflare DoH) and decides where lasting loss starts (a hop counts only if every later answering hop loses at least half as much as the destination). Rounds every 1–1.5 s, a finding after 10 rounds, auto-stop after 300. 21 unit tests in [RouteTracingTests.swift](rinetworkspeedTests/RouteTracingTests.swift). Still open: troubleshooter and ISP report use, IPv6.

- Send probes with increasing `IP_TTL` on an unprivileged ICMP socket (`SOCK_DGRAM` + `IPPROTO_ICMP`, the approach of Apple's SimplePing sample) and read the ICMP Time Exceeded replies. **Verify on device** that Time Exceeded replies are delivered to that socket.
- MTR mode: repeat the trace continuously and show loss and latency per hop over time; add the ASN and provider per hop.
- Automatic finding such as "loss starts at hop 3, inside the provider's network", used by the troubleshooter and added to the ISP report as evidence.
- IPv6 hops if the network has IPv6 (the app is IPv4-only today).

### Step 4.4 — Modem line stats (UPnP IGD / TR-064)

Status: written on 2026-11-17, not yet built or tested on a device. New tool "Modem & Line" ([ModemView.swift](rinetworkspeed/NetworkTools/ModemView.swift)): [UPnPGateway.swift](rinetworkspeed/NetworkTools/UPnPGateway.swift) sends M-SEARCH to the multicast group and to the gateway, reads the device description and calls GetCommonLinkProperties, GetTotalBytesReceived/Sent, GetExternalIPAddress, GetStatusInfo and GetGenericPortMappingEntry. [ModemLine.swift](rinetworkspeed/NetworkTools/ModemLine.swift) compares plan, line and the median of recent Wi-Fi tests (line below 90 % of the plan, or tests below 70 % of the line) and keeps the last reading; a recent DSL reading is added to the ISP report. The layer-1 rate is only called a line rate when the access type is DSL; on Ethernet it is the WAN port speed. A non-public WAN address is explained as CGNAT or double NAT. `NSAllowsLocalNetworking` added to Info.plist for the plain-HTTP UPnP requests. 17 unit tests in [ModemTests.swift](rinetworkspeedTests/ModemTests.swift). Still open: vendor adapters (TR-064 and others) for attenuation, SNR margin and errors; showing the comparison in Test History.

Compare three numbers: the advertised plan, the modem's sync rate and the speed test. Example finding: "Your line syncs at 35 Mbps and your plan is 100 Mbps, so the limit is the line, not your Wi-Fi."

- Discover the modem's UPnP description with a standard SSDP M-SEARCH to `239.255.255.250:1900`. This uses the multicast networking entitlement, granted on 2026-11-17. Pick the device whose address matches the gateway (from 4.0). **Verify on device** with the common modems in Turkey.
- SOAP calls to read: `Layer1UpstreamMaxBitRate` / `Layer1DownstreamMaxBitRate`, WAN IP, uptime, total bytes sent and received (whole-household usage) and the port mapping list.
- Show the plan, sync and test comparison in Test History and in the ISP report.
- Later: vendor adapters (FritzBox TR-064, ZTE, Huawei, TP-Link) for line attenuation, SNR margin and error counters.

### Step 4.5 — Real Wi-Fi signal through a Shortcuts bridge

Status: written on 2026-11-17, not yet built or tested on a device. [WiFiSignal.swift](rinetworkspeed/WiFiSignal.swift) runs the shortcut with `shortcuts://run-shortcut?name=RiNetwork%20Wi-Fi%20Signal`, parses the answer `rinetworkspeed://wifi-signal?rssi=…&noise=…&channel=…&standard=…&tx=…&rx=…&bssid=…` (lenient about units and decimal commas; an RSSI is required) and keeps the last 50 readings. [WiFiSignalView.swift](rinetworkspeed/WiFiSignalView.swift) adds a Signal card to the Wi-Fi details (quality labels for RSSI and SNR, band guessed from the channel, a note when the access point changed within an hour) and a setup sheet with build steps; the ready-made iCloud shortcut link is still to be published. 8 unit tests (14 cases) in [WiFiSignalTests.swift](rinetworkspeedTests/WiFiSignalTests.swift).

iOS gives apps no RSSI API. The Shortcuts action "Get Network Details" is believed to return RSSI, noise, channel, Wi-Fi standard and TX/RX rate since iOS 17. **Verify on device** which fields it returns.

- The user installs a provided shortcut once. The app runs it with `shortcuts://x-callback-url/run-shortcut`, and the shortcut returns the values with `rinetworkspeed://wifi?rssi=…`.
- Use the values for: signal, SNR, band and channel in Wi-Fi details, and access point changes (BSSID) on mesh networks.
- Limits to state in the UI: readings are on demand, not continuous, and each one briefly switches to the Shortcuts app. Update the README sentence that says RSSI is unavailable.

### Step 4.6 — Wi-Fi heatmap

Grows the existing Wi-Fi Survey into a map.

Status: first version written on 2026-11-17, not yet built or tested on a device. Decision: start with tap-to-place on a photo of a floor plan or a blank grid, which works on every iPhone; walking with ARKit and a RoomPlan scan comes after it. New tool "Wi-Fi Heatmap" ([WiFiHeatmapView.swift](rinetworkspeed/NetworkTools/WiFiHeatmapView.swift)). At each tapped spot [WiFiHeatmap.swift](rinetworkspeed/NetworkTools/WiFiHeatmap.swift) sends 10 router probes (average, jitter, loss), optionally a 3-second download over 4 streams and the 4.5 signal reading. Views: router quality (average + 2 × jitter + 200 ms per 100 % loss, 3 ms best, 60 ms worst), download (relative to the best spot) and signal (-45 to -80 dBm). Inverse-distance interpolation on a 48-column grid in four flat colour bands, uncoloured further than 0.3 of the plan from any spot. With the router marked, a mesh spot is suggested halfway to the weakest spot when it scores below 0.5 (a rule of thumb). 12 unit tests in [WiFiHeatmapTests.swift](rinetworkspeedTests/WiFiHeatmapTests.swift). Still open: AR walking mode, RoomPlan floor plans, export/share of the map.

- Floor plan from a RoomPlan scan (LiDAR devices) or from a photo of a plan; ARKit tracks the position while the user walks.
- Sample continuously: gateway latency and jitter (4.2), short throughput bursts, and RSSI when the 4.5 bridge is set up.
- Render a heatmap and suggest where the router or a mesh node should go.

### Backlog — 4.7 to 4.14 written on 2026-11-17

The pure logic of 4.8–4.14 is covered by 23 unit tests in [NetworkChecksTests.swift](rinetworkspeedTests/NetworkChecksTests.swift); the new tools share [ToolScaffold.swift](rinetworkspeed/NetworkTools/ToolScaffold.swift).

| # | Feature | Notes |
|---|---|---|
| 4.7 | Device fingerprinting — **written on 2026-11-17, not yet built or tested on a device**: [DeviceFingerprint.swift](rinetworkspeed/NetworkTools/DeviceFingerprint.swift), used by the IP Scanner and Network Map; 14 service types added to `NSBonjourServices`; 14 unit tests in [DeviceFingerprintTests.swift](rinetworkspeedTests/DeviceFingerprintTests.swift) | Bonjour TXT records (model names; needs `NSBonjourServices` in Info.plist), NetBIOS node status over unicast UDP 137 (name and MAC of Windows/Samba devices), SSDP device descriptions, HTTP title and `Server` headers |
| 4.8 | Hidden camera scan — **Written 2026-11-17, not yet built or tested on a device.** [CameraFinder.swift](rinetworkspeed/NetworkTools/CameraFinder.swift): ports 554, 8554, 8000, 37777, 34567, 9527 on the /24, ONVIF WS-Discovery (multicast), Bonjour/UPnP identities; whole-word camera-maker matching | Builds on 4.7: RTSP 554, ONVIF (WS-Discovery multicast, possible with the granted entitlement), Hikvision 8000, Dahua 37777, mDNS |
| 4.9 | "Is this Wi-Fi safe?" — **Written 2026-11-17, not yet built or tested on a device.** [WiFiSafetyView.swift](rinetworkspeed/NetworkTools/WiFiSafetyView.swift): security type, certificate roots of three sites against a list of public root names (a heuristic), NXDOMAIN check under example.com, visible devices, per-SSID router and BSSID memory | TLS interception (public key hashes of known hosts), DNS hijacking (random non-existent domain returns an address), client isolation, evil twin (known SSID with a new BSSID, gateway or ASN) |
| 4.10 | DNS benchmark and one-tap encrypted DNS — **Written 2026-11-17, not yet built or tested on a device.** [DNSBenchmarkView.swift](rinetworkspeed/NetworkTools/DNSBenchmarkView.swift): 8 popular names × 2 rounds over raw UDP per resolver (the router stands in for the provider's DNS); the DNS Settings entitlement (`com.apple.developer.networking.networkextension` = `dns-settings`) was added | Uncached random subdomains against the provider's DNS, Cloudflare, Google, Quad9 and AdGuard; raw UDP DNS queries are needed because the current tool uses DoH JSON; apply the fastest with `NEDNSSettingsManager` |
| 4.11 | NAT type, CGNAT and double NAT — **Written 2026-11-17, not yet built or tested on a device.** [NATTypeView.swift](rinetworkspeed/NetworkTools/NATTypeView.swift): STUN to Google (19302) and Cloudflare (3478) from one socket; filtering behaviour (RFC 5780) is not tested because it needs a server that supports it | STUN (RFC 5780) for Open, Moderate or Strict; CGNAT when the WAN IP from 4.4 is in `100.64.0.0/10` or differs from the public IP; double NAT when hop 2 in 4.3 is private |
| 4.12 | Real-experience tests — **Written 2026-11-17, not yet built or tested on a device.** [ExperienceTestView.swift](rinetworkspeed/NetworkTools/ExperienceTestView.swift): AVPlayer with Apple's bipbop fMP4 HLS example (stream URL to verify), 7 AWS regions over TCP 443 | Video: `AVPlayer` with an HLS stream and `AVPlayerItemAccessLog` (startup time, stalls, sustainable resolution). Gaming: latency to cloud regions, labeled as an estimate because game servers cannot be measured directly |
| 4.13 | Peak-hour analysis — **Written 2026-11-17, not yet built or tested on a device.** [PeakHourAnalysis.swift](rinetworkspeed/PeakHourAnalysis.swift): four day parts, at least 3 tests per part, reported when the slowest is 30 % or more below the fastest; in Test History and the ISP report | Hour-by-weekday view built from the existing history, with the sample count shown; results go into the ISP report. Samples can come from a Shortcuts personal automation that runs the existing `RunSpeedTestIntent` |
| 4.14 | Cellular context — **Written 2026-11-17, not yet built or tested on a device.** [CellularContext.swift](rinetworkspeed/CellularContext.swift) and [CoverageMapView.swift](rinetworkspeed/CoverageMapView.swift): radio technology and a location rounded to 3 decimals for cellular tests (only with existing permission), map in Test History; the location usage text was updated | Tag tests with the radio technology (`CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology`: 5G, LTE…) and show a personal coverage map from tests with a location |
| 4.15 | Mac menu bar companion | macOS can run continuously and reads RSSI, noise and channel with CoreWLAN; it logs outages and syncs them to the iPhone through CloudKit |

### Not worth pursuing on iOS

- Per-app data usage: there is no API.
- RSSI through `NEHotspotHelper`: needs a special entitlement Apple rarely grants.
- Continuous background measurement through a local VPN (packet tunnel): App Review rules for VPN apps (believed to require an organization developer account; check the current guidelines) and it would break the app's "no traffic interception" privacy promise.

## Platform limits to keep in mind

- iOS does not let the app run continuously in the background. Disconnect and speed notifications therefore fire only while the app is open, or within about 25 seconds after it is backgrounded. For the same reason a live-speed widget is not possible; widgets can only show the last known value.
- The interface byte counters are 32-bit. If the app is not opened for a long time and more than 4 GB passes in between, usage is undercounted. Background refresh reduces this but does not eliminate it.

## Recommended order

1. All of Phase 0
2. Accessibility and localization
3. Widget family
4. History and ISP report card
5. Pro split and paywall
6. Remaining features

The quickest wins inside Phase 0 are 0.5 (data limit), 0.1 (estimated RSSI) and 0.6 (ping). All three are small and independent of each other.
