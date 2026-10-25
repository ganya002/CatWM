import AppKit

func stripComment(_ line: String) -> String {
    var out = ""
    var iterator = line.makeIterator()
    while let character = iterator.next() {
        if character == "#" {
            var peek = iterator
            guard peek.next() == "#" else { break }
            iterator = peek
        }
        out.append(character)
    }
    return out
}
