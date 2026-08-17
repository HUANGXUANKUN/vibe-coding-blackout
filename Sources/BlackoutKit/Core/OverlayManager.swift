import AppKit

/// Owns one black panel per display and keeps that set correct as displays come
/// and go.
///
/// This is the mechanism the whole product rests on: the overlay is composited by
/// WindowServer, so it is instant, exact, and works on every display regardless
/// of what the backlight APIs can reach (PRD 6.1).
public final class OverlayManager {

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private(set) public var isActive = false

    /// Bumped on every state change. Animation completion handlers check it and
    /// bail if they are stale, so rapid toggling can never leave a window parked
    /// at a half-transparent alpha (PRD 3.2 / 3.14).
    private var generation = 0

    private let fadeIn: TimeInterval = 0.22
    private let fadeOut: TimeInterval = 0.18

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Screen bookkeeping

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Creates/removes/reframes windows to exactly match the current screen set.
    ///
    /// `reveal` shows them opaque and in front straight away, with no fade — that
    /// is what a display plugged in mid-blackout needs, because fading a new
    /// overlay in would expose a frame of desktop (PRD 3.1). `activate` passes
    /// `false` and does its own ordering so the fade-in it asked for survives.
    private func syncWindows(reveal: Bool) {
        var seen = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            guard let id = Self.displayID(of: screen) else { continue }
            seen.insert(id)

            let window: OverlayWindow
            if let existing = windows[id] {
                existing.match(screen)
                window = existing
            } else {
                window = OverlayWindow(screen: screen)
                windows[id] = window
            }

            if reveal {
                window.alphaValue = 1
                window.orderFrontRegardless()
            }
        }

        for (id, window) in windows where !seen.contains(id) {
            window.orderOut(nil)
            window.close()
            windows.removeValue(forKey: id)
        }
    }

    /// Builds the windows up front so the very first blackout is as instant as
    /// every later one. This is a panic button; it cannot pay window-creation
    /// cost on first use.
    public func prewarm() {
        syncWindows(reveal: false)
        Log.overlay.info("Prewarmed \(self.windows.count) overlay window(s)")
    }

    @objc private func screensChanged() {
        Log.overlay.info("Screen configuration changed (\(NSScreen.screens.count) screen(s))")
        syncWindows(reveal: isActive)
    }

    // MARK: - Activation

    public func activate(animated: Bool, hint: String?) {
        generation += 1
        let gen = generation
        isActive = true
        syncWindows(reveal: false)

        for window in windows.values {
            window.hideHintImmediately()
            if !animated { window.alphaValue = 1 }
            window.orderFrontRegardless()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeIn
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for window in windows.values { window.animator().alphaValue = 1 }
            }
        }

        guard let hint, !hint.isEmpty else { return }
        // Only on the screen the pointer is on: showing it on all three would be
        // three times the light and three times the thing to read.
        if let target = windowUnderMouse() ?? windows.values.first {
            let delay = animated ? fadeIn : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == gen, self.isActive else { return }
                target.showHint(hint)
            }
        }
    }

    public func deactivate(animated: Bool) {
        generation += 1
        let gen = generation
        isActive = false

        for window in windows.values { window.hideHintImmediately() }

        guard animated else {
            for window in windows.values {
                window.alphaValue = 0
                window.orderOut(nil)
            }
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in windows.values { window.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self, self.generation == gen, !self.isActive else { return }
            for window in self.windows.values { window.orderOut(nil) }
        })
    }

    /// Re-asserts window order after wake / unlock / user switch, where the
    /// overlay can end up below loginwindow's own surfaces (PRD 3.9).
    public func reassertIfActive() {
        guard isActive else { return }
        syncWindows(reveal: true)
    }

    public func tearDown() {
        generation += 1
        isActive = false
        for window in windows.values {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    public var screenCount: Int { windows.count }

    /// Everything that has to be true for "nothing is visible" to hold, measured
    /// rather than assumed. Drives the assertions in `--self-test`.
    public struct Diagnostics: Sendable {
        public let screens: Int
        public let windows: Int
        /// Screens with a visible, fully opaque window covering their whole frame.
        public let coveredScreens: Int
        public let atShieldingLevel: Bool
        public let anyVisible: Bool
    }

    public func diagnostics() -> Diagnostics {
        let shielding = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        var covered = 0
        var atLevel = true
        var anyVisible = false

        for screen in NSScreen.screens {
            guard let id = Self.displayID(of: screen), let window = windows[id] else { continue }
            if window.isVisible { anyVisible = true }
            if window.level != shielding { atLevel = false }
            if window.isVisible, window.isOpaque, window.alphaValue >= 0.999,
               window.frame == screen.frame {
                covered += 1
            }
        }

        return Diagnostics(screens: NSScreen.screens.count,
                           windows: windows.count,
                           coveredScreens: covered,
                           atShieldingLevel: atLevel,
                           anyVisible: anyVisible)
    }

    private func windowUnderMouse() -> OverlayWindow? {
        let location = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(location) {
            if let id = Self.displayID(of: screen) { return windows[id] }
        }
        return nil
    }
}
