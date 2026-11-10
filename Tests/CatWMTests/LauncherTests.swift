@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Foundation
import Testing

@Suite struct LaunchRequestTests {
    @Test func readsPlacementOptionsFromTheEnd() throws {
        let request = try #require(LaunchRequest("Visual Studio Code workspace=3 display=+1 frame=0,0,50%,1"))
        #expect(request.target == "Visual Studio Code")
        #expect(request.workspace == "3")
        #expect(request.display == "+1")
        #expect(request.frame == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(request.placesWindow)
    }

    @Test func keepsEqualsSignsThatAreNotOptions() throws {
        let request = try #require(LaunchRequest("slack://channel?team=T1&id=C2"))
        #expect(request.target == "slack://channel?team=T1&id=C2")
        #expect(!request.placesWindow)
    }

    @Test func refusesABadFrameOrAnEmptyTarget() {
        #expect(LaunchRequest("Safari frame=0.5,0,0.6,1") == nil)
        #expect(LaunchRequest("Safari frame=0,0,1") == nil)
        #expect(LaunchRequest("Safari frame=0,,0,1,1") == nil)
        #expect(LaunchRequest("Safari workspace=") == nil)
        #expect(LaunchRequest("  ") == nil)
    }
}

@Suite struct LauncherResolveTests {
    @Test(arguments: ["mailto:hello@example.com", "tel:+4712345678", "obsidian:open?vault=Work&file=Today"])
    func resolvesURLsWithoutDoubleSlashes(_ text: String) throws {
        #expect(Launcher.resolve(text) == .open(try #require(URL(string: text))))
    }

    @Test func resolvesURLsFilesAndApps() throws {
        #expect(Launcher.resolve("https://example.com") == .open(try #require(URL(string: "https://example.com"))))
        #expect(Launcher.resolve("/tmp") == .open(URL(fileURLWithPath: "/tmp")))
        #expect(Launcher.resolve("~") == .open(URL(fileURLWithPath: NSHomeDirectory())))
        #expect(Launcher.resolve("com.apple.finder").map { if case .app = $0 { true } else { false } } == true)
        #expect(Launcher.resolve("TextEdit") == .app(URL(fileURLWithPath: "/System/Applications/TextEdit.app")))
        #expect(Launcher.resolve("/no/such/file") == nil)
        #expect(Launcher.resolve("No Such App 12345") == nil)
    }

    @Test func resolvesSystemAppsOutsideTheApplicationsFolders() {
        #expect(Launcher.resolve("Finder") == .app(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        #expect(Launcher.resolve("Archive Utility")
            == .app(URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")))
    }
}
