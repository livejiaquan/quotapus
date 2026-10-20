import Foundation

/// Unsaved editor values. Keeps connection validation separate from the SwiftUI layout.
struct RemoteUsageDeviceDraft: Equatable {
    enum Field: CaseIterable, Hashable { case name, host, sshUser, sshPort, wslDistribution, wslUser }

    private let id: String
    private let enabled: Bool
    var name: String
    var host: String
    var sshUser: String
    var sshPort: String
    var wslDistribution: String
    var wslUser: String
    var platform: RemoteUsageDevice.Platform
    /// The machine name a Tailscale pick supplies for a blank Device Name.
    var suggestedName: String?

    init(device: RemoteUsageDevice? = nil) {
        id = device?.id ?? "ssh-\(UUID().uuidString.lowercased())"
        enabled = device?.enabled ?? true
        name = device?.name ?? ""
        host = device?.host ?? ""
        sshUser = device?.sshUser ?? ""
        sshPort = device?.sshPort.map(String.init) ?? ""
        wslDistribution = device?.wslDistribution ?? ""
        wslUser = device?.wslUser ?? ""
        platform = device?.platform ?? .linux
    }

    var validationErrors: [Field: String] {
        var errors: [Field: String] = [:]
        var probe = RemoteUsageDevice(name: "Device", host: trimmed(host), platform: platform)
        if !probe.isValid {
            errors[.host] = trimmed(host).isEmpty ? "Enter a host or IP address."
                : "Use an SSH alias, hostname, or IPv4 address. Enter the username below."
        }
        probe.host = "host"
        probe.sshUser = optional(sshUser)
        if !probe.isValid { errors[.sshUser] = "Use a username, DOMAIN\\user, or user@example.com without spaces." }
        let port = trimmed(sshPort)
        if !port.isEmpty && (Int(port).map { !(1...65_535).contains($0) } ?? true) {
            errors[.sshPort] = "Enter a port from 1 to 65535, or leave it blank."
        }
        if platform == .wsl {
            probe.sshUser = nil
            probe.wslDistribution = optional(wslDistribution)
            if !probe.isValid { errors[.wslDistribution] = "Use a distribution name such as Ubuntu or Ubuntu-24.04." }
            probe.wslDistribution = nil
            probe.wslUser = optional(wslUser)
            if !probe.isValid { errors[.wslUser] = "Use a Linux username without spaces or shell symbols." }
        }
        return errors
    }

    var connectionIdentity: String {
        [trimmed(host), trimmed(sshUser), trimmed(sshPort), platform.rawValue,
         platform == .wsl ? trimmed(wslDistribution) : "",
         platform == .wsl ? trimmed(wslUser) : ""].joined(separator: "|")
    }

    func makeDevice() throws -> RemoteUsageDevice {
        let errors = validationErrors
        if let field = Field.allCases.first(where: { errors[$0] != nil }), let message = errors[field] {
            throw ValidationError(message: message)
        }
        let device = RemoteUsageDevice(
            id: id, name: resolvedName, host: trimmed(host), platform: platform, enabled: enabled,
            sshUser: optional(sshUser), sshPort: Int(trimmed(sshPort)),
            wslDistribution: platform == .wsl ? optional(wslDistribution) : nil,
            wslUser: platform == .wsl ? optional(wslUser) : nil
        )
        guard device.isValid else { throw ValidationError(message: "Check this device's connection details.") }
        return device
    }

    /// The name saved when Device Name is left blank: the picked machine's name (or the host), marked
    /// for WSL so the Windows and WSL devices of one PC read apart.
    var resolvedName: String {
        if let typed = optional(name) { return typed }
        let base = optional(suggestedName ?? "") ?? trimmed(host)
        guard platform == .wsl else { return base }
        return "\(base) (WSL\(optional(wslDistribution).map { " \($0)" } ?? ""))"
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func optional(_ value: String) -> String? { trimmed(value).isEmpty ? nil : trimmed(value) }

    private struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
