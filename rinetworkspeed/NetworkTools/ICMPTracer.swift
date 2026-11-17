//
//  ICMPTracer.swift
//  rinetworkspeed
//
//  TTL-based route tracing with ICMP echo requests on an unprivileged ICMP
//  datagram socket (the approach of Apple's SimplePing sample). Each router
//  on the way answers a probe whose TTL runs out with ICMP Time Exceeded; the
//  destination answers with an echo reply.
//

import Foundation
import Darwin

// MARK: - Packets

/// Building and parsing of the ICMP messages used for tracing. Pure, so it
/// can be unit tested.
nonisolated enum ICMPPacket {
    static let echoReplyType: UInt8 = 0
    static let unreachableType: UInt8 = 3
    static let echoRequestType: UInt8 = 8
    static let timeExceededType: UInt8 = 11
    static let protocolICMP: UInt8 = 1

    nonisolated struct Reply: Equatable, Sendable {
        nonisolated enum Kind: Equatable, Sendable {
            /// The destination answered.
            case echoReply
            /// A router on the way: the probe's TTL ran out there.
            case timeExceeded
            /// A router or the destination reported the probe undeliverable.
            case unreachable
        }

        let kind: Kind
        /// Identifier and sequence of the echo request this answers.
        let identifier: UInt16
        let sequence: UInt16
    }

    /// An echo request with a small counting payload and a valid checksum.
    static func echoRequest(identifier: UInt16, sequence: UInt16, payloadSize: Int = 32) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadSize)
        packet[0] = echoRequestType
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        for i in 0..<payloadSize {
            packet[8 + i] = UInt8(truncatingIfNeeded: i)
        }
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Internet checksum (RFC 1071) over big-endian 16-bit words. Written high
    /// byte first; a packet that includes its own checksum sums to zero.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += (UInt32(bytes[index]) << 8) | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    /// Parses a received message. Darwin delivers ICMP datagram socket reads
    /// with the IPv4 header in front; a message without it is also accepted.
    /// Time Exceeded and Unreachable carry the start of the original probe,
    /// which gives back its identifier and sequence.
    static func parse(_ bytes: [UInt8]) -> Reply? {
        var start = 0
        if let first = bytes.first, first >> 4 == 4 {
            start = Int(first & 0x0F) * 4
        }
        guard start >= 0, bytes.count >= start + 8 else { return nil }

        switch bytes[start] {
        case echoReplyType:
            return Reply(kind: .echoReply,
                         identifier: word(bytes, start + 4),
                         sequence: word(bytes, start + 6))

        case timeExceededType, unreachableType:
            // ICMP header (8 bytes), then the original IPv4 header and at
            // least the first 8 bytes of the original ICMP message.
            let inner = start + 8
            guard bytes.count >= inner + 20, bytes[inner] >> 4 == 4 else { return nil }
            let innerHeaderLength = Int(bytes[inner] & 0x0F) * 4
            let original = inner + innerHeaderLength
            guard innerHeaderLength >= 20,
                  bytes.count >= original + 8,
                  bytes[inner + 9] == protocolICMP,
                  bytes[original] == echoRequestType else { return nil }
            return Reply(kind: bytes[start] == timeExceededType ? .timeExceeded : .unreachable,
                         identifier: word(bytes, original + 4),
                         sequence: word(bytes, original + 6))

        default:
            return nil
        }
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}

// MARK: - Tracer

/// What came back for one probe.
nonisolated struct HopReply: Equatable, Sendable {
    let address: String
    let milliseconds: Double
    /// True when the destination itself answered (echo reply).
    let reachedDestination: Bool
}

/// Owns one ICMP socket and sends probes to a single IPv4 destination. The
/// calls block, so they run on a private queue.
nonisolated final class ICMPTracer: @unchecked Sendable {
    private let socketDescriptor: Int32
    private let destination: in_addr
    private let identifier = UInt16.random(in: 1...UInt16.max)
    private var nextSequenceBase = UInt16.random(in: 0...UInt16.max)
    private let queue = DispatchQueue(label: "rinetworkspeed.traceroute.icmp")

    /// Nil when `address` is not an IPv4 address or the socket cannot be opened.
    init?(destination address: String) {
        var target = in_addr()
        guard inet_pton(AF_INET, address, &target) == 1 else { return nil }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { return nil }
        destination = target
        socketDescriptor = descriptor
    }

    deinit {
        close(socketDescriptor)
    }

    /// Sends one probe for every TTL at once and collects the answers until
    /// all came back or `timeout` passed. Missing TTLs were lost.
    func round(ttls: ClosedRange<Int>, timeout: TimeInterval) async -> [Int: HopReply] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.runRound(ttls: ttls, timeout: timeout))
            }
        }
    }

    private func runRound(ttls: ClosedRange<Int>, timeout: TimeInterval) -> [Int: HopReply] {
        // Sequences of this round; rounds never share one, so a late answer
        // to an earlier round is ignored.
        let base = nextSequenceBase
        nextSequenceBase &+= 64

        var pending: [UInt16: (ttl: Int, sentAt: UInt64)] = [:]
        for ttl in ttls {
            let sequence = base &+ UInt16(truncatingIfNeeded: ttl)
            guard setTTL(Int32(ttl)) else { continue }
            let packet = ICMPPacket.echoRequest(identifier: identifier, sequence: sequence)
            let sentAt = DispatchTime.now().uptimeNanoseconds
            if send(packet) {
                pending[sequence] = (ttl, sentAt)
            }
        }

        var replies: [Int: HopReply] = [:]
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while !pending.isEmpty {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            guard let received = receive(waitingUpTo: Double(deadline - now) / 1_000_000_000) else { continue }
            let receivedAt = DispatchTime.now().uptimeNanoseconds

            // Matched on the sequence: some kernels replace the identifier of
            // datagram ICMP sockets, and sequences are unique to this tracer.
            guard let reply = ICMPPacket.parse(received.bytes),
                  let probe = pending.removeValue(forKey: reply.sequence) else { continue }
            replies[probe.ttl] = HopReply(
                address: received.from,
                milliseconds: Double(receivedAt - probe.sentAt) / 1_000_000,
                reachedDestination: reply.kind == .echoReply
            )
        }
        return replies
    }

    // MARK: Socket calls

    private func setTTL(_ ttl: Int32) -> Bool {
        var value = ttl
        return setsockopt(socketDescriptor, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size)) == 0
    }

    private func send(_ packet: [UInt8]) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = destination

        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketDescriptor, buffer.baseAddress, buffer.count, 0, $0,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }

    /// Waits for one incoming message; nil on timeout or error.
    private func receive(waitingUpTo seconds: Double) -> (bytes: [UInt8], from: String)? {
        var descriptor = pollfd(fd: socketDescriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(max(1, (seconds * 1000).rounded(.up)))
        guard poll(&descriptor, 1, milliseconds) > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 2048)
        var source = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketDescriptor, bytes.baseAddress, bytes.count, 0, $0, &sourceLength)
                }
            }
        }
        guard count > 0 else { return nil }

        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var sourceAddress = source.sin_addr
        guard inet_ntop(AF_INET, &sourceAddress, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return (Array(buffer.prefix(count)), String(cString: text))
    }
}
