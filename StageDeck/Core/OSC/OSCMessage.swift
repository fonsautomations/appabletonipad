import Foundation

/// A single OSC 1.0 argument value.
public enum OSCValue: Equatable, CustomStringConvertible {
    case int32(Int32)
    case int64(Int64)
    case float(Float)
    case double(Double)
    case string(String)
    case blob(Data)
    case bool(Bool)
    case null
    case impulse
    case timetag(UInt64)

    public var description: String {
        switch self {
        case .int32(let v): return "\(v)"
        case .int64(let v): return "\(v)h"
        case .float(let v): return "\(v)f"
        case .double(let v): return "\(v)d"
        case .string(let v): return "\"\(v)\""
        case .blob(let d): return "blob(\(d.count))"
        case .bool(let b): return b ? "T" : "F"
        case .null: return "nil"
        case .impulse: return "I"
        case .timetag(let t): return "t\(t)"
        }
    }

    /// Integer interpretation (ints, floats and bools convert; strings parse).
    public var intValue: Int? {
        switch self {
        case .int32(let v): return Int(v)
        case .int64(let v): return Int(v)
        case .float(let v): return v.isFinite ? Int(v.rounded()) : nil
        case .double(let v): return v.isFinite ? Int(v.rounded()) : nil
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int32(let v): return Double(v)
        case .int64(let v): return Double(v)
        case .float(let v): return Double(v)
        case .double(let v): return v
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var floatValue: Float? {
        guard let d = doubleValue else { return nil }
        return Float(d)
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int32(let v): return String(v)
        case .int64(let v): return String(v)
        case .float(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int32(let v): return v != 0
        case .int64(let v): return v != 0
        case .float(let v): return v != 0
        case .double(let v): return v != 0
        case .string(let s):
            let l = s.lowercased()
            if l == "true" || l == "1" { return true }
            if l == "false" || l == "0" { return false }
            return nil
        default: return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

/// An OSC message: address pattern plus arguments.
public struct OSCMessage: Equatable, CustomStringConvertible {
    public var address: String
    public var arguments: [OSCValue]

    public init(_ address: String, _ arguments: [OSCValue] = []) {
        self.address = address
        self.arguments = arguments
    }

    /// Convenience constructor accepting Swift literals.
    public init(_ address: String, args: [Any]) {
        self.address = address
        self.arguments = args.map { OSCMessage.value(from: $0) }
    }

    public static func value(from any: Any) -> OSCValue {
        switch any {
        case let v as OSCValue: return v
        case let v as Int: return .int32(Int32(clamping: v))
        case let v as Int32: return .int32(v)
        case let v as Int64: return .int64(v)
        case let v as Float: return .float(v)
        case let v as Double: return .float(Float(v))
        case let v as Bool: return .bool(v)
        case let v as String: return .string(v)
        case let v as Data: return .blob(v)
        default: return .string(String(describing: any))
        }
    }

    public var description: String {
        "\(address) " + arguments.map { $0.description }.joined(separator: " ")
    }

    // MARK: Encoding

    public func encode() -> Data {
        var data = Data()
        OSCCodec.appendString(address, to: &data)
        var tags = ","
        var payload = Data()
        for arg in arguments {
            switch arg {
            case .int32(let v):
                tags.append("i")
                OSCCodec.appendInt32(v, to: &payload)
            case .int64(let v):
                tags.append("h")
                OSCCodec.appendInt64(v, to: &payload)
            case .float(let v):
                tags.append("f")
                OSCCodec.appendFloat(v, to: &payload)
            case .double(let v):
                tags.append("d")
                OSCCodec.appendDouble(v, to: &payload)
            case .string(let s):
                tags.append("s")
                OSCCodec.appendString(s, to: &payload)
            case .blob(let b):
                tags.append("b")
                OSCCodec.appendInt32(Int32(b.count), to: &payload)
                payload.append(b)
                OSCCodec.pad(&payload)
            case .bool(let b):
                tags.append(b ? "T" : "F")
            case .null:
                tags.append("N")
            case .impulse:
                tags.append("I")
            case .timetag(let t):
                tags.append("t")
                OSCCodec.appendUInt64(t, to: &payload)
            }
        }
        OSCCodec.appendString(tags, to: &data)
        data.append(payload)
        return data
    }

    // MARK: Decoding

    /// Decodes a datagram. Bundles are flattened into their messages (recursively).
    public static func decodePacket(_ data: Data) -> [OSCMessage] {
        if data.count >= 8, data.starts(with: Array("#bundle".utf8) + [0]) {
            return decodeBundle(data)
        }
        if let m = decodeMessage(data) { return [m] }
        return []
    }

    static func decodeBundle(_ data: Data) -> [OSCMessage] {
        var out: [OSCMessage] = []
        var cursor = 16 // "#bundle\0" + 8-byte timetag
        while cursor + 4 <= data.count {
            guard let size = OSCCodec.readInt32(data, at: cursor) else { break }
            cursor += 4
            let length = Int(size)
            guard length >= 0, cursor + length <= data.count else { break }
            let element = data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + length))
            out.append(contentsOf: decodePacket(element))
            cursor += length
        }
        return out
    }

    public static func decodeMessage(_ data: Data) -> OSCMessage? {
        var cursor = 0
        guard let address = OSCCodec.readString(data, at: &cursor), address.hasPrefix("/") else { return nil }
        guard cursor < data.count else { return OSCMessage(address, []) }
        guard let tags = OSCCodec.readString(data, at: &cursor), tags.hasPrefix(",") else {
            return OSCMessage(address, [])
        }
        var args: [OSCValue] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard let v = OSCCodec.readInt32(data, at: cursor) else { return nil }
                cursor += 4
                args.append(.int32(v))
            case "h":
                guard let v = OSCCodec.readInt64(data, at: cursor) else { return nil }
                cursor += 8
                args.append(.int64(v))
            case "f":
                guard let v = OSCCodec.readInt32(data, at: cursor) else { return nil }
                cursor += 4
                args.append(.float(Float(bitPattern: UInt32(bitPattern: v))))
            case "d":
                guard let v = OSCCodec.readInt64(data, at: cursor) else { return nil }
                cursor += 8
                args.append(.double(Double(bitPattern: UInt64(bitPattern: v))))
            case "s", "S":
                guard let s = OSCCodec.readString(data, at: &cursor) else { return nil }
                args.append(.string(s))
            case "b":
                guard let size = OSCCodec.readInt32(data, at: cursor) else { return nil }
                cursor += 4
                let len = Int(size)
                guard len >= 0, cursor + len <= data.count else { return nil }
                args.append(.blob(data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + len))))
                cursor += len
                cursor = OSCCodec.padded(cursor)
            case "T": args.append(.bool(true))
            case "F": args.append(.bool(false))
            case "N": args.append(.null)
            case "I": args.append(.impulse)
            case "t":
                guard let v = OSCCodec.readInt64(data, at: cursor) else { return nil }
                cursor += 8
                args.append(.timetag(UInt64(bitPattern: v)))
            case "[", "]":
                continue
            default:
                // Unknown tag: we cannot know its size; stop parsing arguments.
                return OSCMessage(address, args)
            }
        }
        return OSCMessage(address, args)
    }
}

/// Low-level helpers for OSC binary encoding.
public enum OSCCodec {
    public static func padded(_ n: Int) -> Int { (n + 3) & ~3 }

    public static func pad(_ data: inout Data) {
        let target = padded(data.count)
        while data.count < target { data.append(0) }
    }

    public static func appendString(_ s: String, to data: inout Data) {
        data.append(contentsOf: Array(s.utf8))
        data.append(0)
        pad(&data)
    }

    public static func appendInt32(_ v: Int32, to data: inout Data) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public static func appendInt64(_ v: Int64, to data: inout Data) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public static func appendUInt64(_ v: UInt64, to data: inout Data) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public static func appendFloat(_ v: Float, to data: inout Data) {
        appendInt32(Int32(bitPattern: v.bitPattern), to: &data)
    }

    public static func appendDouble(_ v: Double, to data: inout Data) {
        appendInt64(Int64(bitPattern: v.bitPattern), to: &data)
    }

    public static func readInt32(_ data: Data, at offset: Int) -> Int32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let base = data.startIndex + offset
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(data[base + i]) }
        return Int32(bitPattern: v)
    }

    public static func readInt64(_ data: Data, at offset: Int) -> Int64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        let base = data.startIndex + offset
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(data[base + i]) }
        return Int64(bitPattern: v)
    }

    public static func readString(_ data: Data, at cursor: inout Int) -> String? {
        guard cursor >= 0, cursor < data.count else { return nil }
        let base = data.startIndex
        var end = cursor
        while end < data.count, data[base + end] != 0 { end += 1 }
        guard end < data.count else { return nil } // no terminator
        let bytes = data.subdata(in: (base + cursor)..<(base + end))
        let s = String(decoding: bytes, as: UTF8.self)
        cursor = padded(end + 1)
        return s
    }
}
