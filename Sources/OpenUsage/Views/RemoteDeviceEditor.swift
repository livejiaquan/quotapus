import AppKit
import SwiftUI

struct RemoteDeviceEditor: View {
    let store: RemoteUsageDeviceStore
    let onFinish: () -> Void
    private let isNew: Bool
    @State private var draft: RemoteUsageDeviceDraft
    @State private var showSSHOptions: Bool
    @State private var showWSLOptions: Bool
    @State private var showSetupGuide: Bool
    @State private var copiedSSHCommand = false
    @State private var touchedFields: Set<RemoteUsageDeviceDraft.Field> = []
    @State private var attemptedSubmit = false
    @State private var operation: Operation?
    @State private var probeResult: RemoteProbeResult?
    @State private var operationError: String?
    @State private var tailscale: TailscaleDiscovery.Outcome?
    /// The host the Tailscale menu last filled in, so its button keeps naming the machine until Host is edited.
    @State private var pickedHost: String?
    /// The last check failed or found no logs for these exact details; the next press saves anyway.
    @State private var allowAnyway = false
    /// Tailscale didn't report the picked machine's system, so Linux is only a guess.
    @State private var systemGuessed = false
    /// `~/.ssh/config` aliases resolved by `ssh -G`, so picking a tailnet machine can reuse one.
    @State private var sshAliases: [String: SSHResolvedDestination] = [:]
    /// The account ssh would log in as when Username is left blank.
    @State private var defaultSSHUser: String?
    @FocusState private var focusedField: RemoteUsageDeviceDraft.Field?
    private enum Operation { case checking, saving }
    /// The saved connection, so editing only the name saves without reconnecting.
    private let originalConnection: String?

    init(store: RemoteUsageDeviceStore, device: RemoteUsageDevice? = nil, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        isNew = device == nil
        // Each editor session owns a fresh draft; no field is persisted before Save.
        let draft = RemoteUsageDeviceDraft(device: device)
        _draft = State(initialValue: draft)
        originalConnection = device == nil ? nil : draft.connectionIdentity
        _showSSHOptions = State(initialValue: device?.sshPort != nil)
        _showWSLOptions = State(initialValue: device?.wslDistribution != nil || device?.wslUser != nil)
        // Setup help stays folded until a connection fails; then it opens on the fix.
        _showSetupGuide = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "Add Device" : "Edit Device").font(.body.weight(.semibold))
                Spacer()
                Button("Cancel", action: onFinish).buttonStyle(.borderless).disabled(operation != nil)
            }
            // With Tailscale, picking the machine fills Host, System, and the name in one step.
            if showsTailscale {
                HStack {
                    Text("Machine").font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    tailscaleMenu
                }
                help("Pick a Tailscale machine, or type its address below.")
                Divider()
            }
            field(.host, "Host or IP Address", placeholder: "lab-server or 192.168.1.20", text: $draft.host)
            // The system decides what the username below means and where logs are read.
            HStack {
                Text("System").font(.caption.weight(.medium))
                Spacer(minLength: 8)
                Picker("System", selection: $draft.platform) {
                    ForEach(Self.platformOrder, id: \.self) { platform in
                        Text(platform == .wsl ? "Windows + WSL" : platform.rawValue).tag(platform)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize().disabled(operation != nil)
            }
            help(systemHelp)
            if systemGuessed {
                Label("Tailscale didn't report this machine's system, so Linux is a guess. Check it.",
                      systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
            field(.sshUser, windowsSSH ? "Windows Username" : "SSH Username",
                  placeholder: sshUserPlaceholder, text: $draft.sshUser, optional: true)
            if let warning = macUsernameWarning {
                Label(warning, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $showSSHOptions) {
                field(.sshPort, "Port", placeholder: "From SSH config, otherwise 22", text: $draft.sshPort, optional: true)
                    .padding(.top, 8)
            } label: {
                Text("Advanced SSH")
                    .accessibilityHint(showSSHOptions
                        ? "Contains the optional SSH port setting."
                        : "Expand to set a custom SSH port.")
            }
            .font(.caption.weight(.medium))
            if draft.platform == .wsl {
                DisclosureGroup(isExpanded: $showWSLOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(.wslDistribution, "Distribution", placeholder: "Windows default", text: $draft.wslDistribution, optional: true)
                        field(.wslUser, "Linux Username", placeholder: "Distribution default", text: $draft.wslUser, optional: true)
                        help("The Linux account whose Claude and Codex logs you want to import.")
                    }
                    .padding(.top, 8)
                } label: {
                    Text("WSL Environment")
                        .accessibilityHint(showWSLOptions
                            ? "Contains the optional WSL distribution and Linux username settings."
                            : "Expand to set a WSL distribution and Linux username.")
                }
                .font(.caption.weight(.medium))
            }
            field(.name, "Device Name", placeholder: draft.resolvedName.isEmpty ? "Named after the machine" : draft.resolvedName,
                  text: $draft.name, optional: true)
            Divider()
            feedback
            setupGuide
            actions
            help("Saving imports history. Uses your SSH keys; only daily summaries stay on this Mac.")
        }
        .padding(12).cardSurface()
        .onChange(of: draft.connectionIdentity) { probeResult = nil; operationError = nil; allowAnyway = false }
        .onChange(of: draft.host) { _, host in
            // A typed address is no longer the picked machine, so its name no longer applies.
            if host.trimmingCharacters(in: .whitespacesAndNewlines) != pickedHost { draft.suggestedName = nil }
        }
        .onChange(of: draft.platform) { _, platform in if platform != .linux { systemGuessed = false } }
        .onChange(of: focusedField) { old, _ in if let old { touchedFields.insert(old) } }
        .task {
            focusedField = isNew ? .host : .name
            if isNew {
                async let peers = TailscaleDiscovery.discover()
                sshAliases = await SSHConfigLookup.resolvedAliases()
                tailscale = await peers
            }
        }
        .task(id: draft.host) {
            // Debounced: ssh -G is local and fast, but there's no need to run it on every keystroke.
            defaultSSHUser = nil
            let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            defaultSSHUser = await SSHConfigLookup.resolve(host)?.user
        }
    }

    private var sshUserPlaceholder: String {
        guard let user = defaultSSHUser else { return "From SSH config, otherwise your Mac username" }
        return user == NSUserName() ? "\(user) (this Mac's username)" : "\(user) (from SSH config)"
    }

    /// A blank Windows username silently becomes this Mac's username, which rarely exists on Windows.
    private var macUsernameWarning: String? {
        guard windowsSSH, draft.sshUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let user = defaultSSHUser, user == NSUserName() else { return nil }
        return "SSH will sign in as “\(user)”, this Mac's username. Enter the Windows account name if it's different."
    }

    private var windowsSSH: Bool { draft.platform == .wsl || draft.platform == .windows }

    /// The Windows host whose WSL distributions the Distribution menu lists, once host, username, and
    /// port are valid (the distribution and Linux user don't matter for listing).
    private var wslHost: RemoteUsageDevice? {
        guard draft.platform == .wsl else { return nil }
        let user = draft.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = draft.sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = RemoteUsageDevice(name: "WSL", host: draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
                                       platform: .wsl, sshUser: user.isEmpty ? nil : user, sshPort: Int(port))
        return device.isValid && (port.isEmpty || device.sshPort != nil) ? device : nil
    }

    private static let platformOrder: [RemoteUsageDevice.Platform] = [.linux, .macOS, .windows, .wsl]

    private var systemHelp: String {
        switch draft.platform {
        case .linux, .macOS: "Reads the SSH account's Claude and Codex logs."
        case .windows: "Reads the Windows account's logs with Python 3 (py -3)."
        case .wsl: "SSH logs in to Windows; logs are read inside WSL."
        }
    }

    /// What has to be true before the first import; the host-key step is the one people miss.
    private var setupGuide: some View {
        DisclosureGroup(isExpanded: $showSetupGuide) {
            VStack(alignment: .leading, spacing: 6) {
                help("1. Set up SSH key login to this device. Passwords aren't supported.")
                help("2. Connect once in Terminal so this Mac trusts its host key:")
                HStack(spacing: 6) {
                    // Wraps instead of truncating, so the whole destination is readable before copying.
                    Text(sshCommand).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(copiedSSHCommand ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sshCommand, forType: .string)
                        copiedSSHCommand = true
                    }
                    .buttonStyle(.borderless).font(.caption).fixedSize()
                    .accessibilityLabel("Copy SSH command")
                }
                .padding(6).background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                help(draft.platform == .windows || draft.platform == .wsl
                     ? "3. Install Python 3 \(draft.platform == .wsl ? "inside WSL" : "on Windows")."
                     : "3. Make sure python3 is installed on the device.")
            }
            .padding(.top, 6)
        } label: {
            Text("Setup Help")
        }
        .font(.caption.weight(.medium))
        .onChange(of: sshCommand) { copiedSSHCommand = false }
    }

    private var sshCommand: String {
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = draft.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = draft.sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
        // Quote a username a shell would mangle (DOMAIN\user loses its backslash unquoted).
        let safeUser = user.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) } ? user : "'\(user)'"
        return "ssh " + (port.isEmpty ? "" : "-p \(port) ") + (user.isEmpty ? "" : "\(safeUser)@")
            + (host.isEmpty ? "your-host" : host) + " exit"
    }

    private func help(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ field: RemoteUsageDeviceDraft.Field, _ label: String,
                       placeholder: String, text: Binding<String>, optional: Bool = false) -> some View {
        let error = attemptedSubmit || touchedFields.contains(field) ? draft.validationErrors[field] : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                if optional {
                    Spacer()
                    if field == .wslDistribution {
                        WSLDistributionMenu(store: store, connection: wslHost, selection: $draft.wslDistribution,
                                            disabled: operation != nil)
                    }
                    Text("Optional").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(field != .name)
                .focused($focusedField, equals: field).disabled(operation != nil)
                .accessibilityLabel(label)
                .accessibilityHint(error ?? (optional ? "Leave blank to use the default." : "Required."))
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The Machine row shows only when Tailscale is installed.
    private var showsTailscale: Bool {
        switch tailscale {
        case .notConnected?, .peers?: true
        case .unavailable?, nil: false
        }
    }

    /// Picking a machine fills Host (its SSH alias or Tailscale IP), System, and the default name.
    @ViewBuilder
    private var tailscaleMenu: some View {
        switch tailscale {
        case .notConnected?:
            tailscaleMenuButton { Button("Tailscale Is Not Connected") {}.disabled(true) }
        case .peers(let peers)?:
            let available = TailscaleDiscovery.unsaved(peers, saved: store.devices, draftPlatform: draft.platform,
                                                       aliases: sshAliases)
            let online = available.filter(\.isOnline)
            let offline = available.filter { !$0.isOnline }
            tailscaleMenuButton {
                if available.isEmpty { Button("No Other Machines Found") {}.disabled(true) }
                ForEach(online) { peer in
                    Button("\(peer.name) · \(systemLabel(peer.system))") { apply(peer) }
                }
                if !online.isEmpty && !offline.isEmpty { Divider() }
                ForEach(offline) { peer in
                    Button("\(peer.name) · \(systemLabel(peer.system)) · Offline") {}.disabled(true)
                }
            }
        case .unavailable?, nil:
            EmptyView()
        }
    }

    private func tailscaleMenuButton<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // A pop-up like the System picker below it; it names the picked machine until Host is edited.
        let picked = pickedHost == draft.host.trimmingCharacters(in: .whitespacesAndNewlines) ? draft.suggestedName : nil
        return Menu(content: content) {
            Text(picked ?? "Choose…")
        }
            .menuStyle(.button).fixedSize()
            .disabled(operation != nil)
            .accessibilityLabel("Tailscale Machine")
            .accessibilityHint("Fills the host, system, and name from a machine on your tailnet.")
    }

    private func systemLabel(_ system: TailscalePeer.System) -> String {
        switch system {
        case .macOS: "Mac"
        case .linux: "Linux"
        case .windows: "Windows"
        case .unknown: "Unknown System"
        }
    }

    private func apply(_ peer: TailscalePeer) {
        // An SSH alias for this machine already carries its username, key, and port; otherwise the
        // Tailscale IP works even when this Mac doesn't use Tailscale DNS.
        draft.host = SSHConfigLookup.alias(for: peer, among: sshAliases) ?? peer.host
        draft.platform = RemoteUsageDevice.Platform(tailscale: peer.system, keeping: draft.platform)
        systemGuessed = peer.system == .unknown
        // A blank Device Name saves as the machine's name; a typed one stays.
        draft.suggestedName = peer.name
        pickedHost = draft.host
    }

    @ViewBuilder
    private var feedback: some View {
        if let operation {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(operation == .checking ? "Connecting and looking for logs…" : "Saving and importing history…")
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
        } else if let probeResult {
            // Only reached when the connection works but no logs were found; a found account saves at once.
            VStack(alignment: .leading, spacing: 4) {
                Label(probeResult.logsSummary, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
                help("Connected as \(probeResult.user) · \(probeResult.home)")
            }
        } else if let operationError {
            Label(operationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.notice)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(primaryTitle) { submit() }.buttonStyle(.borderedProminent)
                .accessibilityHint(allowAnyway
                    ? "Saves this device without a working connection or logs; it imports once they're reachable."
                    : "Connects, checks for Codex and Claude logs, then saves and imports its usage history.")
        }
        .disabled(operation != nil).controlSize(.regular)
    }

    private var primaryTitle: String {
        switch (isNew, allowAnyway) {
        case (true, false): "Add Device"
        case (true, true): "Add Anyway"
        case (false, false): "Save Changes"
        case (false, true): "Save Anyway"
        }
    }

    private func validatedDevice() -> RemoteUsageDevice? {
        attemptedSubmit = true
        operationError = nil
        if let first = RemoteUsageDeviceDraft.Field.allCases.first(where: { draft.validationErrors[$0] != nil }) {
            if first == .sshPort { showSSHOptions = true }
            if first == .wslUser || first == .wslDistribution { showWSLOptions = true }
            focusedField = first
            return nil
        }
        do { return try draft.makeDevice() }
        catch { operationError = error.localizedDescription; return nil }
    }

    /// One button: check the connection and logs first, then save and import. A failed check or an
    /// account without logs stops here with the reason; pressing again (now "Add Anyway") saves regardless,
    /// so an offline machine can still be added. Name-only edits save without reconnecting.
    private func submit() {
        guard operation == nil, let device = validatedDevice() else { return }
        probeResult = nil
        if allowAnyway || draft.connectionIdentity == originalConnection {
            save(device)
            return
        }
        operation = .checking
        Task {
            do {
                let result = try await store.test(device)
                guard result.hasAnyLogs else {
                    probeResult = result
                    allowAnyway = true
                    operation = nil
                    return
                }
                save(device)
            } catch {
                operationError = error.localizedDescription
                allowAnyway = true
                showSetupGuide = true
                operation = nil
            }
        }
    }

    private func save(_ device: RemoteUsageDevice) {
        operation = .saving
        probeResult = nil
        Task {
            defer { operation = nil }
            do {
                if isNew { try await store.add(device) }
                else { try await store.update(device) }
                onFinish()
            } catch { operationError = error.localizedDescription }
        }
    }
}
