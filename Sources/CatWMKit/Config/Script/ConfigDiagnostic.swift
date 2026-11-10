import Foundation

package struct ConfigDiagnostic: Equatable {
    package enum Phase: String {
        case read, resolve, transform, evaluate, validate, migrate
    }

    package var file: String?
    package var line: Int?
    package var phase: Phase
    package var message: String

    package var text: String {
        let place = [file.map(URL.init(fileURLWithPath:)).map(\.lastPathComponent), line.map(String.init)]
            .compactMap(\.self).joined(separator: ":")
        return place.isEmpty ? message : "\(place): \(message)"
    }

    package var json: JSON {
        .object(["file": file.map(JSON.string) ?? .null, "line": line.map(JSON.int) ?? .null,
                 "phase": .string(phase.rawValue), "message": .string(message)])
    }

    package init(file: String? = nil, line: Int? = nil, phase: Phase, message: String) {
        self.file = file
        self.line = line
        self.phase = phase
        self.message = message
    }

    package init?(_ json: JSON) {
        guard let message = json["message"]?.string,
              let phase = json["phase"]?.string.flatMap(Phase.init(rawValue:)) else { return nil }
        let file = json["file"]?.string.map { $0.hasPrefix("file://") ? URL(string: $0)?.path ?? $0 : $0 }
        self.init(file: file, line: json["line"]?.int, phase: phase, message: message)
    }
}
