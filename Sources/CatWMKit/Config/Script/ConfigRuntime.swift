import Foundation

package enum ConfigRuntime {
    package static let source = #"""
    (() => {
      "use strict";
      let records = new Map();
      let previous = new Map();
      const compiled = new Map();
      let ran = [];
      let touched = [];
      const fail = (phase, file, line, message) => ({ catwmDiagnostic: true, phase, file, line, message });

      function load(path) {
        if (!touched.includes(path)) touched.push(path);
        const known = records.get(path);
        if (known) return known.module.exports;
        const source = catwmHost.read(path);
        if (typeof source !== "string") throw fail("resolve", path, null, "CatWM can't read this file");
        let entry = compiled.get(path);
        if (!entry || entry.source !== source) {
          let code;
          try {
            code = strip(source, path);
          } catch (error) {
            const message = String(error.message).replace(/^Error transforming [^:]*: /, "");
            throw fail("transform", path, error.loc ? error.loc.line : null, message);
          }
          entry = { source, factory: catwmHost.compile(path, code) };
          compiled.set(path, entry);
        }
        const record = { module: { exports: {} }, deps: [], source };
        records.set(path, record);
        ran.push(path);
        entry.factory.call(undefined, record.module.exports, (specifier) => {
          const target = catwmHost.resolve(path, String(specifier));
          if (typeof target !== "string") {
            const candidate = catwmHost.candidate(path, String(specifier));
            if (typeof candidate === "string" && !touched.includes(candidate)) touched.push(candidate);
            throw fail("resolve", path, null, `can't find the module "${specifier}"`);
          }
          if (!record.deps.includes(target)) record.deps.push(target);
          return load(target);
        }, record.module);
        return freeze(record.module.exports);
      }

      function freeze(value) {
        if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
          Object.freeze(value);
          for (const key of Object.keys(value)) freeze(value[key]);
        }
        return value;
      }

      function invalidate(changed) {
        const stale = new Set(changed);
        let grew = true;
        while (grew) {
          grew = false;
          for (const [path, record] of records) {
            if (!stale.has(path) && record.deps.some((dep) => stale.has(dep))) { stale.add(path); grew = true; }
          }
        }
        for (const path of stale) records.delete(path);
      }

      function reachable(entry) {
        const seen = new Set();
        const walk = (path) => {
          if (seen.has(path) || !records.has(path)) return;
          seen.add(path);
          records.get(path).deps.forEach(walk);
        };
        walk(entry);
        for (const path of [...records.keys()]) if (!seen.has(path)) records.delete(path);
        for (const path of [...compiled.keys()]) if (!seen.has(path)) compiled.delete(path);
      }

      function check(value, path, entry, parents) {
        const where = path || "the default export";
        if (typeof value === "function") {
          throw fail("validate", entry, null, `\`${where}\` is a function. A config holds only data`);
        }
        if (typeof value === "number" && !Number.isFinite(value)) {
          throw fail("validate", entry, null, `\`${where}\` is ${value}, not a number CatWM can use`);
        }
        if (typeof value === "bigint" || typeof value === "symbol") {
          throw fail("validate", entry, null, `\`${where}\` is a ${typeof value}. A config holds only data`);
        }
        if (value === null || typeof value !== "object") return;
        if (parents.includes(value)) throw fail("validate", entry, null, `\`${where}\` refers to itself`);
        const proto = Object.getPrototypeOf(value);
        if (!Array.isArray(value) && proto !== Object.prototype && proto !== null) {
          const kind = proto && proto.constructor ? proto.constructor.name : "object";
          throw fail("validate", entry, null, `\`${where}\` is a ${kind}. Use plain objects and arrays`);
        }
        parents.push(value);
        if (Array.isArray(value)) value.forEach((item, index) => check(item, `${where}[${index}]`, entry, parents));
        else for (const key of Object.keys(value)) check(value[key], path ? `${path}.${key}` : key, entry, parents);
        parents.pop();
      }

      function describe(error) {
        if (error && error.catwmDiagnostic) return error;
        const message = error && error.message !== undefined ? `${error.name}: ${error.message}` : String(error);
        return fail("evaluate", error && error.sourceURL ? error.sourceURL : null,
                    error && typeof error.line === "number" ? error.line : null, message);
      }

      globalThis.catwmRegistry = {
        changed() {
          return [...records].filter(([path, record]) => catwmHost.read(path) !== record.source).map(([path]) => path);
        },
        run(entry, changed) {
          const before = new Map(records);
          previous = before;
          ran = [];
          touched = [];
          if (changed === null) records.clear(); else invalidate(changed);
          try {
            const exports = load(entry);
            if (!exports || !Object.prototype.hasOwnProperty.call(exports, "default")) {
              throw fail("validate", entry, null, "the config has no default export. Write `export default { … }`");
            }
            check(exports.default, "", entry, []);
            reachable(entry);
            return JSON.stringify({ value: exports.default, ran, files: [...records.keys()] });
          } catch (error) {
            records = before;
            return JSON.stringify({ error: describe(error), ran, files: touched });
          }
        },
        rollback() { records = previous; }
      };
    })();
    """#
}
