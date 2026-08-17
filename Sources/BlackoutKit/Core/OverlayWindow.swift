import AppKit

/// The fading hint drawn on the screen that owns the mouse, so a first-time user
/// is never stranded in the dark wondering how to get out (PRD 4.2).
final class HintView: NSView {
    var text: String = "" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private let horizontalPadding: CGFloat = 22
    private let verticalPadding: CGFloat = 13
    private let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    override var isOpaque: Bool { false }

    private var attributed: NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            // Dim grey: readable at a glance, never bright enough to be a leak.
            .foregroundColor: NSColor(white: 0.62, alpha: 1.0),
            .kern: 0.2,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let size = attributed.size()
        return NSSize(width: ceil(size.width) + horizontalPadding * 2,
                      height: ceil(size.height) + verticalPadding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = pill.height / 2
        let path = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)
        NSColor(white: 1.0, alpha: 0.055).setFill()
        path.fill()
        NSColor(white: 1.0, alpha: 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        let string = attributed
        let size = string.size()
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                y: (bounds.height - size.height) / 2))
    }
}

private final class OverlayContentView: NSView {
    let hint = HintView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        hint.wantsLayer = true
        hint.alphaValue = 0
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        let size = hint.intrinsicContentSize
        hint.frame = NSRect(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2,
                            width: size.width,
                            height: size.height)
    }
}

/// One opaque black panel covering exactly one display.
///
/// A `.nonactivatingPanel` that cannot become key or main: ordering it in front
/// must not steal focus from whatever the user left running (PRD 2.6 / G3).
final class OverlayWindow: NSPanel {

    private let content = OverlayContentView(frame: .zero)

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        // Above the menu bar, the Dock, and — critically — notification banners.
        // One WeChat preview floating over a "blacked out" screen would leak
        // everything (PRD 1.7).
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        alphaValue = 0
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        worksWhenModal = true
        // Stay put across Space switches; without this a new Space is fully
        // exposed (PRD 3.13).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        // Swallow stray clicks instead of letting them reach the apps underneath.
        ignoresMouseEvents = false
        contentView = content
        setFrame(screen.frame, display: false)
    }

    /// When true the panel takes key focus so it can receive `esc` through plain
    /// AppKit, with no event tap and therefore no permission involved. This is
    /// the escape hatch that does not depend on Accessibility being granted or on
    /// macOS not having disabled event taps for secure input.
    ///
    /// `.nonactivatingPanel` means becoming key does *not* activate the app, so
    /// the frontmost application still stays frontmost.
    var acceptsKeys = false
    /// Additionally dismiss on a click. Only enabled when the hotkey is
    /// unavailable, where an extra way out is worth more than the risk of a
    /// stray click undoing the blackout.
    var dismissOnClick = false
    /// Invoked when the user asks to restore from within the overlay itself.
    var onDismissRequest: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // 53 == kVK_Escape. Everything else is swallowed: the screens are hidden,
        // keystrokes have nowhere useful to go.
        if event.keyCode == 53 { onDismissRequest?() }
    }

    override func mouseDown(with event: NSEvent) {
        if dismissOnClick { onDismissRequest?() }
    }

    func match(_ screen: NSScreen) {
        if frame != screen.frame {
            setFrame(screen.frame, display: false)
        }
    }

    // MARK: - Hint

    /// Guards the delayed fade-out against a blackout that was dismissed and
    /// restarted while the hint was still on screen.
    private var hintGeneration = 0

    func showHint(_ text: String, holdFor hold: TimeInterval = 0.9, fadeFor fade: TimeInterval = 1.3) {
        hintGeneration += 1
        let generation = hintGeneration

        content.hint.text = text
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        content.hint.alphaValue = 0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.hint.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22 + hold) { [weak self] in
            guard let self, self.hintGeneration == generation else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fade
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.content.hint.animator().alphaValue = 0
            }
        }
    }

    func hideHintImmediately() {
        hintGeneration += 1
        content.hint.layer?.removeAllAnimations()
        content.hint.alphaValue = 0
    }
}
