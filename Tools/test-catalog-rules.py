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
            ("Tiling/Manager/WindowManager+quickActions.swift", 'out.append(action("dim", "Dim", "toggledim"))'),
            ("Tiling/Manager/WindowManager+quickActions.swift", 'QuickAction(id: "focus.dim", title: "Dim") {}'),
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
        ]
        for path, source in cases:
            with self.subTest(path=path, source=source):
                self.assertTrue(style.catalog_violations("Sources/ouch/" + path, source))
                self.assertTrue(style.catalog_violations("Sources/ouch/" + path, source + " // style-ok: deliberate catalog duplicate"))

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
            ("Keys/Help/KeyHelpModel.swift", "binds.map { KeyHint($0) }"),
            ("Templates/Model/TemplateLibrary.swift", 'QuickAction(id: "template.save", title: "Save") {}'),
            ("Tiling/Focus/FocusDim.swift", 'QuickAction(id: "focus.dim", title: "Dim") {}'),
            ("UI/Components/Rows/TemplateRow.swift", 'static let templates = GalleryExample(order: 15) {}\nQuickAction(id: "x", title: "Save") {}'),
        ]
        for path, source in cases:
            self.assertFalse(style.catalog_violations("Sources/ouch/" + path, source))


if __name__ == "__main__":
    unittest.main()
