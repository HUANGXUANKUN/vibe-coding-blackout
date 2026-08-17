import Foundation

/// A modifier key that can be double-tapped to toggle blackout.
///
/// Only modifier keys are offered: they produce no character, so a stray tap
/// costs nothing, and "double-tap a modifier" is already part of the macOS
/// vocabulary (double-tap ⇧ for caps lock, etc).
public enum TriggerKey: String, CaseIterable, Sendable {
    case rightControl
    case leftControl
    case rightCommand
    case rightOption
    case rightShift

    /// Virtual key code (`kVK_*`) of the physical key.
    public var keyCode: Int64 {
        switch self {
        case .leftControl:  return 59  // kVK_Control
        case .rightControl: return 62  // kVK_RightControl
        case .rightCommand: return 54  // kVK_RightCommand
        case .rightOption:  return 61  // kVK_RightOption
        case .rightShift:   return 60  // kVK_RightShift
        }
    }

    /// Device-dependent flag bit (`NX_DEVICE*KEYMASK`) that is set while this
    /// specific physical key is held. `CGEventFlags` alone cannot tell left from
    /// right, so we read the raw bit.
    public var deviceMask: UInt64 {
        switch self {
        case .leftControl:  return 0x0000_0001  // NX_DEVICELCTLKEYMASK
        case .rightControl: return 0x0000_2000  // NX_DEVICERCTLKEYMASK
        case .rightCommand: return 0x0000_0010  // NX_DEVICERCMDKEYMASK
        case .rightOption:  return 0x0000_0040  // NX_DEVICERALTKEYMASK
        case .rightShift:   return 0x0000_0004  // NX_DEVICERSHIFTKEYMASK
        }
    }

    public var displayName: String {
        switch self {
        case .rightControl: return "Right Control"
        case .leftControl:  return "Left Control"
        case .rightCommand: return "Right Command"
        case .rightOption:  return "Right Option"
        case .rightShift:   return "Right Shift"
        }
    }

    /// Single glyph used in menu titles and the on-screen hint.
    public var symbol: String {
        switch self {
        case .rightControl, .leftControl: return "⌃"
        case .rightCommand:               return "⌘"
        case .rightOption:                return "⌥"
        case .rightShift:                 return "⇧"
        }
    }

    /// Every modifier key code we care about, so the detector can treat a
    /// *different* modifier as sequence-breaking activity.
    public static let allModifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}
