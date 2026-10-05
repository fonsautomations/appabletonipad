import Foundation
import Network
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// UDP OSC transport: sends to Live's AbletonOSC port and listens for replies on the reply port.
final class OSCClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "stagedeck.osc", qos: .userInitiated)
    private var connection: NWConnection?
    private var listener: NWListener?
    private var inbound: [ObjectIdentifier: NWConnection] = [:]
    private(set) var host: String = ""
    private(set) var port: UInt16 = 11000
    private(set) var replyPort: UInt16 = 11001

    /// Called on the OSC queue for each incoming message with the sender's IP.
    var onMessage: (@Sendable (OSCMessage, String) -> Void)?
    var onListenerState: (@Sendable (NWListener.State) -> Void)?

    func configure(host: String, port: Int, replyPort: Int) {
        self.host = host
        self.port = UInt16(clamping: port)
        self.replyPort = UInt16(clamping: replyPort)
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
            self?.openConnectionIfNeeded()
        }
    }

    private func openConnectionIfNeeded() {
        guard connection == nil, !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: params)
        c.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.connection = nil
            }
        }
        c.start(queue: queue)
        connection = c
    }

    func startListening() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            guard let p = NWEndpoint.Port(rawValue: self.replyPort) else { return }
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            do {
                let l = try NWListener(using: params, on: p)
                l.stateUpdateHandler = { [weak self] state in
                    self?.onListenerState?(state)
                    if case .failed = state {
                        self?.listener = nil
                    }
                }
                l.newConnectionHandler = { [weak self] conn in
                    self?.accept(conn)
                }
                l.start(queue: self.queue)
                self.listener = l
            } catch {
                self.onListenerState?(.failed(.posix(.EADDRINUSE)))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.connection?.cancel()
            self.connection = nil
            for (_, c) in self.inbound { c.cancel() }
            self.inbound.removeAll()
        }
    }

    private func accept(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        inbound[key] = conn
        var senderIP = ""
        if case .hostPort(let h, _) = conn.endpoint {
            senderIP = OSCClient.plainIP(from: h)
        }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.inbound.removeValue(forKey: key)
            default: break
            }
        }
        conn.start(queue: queue)
        receiveLoop(conn, senderIP: senderIP)
    }

    private func receiveLoop(_ conn: NWConnection, senderIP: String) {
        conn.receiveMessage { [weak self, weak conn] data, _, _, error in
            guard let self, let conn else { return }
            if let data, !data.isEmpty {
                for m in OSCMessage.decodePacket(data) {
                    self.onMessage?(m, senderIP)
                }
            }
            if error == nil {
                self.receiveLoop(conn, senderIP: senderIP)
            } else {
                self.inbound.removeValue(forKey: ObjectIdentifier(conn))
            }
        }
    }

    static func plainIP(from host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let a): return "\(a)"
        case .ipv6(let a): return "\(a)"
        case .name(let n, _): return n
        @unknown default: return "\(host)"
        }
    }

    /// Sends one message to the configured host.
    func send(_ message: OSCMessage) {
        let data = message.encode()
        queue.async { [weak self] in
            guard let self else { return }
            self.openConnectionIfNeeded()
            guard let c = self.connection else { return }
            c.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    func send(_ messages: [OSCMessage]) {
        for m in messages { send(m) }
    }

    // MARK: - Discovery (UDP broadcast through a BSD socket; Network.framework cannot broadcast)

    /// Broadcasts `/live/test` on every IPv4 interface. Live answers to our reply port, which
    /// reveals its IP address.
    func broadcastDiscovery() {
        let payload = LiveCommand.test().encode()
        let targets = OSCClient.broadcastAddresses() + ["255.255.255.255"]
        #if canImport(Glibc)
        let socketType = Int32(SOCK_DGRAM.rawValue)
        #else
        let socketType = SOCK_DGRAM
        #endif
        let fd = socket(AF_INET, socketType, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        for target in targets {
            var addr = sockaddr_in()
            #if canImport(Darwin)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            #endif
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr(target)
            if addr.sin_addr.s_addr == 0xFFFF_FFFF { continue }
            payload.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = sendto(fd, base, payload.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    /// Directed broadcast addresses of all active IPv4 interfaces (e.g. 192.168.1.255).
    static func broadcastAddresses() -> [String] {
        interfaces().compactMap { iface in
            guard iface.broadcast else { return nil }
            let bcast = in_addr(s_addr: iface.address | ~iface.netmask)
            return String(cString: inet_ntoa(bcast))
        }
    }

    /// Local IPv4 addresses (for display in Settings), e.g. "en0: 192.168.1.20".
    static func localIPAddresses() -> [String] {
        interfaces().map { iface in
            "\(iface.name): \(String(cString: inet_ntoa(in_addr(s_addr: iface.address))))"
        }
    }

    struct IPv4Interface {
        var name: String
        var address: in_addr_t
        var netmask: in_addr_t
        var broadcast: Bool
    }

    static func interfaces() -> [IPv4Interface] {
        var result: [IPv4Interface] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return result }
        defer { freeifaddrs(ifaddrPtr) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = Int32(bitPattern: ifa.pointee.ifa_flags)
            guard (flags & Int32(IFF_UP)) != 0, (flags & Int32(IFF_LOOPBACK)) == 0 else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            var nm: in_addr_t = 0
            if let mask = ifa.pointee.ifa_netmask {
                nm = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            }
            let name = String(cString: ifa.pointee.ifa_name)
            result.append(IPv4Interface(name: name, address: ip, netmask: nm, broadcast: (flags & Int32(IFF_BROADCAST)) != 0 && nm != 0))
        }
        return result
    }
}
