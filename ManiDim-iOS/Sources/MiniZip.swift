import Foundation
import Compression

/// Minimal ZIP reader/writer (replaces /usr/bin/zip and /usr/bin/unzip, which don't exist on iOS).
/// Reads stored + deflate entries; writes stored entries.
enum MiniZip {
    struct ZipError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for b in p { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }

    // MARK: Extract

    static func extract(_ zip: URL, to dest: URL) throws {
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard data.count >= 22 else { throw ZipError(msg: "Not a zip file.") }
        var eocd = -1
        var i = data.count - 22
        while i >= max(0, data.count - 65_557) {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError(msg: "Not a zip file.") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        let fm = FileManager.default
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x02014b50 else { throw ZipError(msg: "Corrupt zip directory.") }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let lho = u32(p + 42)
            let name = String(data: data.subdata(in: (p + 46)..<(p + 46 + nlen)), encoding: .utf8) ?? ""
            p += 46 + nlen + elen + clen
            if name.hasSuffix("/") || name.contains("..") { continue }
            guard lho + 30 <= data.count, u32(lho) == 0x04034b50 else { throw ZipError(msg: "Corrupt zip entry.") }
            let start = lho + 30 + u16(lho + 26) + u16(lho + 28)
            guard start + csize <= data.count else { throw ZipError(msg: "Corrupt zip entry.") }
            let raw = data.subdata(in: start..<(start + csize))
            let out: Data
            switch method {
            case 0: out = raw
            case 8:
                var buf = Data(count: max(usize, 1))
                let n = buf.withUnsafeMutableBytes { d in
                    raw.withUnsafeBytes { s in
                        compression_decode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, usize,
                                                  s.bindMemory(to: UInt8.self).baseAddress!, csize, nil, COMPRESSION_ZLIB)
                    }
                }
                guard n == usize else { throw ZipError(msg: "Couldn't decompress \(name).") }
                out = buf.prefix(n)
            default: throw ZipError(msg: "Unsupported zip compression.")
            }
            let target = dest.appendingPathComponent(name)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: target)
        }
    }

    // MARK: Create

    /// Zips `root` (a folder inside `base`) so entries are stored as "<root name>/…".
    static func create(_ zip: URL, folder: URL) throws {
        let fm = FileManager.default
        let prefix = folder.lastPathComponent
        var out = Data()
        var central = Data()
        var count = 0
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        guard let en = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { throw ZipError(msg: "Nothing to zip.") }
        let basePath = folder.resolvingSymlinksInPath().path
        for case let f as URL in en {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = String(f.resolvingSymlinksInPath().path.dropFirst(basePath.count + 1))
            let name = Array("\(prefix)/\(rel)".utf8)
            let d = try Data(contentsOf: f)
            let crc = Int(crc32(d))
            let off = out.count
            var local = Data()
            local.append(contentsOf: le32(0x04034b50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
                         + le32(crc) + le32(d.count) + le32(d.count) + le16(name.count) + le16(0))
            local.append(contentsOf: name)
            out.append(local); out.append(d)
            central.append(contentsOf: le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
                           + le32(crc) + le32(d.count) + le32(d.count) + le16(name.count) + le16(0) + le16(0)
                           + le16(0) + le16(0) + le32(0) + le32(off))
            central.append(contentsOf: name)
            count += 1
        }
        let cdOff = out.count
        out.append(central)
        out.append(contentsOf: le32(0x06054b50) + le16(0) + le16(0) + le16(count) + le16(count) + le32(central.count) + le32(cdOff) + le16(0))
        try out.write(to: zip)
    }
}
