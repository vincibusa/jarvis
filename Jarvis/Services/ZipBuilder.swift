import Foundation
import zlib

/// Assembles a valid ZIP file in memory.
/// Uses raw DEFLATE (zlib with negative windowBits), the same library used
/// by DocxParser for inflation.
struct ZipBuilder {

    private struct Entry {
        let path: String
        let compressedData: Data
        let crc32: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16  // 0 = stored, 8 = deflate
        let localHeaderOffset: UInt32
    }

    private var entries: [Entry] = []
    private var buffer = Data()

    /// Add a file entry to the archive.
    /// - Parameters:
    ///   - path: Path inside the ZIP (e.g. "word/document.xml")
    ///   - data: Raw (uncompressed) file content
    ///   - compress: If true, deflate the data; falls back to stored if compressed is larger
    mutating func addEntry(path: String, data: Data, compress: Bool = true) {
        let crc = data.zipCRC32()
        let rawSize = UInt32(data.count)

        let (compressedData, method): (Data, UInt16)
        if compress, let deflated = zipDeflate(data), deflated.count < data.count {
            compressedData = deflated
            method = 8
        } else {
            compressedData = data
            method = 0
        }

        let localHeaderOffset = UInt32(buffer.count)
        let pathBytes = path.data(using: .utf8) ?? Data()

        // Local file header (30 bytes + filename)
        buffer.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])  // signature
        buffer.zipWriteUInt16(20)                              // version needed
        buffer.zipWriteUInt16(0)                               // flags
        buffer.zipWriteUInt16(method)                          // compression
        buffer.zipWriteUInt16(0)                               // mod time
        buffer.zipWriteUInt16(0)                               // mod date
        buffer.zipWriteUInt32(crc)
        buffer.zipWriteUInt32(UInt32(compressedData.count))
        buffer.zipWriteUInt32(rawSize)
        buffer.zipWriteUInt16(UInt16(pathBytes.count))
        buffer.zipWriteUInt16(0)                               // extra field length
        buffer.append(pathBytes)
        buffer.append(compressedData)

        entries.append(Entry(
            path: path,
            compressedData: compressedData,
            crc32: crc,
            uncompressedSize: rawSize,
            compressionMethod: method,
            localHeaderOffset: localHeaderOffset
        ))
    }

    /// Finalize and return the complete ZIP file as Data.
    mutating func finalize() -> Data {
        let centralDirStart = UInt32(buffer.count)
        var centralDirSize: UInt32 = 0

        for entry in entries {
            let pathBytes = entry.path.data(using: .utf8) ?? Data()
            // Central directory header (46 bytes + filename)
            buffer.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])  // signature
            buffer.zipWriteUInt16(20)           // version made by
            buffer.zipWriteUInt16(20)           // version needed
            buffer.zipWriteUInt16(0)            // flags
            buffer.zipWriteUInt16(entry.compressionMethod)
            buffer.zipWriteUInt16(0)            // mod time
            buffer.zipWriteUInt16(0)            // mod date
            buffer.zipWriteUInt32(entry.crc32)
            buffer.zipWriteUInt32(UInt32(entry.compressedData.count))
            buffer.zipWriteUInt32(entry.uncompressedSize)
            buffer.zipWriteUInt16(UInt16(pathBytes.count))
            buffer.zipWriteUInt16(0)            // extra length
            buffer.zipWriteUInt16(0)            // comment length
            buffer.zipWriteUInt16(0)            // disk start
            buffer.zipWriteUInt16(0)            // internal attrs
            buffer.zipWriteUInt32(0)            // external attrs
            buffer.zipWriteUInt32(entry.localHeaderOffset)
            buffer.append(pathBytes)

            centralDirSize += UInt32(46 + pathBytes.count)
        }

        // End of central directory record
        buffer.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])  // signature
        buffer.zipWriteUInt16(0)                // disk number
        buffer.zipWriteUInt16(0)                // disk with central dir
        buffer.zipWriteUInt16(UInt16(entries.count))
        buffer.zipWriteUInt16(UInt16(entries.count))
        buffer.zipWriteUInt32(centralDirSize)
        buffer.zipWriteUInt32(centralDirStart)
        buffer.zipWriteUInt16(0)                // comment length

        return buffer
    }

    // MARK: - Raw DEFLATE (no zlib/gzip header, same as ZIP compression method 8)

    private func zipDeflate(_ data: Data) -> Data? {
        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        let capacity = Int(deflateBound(&stream, uLong(data.count)))
        var output = Data(count: capacity)

        let result: Int32 = data.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: src.bindMemory(to: Bytef.self).baseAddress!
                )
                stream.avail_in = uInt(data.count)
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(capacity)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }
}

// MARK: - Data helpers (file-private to avoid collision with DocumentParser.swift)

private extension Data {
    func zipCRC32() -> UInt32 {
        let result: uLong = withUnsafeBytes { buf in
            zlib.crc32(0, buf.bindMemory(to: Bytef.self).baseAddress, uInt(count))
        }
        return UInt32(result)
    }
}

extension Data {
    mutating func zipWriteUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func zipWriteUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
