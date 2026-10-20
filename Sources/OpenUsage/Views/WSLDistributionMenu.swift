import SwiftUI

/// The Distribution field's **From Windows** menu: lists the host's WSL distributions over SSH (without
/// starting any) so the name doesn't have to be typed. Picking one fills the field; typing still works.
struct WSLDistributionMenu: View {
    let store: RemoteUsageDeviceStore
    /// The Windows host to ask, or nil while its host, username, or port isn't valid yet.
    let connection: RemoteUsageDevice?
    @Binding var selection: String
    let disabled: Bool
    @State private var state: LoadState?

    private enum LoadState {
        case loading
        case loaded([WSLDistribution])
        case failed(String)
    }

    var body: some View {
        // Same size and weight as the field label beside it, like From Tailscale.
        Menu {
            switch state {
            case .loading?, nil:
                Button("Listing Distributions…") {}.disabled(true)
            case .loaded(let distributions)?:
                if distributions.isEmpty { Button("No WSL Distributions Found") {}.disabled(true) }
                ForEach(distributions) { distribution in
                    Button(label(distribution)) { selection = distribution.name }
                }
            case .failed(let message)?:
                Button("Couldn't List Distributions") {}.disabled(true)
                Button(message) {}.disabled(true)
                Button("Try Again") { Task { await load(debounce: false) } }
            }
        } label: {
            Text("From Windows").font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
        .disabled(disabled || connection == nil)
        .accessibilityHint("Lists the WSL distributions on this Windows device and fills the one you pick.")
        .task(id: connection?.connectionKey) { await load(debounce: true) }
    }

    private func label(_ distribution: WSLDistribution) -> String {
        ([distribution.name] + (distribution.isDefault ? ["Default"] : []) + [distribution.state])
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func load(debounce: Bool) async {
        state = nil
        guard let connection else { return }
        // The host field changes per keystroke; only ask once it settles.
        if debounce, (try? await Task.sleep(for: .milliseconds(600))) == nil { return }
        state = .loading
        do {
            let distributions = try await store.wslDistributions(on: connection)
            if !Task.isCancelled { state = .loaded(distributions) }
        } catch {
            if !Task.isCancelled { state = .failed(error.localizedDescription) }
        }
    }
}
