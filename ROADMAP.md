# RI Network Speed — Improvement Roadmap

Based on a full review of the codebase on 2026-11-12 (about 12k lines of Swift).

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

Status: implemented on 2026-11-12, except scheduled speed tests, which were dropped by decision (the ISP report card was built without them). Wake-on-LAN needs Apple's multicast entitlement before it can send packets on a device.

1. **Widget family.** Small and medium home screen, Lock Screen and StandBy widgets showing the last test result and period usage.
2. **Scheduled speed tests and ISP report card.** Periodic tests, comparison against the advertised plan speed, and a PDF for ISP complaints. Builds on [PDFReportGenerator.swift](rinetworkspeed/PDFReportGenerator.swift).
3. **Connection troubleshooter.** One tap runs gateway → DNS → internet → latency and gives a plain-language diagnosis. Combines the existing tools.
4. **Per-network profiles.** Separate test history and averages per SSID ("Home" against "Office").
5. **New device alert.** Store IP scanner results and show when an unknown device joins the network.
6. **Room-by-room Wi-Fi survey.** Name rooms, run a test in each, and show the best and worst spots.
7. **Small tools.** Wake-on-LAN, subnet calculator, favorite hosts list, share and copy for tool output.

## Phase 3 — Growth and revenue

- **Free and Pro split.** Even the speed test is Pro today. Make the speed test and live speed free. Move widgets, scheduled tests, unlimited history, PDF and advanced tools to Pro.
- **Paywall.** Add a free trial and emphasize the annual plan. When the user taps a locked feature, highlight that feature.
- **Review prompt.** Call `requestReview` after a successful test.
- **Tests.** The test targets are still the template (18 lines). Add unit tests for the `DataUsageMonitor` delta logic and the speed test math.

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
