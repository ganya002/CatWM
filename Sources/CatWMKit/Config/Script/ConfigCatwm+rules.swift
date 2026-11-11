import Foundation

extension ConfigCatwm {
    static let rules = #"""
      function recorder(actions) {
        const push = (name, arg) => actions.push(arg === undefined ? name : [name, arg]);
        return {
          float: () => push("setfloating"),
          tile: () => push("settiled"),
          fullscreen: () => push("fullscreen"),
          resize: (width, height) =>
            push("resizeactive", `exact ${finite(width, "width")} ${finite(height, "height")}`),
          move: (x, y) => push("moveactive", `exact ${finite(x, "x")} ${finite(y, "y")}`),
          center: () => push("centerwindow"),
          moveTo: (workspace) => push("movetoworkspacesilent", String(workspace))
        };
      }

      function ruleWindow(actions) {
        const api = recorder(actions);
        const win = { float: api.float, tile: api.tile, fullscreen: api.fullscreen };
        Object.defineProperties(win, {
          size: {
            set(value) {
              if (!isObject(value)) throw usage("`size` must be { width, height }");
              api.resize(value.width, value.height);
            }
          },
          position: {
            set(value) {
              if (value === "center") api.center();
              else if (isObject(value)) api.move(value.x, value.y);
              else throw usage("`position` must be \"center\" or { x, y }");
            }
          },
          workspace: { set: (value) => api.moveTo(value) },
          display: { set: (value) => actions.push(["movewindowtomonitor", String(value)]) }
        });
        return Object.preventExtensions(win);
      }

      function matchOf(match) {
        if (!isPlain(match)) throw usage("the first argument must be an object that says which windows match");
        return Object.fromEntries(Object.entries(match).map(([key, value]) =>
          [key, value instanceof RegExp ? { regex: value.source, flags: value.flags } : value]));
      }

      function declare(name) {
        if (state.phase === "load") return;
        throw refuse(state.phase === "workspaceRule"
          ? `catwm.${name} can't be used inside catwm.workspaces`
          : `call catwm.${name} while the config loads, at the top level of a config file`);
      }

      const api = {
        bind(mods, key, run, options) {
          declare("bind");
          const extra = Object.keys(options || {}).filter((name) => name !== "repeat" && name !== "submap");
          if (extra.length > 0) throw usage(`catwm.bind has no option \`${extra[0]}\` (repeat, submap)`);
          const entry = { mods: Array.isArray(mods) ? [...mods] : mods, key };
          if (typeof run === "function") {
            state.functions.push(run);
            entry.run = { function: state.functions.length - 1 };
          } else {
            entry.run = Array.isArray(run) ? [...run] : run;
          }
          if (options && options.repeat !== undefined) entry.repeat = options.repeat;
          const submap = options && options.submap;
          if (submap) (state.data.submaps[submap] = state.data.submaps[submap] || []).push(entry);
          else state.data.binds.push(entry);
        },
        windows(match, set) {
          declare("windows");
          if (typeof set !== "function") throw usage("catwm.windows needs a function as its second argument");
          const entry = { match: matchOf(match), set: [] };
          state.phase = "windowRule";
          try { set(ruleWindow(entry.set)); } finally { state.phase = "load"; }
          state.data.windowRules.push(entry);
        },
        workspaces(match, set) {
          declare("workspaces");
          if (typeof set !== "function") throw usage("catwm.workspaces needs a function as its second argument");
          const entry = { match: matchOf(match), set: {} };
          const saved = state.data;
          const copy = clone(saved);
          const before = new Map(leaves(setup.defaults, "")
            .filter((leaf) => !hidden.has(leaf) && Array.isArray(shapeAt(leaf)))
            .map((leaf) => [leaf, JSON.stringify(readPath(leaf))]));
          state.data = copy;
          state.written = new Set();
          state.phase = "workspaceRule";
          try {
            set(state.root);
            for (const [leaf, text] of before) if (JSON.stringify(readPath(leaf)) !== text) state.written.add(leaf);
            for (const leaf of [...state.written].sort()) entry.set[leaf] = JSON.parse(JSON.stringify(readPath(leaf)));
          } finally {
            state.phase = "load";
            state.written = null;
            state.data = saved;
          }
          state.data.workspaceRules.push(entry);
        }
      };
    """#
}
