import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGISTRATION = re.compile(r"static\s+let\s+(\w+)\s*=\s*GalleryExample\(\s*order:\s*(\d+)\s*\)")


def gallery_examples():
    examples = []
    paths = sorted(path for base in ("UI", "Motion/Kit") for path in (ROOT / "Sources/CatWM" / base).rglob("*.swift"))
    for path in paths:
        for match in REGISTRATION.finditer(path.read_text()):
            if "Gallery" in path.parts:
                raise ValueError(f"{path}: put the example in its control file")
            examples.append((int(match[2]), match[1]))
    if len({order for order, name in examples}) != len(examples):
        raise ValueError("Gallery example order must be unique")
    if len({name for order, name in examples}) != len(examples):
        raise ValueError("Gallery example names must be unique")
    return sorted(examples)


def config_doc_digest(root=ROOT):
    manifest = json.loads((root / "Tools/config-doc-inputs.json").read_text())
    paths = manifest["files"][:]
    for directory in manifest["directories"]:
        paths += [str(path.relative_to(root)) for path in (root / directory).glob("*.swift")]
    digest = hashlib.sha256()
    for name in sorted(paths):
        digest.update(name.encode() + b"\0" + (root / name).read_bytes() + b"\0")
    return digest.hexdigest() + "\n"


def render():
    names = ",\n".join("        " + name for order, name in gallery_examples())
    gallery = "#if DEBUG\nextension GalleryExamples {\n    static let all: [GalleryExample] = [\n" + names + "\n    ]\n}\n#endif\n"
    palette = (ROOT / "Sources/CatWM/UI/Theme/Palette.swift").read_text()
    colors = [name.strip() for fields in re.findall(r"^    var ([\w, ]+): Pair$", palette, re.M) for name in fields.split(",")]
    tokens = ",\n".join('        ColorToken(name: "' + name + '", path: \\.' + name + ')' for name in colors)
    settings = []
    for path in sorted((ROOT / "Sources/CatWM/Settings").rglob("*.swift")):
        if "Search" in path.parts:
            continue
        for match in re.finditer(r"static\s+let\s+(search\w+)\s*=\s*SettingEntry\(", path.read_text()):
            settings.append(path.stem + "." + match[1])
    placements = []
    pattern = r'OptionRows\s*\(\s*pane:\s*\.(\w+)\s*,\s*section:\s*"([^"]+)"(?:\s*,\s*advanced:\s*(true|false))?'
    for path in sorted((ROOT / "Sources/CatWM/Settings/Panes").glob("*.swift")):
        for pane, section, advanced in re.findall(pattern, path.read_text()):
            placements.append('        OptionPlacement(pane: .' + pane + ', section: "' + section + '", advanced: ' + (advanced or "false") + ')')
    placement_rows = ",\n".join(placements)
    entries = ",\n".join("        " + entry for entry in settings)
    theme = (ROOT / "Sources/CatWM/UI/Theme/Theme.swift").read_text()
    metrics = []
    for kind, name in [("Radius", "radii"), ("Space", "spaces"), ("Icon", "icons")]:
        body = theme.split("    enum " + kind + " {", 1)[1].split("}", 1)[0]
        names = re.findall(r"\b(\w+)\s*(?::\s*CGFloat)?\s*=", body)
        values = ", ".join('("' + value + '", Theme.' + kind + '.' + value + ')' for value in names)
        metrics.append("    static let " + name + ": [(String, CGFloat)] = [" + values + "]")
    metric_source = "\n#if DEBUG\nenum GalleryMetrics {\n" + "\n".join(metrics) + "\n}\n#endif\n"
    return ("import AppKit\nimport CatWMKit\n" + metric_source + gallery
            + "\n#if DEBUG\nextension ColorToken {\n    static let all: [ColorToken] = [\n" + tokens + "\n    ]\n}\n#endif\n"
            + "\nenum CustomSettingsIndex {\n    static let all: [SettingEntry] = [\n" + entries + "\n    ]\n}\n"
            + "\nenum OptionPlacements {\n    static let all: [OptionPlacement] = [\n" + placement_rows + "\n    ]\n}\n")


if __name__ == "__main__":
    pathlib.Path(sys.argv[1]).write_text(render())
