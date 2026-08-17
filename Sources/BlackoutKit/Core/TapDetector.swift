import Foundation

/// Timing rules for the double-tap gesture. All values in seconds.
public struct TapDetectorConfig: Equatable, Sendable {
    /// Maximum time between the *release* of tap N and the *press* of tap N+1.
    public var maxGap: TimeInterval
    /// Maximum time a single tap may be held down. Longer = the user is using the
    /// key as a modifier, not tapping it.
    public var maxHold: TimeInterval
    /// After firing, ignore the trigger key for this long so one gesture cannot
    /// be read as two (which would flash the screen back on).
    public var rearmDelay: TimeInterval
    /// How many clean taps make the gesture.
    public var tapsRequired: Int

    public init(maxGap: TimeInterval = 0.40,
                maxHold: TimeInterval = 0.45,
                rearmDelay: TimeInterval = 0.35,
                tapsRequired: Int = 2) {
        self.maxGap = maxGap
        self.maxHold = maxHold
        self.rearmDelay = rearmDelay
        self.tapsRequired = tapsRequired
    }

    public static let fast = TapDetectorConfig(maxGap: 0.25)
    public static let normal = TapDetectorConfig(maxGap: 0.40)
    public static let relaxed = TapDetectorConfig(maxGap: 0.60)
}

/// Named speed presets exposed in the menu.
public enum TapSpeed: String, CaseIterable, Sendable {
    case fast, normal, relaxed

    public var config: TapDetectorConfig {
        switch self {
        case .fast:    return .fast
        case .normal:  return .normal
        case .relaxed: return .relaxed
        }
    }

    public var displayName: String {
        switch self {
        case .fast:    return "Fast (250 ms)"
        case .normal:  return "Normal (400 ms)"
        case .relaxed: return "Relaxed (600 ms)"
        }
    }
}

public enum TapInput: Equatable, Sendable {
    /// The trigger key went down.
    case triggerDown(TimeInterval)
    /// The trigger key came up.
    case triggerUp(TimeInterval)
    /// Any *other* key or modifier changed state. This invalidates the sequence
    /// so that `⌃C`, `⌃⌥←` and friends can never fire the gesture.
    case foreignKey(TimeInterval)
}

/// Recognises "N clean taps of one key within a time budget".
///
/// Deliberately a plain value type with an injected clock (timestamps arrive with
/// each input) and no AppKit/CoreGraphics dependency, so every rule below is
/// unit-testable without a keyboard. See `Sources/BlackoutTests`.
public struct TapDetector: Sendable {
    public var config: TapDetectorConfig

    private var taps = 0
    private var downAt: TimeInterval?
    private var lastUpAt: TimeInterval?
    /// Set when a foreign key is seen while the trigger is held: that press can
    /// no longer count as a tap.
    private var contaminated = false
    /// Inputs at or before this timestamp are ignored (post-fire cool-down).
    private var blockedUntil: TimeInterval = -.greatestFiniteMagnitude

    public init(config: TapDetectorConfig = .normal) {
        self.config = config
    }

    public mutating func reset() {
        taps = 0
        downAt = nil
        lastUpAt = nil
        contaminated = false
    }

    /// Feeds one input. Returns `true` exactly on the input that completes the
    /// gesture (the final release).
    public mutating func handle(_ input: TapInput) -> Bool {
        switch input {
        case .foreignKey:
            // Break the sequence. If the trigger is currently held, that hold is
            // part of a chord and must not count when it is released.
            if downAt != nil { contaminated = true }
            taps = 0
            lastUpAt = nil
            return false

        case .triggerDown(let now):
            guard now > blockedUntil else {
                reset()
                return false
            }
            // Ignore auto-repeat / duplicate downs without an intervening up.
            guard downAt == nil else { return false }
            if let lastUp = lastUpAt, now - lastUp > config.maxGap {
                taps = 0
            }
            downAt = now
            contaminated = false
            return false

        case .triggerUp(let now):
            guard let pressedAt = downAt else {
                // Up without a down we saw (e.g. key was already held when the
                // tap was installed). Start clean.
                reset()
                return false
            }
            downAt = nil

            guard now > blockedUntil else {
                reset()
                return false
            }
            guard !contaminated, now - pressedAt <= config.maxHold else {
                taps = 0
                lastUpAt = nil
                contaminated = false
                return false
            }

            taps += 1
            lastUpAt = now

            if taps >= config.tapsRequired {
                taps = 0
                lastUpAt = nil
                blockedUntil = now + config.rearmDelay
                return true
            }
            return false
        }
    }
}
