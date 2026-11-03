import Foundation

/// Parser CSV mínimo (RFC 4180): separador configurable, campos entre comillas con
/// comas o saltos de línea dentro, comillas dobles escapadas como "", finales de línea
/// LF o CRLF y BOM de UTF-8 al principio.
///
/// Recorre escalares Unicode y no `Character`, porque en Swift "\r\n" es un único
/// `Character` y rompería la detección de fin de línea.
enum CSVParser {
    static func parse(_ text: String, separator: Unicode.Scalar = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldStarted = false

        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }

        var iterator = scalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldStarted = false
        }
        func endRow() {
            endField()
            // Ignora líneas totalmente vacías.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let scalar = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if scalar == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where !fieldStarted:
                inQuotes = true
                fieldStarted = true
            case separator:
                endField()
            case "\r":
                let next = iterator.next()
                if next != "\n" { pending = next }
                endRow()
            case "\n":
                endRow()
            default:
                field.append(scalar)
                fieldStarted = true
            }
        }
        if fieldStarted || !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
