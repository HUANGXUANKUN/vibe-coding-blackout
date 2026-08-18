import AppKit

/// Wires the mechanism to the UI. Holds no state of its own.
public final class BlackoutAppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences.shared
    private let controller = BlackoutController()
    private let monitor = EventTapMonitor()
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController?
    private var signalSources: [DispatchSourceSignal] = []

    /// Used by the `atexit` hook, which cannot capture context.
    private static weak var liveDelegate: BlackoutAppDelegate?

    public override init() {
        super.init()
        Self.liveDelegate = self
    }

    /// Posted by a second instance just before it exits, so the one that is
    /// already running can show itself instead of the launch appearing to do
    /// nothing.
    static let showOnboardingNotification = Notification.Name("com.huangxuankun.blackout.showOnboarding")

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // One Blackout at a time. Two instances means two event taps both firing
        // on the same double-tap, two sets of overlays, and two brightness
        // controllers writing the same display — they race, and a restore can
        // land before the other one's dim. Easy to hit by accident, because
        // dist/Blackout.app and /Applications/Blackout.app are the same build
        // with the same signature.
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication
               .runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            Log.app.notice("Another Blackout is running (pid \(existing.processIdentifier)); exiting")
            DistributedNotificationCenter.default().postNotificationName(
                Self.showOnboardingNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        // Before anything else touches the displays: undo a dim that a crashed or
        // force-quit run left behind (PRD 6.4 / F8).
        controller.recoverIfNeeded()

        statusItem = StatusItemController(controller: controller, monitor: monitor, prefs: prefs)
        statusItem.onShowOnboarding = { [weak self] in self?.showOnboarding() }
        statusItem.onQuit = { NSApp.terminate(nil) }

        controller.onStateChange = { [weak self] in self?.statusItem.refresh() }
        controller.isHotkeyAvailable = { [weak self] in
            guard let self else { return false }
            // Secure input counts as unavailable: macOS has already killed the tap.
            return self.monitor.isInstalled && !self.monitor.isSecureInputActive
        }
        controller.prewarm()

        // Hop off the event-tap callback before doing window work: a slow
        // callback gets the tap disabled by the system (PRD 2.2).
        monitor.onGesture = { [weak self] in
            DispatchQueue.main.async { self?.controller.toggle() }
        }
        monitor.onEscape = { [weak self] in self?.controller.handleEscape() ?? false }
        monitor.isBlockingInput = { [weak self] in self?.controller.shouldBlockInput() ?? false }
        monitor.onStatusChange = { [weak self] in self?.statusItem.refresh() }
        monitor.configure(trigger: prefs.triggerKey, speed: prefs.tapSpeed)
        monitor.start()

        prefs.onChange = { [weak self] in
            guard let self else { return }
            self.monitor.configure(trigger: self.prefs.triggerKey, speed: self.prefs.tapSpeed)
            self.statusItem.refresh()
        }

        installTerminationHandlers()

        // A second launch attempt asks this instance to surface itself.
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showOnboardingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showOnboarding()
        }

        if !prefs.didOnboard {
            showOnboarding()
        } else if !monitor.hasAccessibilityAccess {
            // Silent-but-useless is the worst outcome; ask once. Deliberately not
            // opening System Settings here — that would happen on every launch
            // until the box is ticked.
            PermissionPrompt.promptAccessibility()
        }

        Log.app.notice("Blackout ready (accessibility: \(self.monitor.hasAccessibilityAccess))")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        controller.tearDown()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showOnboarding()
        return true
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if onboarding == nil {
            let window = OnboardingWindowController(prefs: prefs)
            window.onTryIt = { [weak self] in self?.runTryIt() }
            onboarding = window
        }
        onboarding?.present()
    }

    /// A supervised 1.5 s blackout: the user gets to see the real thing while
    /// knowing it will end by itself.
    private func runTryIt() {
        controller.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.controller.deactivate()
        }
    }

    // MARK: - Abnormal exit

    /// Brightness and the power assertion are system-wide state that outlives the
    /// process, so every exit path has to undo them (PRD 3.8).
    private func installTerminationHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        atexit {
            // Last line of defence. Only the out-of-process state (backlight,
            // power assertion) — the overlay windows die with the process anyway,
            // and AppKit is not worth talking to this late.
            BlackoutAppDelegate.liveDelegate?.controller.tearDownSystemState()
        }
    }
}
