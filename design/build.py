import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
tokens = json.loads((HERE / "tokens.json").read_text())


def themed(value, theme, first):
    if isinstance(value, dict):
        return value.get(theme, value[first])
    return value


def block(selector, lines):
    return selector + " {\n" + "".join(f"  {line}\n" for line in lines) + "}\n"


themes = [t["id"] for t in tokens["color"]["themes"]]
first = themes[0]
out = [f"/* {tokens['name']} — generated from tokens.json by build.py */\n"]

for theme in themes:
    lines = []
    for t in tokens["color"]["tokens"]:
        if theme in t["value"] or theme == first:
            lines.append(f"--{t['name']}: {themed(t['value'], theme, first)};")
    for t in tokens.get("shadow", {}).get("tokens", []):
        lines.append(f"--{t['name']}: {themed(t['value'], theme, first)};")
    selector = f':root, [data-theme="{theme}"]' if theme == first else f'[data-theme="{theme}"]'
    out.append(block(selector, lines))

root = []
for family in ("spacing", "radius", "size"):
    for t in tokens.get(family, {}).get("tokens", []):
        root.append(f"--{t['name']}: {t['value']};")
for name, stack in tokens["type"]["families"].items():
    root.append(f"--font-{name}: {stack};")
for group in tokens["type"]["groups"]:
    for s in group["styles"]:
        family = s.get("family") or group["family"]
        root.append(f"--text-{s['name']}: {s['fontWeight']} {s['fontSize']}/{s['lineHeight']} var(--font-{family});")
out.append(block(":root", root))

for group in tokens["type"]["groups"]:
    for s in group["styles"]:
        family = s.get("family") or group["family"]
        out.append(block(f".{s['name']}", [
            f"font-family: var(--font-{family});",
            f"font-size: {s['fontSize']};",
            f"line-height: {s['lineHeight']};",
            f"font-weight: {s['fontWeight']};",
            f"letter-spacing: {s['letterSpacing']};",
        ]))

for f in tokens["type"]["fonts"]:
    out.append(block("@font-face", [
        f'font-family: "{f["family"]}";',
        f'src: url("{f["file"]}") format("woff2");',
        f'font-weight: {f["weight"]};',
        f'font-style: {f.get("style", "normal")};',
        "font-display: swap;",
    ]))

(HERE / "tokens.css").write_text("\n".join(out))

cards = []
for preview in sorted((HERE / "components").glob("*/preview.html")):
    head = preview.read_text().splitlines()[0]
    meta = {k: a or b for k, a, b in re.findall(r'(\w+)=(?:"([^"]*)"|(\d+))', head)}
    cards.append({
        "name": preview.parent.name,
        "group": meta.get("group", ""),
        "height": int(meta.get("height", 200)),
        "width": int(meta["width"]) if "width" in meta else None,
        "subtitle": meta.get("subtitle", ""),
    })
(HERE / "components" / "index.json").write_text(json.dumps({"themes": themes, "cards": cards}, indent=2) + "\n")
print(f"tokens.css: {len(themes)} themes; {len(cards)} component previews")
