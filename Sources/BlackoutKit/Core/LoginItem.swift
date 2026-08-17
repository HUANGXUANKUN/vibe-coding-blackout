import Foundation
import ServiceManagement

/// "Launch at Login" via `SMAppService`. Only meaningful for a real .app bundle;
/// reports `.unsupported` when running the bare SwiftPM binary.
public enum LoginItem {

    public static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    public static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Never throws at the caller: a failed toggle just
    /// leaves the menu item unchecked with a log line.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            Log.app.error("Login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
