import AppKit

/// All artwork is drawn in code — no asset catalog, no Xcode required, and the
/// menu-bar mark and the app icon are guaranteed to stay the same shape because
/// they come from one function.
public enum Artwork {

    /// The mark: a display. Outlined when the screens are visible, filled solid
    /// when they are blacked out — the state reads at a glance without colour
    /// (PRD 4.3).
    private static func drawDisplay(in size: NSSize, filled: Bool, lineWidth: CGFloat) {
        let s = min(size.width, size.height) / 18.0

        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }

        NSBezierPath(rect: rect(7.4, 3.5, 3.2, 2.1)).fill()
        NSBezierPath(roundedRect: rect(4.4, 2.0, 9.2, 1.6),
                     xRadius: 0.8 * s, yRadius: 0.8 * s).fill()

        let screenRect = rect(1.5, 5.4, 15, 10.6)
        if filled {
            NSBezierPath(roundedRect: screenRect, xRadius: 2.3 * s, yRadius: 2.3 * s).fill()
        } else {
            // Stroke on the path centre-line, so inset by half the width to keep
            // the mark inside its box at 18pt.
            let stroke = lineWidth * s
            let path = NSBezierPath(roundedRect: screenRect.insetBy(dx: stroke / 2, dy: stroke / 2),
                                    xRadius: 2.3 * s - stroke / 2,
                                    yRadius: 2.3 * s - stroke / 2)
            path.lineWidth = stroke
            path.stroke()
        }
    }

    /// Menu-bar template image. `isTemplate` lets macOS handle light/dark,
    /// highlight and Reduce Transparency for us.
    public static func statusItemImage(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            drawDisplay(in: size, filled: active, lineWidth: 1.4)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Larger glyph used inside the onboarding window.
    public static func heroImage(active: Bool, side: CGFloat = 72) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.setFill()
            NSColor.labelColor.setStroke()
            drawDisplay(in: size, filled: active, lineWidth: 1.25)
            return true
        }
        return image
    }

    /// App icon at one size. Only visible in Finder (the app is an accessory with
    /// no Dock tile), but a bundle without an icon looks broken.
    public static func appIcon(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let inset = side * 0.085
            let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            let squircle = NSBezierPath(roundedRect: box,
                                        xRadius: box.width * 0.225,
                                        yRadius: box.width * 0.225)
            squircle.addClip()

            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.16, alpha: 1),
                NSColor(calibratedWhite: 0.02, alpha: 1),
            ])
            gradient?.draw(in: box, angle: -90)

            NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
            let hairline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: box.width * 0.225,
                                        yRadius: box.width * 0.225)
            hairline.lineWidth = 1
            hairline.stroke()

            // Centred glyph at ~52% of the icon box.
            let glyph = box.width * 0.52
            let origin = NSPoint(x: box.midX - glyph / 2, y: box.midY - glyph / 2)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: origin.x, yBy: origin.y)
            transform.concat()
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            NSColor(calibratedWhite: 0.93, alpha: 1).setStroke()
            drawDisplay(in: NSSize(width: glyph, height: glyph), filled: true, lineWidth: 1.4)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// Writes an `.iconset` directory that `iconutil` can turn into an `.icns`.
    /// Driven by `blackout --emit-iconset <dir>` from `scripts/bundle.sh`.
    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let variants: [(name: String, side: CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for variant in variants {
            // Render into an explicitly sized bitmap: relying on
            // `tiffRepresentation` would give whatever the current backing scale
            // is, and iconutil rejects mis-sized slices.
            let pixels = Int(variant.side)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else {
                throw CocoaError(.fileWriteUnknown)
            }
            rep.size = NSSize(width: variant.side, height: variant.side)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            appIcon(side: variant.side).draw(in: NSRect(x: 0, y: 0, width: variant.side, height: variant.side))
            NSGraphicsContext.restoreGraphicsState()

            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: directory.appendingPathComponent("\(variant.name).png"))
        }
    }
}
