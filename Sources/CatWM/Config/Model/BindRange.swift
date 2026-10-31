import AppKit

enum BindRange {
    struct Failure: Error { let message: String }

    static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    static func isRange(_ text: String) -> Bool { text.contains("..") || text.contains("|") }

    static func expand(_ raw: String, keys: Bool) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("|") {
            let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.contains(where: \.isEmpty) ? nil : parts
        }
        guard let dots = trimmed.range(of: "..") else { return [trimmed] }
        let first = trimmed[..<dots.lowerBound].trimmingCharacters(in: .whitespaces)
        var last = trimmed[dots.upperBound...].trimmingCharacters(in: .whitespaces)
        while last.hasPrefix(".") { last.removeFirst() }
        guard !first.isEmpty, !last.isEmpty else { return nil }

        if keys, let i = numberRow.firstIndex(of: first), let j = numberRow.firstIndex(of: last) {
            return i <= j ? Array(numberRow[i...j]) : Array(numberRow[j...i].reversed())
        }
        if first.count == 1, last.count == 1,
           let x = first.lowercased().unicodeScalars.first, let y = last.lowercased().unicodeScalars.first,
           ("a"..."z").contains(Character(x)), ("a"..."z").contains(Character(y)) {
            let seq = x.value <= y.value ? Array(x.value...y.value) : Array((y.value...x.value).reversed())
            let upper = first == first.uppercased()
            return seq.compactMap { UnicodeScalar($0) }
                .map { String(Character($0)) }
                .map { upper ? $0.uppercased() : $0 }
        }
        func split(_ text: String) -> (prefix: String, number: Int)? {
            let digits = text.reversed().prefix(while: \.isNumber)
            guard !digits.isEmpty, let number = Int(String(digits.reversed())) else { return nil }
            var prefix = String(text.dropLast(digits.count))
            if prefix.hasSuffix("-"), prefix.count == 1 { return (String(prefix.dropLast()), -number) }
            if prefix == "+" { prefix = "" }
            return (prefix, number)
        }
        guard let (firstPrefix, firstNumber) = split(first), let (lastPrefix, lastNumber) = split(last),
              lastPrefix.isEmpty || firstPrefix.lowercased() == lastPrefix.lowercased() else { return nil }
        let (span, overflow) = lastNumber.subtractingReportingOverflow(firstNumber)
        guard !overflow, span.magnitude < 100 else { return nil }
        let seq = firstNumber <= lastNumber
            ? Array(firstNumber...lastNumber)
            : Array((lastNumber...firstNumber).reversed())
        return seq.map { firstPrefix + String($0) }
    }

    static func pairs(key: String, dispatcher: String, arg: String) -> Result<[(key: String, arg: String)], Failure> {
        guard let keys = expand(key, keys: true) else {
            return .failure(Failure(message: "can't read the key range `\(key)`"))
        }
        var args = [arg]
        if dispatcher != "exec", !arg.contains(" "), isRange(arg) {
            let expanded = expand(arg, keys: false)
            if dispatcher.lowercased() == "launch", arg.contains("://") || expanded?.count != keys.count {
                return .success(keys.map { ($0, arg) })
            }
            guard let expanded else {
                return .failure(Failure(message: "can't read the range `\(arg)`"))
            }
            args = expanded
        }
        if args.count == 1 { return .success(keys.map { ($0, args[0]) }) }
        guard args.count == keys.count else {
            return .failure(Failure(message: "\(keys.count) key\(keys.count == 1 ? "" : "s") but \(args.count) values"))
        }
        return .success(Array(zip(keys, args)).map { ($0, $1) })
    }
}
