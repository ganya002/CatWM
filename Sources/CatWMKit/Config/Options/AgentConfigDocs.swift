import CryptoKit
import Foundation

package enum AgentConfigDocs {
    package static func render(_ template: String) -> String {
        let rows = Options.all.map { option in
            let names = option.names.map { "`\($0)`" }.joined(separator: " / ")
            let notes = option.documentation.isEmpty ? "" : " " + option.documentation + "."
            let value = "\(option.valueDescription) | `\(option.defaultText)`"
            return "| `\(option.script)` | \(value) |\(notes) `.conf`: \(names) |"
        }.joined(separator: "\n")
        let defaultLayouts = Config().layouts.map(\.rawValue).joined(separator: ", ")
        let layouts = Layout.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", ")
        return template.replacingOccurrences(of: "{{options}}", with: rows)
            .replacingOccurrences(of: "{{default-layouts}}", with: defaultLayouts)
            .replacingOccurrences(of: "{{layouts}}", with: layouts)
    }

    package static func write(in root: URL) throws {
        let directory = root.appendingPathComponent("Resources/AgentDocs")
        let template = try String(contentsOf: directory.appendingPathComponent("config.template.md"), encoding: .utf8)
        try render(template).write(to: directory.appendingPathComponent("config.md"), atomically: true, encoding: .utf8)
        try ConfigTypes.render().write(to: directory.appendingPathComponent(ConfigTypes.fileName), atomically: true,
                                       encoding: .utf8)
        let manifest = try Data(contentsOf: root.appendingPathComponent("Tools/config-doc-inputs.json"))
        let inputs = try JSONDecoder().decode(Inputs.self, from: manifest)
        var paths = inputs.files
        for directory in inputs.directories {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
            paths += files.filter { $0.hasSuffix(".swift") }.map { directory + "/" + $0 }
        }
        var data = Data()
        for path in paths.sorted() {
            data.append(Data((path + "\0").utf8))
            data.append(try Data(contentsOf: root.appendingPathComponent(path)))
            data.append(0)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "\n"
        try digest.write(to: directory.appendingPathComponent("config.catalog.sha256"), atomically: true,
                         encoding: .utf8)
    }

    private struct Inputs: Decodable {
        package let directories: [String]
        package let files: [String]
    }
}
