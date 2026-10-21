enum WorkspaceKey {
    static func make(_ number: String, on display: String, perDisplay: Bool) -> String {
        perDisplay ? "\(display)/\(number)" : number
    }

    static func display(_ key: String) -> String? {
        key.lastIndex(of: "/").map { String(key[..<$0]) }
    }

    static func number(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? key
    }
}
