import AppKit

enum BindRange {
    struct Failure: Error { let message: String }

    static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    static func isRange(_ s: String) -> Bool { s.contains("..") || s.contains("|") }

    static func expand(_ raw: String, keys: Bool) -> [String]? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.contains("|") {
            let parts = t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.contains(where: \.isEmpty) ? nil : parts
        }
        guard let r = t.range(of: "..") else { return [t] }
        let a = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        var b = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        while b.hasPrefix(".") { b.removeFirst() }
        guard !a.isEmpty, !b.isEmpty else { return nil }

        if keys, let i = numberRow.firstIndex(of: a), let j = numberRow.firstIndex(of: b), i <= j {
            return Array(numberRow[i...j])
        }
        if a.count == 1, b.count == 1, let x = a.lowercased().unicodeScalars.first, let y = b.lowercased().unicodeScalars.first,
           ("a"..."z").contains(Character(x)), ("a"..."z").contains(Character(y)) {
            let seq = x.value <= y.value ? Array(x.value...y.value) : Array((y.value...x.value).reversed())
            let upper = a == a.uppercased()
            return seq.map { String(Character(UnicodeScalar($0)!)) }.map { upper ? $0.uppercased() : $0 }
        }
        func split(_ s: String) -> (prefix: String, n: Int)? {
            let digits = s.reversed().prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(String(digits.reversed())) else { return nil }
            var prefix = String(s.dropLast(digits.count))
            if prefix.hasSuffix("-"), prefix.count == 1 { return (String(prefix.dropLast()), -n) }
            if prefix == "+" { prefix = "" }
            return (prefix, n)
        }
        guard let (pa, na) = split(a), let (pb, nb) = split(b), pb.isEmpty || pa.lowercased() == pb.lowercased() else { return nil }
        let (span, overflow) = nb.subtractingReportingOverflow(na)
        guard !overflow, span.magnitude < 100 else { return nil }
        let seq = na <= nb ? Array(na...nb) : Array((nb...na).reversed())
        return seq.map { pa + String($0) }
    }

    static func pairs(key: String, dispatcher: String, arg: String) -> Result<[(key: String, arg: String)], Failure> {
        guard let keys = expand(key, keys: true) else { return .failure(Failure(message: "can't read the key range `\(key)`")) }
        var args = [arg]
        if dispatcher != "exec", !arg.contains(" "), isRange(arg) {
            guard let a = expand(arg, keys: false) else { return .failure(Failure(message: "can't read the range `\(arg)`")) }
            args = a
        }
        if args.count == 1 { return .success(keys.map { ($0, args[0]) }) }
        guard args.count == keys.count else {
            return .failure(Failure(message: "\(keys.count) key\(keys.count == 1 ? "" : "s") but \(args.count) values"))
        }
        return .success(Array(zip(keys, args)).map { ($0, $1) })
    }
}
