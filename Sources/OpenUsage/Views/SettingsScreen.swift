import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UserNotifications

/// The in-popover Settings screen — the popover's third mode alongside the dashboard and
/// Customize. It replaces the old separate Settings window, which forced the popover closed every
/// time it opened. Sections are Customize-style cards (caption header over a rounded card of rows)
/// so the popover keeps one visual language; controls sit on each row's trailing edge like
/// System Settings. The footer already shows the version; the release build adds an "Updates" section
/// (auto-check, beta channel, and a full-width manual check button).
struct SettingsScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(LayoutStore.self) private var layout
    @Environment(UpdaterController.self) private var updater

    @State private var launchAtLogin = LaunchAtLoginSetting()
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @AppStorage(ReduceAnimationsSetting.key) private var reduceAnimations = ReduceAnimationsSetting.fallback
    @AppStorage(LogLevelSetting.key) private var logLevel = LogLevelSetting.fallback
    /// Surfaced under the Advanced rows when copying the path or revealing the file fails.
    /// macOS notification authorization for OpenUsage, surfaced in the Notifications section so a
    /// warning glyph and action button can appear when alerts can't be delivered. Refreshed on appear,
    /// when a trigger turns on, and when the app becomes active again (e.g. the user returns from
    /// System Settings after re-enabling).
    private enum NotificationsAuthState { case authorized, denied, notDetermined }
    @State private var notificationsAuth: NotificationsAuthState = .authorized
    /// Gates the destructive Reset All Settings action behind a confirmation alert. Settings remains
    /// mounted after its first visit, so leaving the screen must explicitly dismiss a pending alert.
    @State private var isPresentingResetConfirm = false
    /// Remounts `ShortcutRecorderField` after a reset. The field seeds its chip from the
    /// KeyboardShortcuts store only on appear (the store isn't observable), so without a fresh
    /// identity the still-mounted Settings screen would keep showing the cleared shortcut.
    @State private var shortcutFieldGeneration = 0
    /// Settings stays mounted between visits, so explicitly restore its previous scroll-to-top behavior.
    @State private var scrollPosition = ScrollPosition(edge: .top)

    /// Fills the region the dashboard's pinned footer leaves. Same scroller treatment as Customize:
    /// the overlay scroller stays (the scroll edge effect needs it) but is invisible.
    var body: some View {
        PopoverScrollView {
            content
        }
        .scrollPosition($scrollPosition)
    }

    private var content: some View {
        // Same section rhythm as the dashboard and Customize (all read the density setting).
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            generalSection
            RemoteDevicesSettingsSection(store: container.remoteDevices)
                // Settings stays mounted while hidden. A new visit starts at the device list.
                .id(layout.screen == .settings)
            LiveActivitySettingsSection()
            appearanceSection
            usageDisplaySection
            notificationsSection
            privacySection
            advancedSection
            updatesSection
            // Mirror of the Customize cross-link — the layout controls live on the other screen.
            ScreenCrossLinkRow(
                systemImage: "slider.horizontal.3",
                title: "Customize",
                subtitle: "Choose what's visible and where",
                destination: .customize
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .task { await refreshNotificationsAuth() }
        .onChange(of: layout.screen) { _, screen in
            if screen == .settings {
                scrollPosition.scrollTo(edge: .top)
                launchAtLogin.refreshStatus()
                Task { await refreshNotificationsAuth() }
            } else {
                isPresentingResetConfirm = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard layout.screen == .settings else { return }
            launchAtLogin.refreshStatus()
            Task { await refreshNotificationsAuth() }
        }
    }

    private var generalSection: some View {
        section("General") {
            row("Launch at Login") {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.update(to: $0) }
                ))
                    .settingsSwitchStyle()
            }
            if let launchAtLoginError = launchAtLogin.errorMessage {
                inlineNotice(launchAtLoginError)
            }
            // Click-to-record field; its ⓧ clears the combo and disables the shortcut.
            row("Global Shortcut") {
                ShortcutRecorderField(name: .togglePopover, isVisible: layout.screen == .settings)
                    .id(shortcutFieldGeneration)
                    .hoverTooltip("Open \(AppBrand.name) from anywhere")
            }
        }
    }

    private var appearanceSection: some View {
        @Bindable var layout = container.layout
        @Bindable var transparency = container.transparency
        return section("Appearance") {
            row("Icon Style") {
                picker($layout.menuBarStyle, options: MenuBarStyle.allCases, label: \.label)
            }
            row("Theme") {
                picker($appearance, options: AppearanceSetting.allCases, label: \.label)
                    // NSApp-level so the popover panel restyles too (it ignores preferredColorScheme).
                    .onChange(of: appearance) {
                        AppearanceSetting.applyCurrent()
                    }
            }
            row("Density") {
                picker($density, options: DensitySetting.allCases, label: \.label)
            }
            row("Reduce Animations") {
                Toggle("", isOn: $reduceAnimations)
                    .settingsSwitchStyle()
            }
            // Translucent popover the proper way (behind-window vibrancy, text stays legible). It
            // yields to the system accessibility settings, and to the party easter egg while that's
            // running (the egg drives the look) — either way, see the paused notice below.
            row("Increase Transparency") {
                Toggle("", isOn: $transparency.increaseTransparency)
                    .settingsSwitchStyle()
                    // Party mode owns the look while it's active, so disable (dim) the toggle to show
                    // it has no effect right now — its stored value resumes once the egg is exited.
                    .disabled(transparency.secretCodeActive)
            }
            // Egg first: while Party runs it overrides the toggle regardless of the system flags, so
            // its notice takes precedence over the accessibility one.
            if transparency.secretCodeActive {
                inlineNotice("Party mode is on, so this stays paused.")
            } else if transparency.isPaused {
                inlineNotice("macOS Reduce Transparency or Increase Contrast is on, so this stays paused.")
            }
            // Both rows surface only after the secret code has been entered. Party Mode is the egg's
            // own switch: turning it off (like re-typing the code) exits the egg and hides both rows,
            // dropping back to the base state. Drunk Mode escalates the readable party into the woozy,
            // barely-readable state and back — turning it off stays in the party (4 → 3), while turning
            // Party Mode off from there clears Drunk Mode too (4 → base).
            if transparency.secretCodeActive {
                row("Party Mode") {
                    Toggle("", isOn: $transparency.partyModeActive)
                        .settingsSwitchStyle()
                }
                row("Drunk Mode") {
                    Toggle("", isOn: $transparency.drunkMode)
                        .settingsSwitchStyle()
                }
                // The egg yields to the accessibility flags too: when one is on the panel stays
                // opaque, so explain why the party looks normal rather than leaving it a mystery.
                if transparency.partyPaused {
                    inlineNotice("macOS Reduce Transparency or Increase Contrast is on, so the party stays paused.")
                }
            }
        }
    }

    private var usageDisplaySection: some View {
        @Bindable var store = container.dataStore
        return section("Usage Display") {
            row("Show Usage As") {
                picker($store.meterStyle, options: WidgetDisplayMode.allCases, label: \.label)
            }
            row("Reset Times") {
                picker($store.resetDisplayMode, options: ResetDisplayMode.allCases, label: \.label)
            }
            // Off (default) leaves pacing on yellow and red only. On also surfaces projection
            // and the even-pace tick on blue rows.
            row("Always Show Pacing") {
                Toggle("", isOn: $store.alwaysShowPacing)
                    .settingsSwitchStyle()
                    .hoverTooltip("Show how you're pacing on every metric, not just ones near their limit")
            }
        }
    }

    private var privacySection: some View {
        @Bindable var privacy = container.privacy
        return section("Privacy") {
            row("Hide From Screen Share") {
                Toggle("", isOn: $privacy.hideUsageWhileScreenSharing)
                    .settingsSwitchStyle()
            }
            Text("While your screen is shared or recorded, the menu bar shows “\(AppBrand.name)” instead of your usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        @Bindable var updater = updater
        // Visible whenever the updater is active (only the signed release build ships a feed; the
        // dev build and a bare `swift run`, with no feed, hide this).
        if updater.isActive {
            section("Updates") {
                row("Check Automatically") {
                    Toggle("", isOn: $updater.automaticallyChecksForUpdates)
                        .settingsSwitchStyle()
                        .hoverTooltip("Checks hourly and shows a banner when an update is available.")
                }
                row("Beta Updates") {
                    Toggle("", isOn: $updater.betaChannelEnabled)
                        .settingsSwitchStyle()
                        .hoverTooltip("Receive pre-release builds before they ship to everyone")
                }
                // No version label here — the footer already shows it. The frame goes on the label so
                // the glass background stretches the full row width instead of hugging the text.
                // (Glass on macOS 26+, bordered fallback on macOS 15.)
                Button { updater.checkForUpdates() } label: {
                    Text("Check for Updates…").frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
                .controlSize(.regular)
                .disabled(!updater.canCheckForUpdates)
                .padding(.horizontal, 12)
                .padding(.vertical, density.controlRowPadding)
            }
        }
    }

    // MARK: - Notifications

    /// Quota pace notifications: three per-trigger toggles (no master switch — turn all three off to
    /// silence), each with an (i) tooltip. A warning glyph on the section header and an action row under
    /// the toggles appear when macOS permission isn't authorized and at least one trigger is on. Defaults
    /// are all off; the app requests authorization the first time a trigger is turned on.
    private var notificationsSection: some View {
        @Bindable var notifications = container.notificationSettings
        let needsAttention = notificationsAuth != .authorized && anyToggleOn
        return VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            HStack(spacing: 6) {
                Text("Notifications")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if needsAttention {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .hoverTooltip(notificationsAuth == .denied
                            ? "Notifications are turned off for \(AppBrand.name). Enable them in System Settings."
                            : "\(AppBrand.name) needs permission to send alerts.")
                }
            }
            .padding(.horizontal, 8)
            VStack(spacing: 0) {
                notifToggleRow(.underTenPercent, isOn: $notifications.underTenPercent)
                notifToggleRow(.healthyToClose, isOn: $notifications.healthyToClose)
                notifToggleRow(.closeToRunningOut, isOn: $notifications.closeToRunningOut)
                if needsAttention {
                    notificationsActionRow
                }
            }
            .cardSurface()
        }
        .onChange(of: anyToggleOn) { _, on in
            if on {
                // The first time a trigger is turned on, ask macOS for permission (memoized — it only
                // prompts while authorization is still not determined). Then refresh so the
                // warning/action row reflects the new status.
                AppNotifications.shared.requestAuthorization()
                Task { await refreshNotificationsAuth() }
            }
        }
    }

    /// One trigger row: the setting label with a one-line explanation under it, and the toggle.
    private func notifToggleRow(_ milestone: PaceMilestone, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(milestone.settingLabel)
                Text(milestone.tooltip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .settingsSwitchStyle()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.controlRowPadding)
    }

    /// The conditional action under the toggles: a full-width "Open System Settings" button when macOS
    /// denied permission, or "Allow Notifications" when still undecided. The reason lives in the header
    /// triangle's tooltip. Shown only when a trigger is on.
    private var notificationsActionRow: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if notificationsAuth == .denied {
                    AppNotifications.shared.openSystemNotificationsSettings()
                } else {
                    AppNotifications.shared.requestAuthorization()
                    Task { await refreshNotificationsAuth() }
                }
            } label: {
                Text(notificationsAuth == .denied ? "Open System Settings" : "Allow Notifications")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.vertical, density.controlRowPadding)
        }
    }

    /// True when at least one trigger is on — the gate for the permission warning + action row.
    /// Delegates to the store's `anyEnabled` so the disjunction lives in one place.
    private var anyToggleOn: Bool {
        container.notificationSettings.anyEnabled
    }

    /// Read the live macOS authorization status into `notificationsAuth`, but only when at least one
    /// trigger is on so no warning shows while all alerts are off.
    private func refreshNotificationsAuth() async {
        guard anyToggleOn else {
            notificationsAuth = .authorized
            return
        }
        let status = await AppNotifications.shared.authorizationStatus()
        switch status {
        case .denied: notificationsAuth = .denied
        case .notDetermined: notificationsAuth = .notDetermined
        default: notificationsAuth = .authorized
        }
    }

    // MARK: - Advanced (logging)

    /// Log-level control plus copy/reveal buttons for the file log, and the Reset All Settings row.
    /// The file lives at a fixed path (`~/Library/Logs/OpenUsage/OpenUsage.log`); raising the level
    /// here applies live (no restart) and persists across launches. Default Info, Debug is opt-in.
    private var advancedSection: some View {
        section("Advanced") {
            row("Log Level") {
                picker($logLevel, options: LogLevelSetting.allCases, label: \.label)
                    .onChange(of: logLevel) {
                        // Apply the new floor to the file sink immediately, then record the transition.
                        AppLog.reloadLevel()
                        AppLog.info(.config, "Log level changed to \(logLevel.rawValue)")
                    }
            }
            // Its own row, so the Log Level picker lines up with the other right-hand controls.
            row("Log File") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([LogFile.url])
                }
                .controlSize(.small)
            }
            // The Settings-wide destructive reset (issue #602). Red label, confirmation alert;
            // confirming restores every preference to its default — the container-owned stores plus
            // the two view-scoped ones (Launch at Login lives in the system's login-item registry,
            // the update preferences on the updater controller).
            Button {
                isPresentingResetConfirm = true
            } label: {
                Text("Reset All Settings…")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .controlSize(.regular)
            .padding(.horizontal, 12)
            .padding(.vertical, density.controlRowPadding)
            .alert("Reset All Settings?", isPresented: $isPresentingResetConfirm) {
                Button("Reset", role: .destructive) {
                    withAnimation(Motion.spring) { container.resetAllSettings() }
                    launchAtLogin.update(to: false)
                    updater.resetToDefaults()
                    shortcutFieldGeneration += 1
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restores every setting and customization to its default and turns providers back on for the tools you have installed. Remote devices and their imported history are removed. This cannot be undone.")
            }
        }
    }

    // MARK: - Section / row scaffolding

    /// A caption header over a rounded card of rows — the Customize block shape. The header is
    /// inset 8pt so it aligns with the rows' content, matching how Customize lines its provider
    /// headers up with the card rows.
    private func section(
        _ title: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                rows()
            }
            .cardSurface()
        }
    }

    /// One settings row: label on the leading edge, the control on the trailing edge. Same insets
    /// as a Customize metric row so the cards share one rhythm.
    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.controlRowPadding)
    }

    /// An inline orange caption under a row — the single definition of the notice idiom shared by the
    /// General/Advanced error lines and the "this setting is paused" captions (Increase Transparency
    /// paused by a system accessibility setting, or by Party mode taking over the look).
    private func inlineNotice(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.notice)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A trailing popup picker that hugs its selection — segmented controls don't fit the 320pt
    /// popover once options have real words in them.
    private func picker<Value: Hashable>(
        _ selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}
