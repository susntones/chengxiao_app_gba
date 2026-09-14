import Foundation

struct Cheat: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var code: String
    var format: Format = .auto
    var isEnabled = true

    enum Format: Int, Codable, CaseIterable, Identifiable {
        case auto = 0, codeBreaker, gameShark, actionReplay, raw
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .auto: return "自动识别"
            case .codeBreaker: return "CodeBreaker"
            case .gameShark: return "GameShark"
            case .actionReplay: return "Action Replay"
            case .raw: return "原始代码（VBA）"
            }
        }
    }

    func validated() throws -> Cheat {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.code = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n").uppercased()
        let raw = "[0-9A-F]{8}:(?:[0-9A-F]{2}|[0-9A-F]{4}|[0-9A-F]{8})"
        let short = "[0-9A-F]{8}[ \\t]*[0-9A-F]{4}"
        let long = "[0-9A-F]{8}[ \\t]*[0-9A-F]{8}"
        let pattern: String
        switch format {
        case .auto: pattern = "(?:\(raw)|\(short)|\(long))"
        case .raw: pattern = raw
        case .codeBreaker: pattern = short
        case .gameShark, .actionReplay: pattern = long
        }
        guard !result.name.isEmpty, !result.code.isEmpty,
              result.code.components(separatedBy: "\n").allSatisfy({
                  $0.range(of: "^\(pattern)$", options: .regularExpression) != nil
              }) else {
            throw CheatError.invalidCode
        }
        return result
    }
}

enum CheatError: LocalizedError {
    case invalidCode
    var errorDescription: String? {
        "请填写名称和有效代码，每行一条；检查代码格式是否匹配。"
    }
}

/// Stable ROM filename key, independent of SwiftData's process-dependent hash values.
struct CheatStore {
    let url: URL

    func load() throws -> [Cheat] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Cheat].self, from: Data(contentsOf: url))
    }

    func save(_ cheats: [Cheat]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cheats).write(to: url, options: .atomic)
    }
}
