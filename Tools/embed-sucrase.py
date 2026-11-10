import pathlib
import sys

WIDTH = 116


def render(script):
    lines = []
    for line in script.rstrip("\n").split("\n"):
        chunks = [line[i:i + WIDTH] for i in range(0, len(line), WIDTH)] or [""]
        lines += [chunk + "\\##" for chunk in chunks[:-1]] + [chunks[-1]]
    return 'package enum Sucrase {\n    static let source = ##"""\n' + "\n".join(lines) + '\n"""##\n}\n'


if __name__ == "__main__":
    source, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    output.write_text(render(source.read_text()))
