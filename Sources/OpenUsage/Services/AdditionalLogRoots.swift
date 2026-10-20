import Foundation

/// Optional, read-only session archives. These extend local history without changing where the
/// Claude and Codex CLIs write their live sessions.
struct AdditionalLogRoots: Equatable, Sendable {
    var claudeProjectDirectories: [String] = []
    var codexSessionDirectories: [String] = []

    static func load(text: String?) -> Self {
        guard let text,
              let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sources = root["logSources"] as? [String: Any]
        else { return Self() }

        func paths(_ key: String) -> [String] {
            guard let values = sources[key] as? [String] else { return [] }
            var seen: Set<String> = []
            return values.compactMap { value in
                let path = NSString(string: value).expandingTildeInPath
                guard path.hasPrefix("/"), seen.insert(path).inserted else { return nil }
                return path
            }
        }
        return Self(
            claudeProjectDirectories: paths("claudeProjectDirectories"),
            codexSessionDirectories: paths("codexSessionDirectories")
        )
    }

    static func read() -> Self {
        let path = NSString(string: "~/.quotapus/config.json").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return Self() }
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            AppLog.warn(.config, "extra log roots ignored: can't read ~/.quotapus/config.json: \(error.localizedDescription)")
            return Self()
        }
        if let issue = issue(in: text) {
            AppLog.warn(.config, "extra log roots in ~/.quotapus/config.json: \(issue)")
        }
        return load(text: text)
    }

    /// Why the file's `logSources` can't be used as written, or nil when it can (or isn't set). A
    /// malformed file otherwise just drops the archives, and their spend with them, without a trace.
    static func issue(in text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "the file isn't a valid JSON object, so no extra roots are read" }
        guard let raw = root["logSources"] else { return nil }
        guard let sources = raw as? [String: Any] else { return "\"logSources\" must be an object" }
        for key in ["claudeProjectDirectories", "codexSessionDirectories"] {
            guard let value = sources[key] else { continue }
            guard let paths = value as? [String] else { return "\"\(key)\" must be a list of paths" }
            if let relative = paths.first(where: { !NSString(string: $0).expandingTildeInPath.hasPrefix("/") }) {
                return "\"\(relative)\" in \"\(key)\" is skipped; use an absolute path or one starting with ~"
            }
        }
        return nil
    }
}
