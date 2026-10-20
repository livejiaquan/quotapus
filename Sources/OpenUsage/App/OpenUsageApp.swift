import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let processStartedAt = ProcessInfo.processInfo.systemUptime
    private var container: AppContainer?
    private var statusItemController: StatusItemController?
    private var firstLaunchWindow: FirstLaunchWindowController?
    private var singleInstanceLock: SingleInstanceLock.Token?
    private let updater = UpdaterController()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Open/trim the file log, seed the cached level, and emit the startup line BEFORE anything
        // else logs, so the first lines of a session are captured.
        AppLog.bootstrap()
        // Kernel-level single-instance lock (#874): rejects a duplicate even when two copies launch
        // so close together that the workspace guard's LaunchServices snapshot misses the peer.
        var holdsLock = false
        if let bundleID = Bundle.main.bundleIdentifier {
            switch SingleInstanceLock.acquire(bundleIdentifier: bundleID) {
            case .acquired(let token):
                singleInstanceLock = token
                holdsLock = true
                listenForOtherCopies()
            case .alreadyRunning:
                SingleInstanceGuard.activateExistingInstance()
                Self.askRunningCopyToShowItself(bundleID)
                AppLog.info(.lifecycle, "duplicate launch detected by process lock; terminating")
                NSApp.terminate(nil)
                return
            case .failed(let message):
                AppLog.error(.lifecycle, "single-instance lock unavailable: \(message)")
            }
        }
        // The lock winner must NOT consult the workspace guard: its snapshot can still contain a
        // lock loser that is mid-exit (alive, lower PID), and yielding to it leaves ZERO instances
        // (reproduced in #874). The guard remains only as the fallback for unbundled launches
        // (`swift run` has no bundle ID) or lock setup failure. `terminate(_:)` unwinds
        // asynchronously and is cancellable, so we MUST return here — otherwise this method keeps
        // running and creates the very duplicate it was meant to prevent.
        if !holdsLock, SingleInstanceGuard.deferToExistingInstance() {
            AppLog.info(.lifecycle, "duplicate launch detected; handing off to the running instance and terminating")
            NSApp.terminate(nil)
            return
        }
        // Versioned settings migration — replaces the old beta-era "wipe all settings on every update".
        // MUST run before anything reads or writes UserDefaults (AppKit below, AppearanceSetting, and the
        // AppContainer stores), so migrated values are in place when the stores load and a genuine fresh
        // install still presents an empty domain — how the migrator tells a first launch from an upgrade.
        // Nothing is wiped now; settings carry across updates. See `SettingsMigrator`.
        // The fresh-install answer is captured BEFORE migrating (the schema stamp makes the domain
        // non-empty) and handed to `AppContainer`, whose `FirstRunSeeder` starts with no providers on
        // until the welcome screen turns on the user's picks.
        let isFreshInstall = SettingsMigrator.isFreshInstall()
        SettingsMigrator.migrate()
        if isFreshInstall { FirstLaunchSetup.markPending() }
        // Let only the `SMAppService` login item drive startup: opt out of AppKit's reopen-on-login
        // so a reboot doesn't also restore us and race the login item in the first place. The lock
        // above resolves same-bundle startup races even if both launch triggers fire; this just avoids
        // the wasted second launch.
        NSApp.disableRelaunchOnLogin()
        // App-wide theme override (NSApp.appearance): the popover ignores SwiftUI's
        // preferredColorScheme, so the override is applied at the AppKit level once at launch;
        // the Theme picker on the Settings screen re-applies it on change.
        AppearanceSetting.applyCurrent()

        if ShellEnvironmentSnapshotStore.launchSnapshot == nil,
           !LoginShellEnvironment.shared.capturedSuccessfully {
            Task { [weak self] in
                await Task.detached(priority: .userInitiated) {
                    _ = LoginShellEnvironment.shared.ensureCaptured()
                }.value
                await self?.finishLaunching(isFreshInstall: isFreshInstall)
            }
            return
        }
        Task { [weak self] in
            await self?.finishLaunching(isFreshInstall: isFreshInstall)
        }
    }

    private func finishLaunching(isFreshInstall: Bool) async {
        let showsWelcome = FirstLaunchSetup.isPending()
        // Nothing asks for Keychain access before the user picks providers on the welcome screen.
        if showsWelcome { KeychainAccessGuard.holdPopups() }
        // A first launch that quit before seeding still owes the empty seed, or the welcome would
        // open with every provider on.
        let container = await AppContainer(isFreshInstall: isFreshInstall || showsWelcome)
        self.container = container
        guard showsWelcome else {
            startDashboard(container)
            return
        }
        let setup = FirstLaunchSetup(
            providers: ProviderCatalog.make().map(\.provider),
            cards: container.providers,
            enablement: container.enablement,
            dataStore: container.dataStore
        )
        // The hop lets the clicked button's action return before its window is torn down.
        firstLaunchWindow = FirstLaunchWindowController(setup: setup) { [weak self] in
            Task { self?.finishWelcome(container) }
        }
        firstLaunchWindow?.show()
    }

    private func finishWelcome(_ container: AppContainer) {
        firstLaunchWindow?.finish()
        firstLaunchWindow = nil
        KeychainAccessGuard.allowPopups()
        FirstLaunchSetup.clearPending()
        // With nothing on, the empty dashboard already points to Customize.
        if container.enablement.enabledIDs?.isEmpty == true {
            container.onboarding.dismissCustomizeHint()
        }
        startDashboard(container)
        MenuBarPopover.showHandler?()
    }

    private func startDashboard(_ container: AppContainer) {
        container.startRefreshing()
        statusItemController = StatusItemController(container: container, updater: updater)
        let launchDurationMS = Int((ProcessInfo.processInfo.systemUptime - processStartedAt) * 1_000)
        AppLog.info(.lifecycle, "launch to status item ready: \(launchDurationMS) ms")
        // Starts background update checks (release build only; dormant under preview/`swift run`).
        updater.start()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showItself()
        return true
    }

    /// Opening the app while it runs should always show something: the welcome window while it's
    /// pending, otherwise the dashboard panel under the menu bar icon.
    private func showItself() {
        if let firstLaunchWindow {
            firstLaunchWindow.show()
        } else {
            MenuBarPopover.showHandler?()
        }
    }

    private static func showItselfNotification(_ bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).showItself")
    }

    /// A second copy (say, one opened from the DMG while the installed copy runs) quits right away, so
    /// it asks the running copy to show itself first; otherwise opening the app would look like nothing happened.
    private static func askRunningCopyToShowItself(_ bundleID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            showItselfNotification(bundleID), object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private func listenForOtherCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showItselfNotification(bundleID), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.info(.lifecycle, "another copy was opened; showing this one")
                self?.showItself()
            }
        }
    }

    /// Flush pending snapshot writes on quit so the last refresh isn't lost across a clean quit.
    public func applicationWillTerminate(_ notification: Notification) {
        container?.dataStore.flushPendingSnapshotWork()
    }
}
