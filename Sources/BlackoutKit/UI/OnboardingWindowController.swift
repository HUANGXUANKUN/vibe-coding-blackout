import AppKit

/// First-run explainer. Shown once automatically, and afterwards from
/// "How It Works…".
///
/// The one window in the app. It exists because the product is invisible by
/// design: without it, a new user has an unexplained menu-bar icon and no idea
/// that a keyboard gesture exists (PRD 4.4).
public final class OnboardingWindowController: NSWindowController {

    private let prefs: Preferences
    private var statusLabel: NSTextField!
    private var grantButton: NSButton!
    private var pollTimer: Timer?

    /// Blacks out for a moment and restores automatically, so the user's first
    /// experience of a fully black screen happens on purpose, with a known way out.
    public var onTryIt: (() -> Void)?

    public init(prefs: Preferences = .shared) {
        self.prefs = prefs
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Blackout"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let hero = NSImageView(image: Artwork.heroImage(active: true, side: 76))
        hero.imageScaling = .scaleProportionallyUpOrDown

        let title = label("Hide every screen instantly", size: 19, weight: .semibold)
        title.alignment = .center

        let gesture = label("Double-tap \(prefs.triggerKey.displayName)", size: 15, weight: .medium)
        gesture.alignment = .center
        gesture.textColor = .secondaryLabelColor

        // Built-in MacBook keyboards have no right-hand Control key at all, so the
        // default trigger is unreachable there and the app looks broken. Say so
        // rather than letting people conclude it does not work.
        let keyboardNote = label(
            "No such key on your keyboard? Built-in MacBook keyboards have no right-hand\n"
            + "Control — pick a different trigger from the menu bar icon ▸ Trigger.",
            size: 11, weight: .regular
        )
        keyboardNote.alignment = .center
        keyboardNote.textColor = .tertiaryLabelColor

        let body = label(
            """
            All of your displays go completely black while your Mac keeps \
            working — nothing is locked, nothing is interrupted.

            •  Double-tap again, or press esc, to bring them back
            •  Keyboard and mouse are ignored while hidden
            •  Your Mac is kept awake so long-running work continues
            •  Each display returns to its own previous brightness
            """,
            size: 12.5, weight: .regular
        )
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 380

        statusLabel = label("", size: 12, weight: .medium)
        statusLabel.alignment = .center

        grantButton = NSButton(title: "Enable Accessibility Access…",
                               target: self, action: #selector(grant))
        grantButton.bezelStyle = .rounded

        let tryButton = NSButton(title: "Try It Now", target: self, action: #selector(tryIt))
        tryButton.bezelStyle = .rounded

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [tryButton, doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [hero, title, gesture, keyboardNote, body, statusLabel, grantButton, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 36, bottom: 26, right: 36)
        stack.setCustomSpacing(18, after: hero)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(6, after: gesture)
        stack.setCustomSpacing(20, after: keyboardNote)
        stack.setCustomSpacing(20, after: body)
        stack.setCustomSpacing(14, after: grantButton)

        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        return field
    }

    // MARK: - Presentation

    public func present() {
        refreshPermissionState()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // The app is an accessory (no Dock tile), so it must be activated
        // explicitly or the window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)

        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refreshPermissionState() {
        let granted = PermissionPrompt.isAccessibilityGranted
        grantButton.isHidden = granted
        if granted {
            statusLabel.stringValue = "✓  Accessibility access granted — the gesture is live"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "Accessibility access is needed for the keyboard gesture"
            statusLabel.textColor = .systemOrange
        }
    }

    @objc private func grant() { PermissionPrompt.requestAccessibility() }

    @objc private func tryIt() { onTryIt?() }

    @objc private func done() {
        prefs.didOnboard = true
        pollTimer?.invalidate()
        pollTimer = nil
        close()
    }

    public override func windowWillLoad() { super.windowWillLoad() }
}
