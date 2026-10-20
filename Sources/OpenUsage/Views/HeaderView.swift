import AppKit
import SwiftUI

/// The dashboard footer's trailing control: a single **Options ⌄** menu button (plain text in Quotapus). The
/// earlier split button ("Customize" + separate chevron) confused people — two tap targets in one
/// capsule read as one — so everything now lives in one obvious menu: Customize / Settings / Share
/// Screenshot / Check for Updates / Report an Issue / About / Quit. Customize leads because it's the
/// screen users reach for most; Settings stays one click away (and always via ⌘,).
///
/// It is a `.buttonStyle(.plain)` `Menu` with no capsule: the footer's glass band already reads as
/// chrome. The menu renders in its own `NSMenu`-backed window, which the panel's outside-click policy
/// keeps the popover open for.
///
/// Only the dashboard shows this; the Customize and Settings screens carry their own top-leading back
/// button (`PopoverTopBar`) to return home — the macOS-native place for it — so the footer control
/// simply drops away there.
///
/// Shortcuts survive: ⌘, (Settings), ⏎ (Customize) and Esc are handled by the always-on
/// `PopoverKeyReader` monitor, so they fire from every screen (including Settings, whose footer shows
/// only the identity line — no actions). The menu items only carry their ⌘ key-equivalents as labels
/// and fire while the menu is open, so the monitor and the items never double-fire. ⌘Q (Quit) is
/// unowned elsewhere, so it rides its menu item directly.
struct HeaderView: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(WidgetDataStore.self) private var dataStore
    @Environment(UpdaterController.self) private var updater
    /// The current screen. The footer is fixed chrome keyed off `layout.screen` (it no longer slides
    /// per-page), so this control shows only when that's `.dashboard` and swaps in place on a switch.
    let screen: PopoverScreen

    /// Control height, so the capsule matches the footer's other chrome.
    private static let controlHeight: CGFloat = 28

    var body: some View {
        leadingControl
    }

    /// On the dashboard, the Options menu as plain text ("Options ⌄"), like the design; the glass footer
    /// already reads as chrome, so a second capsule only added weight.
    @ViewBuilder
    private var leadingControl: some View {
        if screen == .dashboard {
            optionsButton
                .fixedSize()
        }
    }

    /// The Options pull-down: label plus its own chevron glyph. `.menuStyle(.button)` +
    /// `.buttonStyle(.plain)` strip the menu chrome so `interactiveGlass` owns the surface;
    /// `.menuIndicator(.hidden)` drops the built-in arrow in favor of our styled chevron.
    private var optionsButton: some View {
        Menu {
            menuItems
        } label: {
            HStack(spacing: 5) {
                Text("Options")
                    .font(.system(size: 13, weight: .semibold))
                MenuChevron()
            }
            .padding(.horizontal, 4)
            .frame(height: Self.controlHeight)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The menu's items, mirroring their in-popover entry points. Customize leads, then Settings.
    /// `autoenablesItems` has no SwiftUI equivalent, so the Check for Updates item disables itself when
    /// Sparkle can't currently check — e.g. dev builds with no feed, or while a check is already in
    /// flight. Customize and Settings carry their key equivalents so the menu shows the shortcuts: when
    /// the menu is open the items handle them; when it's closed the `PopoverKeyReader` monitor
    /// handles (and consumes) them first, so the equivalents can't double-fire. Same split as the Quit
    /// ⌘Q item below.
    @ViewBuilder
    private var menuItems: some View {
        Button { toggle(.customize) } label: {
            Label("Customize", systemImage: "slider.horizontal.3")
        }
        .keyboardShortcut(.return, modifiers: [])

        Button { toggle(.settings) } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Divider()

        // Builds without an update feed (every build until Quotapus has its own releases) hide this
        // rather than show an item that can never work.
        if updater.isAvailable {
            Button { updater.checkForUpdates() } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updater.canCheckForUpdates)
        }

        Divider()

        Link(destination: URL(string: AppBrand.newIssueURL)!) {
            Label("Report an Issue…", systemImage: "ladybug")
        }

        Button { AboutPanel.present() } label: {
            Label("About \(AppBrand.name)", systemImage: "info.circle")
        }
        Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
            Label("Quit \(AppBrand.name)", systemImage: "power")
        }
        .keyboardShortcut("q") // ⌘Q — unowned elsewhere, so safe to register on the item.
    }

    private func toggle(_ screen: PopoverScreen) {
        withAnimation(Motion.modeSwitch) {
            layout.screen = layout.screen == screen ? .dashboard : screen
        }
    }
}
