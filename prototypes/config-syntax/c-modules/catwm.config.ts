// PROTOTYPE for #342, candidate C: composable modules. The root only lists them.
//
// HMR: each module is a boundary. CatWM keeps the module graph and the fragment each
// module returned, so a save of submaps/window.ts swaps that module and re-installs only
// the window mode; options.ts re-tiles; nothing else runs again.
// Trade-offs: the real HMR story, and modules can be shared or published ("my vim keys").
// More files and one more idea (fragments) for a new user; the default config should
// stay one file that the user splits when they want to (#347 decides what a module may hold).

import { config } from "catwm"
import options from "./options"
import floatingApps from "./rules/floating"
import globalBinds from "./binds/global"
import windowMode from "./binds/window-mode"

export default config(options, floatingApps, globalBinds, windowMode)
