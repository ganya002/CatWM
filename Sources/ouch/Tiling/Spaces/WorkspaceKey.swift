enum WorkspaceKey {
    static func make(_ number: String, on display: String, perDisplay: Bool) -> String {
        perDisplay ? "\(display)/\(number)" : number
    }

    static func display(_ key: String) -> String? {
        key.contains("/") ? String(key[..<key.lastIndex(of: "/")!]) : nil
    }

    static func number(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? key
    }
}
