import Foundation

/// What `ssh -G` resolves for a destination: the account, address, and port ssh would actually use.
struct SSHResolvedDestination: Equatable, Sendable {
    var user: String
    var hostName: String
    var port: Int
}

/// Reads the user's SSH config through `ssh -G`, which never touches the network. Lets Add Device say
/// which account an empty username means, and reuse an alias that already points at a tailnet machine.
enum SSHConfigLookup {
    static let timeout: TimeInterval = 3

    static func resolve(_ destination: String, executable: String = "/usr/bin/ssh") async -> SSHResolvedDestination? {
        // The host rule rejects anything ssh could read as an option.
        guard RemoteUsageDevice(name: "Device", host: destination, platform: .linux).isValid else { return nil }
        do {
            let output = try await SSHProcess.run(
                executable: executable, arguments: ["-G", destination], input: Data(),
                timeout: timeout, maxOutput: 256 * 1024
            )
            guard output.status == 0, let resolved = parse(output.stdout) else {
                let stderr = String(decoding: output.stderr.prefix(500), as: UTF8.self)
                AppLog.warn(.subprocess, "ssh -G \(destination) exited \(output.status): \(stderr)")
                return nil
            }
            return resolved
        } catch {
            AppLog.warn(.subprocess, "ssh -G \(destination) failed: \(error)")
            return nil
        }
    }

    static func parse(_ data: Data) -> SSHResolvedDestination? {
        var values: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            if values[key] == nil { values[key] = String(parts[1]) }
        }
        guard let user = values["user"], let hostName = values["hostname"] else { return nil }
        return SSHResolvedDestination(user: user, hostName: hostName, port: values["port"].flatMap(Int.init) ?? 22)
    }

    /// Literal `Host` names from the user's own config; wildcard and negated patterns aren't destinations.
    static func aliases(configText: String) -> [String] {
        var seen = Set<String>()
        return configText.split(whereSeparator: \.isNewline).flatMap { line -> [String] in
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
            guard words.first?.lowercased() == "host" else { return [] }
            return words.dropFirst().filter { word in
                !word.contains(where: { "*?!".contains($0) })
                    && RemoteUsageDevice(name: "Device", host: word, platform: .linux).isValid
                    && seen.insert(word.lowercased()).inserted
            }
        }
    }

    /// Each alias in `~/.ssh/config`, resolved. Missing config means no aliases.
    static func resolvedAliases(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    ) async -> [String: SSHResolvedDestination] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [:] }
        var result: [String: SSHResolvedDestination] = [:]
        for alias in aliases(configText: text) {
            if let resolved = await resolve(alias) { result[alias] = resolved }
        }
        return result
    }

    /// The alias whose address is this tailnet machine, so picking it keeps the user, key, and port
    /// already set up for it. Ties go to the alphabetically first alias.
    static func alias(for peer: TailscalePeer, among aliases: [String: SSHResolvedDestination]) -> String? {
        let addresses = Set(peer.addresses.map { $0.lowercased() })
        return aliases.filter { addresses.contains($0.value.hostName.lowercased()) }.keys.sorted().first
    }
}
