#!/usr/bin/env python3
import os
import re
import sys

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STYLE_ALLOW = re.compile(
    r"^Sources/CatWM/(UI/|Keys/Keyboard/)"
)
STYLE = re.compile(
    r"\.system\(size:"
    r"|Color\(red:"
    r"|cornerRadius: *[0-9]"
    r"|\.(?:easeOut|easeInOut|easeIn|linear)\(duration: *[0-9]"
    r"|\.spring\("
    r"|\.shadow\("
)
PANEL = re.compile(r"\bNSPanel\(")
TOOLS = "// swift-tools-version:"
OK = re.compile(r"^// style-ok: (\S.*\S)$")


def swift_files():
    yield "Package.swift"
    for base in ("Sources", "Tests", "Tools", "Plugins"):
        for dirpath, dirnames, names in os.walk(os.path.join(ROOT, base)):
            dirnames[:] = [d for d in dirnames if d not in (".build", "node_modules")]
            for name in names:
                if name.endswith(".swift"):
                    yield os.path.relpath(os.path.join(dirpath, name), ROOT)


def outside(line, in_multi):
    i = 0
    n = len(line)
    while i < n:
        if in_multi:
            end = line.find('"""', i)
            if end < 0:
                return None, True
            i = end + 3
            in_multi = False
            continue
        if line.startswith('"""', i):
            i += 3
            in_multi = True
            continue
        if line[i] == '"':
            i += 1
            while i < n:
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if i + 1 < n and line[i] == "/" and line[i + 1] in "/*":
            return i, in_multi
        i += 1
    return None, in_multi


def reason_ok(text):
    return " " in text and len(text) >= 12


def banned(path, code):
    hits = []
    if path.startswith("Sources/CatWM/") and not STYLE_ALLOW.search(path) and STYLE.search(code):
        hits.append("hard-coded style. Use a Theme token")
    if path.startswith("Sources/CatWM/") and PANEL.search(code):
        hits.append("NSPanel. Use CatWMPanel")
    return hits


def catalog_violations(path, source):
    if not path.startswith("Sources/CatWM/"):
        return []
    failures = []

    def reject(pattern, reason):
        for match in re.finditer(pattern, source, re.M):
            number = source.count("\n", 0, match.start()) + 1
            failures.append((path, number, reason, source.splitlines()[number - 1].strip()))

    renderer = "Sources/CatWM/Settings/Rows/OptionRows.swift"
    pointer = "Sources/CatWM/Settings/Panes/CursorShortcutSpec.swift"
    feature = "Sources/CatWM/Tiling/Focus/FocusDim.swift"
    quick = "Sources/CatWM/Tiling/Manager/WindowManager+quickActions.swift"
    action_owners = {
        "Sources/CatWM/Templates/Model/TemplateLibrary.swift",
        feature,
    }
    if path != renderer:
        reject(r"\bOption(?:Switch|Slider|Row)(?:<[^>]+>)?\s*(?:\(|\.init\s*\()",
               "catalog: construct option rows only in OptionRows, which reads Options.all")
    if path not in (pointer, feature):
        reject(r"\bCursorShortcutSpec\s*(?:\(|\.init\s*\()", "catalog: declare pointer actions only in PointerActions or the effect descriptor")
        reject(r"\[CursorShortcutSpec\]\s*=\s*\[", "catalog: a second pointer action array is not allowed")
    gallery_registration = re.compile(r"static\s+let\s+\w+\s*=\s*GalleryExample\(\s*order:\s*\d+\s*\)")
    registered_example = path.startswith("Sources/CatWM/UI/") and "/Gallery/" not in path and gallery_registration.search(source)
    if path not in action_owners and not registered_example:
        reject(r"\bQuickAction\s*(?:\(|\.init\s*\()", "catalog: declare quick actions on the feature or its gallery example")
    reject(r"\[(?:QuickAction|KeyHint)\]\s*=\s*\[\s*[^]\s]", "catalog: a hand-written quick action or key hint table is not allowed")
    if path == quick:
        reject(r'\baction\(\s*"', "catalog: quick action literals belong in PointerActions")
    if path == "Sources/CatWM/Keys/Keyboard/KeyHint.swift":
        reject(r'"(?:togglefloating|fullscreen|nativefullscreen|toggledim|toggleblur|killactive|minimize)"',
               "catalog: pointer key hints belong in the action descriptor")
    if path not in (pointer, feature, "Sources/CatWM/Keys/Map/KeyEditor.swift", "Sources/CatWM/Config/Document/Actions.swift"):
        reject(r'\bAction\s*\(\s*title:\s*"', "catalog: action declarations belong in Actions or PointerActions")
    reject(r"\[(?:GalleryExample|ColorToken|SettingEntry|OptionPlacement)\]\s*=\s*\[", "catalog: the build generates gallery, palette, and custom search registries")
    if path != pointer:
        reject(r'PointerActions\.named\(\s*"', "catalog: walk PointerActions.all instead of listing action identities")
    reject(r"static let dispatchers(?:\s*:\s*\[String\])?\s*=\s*\[", "catalog: dispatcher names come from the dispatch implementation")
    if "/UI/Gallery/" in path:
        reject(r"\bGalleryExample\s*\(", "catalog: register the gallery example in its control file")
        reject(r'\bblock\(\s*"', "catalog: put gallery content in the control file")
    if path.endswith("/DesignGalleryView+block.swift"):
        reject(r"\b(?!(?:ScrollView|VStack|ForEach)\b)[A-Z]\w*\s*\(",
               "catalog: the gallery body can only render the discovered registry")
    if "DesignGalleryView" in path:
        reject(r"\bvar\s+(?!(?:body|header|model)\b)\w+\s*:", "catalog: the gallery view must walk GalleryExamples.all")
    if path == "Sources/CatWM/Config/Document/Actions.swift":
        reject(r'\badd\([^\n]*"(?:togglefloating|fullscreen|nativefullscreen|killactive|minimize|toggledim|toggleblur)"',
               "catalog: read pointer commands from PointerActions")
    reject(r'\("[^"\n]+", Theme\.(?:Radius|Space|Icon)\.', "catalog: gallery metrics come from the Theme declarations")
    reject(r'ForEach\(\s*\[\("sm", Elevation', "catalog: elevations come from Elevation.allCases")
    reject(r'for \(dir, name, arrow\) in \[', "catalog: direction actions come from Direction.allCases")
    reject(r'(?:let|var) arrows\s*=\s*\[', "catalog: direction hints come from Direction.hintArrows")
    if path == "Sources/CatWM/Config/Options/Options.swift":
        reject(r'"# tall,', "catalog: layout names come from Layout.allCases")
    return failures


def main():
    failures = []
    for path in sorted(swift_files()):
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            failures.extend(catalog_violations(path, handle.read()))
        in_multi = False
        in_block = False
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            for number, raw in enumerate(handle, 1):
                line = raw.rstrip("\n")
                if in_block:
                    if "*/" in line:
                        in_block = False
                    continue
                idx, in_multi = outside(line, in_multi)
                code = line if idx is None else line[:idx]
                hits = banned(path, code)
                if idx is None:
                    for hit in hits:
                        failures.append((path, number, hit, line.strip()))
                    continue
                comment = line[idx:].strip()
                if comment.startswith("/*"):
                    failures.append((path, number, "block comment. Delete it", line.strip()))
                    if "*/" not in comment:
                        in_block = True
                    continue
                if path == "Package.swift" and comment.startswith(TOOLS):
                    continue
                match = OK.match(comment)
                if match and reason_ok(match.group(1)) and hits:
                    continue
                if match and not reason_ok(match.group(1)):
                    why = "style-ok needs a reason of at least two words"
                elif match and not hits:
                    why = "style-ok is only allowed on a line that breaks a check"
                else:
                    why = "comment. Delete it. A one-off may end with // style-ok: <why this line>"
                failures.append((path, number, why, line.strip()))
            if in_multi:
                failures.append((path, number, "unclosed string", ""))
    import importlib.util
    spec = importlib.util.spec_from_file_location("catalog_generator", os.path.join(ROOT, "Tools/generate-catalogs.py"))
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    try:
        digest_path = os.path.join(ROOT, "Resources/AgentDocs/config.catalog.sha256")
        if not os.path.exists(digest_path) or open(digest_path, encoding="utf-8").read() != generator.config_doc_digest():
            failures.append(("Resources/AgentDocs/config.md", 1, "catalog: config docs are stale. Run ./build.sh --dev", ""))
        generator.gallery_examples()
        option_sources = [os.path.join(ROOT, "Sources/CatWM/Config/Options/Options.swift"), os.path.join(ROOT, "Sources/CatWM/Tiling/Focus/FocusDim.swift")]
        keys = set()
        for source_path in option_sources:
            source = open(source_path, encoding="utf-8").read()
            keys.update(re.findall(r'(?:\.(?:bool|points|number|choice)|ConfigOption)\(\s*"([^"]+)"', source))
            keys.update(re.findall(r'\.aliases\(\s*"([^"]+)"', source))
        template = open(os.path.join(ROOT, "Resources/AgentDocs/config.template.md"), encoding="utf-8").read()
        for marker in ("{{options}}", "{{layouts}}", "{{default-layouts}}"):
            if template.count(marker) != 1:
                failures.append(("Resources/AgentDocs/config.template.md", 1,
                                 "catalog: keep one generated " + marker + " placeholder", ""))
        for match in re.finditer(r'^\| `([^`]+)`', template, re.M):
            if match[1] in keys:
                failures.append(("Resources/AgentDocs/config.template.md", template.count("\n", 0, match.start()) + 1,
                                 "catalog: option table rows come from Options.all", match[0]))
    except ValueError as error:
        failures.append(("Tools/generate-catalogs.py", 1, str(error), ""))
    if failures:
        for path, number, why, text in failures:
            print(f"{path}:{number}: {why}")
            if text:
                print(f"    {text}")
        print()
        print(f"check-style: {len(failures)} violation(s).")
        return 1
    print("check-style: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
