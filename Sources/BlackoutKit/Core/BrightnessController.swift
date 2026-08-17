import CoreGraphics
import Foundation

/// Lowers display backlights and restores them to their previous per-display
/// values.
///
/// This is the *secondary* mechanism: it removes the backlight glow so a screen
/// reads as switched off, and saves power. It is allowed to fail — the black
/// overlay is what actually guarantees nothing is visible (PRD 6.1).
///
/// Uses the private `DisplayServices` framework via `dlsym` rather than linking
/// it, so if Apple moves or removes the symbols the app merely loses dimming
/// instead of failing to launch.
public final class BrightnessController {

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private let getFn: GetBrightness?
    private let setFn: SetBrightness?
    private let canFn: CanChange?

    /// Values captured at dim time, keyed by stable display key.
    private var captured: [String: Double] = [:]
    private let prefs: Preferences

    public var isAvailable: Bool { getFn != nil && setFn != nil }

    public init(prefs: Preferences = .shared) {
        self.prefs = prefs
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        let library = dlopen(path, RTLD_LAZY)
        handle = library

        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let library, let raw = dlsym(library, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }
        getFn = sym("DisplayServicesGetBrightness", as: GetBrightness.self)
        setFn = sym("DisplayServicesSetBrightness", as: SetBrightness.self)
        canFn = sym("DisplayServicesCanChangeBrightness", as: CanChange.self)

        if !isAvailable {
            Log.brightness.warning("DisplayServices unavailable; backlight dimming disabled")
        }
    }

    // MARK: - Display enumeration

    /// A key that survives unplug/replug, unlike `CGDirectDisplayID`.
    static func stableKey(for id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))-\(CGDisplayUnitNumber(id))"
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func read(_ id: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        guard getFn(id, &value) == 0 else { return nil }
        guard value.isFinite, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }

    private func write(_ id: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let setFn else { return false }
        let clamped = Float(min(max(value, 0), 1))
        return setFn(id, clamped) == 0
    }

    private func canChange(_ id: CGDirectDisplayID) -> Bool {
        canFn?(id) ?? true
    }

    // MARK: - Public API

    /// Snapshot of what is currently dimmable, for the self-test report.
    public func report() -> [(id: CGDirectDisplayID, brightness: Double?, dimmable: Bool)] {
        Self.activeDisplays().map { ($0, read($0), canChange($0)) }
    }

    /// Captures current brightness for every readable display, persists it, then
    /// drives everything to minimum.
    ///
    /// A display whose brightness cannot be *read* is deliberately left alone:
    /// dimming it would leave us unable to restore it (PRD 3.3).
    public func dim() {
        guard isAvailable else { return }
        var snapshot: [String: Double] = [:]
        var targets: [(CGDirectDisplayID, String)] = []

        for id in Self.activeDisplays() {
            guard canChange(id), let current = read(id) else { continue }
            let key = Self.stableKey(for: id)
            snapshot[key] = current
            targets.append((id, key))
        }

        guard !snapshot.isEmpty else {
            Log.brightness.info("No dimmable displays")
            return
        }

        // Persist BEFORE mutating: brightness outlives this process, so the
        // record on disk is what lets a `kill -9` be recovered from.
        captured = snapshot
        prefs.dirtyBrightness = snapshot

        for (id, _) in targets {
            if !write(id, 0) {
                Log.brightness.warning("Failed to dim display \(id)")
            }
        }
        Log.brightness.info("Dimmed \(targets.count) display(s)")
    }

    /// Restores captured values. Idempotent; clears the on-disk record on success.
    public func restore() {
        let source = captured.isEmpty ? prefs.dirtyBrightness : captured
        guard !source.isEmpty else { return }
        guard isAvailable else {
            // Cannot act, but do not keep a stale record around forever.
            captured = [:]
            prefs.dirtyBrightness = [:]
            return
        }

        var restored = 0
        for id in Self.activeDisplays() {
            guard let value = source[Self.stableKey(for: id)] else { continue }
            if write(id, value) { restored += 1 }
        }
        captured = [:]
        prefs.dirtyBrightness = [:]
        Log.brightness.info("Restored \(restored) display(s)")
    }

    /// Re-applies minimum brightness. Called after wake/unlock, where macOS may
    /// have reset the backlight behind our back (PRD 3.9).
    public func reassertDim() {
        guard isAvailable, !captured.isEmpty else { return }
        for id in Self.activeDisplays() where captured[Self.stableKey(for: id)] != nil {
            _ = write(id, 0)
        }
    }

    /// True when a previous run died while displays were dimmed.
    public var hasPendingRecovery: Bool { !prefs.dirtyBrightness.isEmpty }

    /// Restores brightness left over from a crashed or force-quit run.
    public func recoverFromPreviousRun() {
        guard hasPendingRecovery else { return }
        Log.brightness.notice("Recovering brightness left dimmed by a previous run")
        restore()
    }
}
