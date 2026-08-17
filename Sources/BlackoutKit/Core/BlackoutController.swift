import AppKit

/// The single source of truth for "are the screens hidden right now".
///
/// Overlay windows, backlight level, the power assertion and input blocking are
/// all *derived outputs* of `isActive`. The UI only ever reads this and sends
/// commands; it never keeps its own copy of the state (PRD 6.5).
public final class BlackoutController {

    public private(set) var isActive = false

    private let overlays = OverlayManager()
    private let brightness: BrightnessController
    private let power = PowerAssertion()
    private let prefs: Preferences

    /// Called after every state change, on the main thread.
    public var onStateChange: (() -> Void)?

    public init(prefs: Preferences = .shared) {
        self.prefs = prefs
        self.brightness = BrightnessController(prefs: prefs)
        registerSystemObservers()
    }

    public var backlightControlAvailable: Bool { brightness.isAvailable }

    /// True when a previous run died while displays were dimmed.
    public var hasPendingRecovery: Bool { brightness.hasPendingRecovery }

    /// Restores brightness that a crashed or force-quit run left at minimum.
    /// Call once at launch, before anything else touches the displays (PRD 6.4).
    public func recoverIfNeeded() {
        brightness.recoverFromPreviousRun()
    }

    // MARK: - Commands

    public func toggle() {
        isActive ? deactivate() : activate()
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true

        let hint = prefs.showHint ? hintText() : nil
        overlays.activate(animated: prefs.fadeEnabled, hint: hint)

        if prefs.dimBacklight { brightness.dim() }
        if prefs.keepAwake { power.acquire() }

        Log.app.notice("Blacked out \(self.overlays.screenCount) screen(s)")
        onStateChange?()
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false

        overlays.deactivate(animated: prefs.fadeEnabled)
        brightness.restore()
        power.release()

        Log.app.notice("Screens restored")
        onStateChange?()
    }

    /// Input is only swallowed while blacked out, and only if the user left the
    /// setting on. Outside those two conditions the tap is a pure observer.
    public func shouldBlockInput() -> Bool {
        isActive && prefs.blockInput
    }

    /// `esc` handler. Returns true when it will restore, so the caller knows to
    /// consume the keypress.
    ///
    /// The decision is synchronous (the event tap needs an answer now) but the
    /// work is not: tearing down windows inside the tap callback risks the
    /// system killing the tap for being slow (PRD 2.2).
    public func handleEscape() -> Bool {
        guard isActive, prefs.escapeRestores else { return false }
        DispatchQueue.main.async { [weak self] in self?.deactivate() }
        return true
    }

    /// Builds the overlay windows ahead of first use so the panic button is
    /// instant the first time too.
    public func prewarm() {
        overlays.prewarm()
    }

    /// Best-effort synchronous cleanup for quit / signal / `atexit` paths.
    /// Brightness and the power assertion outlive the process, so they must be
    /// undone even on an abrupt exit (PRD 3.8).
    public func tearDown() {
        overlays.tearDown()
        tearDownSystemState()
        isActive = false
    }

    /// The subset of cleanup that touches state outside this process. Safe to call
    /// from `atexit`, where AppKit is no longer worth talking to.
    public func tearDownSystemState() {
        brightness.restore()
        power.release()
    }

    private func hintText() -> String {
        let symbol = prefs.triggerKey.symbol
        if prefs.escapeRestores {
            return "Screens blacked out · double-tap \(symbol) or press esc to restore"
        }
        return "Screens blacked out · double-tap \(symbol) to restore"
    }

    // MARK: - System events

    private func registerSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(reassert),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(reassert),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(reassert),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Screen lock/unlock is only published on the distributed centre.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reassert),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// After wake / unlock / fast user switch, macOS may have reordered windows
    /// or reset the backlight. Put things back (PRD F9 / 3.9).
    @objc private func reassert() {
        guard isActive else { return }
        Log.app.info("Re-asserting blackout after system event")
        overlays.reassertIfActive()
        if prefs.dimBacklight { brightness.reassertDim() }
        if prefs.keepAwake { power.acquire() }
    }

    // MARK: - Diagnostics

    /// Used by `--self-test`.
    public func brightnessReport() -> [(id: CGDirectDisplayID, brightness: Double?, dimmable: Bool)] {
        brightness.report()
    }

    public func overlayDiagnostics() -> OverlayManager.Diagnostics {
        overlays.diagnostics()
    }
}
