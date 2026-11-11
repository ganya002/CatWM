import Foundation

package enum ConfigRuntime {
    package static let source = #"""
    (() => {
      "use strict";
      const compiled = new Map();
      const hostModule = /^\.{1,2}\/(.*\/)?catwm(\.js)?$/;
      let modules = new Map();
      let touched = [];
      let committed = [];
      const fail = (phase, file, line, message) => ({ catwmDiagnostic: true, phase, file, line, message });

      function load(path) {
        if (!touched.includes(path)) touched.push(path);
        const known = modules.get(path);
        if (known) return known.exports;
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
        const module = { exports: {} };
        modules.set(path, module);
        entry.factory.call(undefined, module.exports, (specifier) => {
          if (hostModule.test(String(specifier))) return catwmModule.exports;
          const target = catwmHost.resolve(path, String(specifier));
          if (typeof target !== "string") {
            const candidate = catwmHost.candidate(path, String(specifier));
            if (typeof candidate === "string" && !touched.includes(candidate)) touched.push(candidate);
            throw fail("resolve", path, null, `can't find the module "${specifier}"`);
          }
          return load(target);
        }, module);
        return freeze(module.exports);
      }

      function freeze(value) {
        const host = catwmModule.hosts.has(value) || catwmModule.lists.has(value);
        if (!host && value !== null && typeof value === "object" && !Object.isFrozen(value)) {
          Object.freeze(value);
          for (const key of Object.keys(value)) freeze(value[key]);
        }
        return value;
      }

      function check(value, path, entry, parents) {
        const where = path || "the config";
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

      function rejectDefaultExport(path) {
        const module = modules.get(path);
        if (module && Object.prototype.hasOwnProperty.call(module.exports, "default")) {
          const value = module.exports.default;
          const keys = value !== null && typeof value === "object" && !Array.isArray(value) ? Object.keys(value) : [];
          const examples = (keys.length > 0 ? keys.slice(0, 2) : ["gaps.size"]).map((key) => `catwm.${key} = …`);
          throw fail("validate", path, null, "`export default` no longer sets the config. Add "
            + "`import { catwm } from \"./catwm\"` and assign each option on it, such as "
            + examples.join(" and "));
        }
      }

      function describe(error) {
        if (error && error.catwmDiagnostic) return error;
        if (error && error.catwmUsage) {
          return { ...fail("validate", null, null, error.message), ...catwmModule.locate(error) };
        }
        const message = error && error.message !== undefined ? `${error.name}: ${error.message}` : String(error);
        return fail("evaluate", error && error.sourceURL ? error.sourceURL : null,
                    error && typeof error.line === "number" ? error.line : null, message);
      }

      globalThis.catwmRegistry = {
        run(entry, legacy) {
          touched = [];
          modules = new Map();
          catwmModule.begin();
          try {
            load(entry);
            if (!legacy) rejectDefaultExport(entry);
            const written = catwmModule.finish();
            const value = legacy ? modules.get(entry).exports.default : written;
            check(value, "", entry, []);
            for (const path of [...compiled.keys()]) if (!modules.has(path)) compiled.delete(path);
            return JSON.stringify({ value, files: [...modules.keys()] });
          } catch (error) {
            catwmModule.finish();
            return JSON.stringify({ error: describe(error), files: touched });
          }
        },
        commit() { committed = catwmModule.functions(); },
        late() { return catwmModule.takeLate(); },
        call(index, snapshot) {
          const run = committed[index];
          if (typeof run !== "function") {
            const message = "this key's function is from an older config";
            return JSON.stringify({ error: fail("evaluate", null, null, message) });
          }
          try {
            return JSON.stringify({ actions: catwmModule.call(run, snapshot) });
          } catch (error) {
            return JSON.stringify({ error: describe(error) });
          }
        }
      };
    })();
    """#
}
