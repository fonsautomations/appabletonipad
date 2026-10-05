import Foundation
#if canImport(Compression)
import Compression
#endif

/// Reads an .als file: gunzips it and parses the XML into a snapshot.
enum AbletonSetImport {
    enum ImportError: Error, CustomStringConvertible {
        case unreadable(String)
        case notGzip
        case inflateFailed
        var description: String {
            switch self {
            case .unreadable(let m): return "Could not read the file: \(m)"
            case .notGzip: return "This is not a Live Set (.als files are gzip-compressed XML)."
            case .inflateFailed: return "Could not decompress the Live Set."
            }
        }
    }

    static func load(url: URL) throws -> AbletonSetSnapshot {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        let xml: Data
        if data.count > 2, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B {
            guard let inflated = gunzip(data) else { throw ImportError.inflateFailed }
            xml = inflated
        } else if data.starts(with: Array("<?xml".utf8)) || data.starts(with: Array("<Ableton".utf8)) {
            xml = data
        } else {
            throw ImportError.notGzip
        }
        let name = url.deletingPathExtension().lastPathComponent
        return try AbletonSetParser.parse(xml: xml, name: name)
    }

    /// gzip = 10-byte header (+ optional fields) + raw DEFLATE stream + 8-byte trailer.
    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18 else { return nil }
        let bytes = [UInt8](data)
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            let len = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + len
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { return nil }
        // ISIZE (last 4 bytes) = uncompressed size mod 2^32: a good capacity hint.
        let isize = Int(bytes[bytes.count - 4]) | (Int(bytes[bytes.count - 3]) << 8) | (Int(bytes[bytes.count - 2]) << 16) | (Int(bytes[bytes.count - 1]) << 24)
        let deflate = Data(bytes[offset..<(bytes.count - 8)])
        return inflateRaw(deflate, expectedSize: isize)
    }

    static func inflateRaw(_ input: Data, expectedSize: Int) -> Data? {
        #if canImport(Compression)
        var output = Data()
        output.reserveCapacity(max(expectedSize, input.count * 4))
        let bufferSize = 1 << 20
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }
        var stream = compression_stream(dst_ptr: dst, dst_size: bufferSize, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }
        let result: Data? = input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = base
            stream.src_size = input.count
            while true {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(dst, count: produced) }
                switch status {
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && stream.src_size == 0 { return output }
                    continue
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    return nil
                }
            }
        }
        return result
        #else
        return nil
        #endif
    }
}
