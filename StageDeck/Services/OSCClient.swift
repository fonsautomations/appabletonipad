import Foundation
import Network
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// UDP OSC transport on one BSD socket bound to the reply port: everything we send leaves from
/// port 11001 and AbletonOSC answers to the sender IP on 11001, so replies, listener pushes and
/// broadcast discovery all land on the same socket. (Network.framework's inbound UDP flows were
/// unreliable here: the first reply arrived, the following ones were dropped.)
final class OSCClient: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var generation = 0
    private(set) var host: String = ""
    private(set) var port: UInt16 = 11000
    private(set) var replyPort: UInt16 = 11001

    /// Called on a background thread for each incoming message with the sender's IP.
    var onMessage: (@Sendable (OSCMessage, String) -> Void)?
    /// Called with "" when the reply port is bound, or with an error text.
    var onListenerError: (@Sendable (String) -> Void)?

    func configure(host: String, port: Int, replyPort: Int) {
        lock.lock()
        self.host = host
        self.port = UInt16(clamping: port)
        let newReply = UInt16(clamping: replyPort)
        let rebind = newReply != self.replyPort && fd >= 0
        self.replyPort = newReply
        lock.unlock()
        if rebind { stop(); startListening() }
    }

    /// Opens the socket on the reply port (idempotent) and starts the receive thread.
    func startListening() {
        lock.lock(); defer { lock.unlock() }
        guard fd < 0 else { return }
        #if canImport(Glibc)
        let socketType = Int32(SOCK_DGRAM.rawValue)
        #else
        let socketType = SOCK_DGRAM
        #endif
        let sock = socket(AF_INET, socketType, 0)
        guard sock >= 0 else { onListenerError?("Could not create a UDP socket"); return }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = replyPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(sock)
            onListenerError?("Reply port \(replyPort) is in use by another app")
            return
        }
        fd = sock
        generation += 1
        let gen = generation
        onListenerError?("")
        let thread = Thread { [weak self] in self?.receiveLoop(socket: sock, generation: gen) }
        thread.name = "stagedeck.osc.receive"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stop() {
        lock.lock()
        let sock = fd
        fd = -1
        generation += 1
        lock.unlock()
        if sock >= 0 {
            shutdown(sock, Int32(SHUT_RDWR))
            close(sock)
        }
    }

    private func receiveLoop(socket sock: Int32, generation gen: Int) {
        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while true {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(sock, buffer, bufferSize, 0, $0, &fromLen) }
            }
            lock.lock(); let alive = generation == gen && fd == sock; lock.unlock()
            if !alive { return }
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                return
            }
            var ip = from.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let sender = inet_ntop(AF_INET, &ip, &text, socklen_t(INET_ADDRSTRLEN)) != nil ? String(cString: text) : ""
            let data = Data(bytes: buffer, count: n)
            for m in OSCMessage.decodePacket(data) { onMessage?(m, sender) }
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
        lock.lock()
        let sock = fd, target = host, p = port
        lock.unlock()
        guard sock >= 0, !target.isEmpty else { return }
        sendTo(sock, address: target, port: p, payload: message.encode())
    }

    func send(_ messages: [OSCMessage]) {
        for m in messages { send(m) }
    }

    private func sendTo(_ sock: Int32, address: String, port: UInt16, payload: Data) {
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(address)
        if addr.sin_addr.s_addr == 0xFFFF_FFFF && address != "255.255.255.255" { return }
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(sock, base, payload.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Discovery (UDP broadcast of /live/test; Live answers to our reply port, which reveals its IP)

    func broadcastDiscovery() {
        lock.lock(); let sock = fd, p = port; lock.unlock()
        guard sock >= 0 else { return }
        let payload = LiveCommand.test().encode()
        for target in OSCClient.broadcastAddresses() + ["255.255.255.255"] {
            sendTo(sock, address: target, port: p, payload: payload)
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
