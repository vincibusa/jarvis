import Foundation
import PDFKit
import UIKit
import zlib

// MARK: - Protocol

protocol DocumentParser {
    func parse(url: URL) async throws -> String
}

// MARK: - PDF

final class PDFDocumentParser: DocumentParser {
    private let visionService = VisionService()

    func parse(url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ParserError.cannotOpen(url.lastPathComponent)
        }

        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }

            // Render page to CGImage for Vision OCR (handles multi-column layouts correctly)
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            if let cgImage = page.thumbnail(of: size, for: .mediaBox).cgImage,
               let ocrText = try? await visionService.recognizeText(in: cgImage) {
                let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    pages.append(trimmed)
                    continue
                }
            }

            // Fallback: PDFKit text extraction
            if let text = page.string {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    pages.append(trimmed)
                }
            }
        }

        let result = pages.joined(separator: "\n\n")
        if result.isEmpty {
            throw ParserError.emptyContent(url.lastPathComponent)
        }
        return result
    }
}

// MARK: - Plain text

final class PlainTextParser: DocumentParser {
    func parse(url: URL) async throws -> String {
        let data = try Data(contentsOf: url)

        // Try UTF-8 first, then fallback to Latin-1
        if let text = String(data: data, encoding: .utf8) {
            return text
        } else if let text = String(data: data, encoding: .isoLatin1) {
            return text
        } else {
            throw ParserError.cannotOpen(url.lastPathComponent)
        }
    }
}

// MARK: - DOCX

/// DOCX files are ZIP archives. We locate and decompress word/document.xml
/// using Apple's Compression framework, then strip XML tags to get plain text.
final class DocxParser: NSObject, DocumentParser, XMLParserDelegate {

    private var extractedText = ""
    private var insideTextRun = false

    func parse(url: URL) async throws -> String {
        let data = try Data(contentsOf: url)

        // Find "word/document.xml" entry in the ZIP central directory
        guard let xmlData = extractZipEntry(named: "word/document.xml", from: data) else {
            throw ParserError.cannotOpen(url.lastPathComponent)
        }

        return parseXML(data: xmlData)
    }

    // MARK: - ZIP extraction (minimal implementation)

    private func extractZipEntry(named targetPath: String, from zipData: Data) -> Data? {
        // ZIP local file header signature: 0x04034b50
        let signature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        var offset = 0

        while offset + 30 < zipData.count {
            // Check local file header signature
            let sig = zipData[offset..<(offset + 4)]
            guard sig.elementsEqual(signature) else { break }

            // Read compression method (bytes 8-9, little endian)
            let compressionMethod = zipData.readUInt16LE(at: offset + 8)

            // Read compressed size (bytes 18-21)
            let compressedSize = Int(zipData.readUInt32LE(at: offset + 18))

            // Read file name length (bytes 26-27)
            let fileNameLength = Int(zipData.readUInt16LE(at: offset + 26))

            // Read extra field length (bytes 28-29)
            let extraLength = Int(zipData.readUInt16LE(at: offset + 28))

            // Extract file name
            let nameStart = offset + 30
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= zipData.count else { break }
            let nameBytes = zipData[nameStart..<nameEnd]
            let entryName = String(bytes: nameBytes, encoding: .utf8) ?? ""

            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize

            if entryName == targetPath {
                guard dataEnd <= zipData.count else { return nil }
                let entryData = zipData[dataStart..<dataEnd]

                if compressionMethod == 0 {
                    // Stored (no compression)
                    return Data(entryData)
                } else if compressionMethod == 8 {
                    // Deflate
                    return inflate(Data(entryData))
                }
                return nil
            }

            offset = dataEnd
        }
        return nil
    }

    private func inflate(_ data: Data) -> Data? {
        // Raw DEFLATE decompression using zlib with negative windowBits
        var stream = z_stream()

        // inflateInit2 with -MAX_WBITS = raw deflate (no zlib/gzip header)
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let capacity = max(data.count * 10, 65536)
        var output = Data(count: capacity)

        let zlibResult: Int32 = data.withUnsafeBytes { srcBuf in
            output.withUnsafeMutableBytes { dstBuf in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBuf.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(data.count)
                stream.next_out = dstBuf.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(capacity)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }

        guard zlibResult == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }

    // MARK: - XML parsing

    private func parseXML(data: Data) -> String {
        extractedText = ""
        insideTextRun = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        // Clean up excessive whitespace
        let lines = extractedText.components(separatedBy: "\n")
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.joined(separator: " ")
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // w:t = text run in Word XML
        if elementName == "w:t" || elementName == "t" {
            insideTextRun = true
        } else if elementName == "w:p" || elementName == "p" {
            extractedText += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTextRun {
            extractedText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "w:t" || elementName == "t" {
            insideTextRun = false
        }
    }
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case cannotOpen(String)
    case emptyContent(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let name):
            return "Impossibile aprire il documento: \(name)"
        case .emptyContent(let name):
            return "Il documento non contiene testo: \(name)"
        case .unsupportedFormat(let ext):
            return "Formato non supportato: \(ext)"
        }
    }
}

// MARK: - Data helpers

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
