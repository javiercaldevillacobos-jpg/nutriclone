import Foundation

/// Códigos de barras de productos (GTIN: EAN-8, EAN-13, UPC-A, UPC-E).
enum Barcode {
    /// Deja solo los dígitos y lo convierte a la forma con la que Open Food Facts guarda los productos:
    /// UPC-E se expande a UPC-A y UPC-A (12 dígitos) pasa a EAN-13 con un 0 delante.
    /// Devuelve nil si la longitud o el dígito de control no son válidos (lectura defectuosa).
    /// `isUPCE`: el lector indicó que es UPC-E. Sin esa pista, un código de 8 cifras que empieza
    /// por 0/1 y no cuadra como EAN-8 se prueba como UPC-E (útil al teclearlo a mano).
    static func normalize(_ raw: String, isUPCE: Bool = false) -> String? {
        var digits = String(raw.filter(\.isNumber))
        if digits.count == 8, isUPCE || ((digits.first == "0" || digits.first == "1") && !isValidChecksum(digits)),
           let expanded = expandUPCE(digits) {
            digits = expanded
        }
        switch digits.count {
        case 8, 13, 14:
            break
        case 12:
            digits = "0" + digits
        default:
            return nil
        }
        return isValidChecksum(digits) ? digits : nil
    }

    /// Dígito de control GTIN (módulo 10, pesos 3 y 1 desde la derecha sin contar el último).
    static func isValidChecksum(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 8, let check = values.last else { return false }
        let body = values.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { total, item in
            total + item.element * (item.offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// Expande un UPC-E de 8 dígitos (sistema 0 o 1) a UPC-A de 12.
    static func expandUPCE(_ code: String) -> String? {
        let d = code.compactMap(\.wholeNumberValue)
        guard d.count == 8, d[0] == 0 || d[0] == 1 else { return nil }
        let system = d[0]
        let m = Array(d[1...6])
        let check = d[7]
        let body: [Int]
        switch m[5] {
        case 0, 1, 2:
            body = [m[0], m[1], m[5], 0, 0, 0, 0, m[2], m[3], m[4]]
        case 3:
            body = [m[0], m[1], m[2], 0, 0, 0, 0, 0, m[3], m[4]]
        case 4:
            body = [m[0], m[1], m[2], m[3], 0, 0, 0, 0, 0, m[4]]
        default:
            body = [m[0], m[1], m[2], m[3], m[4], 0, 0, 0, 0, m[5]]
        }
        return ([system] + body + [check]).map(String.init).joined()
    }
}
