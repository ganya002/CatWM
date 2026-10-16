# Comments

Comments are unallowed. Do not add comments.

`Package.swift` keeps its `// swift-tools-version:` line. Swift Package Manager requires that line.

Building the project

```text
./build.sh 
```

For fast rebuilds while you work, use `./build.sh --dev` (debug build, a few seconds per rebuild). Do not ship a `--dev` build.

# Verifying

### Requires visual verification

build the project
output `open build/ouch.app`
state verifying needs
