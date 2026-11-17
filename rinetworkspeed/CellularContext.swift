//
//  CellularContext.swift
//  rinetworkspeed
//
//  Radio technology (5G, 4G…) and an approximate location for cellular
//  speed tests, for the personal coverage map. Locations are rounded to
//  about 100 m and stay on the device.
//

import Foundation
import CoreTelephony
import CoreLocation

nonisolated enum RadioTechnology {
    /// Short label for a CTRadioAccessTechnology value.
    static func label(_ raw: String) -> String? {
        switch raw {
        case CTRadioAccessTechnologyNR: return "5G"
        case CTRadioAccessTechnologyNRNSA: return "5G NSA"
        case CTRadioAccessTechnologyLTE: return "4G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
            return "2G"
        default:
            return nil
        }
    }

    /// Technology of the data line right now, when on cellular.
    static func current() -> String? {
        let info = CTTelephonyNetworkInfo()
        let raw = info.dataServiceIdentifier.flatMap { info.serviceCurrentRadioAccessTechnology?[$0] }
            ?? info.serviceCurrentRadioAccessTechnology?.values.first
        return raw.flatMap(label)
    }
}

nonisolated enum ApproximateLocation {
    /// Rounds to three decimals (about 100 m).
    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    /// One location fix, only when location access was already granted;
    /// never asks for permission. Nil after `timeout` seconds.
    static func current(timeout: TimeInterval = 5) async -> (latitude: Double, longitude: Double)? {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        return await withTaskGroup(of: (latitude: Double, longitude: Double)?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 500 {
                            return (rounded(location.coordinate.latitude), rounded(location.coordinate.longitude))
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
