# CatWM libraries

Control the running CatWM app from your own code. Each library is generated from [`schema.json`](schema.json), so each one has every command and event. CatWM must run. The libraries connect to `~/.config/catwm/catwm.sock`. Set `CATWM_SOCKET` to use another path.

```python
# Python 3.10+, no dependencies. Add Clients/python to PYTHONPATH, or pip install it.
from catwm import CatWM

with CatWM() as catwm:
    catwm.workspace("2")
    print(catwm.windows())

for event in CatWM.events("focus.changed"):
    print(event["data"])
```

```ts
// Node 18+. Run `npm install && npm run build` in Clients/typescript.
import { CatWM } from "catwm-client";

const catwm = await CatWM.connect();
await catwm.movefocus("left");
for await (const event of catwm.events("focus.changed")) console.log(event.data);
```

```swift
// Add Clients/swift as a package dependency.
import CatWMClient

let catwm = try CatWM()
try catwm.movefocus(direction: .left)
for try await event in CatWM.events(["focus.changed"]) { print(event) }
```

Each library also has a `call(name, args)` method for any command by name.

Do not edit the generated files. See [docs/internals/control.md](../docs/internals/control.md) to change or add commands.
