import AppKit
import Carbon.HIToolbox

/// Watches the session event stream for the double-tap gesture, and — while the
/// screens are blacked out — swallows keyboard and mouse input so a passer-by
/// cannot use the machine (PRD F1 / F7).
///
/// Uses `.defaultTap`, not `.listenOnly`: a listen-only tap needs only Input
/// Monitoring but is physically unable to consume events, which would both break
/// input blocking and leak the `esc` keypress into whatever is running in the
/// foreground (PRD 2.1).
public final class EventTapMonitor {

    /// Fires when the gesture completes.
    public var onGesture: (() -> Void)?
    /// Called on `esc`. Return `true` if it was acted on, in which case the event
    /// is consumed rather than leaking to the foreground app (PRD 3.6).
    public var onEscape: (() -> Bool)?
    /// Whether input should currently be swallowed.
    public var isBlockingInput: (() -> Bool)?
    /// Called whenever install state or secure-input state changes.
    public var onStatusChange: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var detector = TapDetector()
    private var trigger: TriggerKey = .rightControl

    /// Key codes whose key-down we consumed, so we consume the matching key-up
    /// too and never hand an app an unpaired release.
    private var swallowedKeys = Set<Int64>()
    private var swallowedMouseButtons = Set<Int64>()

    private var watchdog: Timer?
    private(set) public var isInstalled = false
    private(set) public var isSecureInputActive = false

    private static let escapeKeyCode: Int64 = 53

    public init() {}

    // MARK: - Configuration

    public func configure(trigger: TriggerKey, speed: TapSpeed) {
        self.trigger = trigger
        detector = TapDetector(config: speed.config)
    }

    // MARK: - Lifecycle

    /// Starts a watchdog that installs the tap as soon as Accessibility access is
    /// granted, re-installs it if it dies, and tracks secure-input state. The
    /// user never has to restart the app after ticking the checkbox (PRD 3.12).
    public func start() {
        installIfPossible()
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    public func stop() {
        watchdog?.invalidate()
        watchdog = nil
        uninstall()
    }

    private func tick() {
        let secure = IsSecureEventInputEnabled()
        if secure != isSecureInputActive {
            isSecureInputActive = secure
            onStatusChange?()
        }
        if !isInstalled {
            installIfPossible()
        } else if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            // Re-enable rather than rebuild: cheaper and keeps the run loop source.
            Log.hotkey.warning("Event tap was disabled; re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    public var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    private func installIfPossible() {
        guard !isInstalled else { return }
        guard hasAccessibilityAccess else { return }

        // Deliberately absent: mouseMoved. Freezing the cursor would look like a
        // hang and buys nothing (PRD 3.4).
        let watched: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel,
        ]
        let mask = watched.reduce(into: CGEventMask(0)) { mask, type in
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventTapMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("CGEvent.tapCreate failed despite Accessibility access")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        isInstalled = true
        detector.reset()
        Log.hotkey.notice("Event tap installed")
        onStatusChange?()
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        swallowedKeys.removeAll()
        swallowedMouseButtons.removeAll()
        guard isInstalled else { return }
        isInstalled = false
        onStatusChange?()
    }

    // MARK: - Event handling

    /// Runs on the main run loop. Must stay cheap: slow callbacks get the tap
    /// killed with `tapDisabledByTimeout` (PRD 2.2).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.hotkey.warning("Event tap disabled by system (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            detector.reset()
            return pass
        }

        let now = ProcessInfo.processInfo.systemUptime
        let blocking = isBlockingInput?() ?? false

        switch type {
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == trigger.keyCode {
                let isDown = (event.flags.rawValue & trigger.deviceMask) != 0
                if detector.handle(isDown ? .triggerDown(now) : .triggerUp(now)) {
                    onGesture?()
                }
            } else if TriggerKey.allModifierKeyCodes.contains(code) {
                _ = detector.handle(.foreignKey(now))
            }
            // Modifiers always pass through: consuming them desynchronises
            // modifier state in every other app (PRD 3.5 / 3.7).
            return pass

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            _ = detector.handle(.foreignKey(now))

            if code == Self.escapeKeyCode, onEscape?() == true {
                swallowedKeys.insert(code)
                return nil
            }
            guard blocking else { return pass }
            swallowedKeys.insert(code)
            return nil

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowedKeys.remove(code) != nil { return nil }
            return blocking ? nil : pass

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if swallowedMouseButtons.remove(button) != nil { return nil }
            return blocking ? nil : pass

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard blocking else { return pass }
            swallowedMouseButtons.insert(event.getIntegerValueField(.mouseEventButtonNumber))
            return nil

        default:
            return blocking ? nil : pass
        }
    }
}
