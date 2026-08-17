import AppKit
import BlackoutKit

let version = "1.0.0"

func printUsage() {
    print("""
    Blackout \(version) — hide every screen with a double-tap.

    Usage:
      blackout                      Run the menu-bar app
      blackout --self-test          Black out for ~1.2s, restore, verify (safe, no permissions)
      blackout --emit-iconset DIR   Write an .iconset directory for iconutil
      blackout --version            Print the version
      blackout --help               This message
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--version", "-v":
    print(version)
    exit(0)

case "--help", "-h":
    printUsage()
    exit(0)

case "--self-test":
    exit(SelfTest.run())

case "--emit-iconset":
    guard arguments.count >= 2 else {
        FileHandle.standardError.write(Data("error: --emit-iconset needs a destination directory\n".utf8))
        exit(2)
    }
    // Deliberately does not touch NSApplication: offscreen bitmap drawing works
    // without a window-server connection, so this stays usable in CI.
    do {
        try Artwork.writeIconset(to: URL(fileURLWithPath: arguments[1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case .some(let unknown):
    FileHandle.standardError.write(Data("error: unknown option \(unknown)\n".utf8))
    printUsage()
    exit(2)

case .none:
    let app = NSApplication.shared
    let delegate = BlackoutAppDelegate()
    app.delegate = delegate
    app.run()
}
