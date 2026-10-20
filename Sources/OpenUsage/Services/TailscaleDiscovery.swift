import Foundation

/// A machine on the user's tailnet, as reported by the local `tailscale status --json`.
struct TailscalePeer: Equatable, Sendable, Identifiable {
    enum System: Equatable, Sendable { case macOS, linux, windows, unknown }

    /// Tailscale's machine name, for display and as a suggested device name. Can be non-ASCII.
    var name: String
    /// The Tailscale IPv4 (or the MagicDNS name when there is none). Always a valid device host. The IP
    /// comes first because it works even when this Mac doesn't use Tailscale DNS.
    var host: String
    var system: System
    var isOnline: Bool
    /// The MagicDNS name, when Tailscale reports one; only used to recognise this machine elsewhere.
    var dnsName: String? = nil

    var id: String { host }
    /// Every name this machine answers to, for matching saved devices and SSH aliases.
    var addresses: [String] { [host] + (dnsName.map { [$0] } ?? []) }
}

/// Lists tailnet machines for Add Device. Adapted from CodexBar's `TailscaleStatusParser`
/// (steipete/CodexBar, RemoteSessionFetcher.swift), but keeps Windows and unknown-OS peers,
/// uses full MagicDNS names, and returns offline peers so the menu can show them disabled.
enum TailscaleDiscovery {
    enum Outcome: Equatable, Sendable {
        /// Tailscale isn't installed, or no candidate produced readable status. The menu stays hidden.
        case unavailable
        /// Tailscale is installed but its backend isn't running (logged out, stopped).
        case notConnected
        case peers([TailscalePeer])
    }

    /// Parsed status: `nil` from `parse` means the output wasn't Tailscale status at all.
    enum Status: Equatable {
        case running([TailscalePeer])
        case notRunning
    }

    static let timeout: TimeInterval = 5
    private static let maxOutput = 4 * 1024 * 1024
    private static let appBinary = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment) async -> Outcome {
        let candidates = candidates(path: environment["PATH"])
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        let probeEnvironment = cliEnvironment(from: environment)
        return await discover(candidates: candidates) { binary in
            do {
                let output = try await SSHProcess.run(
                    executable: binary, arguments: ["status", "--json"], input: Data(),
                    timeout: timeout, maxOutput: maxOutput, environment: probeEnvironment
                )
                // A stopped backend may exit nonzero yet still print status JSON, so parse whatever came back.
                if output.status != 0 && output.stdout.isEmpty {
                    let stderr = String(decoding: output.stderr.prefix(500), as: UTF8.self)
                    AppLog.warn(.subprocess, "tailscale status via \(binary) exited \(output.status): \(stderr)")
                }
                return output.stdout
            } catch {
                AppLog.warn(.subprocess, "tailscale status via \(binary) failed: \(error)")
                return nil
            }
        }
    }

    /// Tries each candidate in order. A candidate that fails or reports a stopped backend falls
    /// through, so a broken Homebrew CLI doesn't hide a working app binary later in the list.
    static func discover(candidates: [String], run: (String) async -> Data?) async -> Outcome {
        guard !candidates.isEmpty else { return .unavailable }
        var sawNotRunning = false
        for binary in candidates {
            guard let data = await run(binary) else { continue }
            switch parse(data) {
            case .running(let peers): return .peers(peers)
            case .notRunning: sawNotRunning = true
            case nil: AppLog.warn(.subprocess, "tailscale status via \(binary) returned unreadable output")
            }
        }
        if sawNotRunning { return .notConnected }
        AppLog.error(.subprocess, "Tailscale is installed but no candidate returned usable status: \(candidates)")
        return .unavailable
    }

    static func parse(_ data: Data) -> Status? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let state = root["BackendState"] {
            guard let state = state as? String else { return nil }
            guard state.caseInsensitiveCompare("Running") == .orderedSame else { return .notRunning }
        }
        let selfStatus = root["Self"] as? [String: Any]
        let peers: [[String: Any]]
        switch root["Peer"] {
        case let dictionary as [String: [String: Any]]: peers = Array(dictionary.values)
        case let array as [[String: Any]]: peers = array
        case is NSNull: peers = []
        case nil:
            guard selfStatus != nil else { return nil }
            peers = []
        default: return nil
        }

        let localNames = Set([selfStatus?["DNSName"] as? String, selfStatus?["HostName"] as? String]
            .compactMap { $0.map(dnsName)?.lowercased() }.filter { !$0.isEmpty })
        var seen = Set<String>()
        let result = peers.compactMap { peer -> TailscalePeer? in
            guard let system = system(peer["OS"] as? String), let host = host(peer) else { return nil }
            let key = host.lowercased()
            guard !localNames.contains(key), !localNames.contains(firstLabel(key)),
                  seen.insert(key).inserted else { return nil }
            let hostName = (peer["HostName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // iOS reports "localhost"; the DNS label is more useful there.
            let name = hostName.isEmpty || hostName == "localhost" ? firstLabel(host) : hostName
            let dns = (peer["DNSName"] as? String).map(dnsName).flatMap { $0.isEmpty || $0 == host ? nil : $0 }
            return TailscalePeer(name: name, host: host, system: system, isOnline: peer["Online"] as? Bool == true,
                                 dnsName: dns)
        }
        return .running(result.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })
    }

    /// Hides a machine only when it's already saved (by IP, MagicDNS name, or SSH alias) as the System
    /// picking it would fill in, so a Windows host saved as Windows can still be added as Windows + WSL.
    static func unsaved(_ peers: [TailscalePeer], saved: [RemoteUsageDevice],
                        draftPlatform: RemoteUsageDevice.Platform,
                        aliases: [String: SSHResolvedDestination] = [:]) -> [TailscalePeer] {
        let keys = Set(saved.map { "\($0.host.lowercased())|\($0.platform.rawValue)" })
        return peers.filter { peer in
            let platform = RemoteUsageDevice.Platform(tailscale: peer.system, keeping: draftPlatform)
            let names = peer.addresses + aliases.filter { alias in
                peer.addresses.contains { $0.caseInsensitiveCompare(alias.value.hostName) == .orderedSame }
            }.keys
            return !names.contains { keys.contains("\($0.lowercased())|\(platform.rawValue)") }
        }
    }

    /// `tailscale` on PATH, then the usual install paths (a Finder-launched app has a minimal PATH),
    /// then the dual-mode app binary.
    static func candidates(path: String?) -> [String] {
        let directories = (path?.split(separator: ":").map(String.init) ?? []) + ["/usr/local/bin", "/opt/homebrew/bin"]
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }.map { $0 + "/tailscale" } + [appBinary]
    }

    /// Keeps the dual-mode Tailscale app binary in CLI mode instead of launching its GUI.
    static func cliEnvironment(from environment: [String: String]) -> [String: String] {
        var environment = environment
        environment["TAILSCALE_BE_CLI"] = "1"
        if environment["TERM"] == nil, environment["SHLVL"] == nil { environment["SHLVL"] = "1" }
        return environment
    }

    /// Only systems Remote Devices can import from; phones and tablets are dropped.
    /// Some Linux servers (e.g. tsnet nodes) report an empty OS, so those stay as unknown.
    private static func system(_ os: String?) -> TailscalePeer.System? {
        switch os?.lowercased() ?? "" {
        case "macos": .macOS
        case "linux": .linux
        case "windows": .windows
        case "": .unknown
        default: nil
        }
    }

    private static func host(_ peer: [String: Any]) -> String? {
        let candidates = ((peer["TailscaleIPs"] as? [String]) ?? []).filter { !$0.contains(":") }.map(Optional.some)
            + [(peer["DNSName"] as? String).map(dnsName)]
        return candidates.compactMap { $0 }.first { candidate in
            RemoteUsageDevice(name: "Device", host: candidate, platform: .linux).isValid
        }
    }

    private static func dnsName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private static func firstLabel(_ host: String) -> String {
        host.split(separator: ".").first.map(String.init) ?? host
    }
}
