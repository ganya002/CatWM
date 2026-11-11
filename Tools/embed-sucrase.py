import pathlib
import sys

WIDTH = 116


def ascii_only(script):
    # JavaScriptCore lexes and stores a script of 8-bit characters faster than one with any wider character.
    out = []
    for char in script:
        if ord(char) < 128:
            out.append(char)
            continue
        data = char.encode("utf-16-le")
        out += ["\\u%02x%02x" % (data[i + 1], data[i]) for i in range(0, len(data), 2)]
    return "".join(out)


def render(script):
    script = ascii_only(script)
    lines = []
    for line in script.rstrip("\n").split("\n"):
        chunks = [line[i:i + WIDTH] for i in range(0, len(line), WIDTH)] or [""]
        lines += [chunk + "\\##" for chunk in chunks[:-1]] + [chunks[-1]]
    return 'package enum Sucrase {\n    static let source = ##"""\n' + "\n".join(lines) + '\n"""##\n}\n'


if __name__ == "__main__":
    source, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    output.write_text(render(source.read_text()))
