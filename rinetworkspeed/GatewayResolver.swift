//
//  GatewayResolver.swift
//  rinetworkspeed
//
//  Reads the default IPv4 gateway from the kernel routing table instead of
//  guessing it from the subnet (the router is not always the first address,
//  for example 192.168.1.254).
//

import Foundation
import Darwin

nonisolated enum GatewayResolver {

    /// Default IPv4 gateway of `interface` (`en0` is Wi-Fi), or nil when the
    /// interface has no default route or the routing table cannot be read.
    static func defaultGateway(interface: String = "en0") -> String? {
        let index = if_nametoindex(interface)
        guard index != 0, let table = routingTable() else { return nil }
        return parseDefaultGateway(table, interfaceIndex: UInt16(truncatingIfNeeded: index))
    }

    // MARK: - Routing message layout

    // <net/route.h> is not part of the iOS SDK, so the values below are
    // declared here. They match the XNU headers.

    /// `NET_RT_FLAGS`: dump the routes that have the given flags.
    static let netRTFlags: Int32 = 2
    /// `RTF_UP`
    static let routeUp: Int32 = 0x1
    /// `RTF_GATEWAY`
    static let routeGateway: Int32 = 0x2
    /// `RTAX_DST` / `RTAX_GATEWAY`: positions of the addresses after the header.
    static let destinationSlot = 0
    static let gatewaySlot = 1
    /// `RTAX_MAX`
    static let addressSlots = 8
    /// `RTM_VERSION`
    static let messageVersion: UInt8 = 5
    /// `sizeof(struct rt_msghdr)`
    static let headerSize = 92
    /// Offsets of the `rt_msghdr` fields that are read.
    static let lengthOffset = 0      // rtm_msglen (UInt16)
    static let versionOffset = 2     // rtm_version (UInt8)
    static let indexOffset = 4       // rtm_index (UInt16)
    static let flagsOffset = 8       // rtm_flags (Int32)
    static let addressesOffset = 12  // rtm_addrs (Int32)

    // MARK: - Routing table

    private static func routingTable() -> [UInt8]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, netRTFlags, routeGateway]
        // The table can grow between the size query and the read, so retry a
        // few times with some headroom.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
            size += size / 2
            var buffer = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 {
                return Array(buffer.prefix(size))
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    // MARK: - Parsing

    /// Walks the routing messages returned by the sysctl and returns the
    /// gateway of the first default route (destination 0.0.0.0) on the given
    /// interface. Separate from the sysctl so it can be unit tested.
    static func parseDefaultGateway(_ data: [UInt8], interfaceIndex: UInt16) -> String? {
        var offset = 0
        while offset + headerSize <= data.count {
            let length = Int(readUInt16(data, at: offset + lengthOffset))
            guard length >= headerSize, offset + length <= data.count else { return nil }
            defer { offset += length }

            let index = readUInt16(data, at: offset + indexOffset)
            let flags = readInt32(data, at: offset + flagsOffset)
            let present = readInt32(data, at: offset + addressesOffset)
            guard data[offset + versionOffset] == messageVersion,
                  index == interfaceIndex,
                  flags & routeUp != 0,
                  flags & routeGateway != 0 else { continue }

            let addresses = socketAddresses(data, from: offset + headerSize,
                                            to: offset + length, present: present)
            guard addresses.destination == [0, 0, 0, 0],
                  let gateway = addresses.gateway,
                  gateway != [0, 0, 0, 0] else { continue }
            return gateway.map { String($0) }.joined(separator: ".")
        }
        return nil
    }

    /// Destination and gateway of one routing message as IPv4 octets. The
    /// destination is nil when it is missing or not IPv4; missing trailing
    /// bytes count as zero, as the kernel shortens default addresses. The
    /// gateway is nil unless it is a complete IPv4 address (a link-layer
    /// gateway means the route has no router).
    static func socketAddresses(_ data: [UInt8], from start: Int, to end: Int,
                                present: Int32) -> (destination: [UInt8]?, gateway: [UInt8]?) {
        var destination: [UInt8]?
        var gateway: [UInt8]?
        var cursor = start

        for slot in 0..<addressSlots where present & (1 << slot) != 0 {
            guard cursor < end else { break }
            let length = Int(data[cursor])

            if slot == destinationSlot || slot == gatewaySlot {
                let family = length >= 2 && cursor + 1 < end ? Int32(data[cursor + 1]) : AF_INET
                if family == AF_INET {
                    var octets: [UInt8] = []
                    for i in 4..<8 {
                        let position = cursor + i
                        octets.append(i < length && position < end ? data[position] : 0)
                    }
                    if slot == destinationSlot {
                        destination = octets
                    } else if length >= 8 {
                        gateway = octets
                    }
                }
            }
            if slot >= gatewaySlot { break }
            cursor += roundUp(length)
        }
        return (destination, gateway)
    }

    /// Socket addresses in routing messages are padded to 4 bytes; an empty
    /// one still takes 4 bytes (`ROUNDUP` in XNU's route code).
    static func roundUp(_ length: Int) -> Int {
        length > 0 ? 1 + ((length - 1) | 3) : 4
    }

    // Routing messages use the host's byte order.
    private static func readUInt16(_ data: [UInt8], at offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private static func readInt32(_ data: [UInt8], at offset: Int) -> Int32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
    }
}
