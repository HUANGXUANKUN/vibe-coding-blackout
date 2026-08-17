import AppKit

/// `blackout --self-test`: exercises the whole blackout path once, without
/// installing an event tap and without needing any permission, then restores
/// unconditionally.
///
/// It exists so the dangerous part of this app can be verified safely: it can be
/// run at any time, it always comes back on its own, and it prints per-display
/// brightness before / during / after so a broken restore is visible rather than
/// silent (PRD 3.15).
public enum SelfTest {

    public static func run(holdFor hold: TimeInterval = 1.2) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        // Two instances driving the same backlight produce a confusing failure
        // rather than a useful one, so refuse instead of racing.
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.huangxuankun.blackout")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            print("Blackout is already running (pid \(others.map { String($0.processIdentifier) }.joined(separator: ", "))).")
            print("Quit it first — two instances fight over the same display brightness.")
            return 2
        }

        let prefs = Preferences.shared
        let controller = BlackoutController(prefs: prefs)
        var failures: [String] = []

        print("Blackout self-test")
        print("──────────────────────────────────────────")
        print("Screens:            \(NSScreen.screens.count)")
        print("Backlight control:  \(controller.backlightControlAvailable ? "available" : "unavailable")")
        print("Accessibility:      \(PermissionPrompt.isAccessibilityGranted ? "granted" : "not granted (not needed for this test)")")
        // Recovery runs first, exactly as it does at app launch: if a previous
        // run was killed while dimmed, the "before" reading has to be the
        // recovered value, not the leftover 0.0 (PRD 6.4).
        let hadPendingRecovery = controller.hasPendingRecovery
        controller.recoverIfNeeded()
        if hadPendingRecovery {
            print("Recovery:           restored brightness left dimmed by a previous run")
        }
        print("")

        let before = snapshot(controller)
        print("Brightness before:  \(describe(before))")

        controller.activate()
        spin(for: 0.35)

        if !controller.isActive { failures.append("controller did not enter the active state") }
        let during = snapshot(controller)
        print("Brightness during:  \(describe(during))")

        // The overlay is what actually guarantees nothing is visible, so measure
        // it instead of trusting it (PRD A1 / A6).
        let overlay = controller.overlayDiagnostics()
        print("Overlay coverage:   \(overlay.coveredScreens)/\(overlay.screens) screen(s) fully covered")
        if overlay.windows != overlay.screens {
            failures.append("expected one overlay per screen, got \(overlay.windows) for \(overlay.screens)")
        }
        if overlay.coveredScreens != overlay.screens {
            failures.append("only \(overlay.coveredScreens) of \(overlay.screens) screens are fully covered")
        }
        if !overlay.atShieldingLevel {
            failures.append("an overlay is not at the shielding window level")
        }

        print("Holding blackout for \(String(format: "%.1f", hold))s…")
        spin(for: hold)

        controller.deactivate()
        spin(for: 0.6)
        if controller.isActive { failures.append("controller did not leave the active state") }
        if controller.overlayDiagnostics().anyVisible {
            failures.append("an overlay window is still on screen after restoring")
        }

        let after = snapshot(controller)
        print("Brightness after:   \(describe(after))")
        print("")

        if prefs.dimBacklight, controller.backlightControlAvailable {
            for (id, value) in before {
                guard let restored = after[id] else {
                    failures.append("display \(id) disappeared during the test")
                    continue
                }
                if abs(restored - value) > 0.02 {
                    failures.append(String(format: "display %u not restored: %.3f → %.3f", id, value, restored))
                }
            }
            if during.isEmpty && !before.isEmpty {
                failures.append("no display reported a brightness while dimmed")
            }
        }

        if !prefs.dirtyBrightness.isEmpty {
            failures.append("crash-recovery record was not cleared after restore")
        }

        controller.tearDown()

        guard failures.isEmpty else {
            print("FAILED")
            for failure in failures { print("  ✗ \(failure)") }
            return 1
        }
        print("PASSED — all screens blacked out and fully restored")
        return 0
    }

    private static func snapshot(_ controller: BlackoutController) -> [CGDirectDisplayID: Double] {
        var result: [CGDirectDisplayID: Double] = [:]
        for entry in controller.brightnessReport() {
            if let value = entry.brightness { result[entry.id] = value }
        }
        return result
    }

    private static func describe(_ values: [CGDirectDisplayID: Double]) -> String {
        guard !values.isEmpty else { return "(no readable displays)" }
        return values.keys.sorted()
            .map { String(format: "%u=%.2f", $0, values[$0] ?? 0) }
            .joined(separator: "  ")
    }

    /// Runs the main run loop so window animations and timers actually progress.
    private static func spin(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
    }
}
