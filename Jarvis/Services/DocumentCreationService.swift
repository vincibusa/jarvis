import Foundation
import UIKit

/// Generates PDF, DOCX, and XLSX files on-device with no external dependencies.
/// PDF uses UIGraphicsPDFRenderer (native iOS).
/// DOCX and XLSX use ZipBuilder + hand-crafted OpenXML.
enum DocumentCreationService {

    // MARK: - PDF

    static func createPDF(title: String, content: String, filename: String? = nil) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 points
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let margin: CGFloat = 50
        let contentWidth = pageRect.width - margin * 2

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let headingFont = UIFont.boldSystemFont(ofSize: 14)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let black = UIColor.black

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            func drawText(_ str: NSAttributedString) {
                let maxSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
                let bounds = str.boundingRect(with: maxSize,
                                              options: [.usesLineFragmentOrigin, .usesFontLeading],
                                              context: nil)
                if y + bounds.height > pageRect.height - margin {
                    ctx.beginPage()
                    y = margin
                }
                str.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: bounds.height))
                y += bounds.height
            }

            // Title
            let titleStr = NSAttributedString(
                string: title,
                attributes: [.font: titleFont, .foregroundColor: black]
            )
            drawText(titleStr)
            y += 16

            // Content: paragraphs separated by \n\n, sections by ## prefix
            let normalized = content.replacingOccurrences(of: "\\n\\n", with: "\n\n")
                                    .replacingOccurrences(of: "\\n", with: "\n")
            let paragraphs = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            for para in paragraphs {
                let isHeading = para.hasPrefix("## ")
                let text = isHeading ? String(para.dropFirst(3)) : para
                let font = isHeading ? headingFont : bodyFont
                let attrStr = NSAttributedString(
                    string: text,
                    attributes: [.font: font, .foregroundColor: black]
                )
                drawText(attrStr)
                y += isHeading ? 10 : 8
            }
        }

        return try writeTempFile(data: data, name: filename ?? sanitize(title), ext: "pdf")
    }

    // MARK: - DOCX

    static func createDocx(title: String, content: String, filename: String? = nil) throws -> URL {
        var zip = ZipBuilder()

        let normalized = content.replacingOccurrences(of: "\\n\\n", with: "\n\n")
                                .replacingOccurrences(of: "\\n", with: "\n")

        zip.addEntry(path: "[Content_Types].xml",
                     data: Data(docxContentTypes.utf8), compress: false)
        zip.addEntry(path: "_rels/.rels",
                     data: Data(docxRels.utf8), compress: false)
        zip.addEntry(path: "word/_rels/document.xml.rels",
                     data: Data(wordDocRels.utf8), compress: false)
        zip.addEntry(path: "word/document.xml",
                     data: Data(buildDocxBody(title: title, content: normalized).utf8))

        return try writeTempFile(data: zip.finalize(),
                                 name: filename ?? sanitize(title), ext: "docx")
    }

    private static func buildDocxBody(title: String, content: String) -> String {
        var wBody = ""

        // Title paragraph — bold 20pt
        wBody += wParagraph(text: title, bold: true, size: 40)

        let paragraphs = content.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for para in paragraphs {
            let isHeading = para.hasPrefix("## ")
            let text = isHeading ? String(para.dropFirst(3)) : para

            if isHeading {
                wBody += wParagraph(text: text, bold: true, size: 28)
            } else {
                // Handle single newlines as line breaks within one paragraph
                let lines = text.components(separatedBy: "\n")
                wBody += "<w:p>"
                for (i, line) in lines.enumerated() {
                    if i > 0 { wBody += "<w:r><w:br/></w:r>" }
                    wBody += "<w:r><w:t xml:space=\"preserve\">\(xmlEscape(line))</w:t></w:r>"
                }
                wBody += "</w:p>"
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>\(wBody)<w:sectPr/></w:body>
        </w:document>
        """
    }

    private static func wParagraph(text: String, bold: Bool, size: Int) -> String {
        let rpr = bold ? "<w:rPr><w:b/><w:sz w:val=\"\(size)\"/></w:rPr>" : ""
        return "<w:p><w:r>\(rpr)<w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r></w:p>"
    }

    // MARK: - XLSX

    static func createXlsx(
        sheetName: String = "Foglio1",
        headers: String,
        rows: String,
        filename: String? = nil
    ) throws -> URL {
        let headerList = headers.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let normalizedRows = rows
            .replacingOccurrences(of: "\\n", with: "\n")
        let rowsList = normalizedRows.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }

        // Build shared string table (all non-numeric strings)
        var strings: [String] = []
        var stringIndex: [String: Int] = [:]

        func internString(_ s: String) -> Int {
            if let idx = stringIndex[s] { return idx }
            let idx = strings.count
            strings.append(s)
            stringIndex[s] = idx
            return idx
        }

        // Pre-populate headers
        for h in headerList { _ = internString(h) }
        // Pre-populate row strings
        for row in rowsList {
            for cell in row where Double(cell) == nil {
                _ = internString(cell)
            }
        }

        // Sheet XML
        var sheetRows = ""

        // Header row (style 1 = bold)
        sheetRows += "<row r=\"1\">"
        for (col, header) in headerList.enumerated() {
            let ref = xlCellRef(row: 1, col: col)
            let sIdx = internString(header)
            sheetRows += "<c r=\"\(ref)\" t=\"s\" s=\"1\"><v>\(sIdx)</v></c>"
        }
        sheetRows += "</row>"

        // Data rows
        for (rowIdx, row) in rowsList.enumerated() {
            let rowNum = rowIdx + 2
            // Pad short rows to header count
            let padded = row + Array(repeating: "", count: max(0, headerList.count - row.count))
            sheetRows += "<row r=\"\(rowNum)\">"
            for (col, cell) in padded.prefix(max(headerList.count, 1)).enumerated() {
                let ref = xlCellRef(row: rowNum, col: col)
                if let num = Double(cell), !cell.isEmpty {
                    // Integer if whole number, else decimal
                    let val = num.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(num)) : String(num)
                    sheetRows += "<c r=\"\(ref)\" t=\"n\"><v>\(val)</v></c>"
                } else {
                    let sIdx = internString(cell)
                    sheetRows += "<c r=\"\(ref)\" t=\"s\"><v>\(sIdx)</v></c>"
                }
            }
            sheetRows += "</row>"
        }

        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """

        let sharedStringsXML = buildSharedStrings(strings)

        var zip = ZipBuilder()
        zip.addEntry(path: "[Content_Types].xml",     data: Data(xlsxContentTypes.utf8), compress: false)
        zip.addEntry(path: "_rels/.rels",             data: Data(xlsxRels.utf8), compress: false)
        zip.addEntry(path: "xl/_rels/workbook.xml.rels", data: Data(xlsxWorkbookRels.utf8), compress: false)
        zip.addEntry(path: "xl/workbook.xml",         data: Data(xlsxWorkbook(sheetName: sheetName).utf8))
        zip.addEntry(path: "xl/worksheets/sheet1.xml", data: Data(sheetXML.utf8))
        zip.addEntry(path: "xl/sharedStrings.xml",   data: Data(sharedStringsXML.utf8))
        zip.addEntry(path: "xl/styles.xml",          data: Data(xlsxStyles.utf8), compress: false)

        return try writeTempFile(data: zip.finalize(),
                                 name: filename ?? "foglio", ext: "xlsx")
    }

    // MARK: - Shared helpers

    private static func writeTempFile(data: Data, name: String, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("\(UUID().uuidString)-\(name).\(ext)")
        try data.write(to: url)
        return url
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return String(
            name.components(separatedBy: invalid)
                .joined(separator: "_")
                .trimmingCharacters(in: .whitespaces)
                .prefix(50)
        )
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func xlCellRef(row: Int, col: Int) -> String {
        var colName = ""
        var c = col
        repeat {
            colName = String(UnicodeScalar(65 + (c % 26))!) + colName
            c = c / 26 - 1
        } while c >= 0
        return "\(colName)\(row)"
    }

    private static func buildSharedStrings(_ strings: [String]) -> String {
        let items = strings
            .map { "<si><t xml:space=\"preserve\">\(xmlEscape($0))</t></si>" }
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        count="\(strings.count)" uniqueCount="\(strings.count)">\(items)</sst>
        """
    }

    // MARK: - DOCX boilerplate

    private static let docxContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let docxRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="word/document.xml"/>
    </Relationships>
    """

    private static let wordDocRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    </Relationships>
    """

    // MARK: - XLSX boilerplate

    private static let xlsxContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/sharedStrings.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
      <Override PartName="/xl/styles.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let xlsxRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let xlsxWorkbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" \
    Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" \
    Target="sharedStrings.xml"/>
      <Relationship Id="rId3" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" \
    Target="styles.xml"/>
    </Relationships>
    """

    private static func xlsxWorkbook(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(xmlEscape(sheetName))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private static let xlsxStyles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
      </fonts>
      <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
      </fills>
      <borders count="1"><border/></borders>
      <cellStyleXfs count="1">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
      </cellStyleXfs>
      <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>
      </cellXfs>
    </styleSheet>
    """
}
