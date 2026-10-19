import AppKit

enum SortCategory: String, CaseIterable {
    case code = "Code", web = "Web", chat = "Chat", media = "Media", files = "Files"

    static let all = allCases

    private static let table: [SortCategory: [String]] = [
        .code: ["com.apple.dt.", "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2",
                "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.", "com.jetbrains.",
                "com.sublimetext.", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty",
                "co.zeit.hyper", "com.panic.Nova", "com.apple.ScriptEditor2", "com.github.GitHubClient",
                "com.postmanlabs.", "com.exafunction.windsurf", "com.microsoft.VSCodeInsiders"],
        .web: ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.", "org.mozilla.", "app.zen-browser.",
               "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.", "com.vivaldi.Vivaldi",
               "org.chromium.Chromium"],
        .chat: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.apple.mail", "com.hnc.Discord",
                "com.microsoft.teams", "com.microsoft.teams2", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp",
                "us.zoom.xos", "com.apple.FaceTime", "com.readdle.", "com.microsoft.Outlook",
                "org.whispersystems.signal-desktop", "com.facebook.archon"],
        .media: ["com.apple.Music", "com.spotify.client", "com.apple.Preview", "com.apple.Photos", "com.figma.Desktop",
                 "com.apple.TV", "com.apple.podcasts", "com.adobe.", "com.apple.QuickTimePlayerX", "org.videolan.vlc",
                 "com.pixelmatorteam.", "com.bohemiancoding.sketch3"]
    ]

    static func of(_ bundleID: String?) -> SortCategory {
        guard let bundleID else { return .files }
        for category in [SortCategory.code, .web, .chat, .media]
        where table[category, default: []].contains(where: { matches(bundleID, $0) }) {
            return category
        }
        return .files
    }

    private static func matches(_ bundleID: String, _ entry: String) -> Bool {
        entry.hasSuffix(".") ? bundleID.hasPrefix(entry) : bundleID == entry || bundleID.hasPrefix(entry + ".")
    }
}
