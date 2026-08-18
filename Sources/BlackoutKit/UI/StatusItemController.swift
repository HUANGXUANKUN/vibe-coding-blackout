import AppKit

/// The menu-bar item and the entire settings surface.
///
/// There is deliberately no preferences window: every setting fits in the menu,
/// and a menu-bar utility that opens a window to toggle five checkboxes is
/// over-built (PRD 4.3 / 2.8).
public final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let controller: BlackoutController
    private let monitor: EventTapMonitor
    private let prefs: Preferences

    public var onShowOnboarding: (() -> Void)?
    public var onQuit: (() -> Void)?

    private static let repositoryURL = URL(string: "https://github.com/HUANGXUANKUN/vibe-coding-blackout")!

    public init(controller: BlackoutController, monitor: EventTapMonitor, prefs: Preferences = .shared) {
        self.controller = controller
        self.monitor = monitor
        self.prefs = prefs
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // An empty behaviour set means the item cannot be dragged out of the menu
        // bar at all. This is a panic button: it has to be where you look for it,
        // every time. (.terminationOnRemoval, used before, leaves removal on the
        // table and quits the app when it happens — the opposite of what a
        // permanent indicator wants.)
        statusItem.behavior = []
        // Defensive: overrides a visibility flag persisted as false by an earlier
        // run or a menu-bar manager.
        statusItem.isVisible = true

        refresh()

        // The one failure this app cannot report through its own UI is "the icon
        // never appeared", so say it in the log instead.
        Log.app.notice("""
            Status item: button=\(self.statusItem.button != nil) \
            visible=\(self.statusItem.isVisible) \
            length=\(self.statusItem.length) \
            thickness=\(NSStatusBar.system.thickness)
            """)
    }

    /// Mirrors `BlackoutController.isActive` into the menu-bar mark.
    public func refresh() {
        guard let button = statusItem.button else { return }
        button.image = Artwork.statusItemImage(active: controller.isActive)
        button.image?.size = NSSize(width: 18, height: 18)
        button.toolTip = controller.isActive
            ? "Blackout — screens hidden. Double-tap \(prefs.triggerKey.symbol) to restore."
            : "Blackout — double-tap \(prefs.triggerKey.displayName) to hide all screens."
    }

    // MARK: - Menu construction

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(stateItem())
        menu.addItem(subtitleItem("Double-tap \(prefs.triggerKey.displayName)"))
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: controller.isActive ? "Restore Screens" : "Black Out Now",
            action: #selector(toggleBlackout), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        menu.addItem(triggerMenuItem())
        menu.addItem(behaviorMenuItem())
        menu.addItem(.separator())

        for item in diagnosticItems() { menu.addItem(item) }

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isSupported
        if !LoginItem.isSupported {
            login.toolTip = "Available once Blackout is running from Blackout.app"
        }
        menu.addItem(login)
        menu.addItem(.separator())

        let how = NSMenuItem(title: "How It Works…", action: #selector(showOnboarding), keyEquivalent: "")
        how.target = self
        menu.addItem(how)

        let repo = NSMenuItem(title: "GitHub Repository", action: #selector(openRepository), keyEquivalent: "")
        repo.target = self
        menu.addItem(repo)

        let quit = NSMenuItem(title: "Quit Blackout", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func stateItem() -> NSMenuItem {
        let item = NSMenuItem()
        let text = controller.isActive ? "Screens blacked out" : "Screens visible"
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func subtitleItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func triggerMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Trigger", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.displayName, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            item.state = prefs.triggerKey == key ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(subtitleItem("Double-tap speed"))
        for speed in TapSpeed.allCases {
            let item = NSMenuItem(title: speed.displayName, action: #selector(selectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            item.state = prefs.tapSpeed == speed ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        return parent
    }

    private func behaviorMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Behavior", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        func check(_ title: String, _ on: Bool, _ selector: Selector, enabled: Bool = true, tip: String? = nil) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.state = on ? .on : .off
            item.isEnabled = enabled
            item.toolTip = tip
            submenu.addItem(item)
        }

        check("Dim display backlight", prefs.dimBacklight, #selector(toggleDimBacklight),
              enabled: controller.backlightControlAvailable,
              tip: "Lowers the backlight on displays that support it, and restores each display's own level afterwards.")
        check("Keep Mac awake while blacked out", prefs.keepAwake, #selector(toggleKeepAwake),
              tip: "Prevents idle system sleep so long-running work keeps going.")
        check("Block keyboard & mouse", prefs.blockInput, #selector(toggleBlockInput),
              tip: "Swallows keys and clicks while the screens are hidden. esc still restores.")
        check("esc restores", prefs.escapeRestores, #selector(toggleEscapeRestores),
              tip: "A safety exit that never depends on getting the double-tap right.")
        submenu.addItem(.separator())
        check("Fade animation", prefs.fadeEnabled, #selector(toggleFade))
        check("Show hint on blackout", prefs.showHint, #selector(toggleShowHint))

        parent.submenu = submenu
        return parent
    }

    /// Only surfaces problems, and only while they exist. A menu full of green
    /// checkmarks telling you everything is fine is noise.
    private func diagnosticItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if !monitor.hasAccessibilityAccess {
            let item = NSMenuItem(title: "⚠︎  Enable Accessibility access…",
                                  action: #selector(openAccessibilitySettings), keyEquivalent: "")
            item.target = self
            item.toolTip = "Required for the double-tap gesture. You can still black out from this menu without it."
            items.append(item)
        } else if monitor.isSecureInputActive {
            let item = NSMenuItem(title: "⚠︎  Hotkey paused by secure input", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = "A password field or a terminal with secure keyboard entry is focused. macOS disables all hotkeys while that is true."
            items.append(item)
        }

        if !controller.backlightControlAvailable {
            let item = NSMenuItem(title: "ⓘ  Backlight dimming unavailable", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = "Screens still go fully black; only the backlight step is skipped."
            items.append(item)
        }

        if !items.isEmpty { items.append(.separator()) }
        return items
    }

    // MARK: - Actions

    @objc private func toggleBlackout() { controller.toggle() }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = TriggerKey(rawValue: raw) else { return }
        prefs.triggerKey = key
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let speed = TapSpeed(rawValue: raw) else { return }
        prefs.tapSpeed = speed
    }

    @objc private func toggleDimBacklight() { prefs.dimBacklight.toggle() }
    @objc private func toggleKeepAwake() { prefs.keepAwake.toggle() }
    @objc private func toggleBlockInput() { prefs.blockInput.toggle() }
    @objc private func toggleEscapeRestores() { prefs.escapeRestores.toggle() }
    @objc private func toggleFade() { prefs.fadeEnabled.toggle() }
    @objc private func toggleShowHint() { prefs.showHint.toggle() }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openAccessibilitySettings() {
        PermissionPrompt.requestAccessibility()
    }

    @objc private func showOnboarding() { onShowOnboarding?() }

    @objc private func openRepository() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc private func quit() { onQuit?() }
}
