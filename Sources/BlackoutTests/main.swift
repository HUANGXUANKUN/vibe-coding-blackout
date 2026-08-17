import Foundation
import BlackoutKit

// A ~30-line assertion harness instead of XCTest.
//
// XCTest ships with Xcode, not with the Command Line Tools, so `swift test` does
// not run on a CLT-only machine (verified: "no such module 'XCTest'"). An
// executable target keeps the tests runnable everywhere, including CI (PRD 2.7).

var checks = 0
var failures: [String] = []

func expect(_ condition: Bool, _ what: String, line: UInt = #line) {
    checks += 1
    if !condition { failures.append("line \(line): \(what)") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures.append("line \(line): \(what) — expected \(expected), got \(actual)")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("• \(name)")
    body()
}

// MARK: - Helpers

/// Feeds a sequence and returns the timestamps at which the gesture fired.
func fire(_ detector: inout TapDetector, _ inputs: [TapInput]) -> [TimeInterval] {
    var fired: [TimeInterval] = []
    for input in inputs {
        if detector.handle(input) {
            switch input {
            case .triggerDown(let t), .triggerUp(let t), .foreignKey(let t): fired.append(t)
            }
        }
    }
    return fired
}

/// A clean tap: press at `at`, release `hold` later.
func tap(at: TimeInterval, hold: TimeInterval = 0.04) -> [TapInput] {
    [.triggerDown(at), .triggerUp(at + hold)]
}

// MARK: - TapDetector

suite("double-tap recognition") {
    var d = TapDetector()
    let fired = fire(&d, tap(at: 0) + tap(at: 0.15))
    expectEqual(fired.count, 1, "a clean double tap fires exactly once")
    expect(abs((fired.first ?? -1) - 0.19) < 1e-9, "fires on the release of the second tap")
}

suite("single tap does nothing") {
    var d = TapDetector()
    expectEqual(fire(&d, tap(at: 0)).count, 0, "one tap never fires")
}

suite("gap budget") {
    var d = TapDetector()
    // 0.6s apart with a 0.4s budget: too slow.
    expectEqual(fire(&d, tap(at: 0) + tap(at: 0.6)).count, 0, "slow taps do not fire")
    // The late tap becomes tap #1 of a fresh sequence, so a prompt follow-up fires.
    expectEqual(fire(&d, tap(at: 0.70)).count, 1, "a late tap seeds a new sequence")
}

suite("hold is not a tap") {
    var d = TapDetector()
    // First press held for 0.6s (> maxHold 0.45): using the key as a modifier.
    expectEqual(fire(&d, [.triggerDown(0), .triggerUp(0.6)] + tap(at: 0.7)).count, 0,
                "a long first press does not count")

    var e = TapDetector()
    expectEqual(fire(&e, tap(at: 0) + [.triggerDown(0.15), .triggerUp(0.9)]).count, 0,
                "a long second press does not count")
}

suite("chords never fire") {
    var d = TapDetector()
    // ⌃C: press control, press C, release both.
    let ctrlC: [TapInput] = [.triggerDown(0), .foreignKey(0.02), .triggerUp(0.09)]
    expectEqual(fire(&d, ctrlC).count, 0, "control+key does not fire")

    var e = TapDetector()
    // Tap, then a chord inside the double-tap window.
    expectEqual(fire(&e, tap(at: 0) + [.triggerDown(0.1), .foreignKey(0.12), .triggerUp(0.2)]).count, 0,
                "a chord as the second tap does not fire")

    var f = TapDetector()
    // Tap, an unrelated keystroke, then a tap: the sequence is broken.
    expectEqual(fire(&f, tap(at: 0) + [.foreignKey(0.08)] + tap(at: 0.12)).count, 0,
                "typing between taps breaks the sequence")
}

suite("another modifier breaks the sequence") {
    var d = TapDetector()
    expectEqual(fire(&d, tap(at: 0) + [.foreignKey(0.05)] + tap(at: 0.1) + tap(at: 0.2)).count, 1,
                "sequence restarts cleanly after a foreign modifier")
}

suite("post-fire cool-down") {
    var d = TapDetector()
    let fired = fire(&d, tap(at: 0) + tap(at: 0.15) + tap(at: 0.25) + tap(at: 0.35))
    expectEqual(fired.count, 1, "taps inside the 350 ms cool-down cannot fire again")

    var e = TapDetector()
    // Same gesture repeated after the cool-down expires.
    let twice = fire(&e, tap(at: 0) + tap(at: 0.15) + tap(at: 0.70) + tap(at: 0.85))
    expectEqual(twice.count, 2, "a second gesture after the cool-down fires")
}

suite("triple tap fires once") {
    var d = TapDetector()
    expectEqual(fire(&d, tap(at: 0) + tap(at: 0.12) + tap(at: 0.24)).count, 1,
                "three fast taps toggle once, not twice")
}

suite("malformed input is safe") {
    var d = TapDetector()
    // Release with no press we ever saw (key was held when the tap was installed).
    expectEqual(fire(&d, [.triggerUp(0)]).count, 0, "orphan release is ignored")
    expectEqual(fire(&d, tap(at: 0.1) + tap(at: 0.2)).count, 1, "detector still works afterwards")

    var e = TapDetector()
    // Auto-repeat style duplicate presses.
    let repeated: [TapInput] = [.triggerDown(0), .triggerDown(0.01), .triggerDown(0.02), .triggerUp(0.05)]
    expectEqual(fire(&e, repeated + tap(at: 0.1)).count, 1, "duplicate presses collapse into one tap")
}

suite("speed presets") {
    var fast = TapDetector(config: .fast)
    expectEqual(fire(&fast, tap(at: 0) + tap(at: 0.35)).count, 0, "fast preset rejects a 350 ms gap")

    var normal = TapDetector(config: .normal)
    expectEqual(fire(&normal, tap(at: 0) + tap(at: 0.35)).count, 1, "normal preset accepts a 350 ms gap")

    var relaxed = TapDetector(config: .relaxed)
    expectEqual(fire(&relaxed, tap(at: 0) + tap(at: 0.55)).count, 1, "relaxed preset accepts a 550 ms gap")

    expectEqual(TapSpeed.normal.config.maxGap, 0.40, "normal is 400 ms")
    expectEqual(TapSpeed.fast.config.tapsRequired, 2, "presets keep the tap count at two")
}

suite("reset clears pending state") {
    var d = TapDetector()
    _ = fire(&d, tap(at: 0))
    d.reset()
    expectEqual(fire(&d, tap(at: 0.1)).count, 0, "the tap before reset is forgotten")
}

// MARK: - TriggerKey

suite("trigger keys") {
    expectEqual(Set(TriggerKey.allCases.map(\.keyCode)).count, TriggerKey.allCases.count,
                "every trigger has a distinct key code")
    expectEqual(Set(TriggerKey.allCases.map(\.deviceMask)).count, TriggerKey.allCases.count,
                "every trigger has a distinct device mask")
    expect(TriggerKey.allCases.allSatisfy { TriggerKey.allModifierKeyCodes.contains($0.keyCode) },
           "trigger key codes are part of the modifier set")
    expectEqual(TriggerKey.rightControl.keyCode, 62, "right control is kVK_RightControl")
    expectEqual(TriggerKey.rightControl.deviceMask, 0x2000, "right control uses NX_DEVICERCTLKEYMASK")
    expect(TriggerKey.leftControl.deviceMask != TriggerKey.rightControl.deviceMask,
           "left and right control are distinguishable")
    expect(TriggerKey.allCases.allSatisfy { TriggerKey(rawValue: $0.rawValue) == $0 },
           "raw values round-trip")
}

// MARK: - Preferences

suite("preferences defaults and validation") {
    let suiteName = "com.huangxuankun.blackout.tests.\(ProcessInfo.processInfo.processIdentifier)"
    guard let store = UserDefaults(suiteName: suiteName) else {
        failures.append("could not create a test defaults suite")
        return
    }
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let prefs = Preferences(defaults: store)
    expectEqual(prefs.triggerKey, .rightControl, "default trigger is right control")
    expectEqual(prefs.tapSpeed, .normal, "default speed is normal")
    expect(prefs.dimBacklight, "backlight dimming defaults on")
    expect(prefs.keepAwake, "keep-awake defaults on")
    expect(prefs.blockInput, "input blocking defaults on")
    expect(prefs.escapeRestores, "esc restores by default")
    expect(prefs.fadeEnabled, "fade defaults on")
    expect(prefs.showHint, "hint defaults on")
    expect(!prefs.didOnboard, "onboarding has not run yet")

    // A hand-edited or corrupt plist must not take the app down (PRD 3.10).
    store.set("not-a-key", forKey: "triggerKey")
    store.set("warp-speed", forKey: "tapSpeed")
    expectEqual(prefs.triggerKey, .rightControl, "an invalid trigger falls back to the default")
    expectEqual(prefs.tapSpeed, .normal, "an invalid speed falls back to the default")

    prefs.triggerKey = .rightCommand
    expectEqual(prefs.triggerKey, .rightCommand, "a valid trigger persists")

    var notified = 0
    prefs.onChange = { notified += 1 }
    prefs.blockInput = false
    prefs.blockInput = true
    expectEqual(notified, 2, "changes notify observers")
}

suite("crash-recovery record") {
    let suiteName = "com.huangxuankun.blackout.tests.dirty.\(ProcessInfo.processInfo.processIdentifier)"
    guard let store = UserDefaults(suiteName: suiteName) else {
        failures.append("could not create a test defaults suite")
        return
    }
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let prefs = Preferences(defaults: store)
    expect(prefs.dirtyBrightness.isEmpty, "no pending recovery on a clean install")

    prefs.dirtyBrightness = ["1-2-3-4": 0.47, "5-6-7-8": 0.8]
    expectEqual(prefs.dirtyBrightness.count, 2, "the record survives a write")
    expectEqual(prefs.dirtyBrightness["1-2-3-4"] ?? -1, 0.47, "values round-trip exactly")

    // A fresh Preferences over the same store is what the next launch sees.
    expectEqual(Preferences(defaults: store).dirtyBrightness.count, 2,
                "a later launch can see what the crashed run left behind")

    prefs.dirtyBrightness = [:]
    expect(prefs.dirtyBrightness.isEmpty, "clearing removes the record")
}

// MARK: - Report

print("")
if failures.isEmpty {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures.count) of \(checks) checks failed")
    for failure in failures { print("   \(failure)") }
    exit(1)
}
