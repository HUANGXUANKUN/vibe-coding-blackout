import Foundation

/// UserDefaults-backed settings. Every read is validated so a hand-edited or
/// corrupt plist falls back to the default instead of crashing (see PRD 3.10).
public final class Preferences {
    public static let shared = Preferences()

    private let defaults: UserDefaults
    /// Fired after any setting changes, on the main thread.
    public var onChange: (() -> Void)?

    private enum Key {
        static let triggerKey = "triggerKey"
        static let tapSpeed = "tapSpeed"
        static let dimBacklight = "dimBacklight"
        static let keepAwake = "keepAwake"
        static let blockInput = "blockInput"
        static let escapeRestores = "escapeRestores"
        static let fadeEnabled = "fadeEnabled"
        static let showHint = "showHint"
        static let didOnboard = "didOnboard"
        static let dirtyBrightness = "dirtyBrightness"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.triggerKey: TriggerKey.rightControl.rawValue,
            Key.tapSpeed: TapSpeed.normal.rawValue,
            Key.dimBacklight: true,
            Key.keepAwake: true,
            Key.blockInput: true,
            Key.escapeRestores: true,
            Key.fadeEnabled: true,
            Key.showHint: true,
            Key.didOnboard: false,
        ])
    }

    private func notify() {
        if Thread.isMainThread {
            onChange?()
        } else {
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    public var triggerKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: Key.triggerKey) ?? "") ?? .rightControl }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerKey); notify() }
    }

    public var tapSpeed: TapSpeed {
        get { TapSpeed(rawValue: defaults.string(forKey: Key.tapSpeed) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.tapSpeed); notify() }
    }

    public var dimBacklight: Bool {
        get { defaults.bool(forKey: Key.dimBacklight) }
        set { defaults.set(newValue, forKey: Key.dimBacklight); notify() }
    }

    public var keepAwake: Bool {
        get { defaults.bool(forKey: Key.keepAwake) }
        set { defaults.set(newValue, forKey: Key.keepAwake); notify() }
    }

    public var blockInput: Bool {
        get { defaults.bool(forKey: Key.blockInput) }
        set { defaults.set(newValue, forKey: Key.blockInput); notify() }
    }

    public var escapeRestores: Bool {
        get { defaults.bool(forKey: Key.escapeRestores) }
        set { defaults.set(newValue, forKey: Key.escapeRestores); notify() }
    }

    public var fadeEnabled: Bool {
        get { defaults.bool(forKey: Key.fadeEnabled) }
        set { defaults.set(newValue, forKey: Key.fadeEnabled); notify() }
    }

    public var showHint: Bool {
        get { defaults.bool(forKey: Key.showHint) }
        set { defaults.set(newValue, forKey: Key.showHint); notify() }
    }

    public var didOnboard: Bool {
        get { defaults.bool(forKey: Key.didOnboard) }
        set { defaults.set(newValue, forKey: Key.didOnboard) }
    }

    // MARK: - Crash-consistency record

    /// Per-display brightness captured *before* dimming, keyed by a stable
    /// display key. Present on disk == "we owe the user a restore".
    /// Written before the first `set`, cleared after a successful restore.
    public var dirtyBrightness: [String: Double] {
        get { (defaults.dictionary(forKey: Key.dirtyBrightness) as? [String: Double]) ?? [:] }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: Key.dirtyBrightness)
            } else {
                defaults.set(newValue, forKey: Key.dirtyBrightness)
            }
            // Force it to disk now: the whole point is surviving `kill -9`.
            defaults.synchronize()
        }
    }
}
