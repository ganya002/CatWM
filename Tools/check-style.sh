#!/usr/bin/env python3
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STYLE_ALLOW = re.compile(
    r"^Sources/ouch/(UI/|Keys/KeyHintKeyboard\.swift|Keys/MacKeyboard\.swift)"
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
    for base in ("Sources", "Tests", "Tools"):
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
    if path.startswith("Sources/ouch/") and not STYLE_ALLOW.search(path) and STYLE.search(code):
        hits.append("hard-coded style. Use a Theme token")
    if path.startswith("Sources/ouch/") and PANEL.search(code):
        hits.append("NSPanel. Use OuchPanel")
    return hits


def main():
    failures = []
    for path in sorted(swift_files()):
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
