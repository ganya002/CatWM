import AppKit

func stripComment(_ line: String) -> String {
    var out = ""
    var it = line.makeIterator()
    while let ch = it.next() {
        if ch == "#" {
            var peek = it
            guard peek.next() == "#" else { break }
            it = peek
        }
        out.append(ch)
    }
    return out
}
