import Foundation

package enum ConfigCatwm {
    package static let source = #"""
    (() => {
      "use strict";
      const hidden = new Set(["binds", "submaps", "windowRules", "workspaceRules"]);
      const hosts = new WeakSet();
      const lists = new WeakSet();
      const state = { phase: "idle", data: null, written: null, late: [], handle: null, root: null, functions: [] };
      let setup = null;

      const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
      const isPlain = (value) => isObject(value) && [Object.prototype, null].includes(Object.getPrototypeOf(value));

      function usage(message) {
        const error = new Error(message);
        error.catwmUsage = true;
        return error;
      }

      function locate(error) {
        for (const frame of String(error && error.stack || "").split("\n")) {
          const match = /@(.+):(\d+):\d+$/.exec(frame);
          if (match && !/\/(catwm-registry|catwm-module|sucrase)\.js$/.test(match[1])) {
            return { file: match[1], line: Number(match[2]) };
          }
        }
        return { file: null, line: null };
      }

      function refuse(message) {
        const error = usage(message);
        if (state.phase === "idle") state.late.push(error);
        return error;
      }

      function adopt(items) {
        const list = Array.from(items);
        Object.defineProperty(list, "remove", {
          value(item) {
            for (let index = this.indexOf(item); index >= 0; index = this.indexOf(item)) this.splice(index, 1);
          }
        });
        lists.add(list);
        return list;
      }

      function clone(value) {
        if (Array.isArray(value)) return adopt(value.map(clone));
        if (!isObject(value)) return value;
        return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
      }

      const shapeAt = (path) =>
        path ? path.split(".").reduce((node, key) => node[key], setup.defaults) : setup.defaults;
      const readPath = (path) => path.split(".").reduce((node, key) => node[key], state.data);

      function leaves(shape, path) {
        if (!isObject(shape)) return [path];
        return Object.keys(shape).flatMap((key) => leaves(shape[key], path ? `${path}.${key}` : key));
      }

      function unknown(path) {
        if (setup.renamed[path]) return usage(`\`${path}\` was renamed to \`${setup.renamed[path]}\``);
        const parent = path.includes(".") ? path.slice(0, path.lastIndexOf(".")) : "";
        const names = Object.keys(parent ? shapeAt(parent) : setup.defaults)
          .filter((key) => parent || !hidden.has(key));
        if (parent === "motion") names.push("style");
        return usage(`\`${path}\` is not a CatWM option (${parent || "catwm"} has ${names.sort().join(", ")})`);
      }

      function guardWrite() {
        if (state.phase === "load" || state.phase === "workspaceRule") return;
        throw refuse(state.phase === "windowRule"
          ? "a window rule changes its window, not options. Set options outside catwm.windows"
          : "set options while the config loads. A write from a promise or a key function comes too late");
      }

      function store(path, value) {
        const parts = path.split(".");
        const key = parts.pop();
        parts.reduce((node, part) => node[part], state.data)[key] = value;
        if (state.written) state.written.add(path);
      }

      function assign(path, value) {
        guardWrite();
        const shape = shapeAt(path);
        if (value === undefined) return leaves(shape, path).forEach((leaf) => store(leaf, clone(shapeAt(leaf))));
        if (isObject(shape)) {
          if (path === "padding" && typeof value === "number") {
            return Object.keys(shape).forEach((side) => store(`padding.${side}`, value));
          }
          if (!isPlain(value)) {
            throw usage(`\`${path}\` must be an object with ${Object.keys(shape).sort().join(", ")}`);
          }
          for (const key of Object.keys(value)) member(path, key, value[key]);
        } else if (Array.isArray(shape)) {
          if (!Array.isArray(value)) throw usage(`\`${path}\` must be a list`);
          store(path, adopt(value));
        } else {
          store(path, value);
        }
      }

      function member(parent, key, value) {
        const path = parent ? `${parent}.${key}` : key;
        if (parent === "motion" && key === "style") return style(value);
        if (!Object.prototype.hasOwnProperty.call(shapeAt(parent), key) || (!parent && hidden.has(key))) {
          throw unknown(path);
        }
        assign(path, value);
      }

      function style(name) {
        guardWrite();
        if (name === undefined) {
          return ["enabled", "duration", "curve", "bounce"].forEach((key) => assign(`motion.${key}`, undefined));
        }
        const found = setup.styles.find((item) => item.id === String(name).toLowerCase());
        if (!found) throw usage(`unknown motion style \`${name}\` (${setup.styles.map((item) => item.id).join(", ")})`);
        for (const key of Object.keys(found.fields)) assign(`motion.${key}`, found.fields[key]);
      }

      function currentStyle() {
        const match = setup.styles.find((item) =>
          Object.keys(item.fields).every((key) => readPath(`motion.${key}`) === item.fields[key]));
        return match ? match.id : undefined;
      }

      function view(path, shape) {
        const callable = path === "workspaces";
        const target = callable ? () => {} : {};
        for (const key of Object.keys(shape)) {
          if (!path && hidden.has(key)) continue;
          const full = path ? `${path}.${key}` : key;
          const child = isObject(shape[key]) ? view(full, shape[key]) : null;
          Object.defineProperty(target, key, {
            enumerable: true,
            get: () => child || readPath(full),
            set: (value) => assign(full, value)
          });
        }
        if (path === "motion") {
          Object.defineProperty(target, "style", { enumerable: true, get: currentStyle, set: style });
        }
        const proxy = new Proxy(target, {
          set(object, key, value, receiver) {
            if (typeof key === "string" && !(key in object)) throw unknown(path ? `${path}.${key}` : key);
            return Reflect.set(object, key, value, receiver);
          },
          apply: (_, __, args) => callable ? api.workspaces(...args) : undefined
        });
        hosts.add(proxy);
        return proxy;
      }

      function finite(value, name) {
        if (typeof value !== "number" || !Number.isFinite(value)) throw usage(`${name} must be a number`);
        return value;
      }

    \#(rules)

      function begin() {
        state.data = clone(setup.defaults);
        state.functions = [];
        state.late = [];
        state.phase = "load";
      }

      globalThis.catwmModule = {
        locate,
        hosts,
        lists,
        install(text) {
          setup = JSON.parse(text);
          state.data = clone(setup.defaults);
          const root = view("", setup.defaults);
          state.root = root;
          for (const name of ["bind", "windows"]) Object.defineProperty(root, name, { value: api[name] });
          Object.defineProperty(root, "window", {
            value: Object.freeze({
              get focused() {
                if (state.phase !== "call") throw usage("catwm.window.focused works inside a bind function");
                return state.handle;
              }
            })
          });
          this.exports = Object.freeze({ catwm: root });
          hosts.add(this.exports);
        },
        begin,
        finish() { state.phase = "idle"; return state.data; },
        functions() { return state.functions; },
        takeLate() {
          const late = state.late.map((error) => ({
            catwmDiagnostic: true, phase: "validate", ...locate(error), message: error.message
          }));
          state.late = [];
          return JSON.stringify(late);
        },
        call(fn, snapshot) {
          const actions = [];
          state.handle = Object.freeze({
            title: snapshot.title, app: snapshot.app, pid: snapshot.pid,
            frame: Object.freeze({ ...snapshot.frame }), ...recorder(actions)
          });
          state.phase = "call";
          try {
            fn();
            return actions;
          } finally {
            state.phase = "idle";
            state.handle = null;
          }
        }
      };
    })();
    """#
}
