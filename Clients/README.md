# Ouch libraries

Control the running Ouch app from your own code. Each library is generated from [`schema.json`](schema.json), so each one has every command and event. Ouch must run. The libraries connect to `~/.config/ouch/ouch.sock`. Set `OUCH_SOCKET` to use another path.

```python
# Python 3.10+, no dependencies. Add Clients/python to PYTHONPATH, or pip install it.
from ouch import Ouch

with Ouch() as ouch:
    ouch.workspace("2")
    print(ouch.windows())

for event in Ouch.events("focus.changed"):
    print(event["data"])
```

```ts
// Node 18+. Run `npm install && npm run build` in Clients/typescript.
import { Ouch } from "ouch-client";

const ouch = await Ouch.connect();
await ouch.movefocus("left");
for await (const event of ouch.events("focus.changed")) console.log(event.data);
```

```swift
// Add Clients/swift as a package dependency.
import OuchClient

let ouch = try Ouch()
try ouch.movefocus(direction: .left)
for try await event in Ouch.events(["focus.changed"]) { print(event) }
```

Each library also has a `call(name, args)` method for any command by name.

Do not edit the generated files. See [docs/internals/control.md](../docs/internals/control.md) to change or add commands.
