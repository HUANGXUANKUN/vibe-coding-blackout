import Foundation
import os

/// Subsystem-scoped loggers. Read them with:
/// `log stream --predicate 'subsystem == "com.huangxuankun.blackout"'`
public enum Log {
    private static let subsystem = "com.huangxuankun.blackout"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
    public static let brightness = Logger(subsystem: subsystem, category: "brightness")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let power = Logger(subsystem: subsystem, category: "power")
}
