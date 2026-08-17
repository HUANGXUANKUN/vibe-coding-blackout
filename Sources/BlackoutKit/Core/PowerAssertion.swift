import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from going to *idle system* sleep while the screens are blacked
/// out.
///
/// This exists because of the actual use case: the user blacks out the screens
/// precisely because a long-running agent is working. Nobody touches the machine
/// for the next 40 minutes, so without this assertion the Mac idles out and the
/// agent stops — the feature would defeat its own purpose (PRD 1.3).
///
/// Display sleep is *not* prevented: the screens are already black, letting the
/// panels power down is free.
public final class PowerAssertion {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var held = false

    public init() {}

    public var isHeld: Bool { held }

    public func acquire(reason: String = "Blackout: screens hidden, work in progress") {
        guard !held else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.power.warning("Failed to create power assertion: \(result)")
            return
        }
        assertionID = id
        held = true
        Log.power.info("Holding PreventUserIdleSystemSleep")
    }

    /// Must be paired with every `acquire`, including on quit and abnormal exit —
    /// a leaked assertion means the Mac never sleeps again (PRD 3.8).
    public func release() {
        guard held else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        held = false
        Log.power.info("Released power assertion")
    }

    deinit { release() }
}
