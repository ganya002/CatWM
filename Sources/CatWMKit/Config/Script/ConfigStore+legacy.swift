import Foundation

extension ConfigStore {
    package func convertLegacyConfig() {
        guard !embedded, !isLoaded else { return }
        conversionFailure = convertLegacyScript()
    }

    private func convertLegacyScript() -> ConfigDiagnostic? {
        guard let text = try? String(contentsOf: scriptURL, encoding: .utf8),
              text.range(of: #"(?m)^\s*export\s+default\b"#, options: .regularExpression) != nil else { return nil }
        let fail = { (reason: String) in
            let problem = ConfigDiagnostic(file: self.scriptURL.path, phase: .migrate,
                                           message: "CatWM couldn't convert \(Self.scriptName) from `export default` "
                                               + "to `catwm` statements, so it left the file alone: \(reason)")
            Log.info("config: \(problem.text)")
            return problem
        }
        guard let run = ConfigEngine(entry: scriptURL, legacy: true).run(timeout: Self.timeLimit) else {
            return fail("the file didn't finish")
        }
        if let failure = run.failures.first { return fail(failure.message) }
        guard let object = run.value?.object else { return nil }
        let value = ConfigMigration.renamed(object)
        var expected = Config()
        if let problem = ConfigScript.read(.object(value), into: &expected, file: nil).first {
            return fail(problem.message)
        }
        let backup = freeBackupURL()
        let source = ConfigMigration.typescript(from: value, header: [
            "// CatWM config, converted from the old default-export form.",
            "// The original stays next to it as \(backup.lastPathComponent).",
            "// Types and completion come from catwm.d.ts. Save the file and CatWM applies the change."
        ])
        if let problem = install(source, matching: expected, backup: backup, fail: fail) { return problem }
        Log.info("config: converted \(Self.scriptName) from `export default` to `catwm` statements. "
            + "The original, with its comments and helper constants, is kept as \(backup.lastPathComponent)")
        return nil
    }

    private func freeBackupURL() -> URL {
        var url = folder.appendingPathComponent(Self.scriptName + ".bak")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(Self.scriptName).\(number).bak")
            number += 1
        }
        return url
    }
}
