import AppKit
import ApplicationServices

/// Accessibility (`kTCCServiceAccessibility`) is what a `.defaultTap` event tap
/// needs. Nothing else in the app requires a permission.
public enum PermissionPrompt {

    public static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// The system prompt on its own. macOS shows it at most once per binary, so
    /// this is safe to call at launch — it will not nag.
    public static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Prompt *and* open the settings pane. For explicit user actions only: after
    /// the first launch the prompt silently does nothing, so a menu item that
    /// only prompted would look broken.
    public static func requestAccessibility() {
        promptAccessibility()
        openAccessibilitySettings()
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
