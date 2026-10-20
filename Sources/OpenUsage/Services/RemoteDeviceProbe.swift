import Foundation

/// What the connection check before saving a device learned: the remote system, account, and home, and whether the folders an
/// import reads hold any Codex or Claude logs (so a wrong account or WSL distribution shows up before
/// saving instead of as an empty history).
struct RemoteProbeResult: Equatable, Sendable {
    let platform: String
    let user: String
    let home: String
    let hasCodexLogs: Bool
    let hasClaudeLogs: Bool

    /// Parses the exporter's probe line: `linux | ada | /home/ada | codex=1 claude=0`.
    static func parse(_ response: String) -> RemoteProbeResult? {
        let parts = response.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " | ")
        guard parts.count == 4 else { return nil }
        let flags = Set(parts[3].split(separator: " ").map(String.init))
        return RemoteProbeResult(platform: parts[0], user: parts[1], home: parts[2],
                                 hasCodexLogs: flags.contains("codex=1"), hasClaudeLogs: flags.contains("claude=1"))
    }

    var hasAnyLogs: Bool { hasCodexLogs || hasClaudeLogs }

    var logsSummary: String {
        switch (hasCodexLogs, hasClaudeLogs) {
        case (true, true): "Codex and Claude logs found."
        case (true, false): "Codex logs found. No Claude logs."
        case (false, true): "Claude logs found. No Codex logs."
        case (false, false): "No Codex or Claude logs in this account. Check the username or WSL distribution."
        }
    }
}

/// One WSL distribution on a Windows host, as `wsl.exe --list --verbose` reports it. Listing doesn't
/// start any distribution.
struct WSLDistribution: Equatable, Sendable, Identifiable {
    let name: String
    /// Windows' own wording (e.g. "Running", "Stopped"), shown as-is so a localized Windows still reads right.
    let state: String
    let isDefault: Bool

    var id: String { name }

    static let listCommand = "wsl.exe --list --verbose"

    /// Distributions that tools create for their own use; they never hold a user's CLI logs.
    static let internalNames: Set<String> = ["docker-desktop", "docker-desktop-data", "rancher-desktop", "rancher-desktop-data"]

    /// `wsl.exe` writes UTF-16LE unless `WSL_UTF8=1` is set, so decode by content rather than assume.
    static func decode(_ data: Data) -> String {
        let text: String
        if data.contains(0) {
            let even = data.count % 2 == 0 ? data : data.dropLast()
            text = String(data: even, encoding: .utf16LittleEndian) ?? ""
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        return text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\0", with: "")
    }

    /// Rows end in a version number; the header and messages such as "no installed distributions" don't,
    /// so they are skipped whatever the Windows display language.
    static func parse(_ data: Data) -> [WSLDistribution] {
        decode(data).components(separatedBy: .newlines).compactMap { line in
            var row = line.trimmingCharacters(in: .whitespaces)
            let isDefault = row.hasPrefix("*")
            if isDefault { row = String(row.dropFirst()).trimmingCharacters(in: .whitespaces) }
            let columns = row.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 3, let last = columns.last, Int(last) != nil,
                  !internalNames.contains(columns[0].lowercased()) else { return nil }
            return WSLDistribution(name: columns[0], state: columns.dropFirst().dropLast().joined(separator: " "),
                                   isDefault: isDefault)
        }
    }
}
