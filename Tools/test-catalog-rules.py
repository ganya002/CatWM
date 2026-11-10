import importlib.machinery
import importlib.util
import pathlib
import unittest
import tempfile
import sys

sys.dont_write_bytecode = True

ROOT = pathlib.Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("style", str(ROOT / "Tools/check-style.sh"))
spec = importlib.util.spec_from_loader(loader.name, loader)
style = importlib.util.module_from_spec(spec)
loader.exec_module(style)


class CatalogRules(unittest.TestCase):
    def test_rejects_duplicate_declarations(self):
        cases = [
            ("Settings/Panes/WindowsPane.swift", "OptionSwitch(\\.dimOtherWindows, doc: doc, ui: ui)"),
            ("Settings/Panes/LayoutPane.swift", "OptionSlider(\\.windowMarginSize, doc: doc, ui: ui)"),
            ("Settings/Panes/MotionPane.swift", "OptionRow(\\Config.animationCurve, ui: ui)"),
            ("Settings/Panes/WindowsPane.swift", 'CursorShortcutSpec(id: "dim")'),
            ("Settings/Panes/WindowsPane.swift", "let list: [CursorShortcutSpec] = [.init()]"),
            ("Overlays/Cursor/CursorActions+template.swift", 'out.append(action("dim", "Dim", "toggledim"))'),
            ("Overlays/Cursor/CursorActions+template.swift", 'QuickAction(id: "focus.dim", title: "Dim") {}'),
            ("Overlays/Cursor/CursorActions+template.swift", 'let label = "GalleryExample("\nQuickAction(id: "focus.dim", title: "Dim") {}'),
            ("UI/Components/Rows/TemplateRow.swift", 'let label = "GalleryExample("\nQuickAction(id: "x", title: "Save") {}'),
            ("UI/Gallery/DesignGalleryView.swift", 'static let templates = GalleryExample(order: 15) {}\nQuickAction(id: "x", title: "Save") {}'),
            ("Keys/Keyboard/KeyHint.swift", 'case "toggledim": return "Dim"'),
            ("UI/Gallery/DesignGalleryView.swift", 'var buttons: some View { block("Buttons") {} }'),
            ("UI/Gallery/DesignGalleryView+block.swift", 'OButton("New example") {}'),
            ("UI/Gallery/DesignGalleryView.swift", "let example = GalleryExample(order: 1) {}"),
            ("UI/Components/Controls/OButton.swift", "let all: [GalleryExample] = [.buttons]"),
            ("UI/Gallery/ColorToken.swift", 'static let all: [ColorToken] = [.init(name: "bg")]'),
            ("Settings/Search/SettingsIndex.swift", "let rows: [SettingEntry] = []"),
            ("UI/Gallery/GalleryContent.swift", '[("xs", Theme.Radius.xs)]'),
            ("UI/Theme/Elevation.swift", r'ForEach([("sm", Elevation.sm)], id: \.0) {}'),
            ("Config/Document/Actions.swift", 'for (dir, name, arrow) in [("l", "Left", "left")] {}'),
            ("Keys/Keyboard/KeyHint.swift", 'let arrows = ["l": "←"]'),
            ("Config/Document/Actions.swift", 'static let dispatchers = ["toggledim"]'),
            ("Tiling/Manager/WindowManager+status.swift", 'switch dispatcher {\ncase "minimize": break\n}'),
            ("Tiling/Manager/WindowManager+status.swift", 'static let minimize = WindowAction(name: "minimize")'),
            ("Config/Document/Actions.swift", 'add(ActionPicker("Minimize", .window, "", "minus"))'),
        ]
        for path, source in cases:
            with self.subTest(path=path, source=source):
                self.assertTrue(style.catalog_violations("Sources/CatWM/" + path, source))
                self.assertTrue(style.catalog_violations("Sources/CatWM/" + path, source + " // style-ok: deliberate catalog duplicate"))

    def test_stale_docs_change_the_fingerprint(self):
        generator_spec = importlib.util.spec_from_file_location("generator", ROOT / "Tools/generate-catalogs.py")
        generator = importlib.util.module_from_spec(generator_spec)
        generator_spec.loader.exec_module(generator)
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "Tools").mkdir()
            (root / "Tools/config-doc-inputs.json").write_text('{"directories": [], "files": ["config.md", "Options.swift", "Config.swift"]}')
            for name in ("config.md", "Options.swift", "Config.swift"):
                (root / name).write_text("original")
            original = generator.config_doc_digest(root)
            for name in ("config.md", "Options.swift", "Config.swift"):
                (root / name).write_text("changed")
                self.assertNotEqual(original, generator.config_doc_digest(root))
                (root / name).write_text("original")

    def test_accepts_derived_surfaces(self):
        cases = [
            ("Settings/Rows/OptionRows.swift", "OptionSwitch(path, doc: doc, ui: ui)"),
            ("Settings/Panes/WindowsPane.swift", "PointerActions.all.filter { $0.available(context) }"),
            ("UI/Components/Controls/OButton.swift", "static let buttons = GalleryExample(order: 3) {}"),
            ("Keys/Help/KeyHelp.swift", "binds.map { KeyHint($0) }"),
            ("Overlays/Cursor/TemplateLibrary+quickActions.swift", 'QuickAction(id: "template.save", title: "Save") {}'),
            ("Overlays/Dim/FocusDim.swift", 'QuickAction(id: "focus.dim", title: "Dim") {}'),
            ("Actions/WindowActions+window.swift", 'static let minimize = WindowAction(name: "minimize")'),
            ("Actions/LayoutActions.swift", 'ActionPicker("Swap Sides", .layout, "swapsides", "arrow")'),
            ("Actions/FocusActions.swift", 'static let movefocus = WindowAction.direction("movefocus")'),
            ("UI/Components/Rows/TemplateRow.swift", 'static let templates = GalleryExample(order: 15) {}\nQuickAction(id: "x", title: "Save") {}'),
        ]
        for path, source in cases:
            root = "Sources/CatWMKit/" if path.startswith("Actions/") else "Sources/CatWM/"
            self.assertFalse(style.catalog_violations(root + path, source))


class TilingRules(unittest.TestCase):
    engine = "Sources/CatWMKit/Tiling/Manager/WindowManager+start.swift"

    def test_rejects_ui_in_tiling(self):
        cases = [
            'HUD.shared.show("Tiling on", on: nil)',
            "TabStrips.shared.update()",
            "TabDropHint.shared.hide()",
            'Hotkeys.shared.setSubmap("")',
            "SortPanel.shared.abandon()",
            "Notifications.shared.forget(id)",
            "KeyHelp.shared.install()",
        ]
        for code in cases:
            with self.subTest(code=code):
                self.assertTrue(style.banned(self.engine, code))

    def test_accepts_surface_and_ui_outside_tiling(self):
        for code in ('surface.showHUD("Tiling on", on: nil)', "Hotkeys.post(keyCode: 1, flags: [])",
                     "surface.tabsDidChange(instant: false)"):
            with self.subTest(code=code):
                self.assertFalse(style.banned(self.engine, code))
        self.assertFalse(style.banned("Sources/CatWM/App/AppSurface.swift", "TabStrips.shared.update()"))


class SessionRules(unittest.TestCase):
    session = "Sources/CatWMKit/Session/Restore/WindowMatch.swift"

    def test_rejects_catwm_types_in_session(self):
        cases = [
            "let manager = WindowManager.shared",
            "var model: WorkspaceModel",
            "let layout: Layout = .tall",
            "let gap = Theme.Space.md",
            'HUD.shared.show("Saved", on: nil)',
        ]
        for code in cases:
            with self.subTest(code=code):
                self.assertTrue(style.banned(self.session, code))

    def test_accepts_session_code_and_catwm_types_outside_session(self):
        for code in ("let match = WindowMatch.assign(saved, candidates)", "let frame = element.readFrame().value",
                     "var layoutName: String"):
            with self.subTest(code=code):
                self.assertFalse(style.banned(self.session, code))
        self.assertFalse(style.banned("Sources/CatWMKit/Templates/Restore/TemplateRestorer.swift",
                                      "let manager = WindowManager.shared"))


class FailureRules(unittest.TestCase):
    source = "Sources/CatWMKit/Tiling/Manager/WindowManager+start.swift"

    def test_rejects_discarded_run_errors(self):
        for code in ("try? process.run()", "    _ = try? child.run ()", "try? worker.run(arguments)"):
            with self.subTest(code=code):
                self.assertIn("try? drops a run failure. Use do/catch and record the error with Log",
                              style.banned(self.source, code))

    def test_rejects_discarded_directory_errors(self):
        for code in ("try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)",
                     "    try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)",
                     "_ = try? files.createDirectory (at: url, withIntermediateDirectories: true)"):
            with self.subTest(code=code):
                self.assertIn("try? drops a directory creation failure. Use do/catch and record the error with Log",
                              style.banned(self.source, code))

    def test_rejects_fixed_runloop_waits(self):
        path = "Tests/CatWMTests/CursorHoverTests.swift"
        for code in ("RunLoop.main.run(until: Date().addingTimeInterval(0.05))",
                     "    RunLoop.current.run (until: Date().addingTimeInterval (delay))"):
            with self.subTest(code=code):
                self.assertIn("fixed run-loop wait in a test. Wait on a condition or an injected clock",
                              style.banned(path, code))

    def test_accepts_checked_errors_and_condition_waits(self):
        cases = [
            (self.source, "try process.run()"),
            (self.source, 'do { try process.run() } catch { Log.info("launch: \\(error)") }'),
            (self.source, "if (try? process.run()) != nil { started = true }"),
            (self.source, "let started = (try? process.run()) != nil"),
            (self.source, "try files.createDirectory(at: url, withIntermediateDirectories: true)"),
            (self.source, "guard (try? files.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return }"),
            (self.source, 'let text = "try? process.run()"'),
            (self.source, 'let text = "try? files.createDirectory(at: url)"'),
            ("Tests/CatWMTests/Example.swift", 'let text = "RunLoop.main.run(until: Date().addingTimeInterval(1))"'),
            ("Tests/CatWMTests/Example.swift", "RunLoop.current.run(mode: .modalPanel, before: deadline)"),
            ("Tests/CatWMTests/Example.swift", "await fulfillment(of: [done], timeout: 1)"),
            ("Tests/CatWMTests/Example.swift", "try? process.run()"),
            ("Tools/Probe.swift", "try? files.createDirectory(at: url)"),
            ("Tools/Probe.swift", "RunLoop.main.run(until: Date().addingTimeInterval(1))"),
            (self.source, "RunLoop.main.run(until: Date().addingTimeInterval(1))"),
        ]
        for path, code in cases:
            with self.subTest(path=path, code=code):
                self.assertFalse(style.banned(path, code))

    def test_new_rules_keep_style_exemptions(self):
        cases = [
            (self.source, "try? process.run()"),
            (self.source, "try? files.createDirectory(at: url)"),
            ("Tests/CatWMTests/Example.swift", "RunLoop.main.run(until: Date().addingTimeInterval(1))"),
        ]
        for path, code in cases:
            with self.subTest(code=code):
                line = code + " // style-ok: the test requires this failure"
                idx, in_multi = style.outside(line, False)
                self.assertFalse(in_multi)
                self.assertTrue(style.banned(path, line[:idx]))
                match = style.OK.fullmatch(line[idx:])
                self.assertIsNotNone(match)
                self.assertTrue(style.reason_ok(match.group(1)))

    def test_rejects_unsafe_calls(self):
        cases = [
            (self.source, "let app = AXUIElementCreateApplication(pid)", False),
            (self.source, 'NSLog("CatWM: unknown dispatcher %@", dispatcher)', False),
            (self.source, 'print("moved")', False),
            (self.source, 'try? lines.joined(separator: "\\n").write(to: url, atomically: true, encoding: .utf8)', False),
            (self.source, "    try? FileManager.default.moveItem(at: Self.url, to: bak)", False),
            (self.source, "DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { run() }", False),
            (self.source, "DispatchQueue.main.asyncAfter(deadline: .now() + settle) { run() }", False),
            (self.source, "queue.asyncAfter(deadline: deadline, execute: work)", False),
            (self.source, "try await Task.sleep(for: .milliseconds(20))", False),
            (self.source, "private static var cache: [pid_t: NSImage] = [:]", False),
            (self.source, "static var preview: PanelMotion?", False),
            (self.source, "final class Gate: @unchecked Sendable {", False),
            (self.source, "MainActor.assumeIsolated { wake() }", False),
            ("Tests/CatWMTests/AnimatorTests.swift", "try await Task.sleep(for: .milliseconds(20))", False),
            (self.source, 'let saved = defaults.dictionary(forKey: "grabHints")', True),
            (self.source, 'UserDefaults.standard.set(true, forKey: "didSetUpLaunchAtLogin")', True),
            (self.source, "let flag = UserDefaults.standard.bool(forKey: DefaultsKey.grabHints)", True),
            (self.source, "func load(defaults: UserDefaults = .standard) {", True),
        ]
        for path, code, uses_defaults in cases:
            with self.subTest(code=code):
                self.assertTrue(style.banned(path, code, uses_defaults))

    def test_accepts_the_safe_form(self):
        cases = [
            (self.source, "let app = axApp(pid, timeout: 0.1)", False),
            (self.source, "let flag = Instance.defaults.bool(forKey: DefaultsKey.grabHints)", True),
            (self.source, "init(_ arrangement: Arrangement = .standard) {", False),
            ("Sources/CatWMKit/App/Instance.swift", "guard let suite else { return UserDefaults.standard }", True),
            (self.source, "DispatchQueue.main.async { run() }", False),
            ("Sources/CatWM/Keys/Help/KeyHelp.swift", "DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)", False),
            (self.source, "static var defaultValue: [Int: CGFloat] = [:]", False),
            (self.source, "static var isTestDone: Bool { defaults.bool(forKey: key) }", False),
            (self.source, "static var current: Layout {", False),
            ("Sources/CatWM/UI/Menus/Tooltip.swift", "DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { show() }", False),
            (self.source, 'Log.info("unknown dispatcher \\(dispatcher)")', False),
            (self.source, 'Log.attempt("save configs") { try data.write(to: Self.url, options: .atomic) }', False),
            (self.source, "try? FileManager.default.removeItem(at: marker)", False),
            (self.source, "let text = try? String(contentsOf: url, encoding: .utf8)", False),
            (self.source, "if (try? backup.write(to: url, atomically: true, encoding: .utf8)) != nil {}", False),
            (self.source, "let saved = defaults.dictionary(forKey: DefaultsKey.grabHints)", True),
            (self.source, 'layer.add(animation, forKey: "glow")', False),
            ("Sources/CatWMKit/Session/AX/AXRead.swift", "let app = AXUIElementCreateApplication(pid)", False),
            ("Sources/CatWM/main.swift", "print(dir.path)", False),
            ("Sources/CatWMKit/App/Log.swift", "try? handle.write(contentsOf: line)", False),
            ("Sources/CatWMKit/App/DefaultsKey.swift", 'static let grabHints = "grabHints"', True),
        ]
        for path, code, uses_defaults in cases:
            with self.subTest(code=code):
                self.assertFalse(style.banned(path, code, uses_defaults))


if __name__ == "__main__":
    unittest.main()
