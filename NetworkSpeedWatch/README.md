# NetworkSpeedWatch (not built)

These are the sources for a planned watchOS companion app. The Xcode project
does **not** contain a watchOS target yet, so none of these files are compiled
and the app does not advertise Apple Watch support anywhere.

`PhoneSide/WatchConnectivityManager.swift` is the iOS half of the bridge. It was
moved out of the app target so the app no longer activates a `WCSession` and
pushes data on every sample when there is no watch app to receive it.

To ship the watch app:

1. Add a watchOS App target in Xcode that uses the files in this folder.
2. Move `PhoneSide/WatchConnectivityManager.swift` back into `rinetworkspeed/`.
3. Call `WatchConnectivityManager.shared.updateSpeeds(...)` from
   `NetworkStatsMonitor` and `updateDataUsage(...)` from `DataUsageMonitor`,
   and touch `WatchConnectivityManager.shared` in `rinetworkspeedApp.init()`.
4. Add Apple Watch back to `ProFeature`, the paywall and the README.
