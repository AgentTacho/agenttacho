// Renders both DMG window backgrounds into Resources/dmg/ (research.md R5,
// spec 023 research R3): the unnotarized one entirely from code, the
// notarized one by drawing its title on the committed title-less artwork
// (background-notarized-base.png and @2x), so a new app name needs no image
// editing.
//
// Usage (from the repository root): swift scripts/release/render-dmg-backgrounds.swift [output-dir]
//
// The background is written at 1x and 2x for a 660 x 440 pt window, with the
// app icon at (165, 175) and the Applications link at (495, 175), measured from
// the top left as dmgbuild places them (dmg-settings.py LAYOUTS). The
// first-launch steps fill the lower third. Text is dark on a light background, so
// it reads the same in light and dark Finder appearance.
//
// The 440 pt window frame includes Finder's title bar, which is up to 68 pt tall
// (macOS 26 shows a tab bar there), so everything is drawn within the top
// 370 pt of the image.

import AppKit

let appName = "AgentTacho"

let windowSize = NSSize(width: 660, height: 440)
let appCenter = NSPoint(x: 165, y: 175)
let applicationsCenter = NSPoint(x: 495, y: 175)
let iconHalfWidth: CGFloat = 64

let backgroundColor = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.972, alpha: 1)
let textColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let secondaryTextColor = NSColor(srgbRed: 0.30, green: 0.30, blue: 0.33, alpha: 1)
let arrowColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
let panelColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let panelBorderColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1)

/// Converts a point measured from the top left into AppKit's bottom-left space.
func flipped(_ point: NSPoint) -> NSPoint {
    NSPoint(x: point.x, y: windowSize.height - point.y)
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: centerX - size.width / 2, y: windowSize.height - top - size.height))
}

func drawLeft(_ string: NSAttributedString, x: CGFloat, top: CGFloat) -> CGFloat {
    let size = string.size()
    string.draw(at: NSPoint(x: x, y: windowSize.height - top - size.height))
    return size.height
}

func drawArrow() {
    let start = flipped(NSPoint(x: appCenter.x + iconHalfWidth + 24, y: appCenter.y))
    let end = flipped(NSPoint(x: applicationsCenter.x - iconHalfWidth - 24, y: applicationsCenter.y))
    let headLength: CGFloat = 16
    let headHalfHeight: CGFloat = 11

    arrowColor.setStroke()
    arrowColor.setFill()

    let shaft = NSBezierPath()
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.move(to: start)
    shaft.line(to: NSPoint(x: end.x - headLength + 2, y: end.y))
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - headLength, y: end.y + headHalfHeight))
    head.line(to: NSPoint(x: end.x - headLength, y: end.y - headHalfHeight))
    head.close()
    head.fill()
}

func drawFirstLaunchSteps() {
    let panelRect = NSRect(x: 40, y: 76, width: windowSize.width - 80, height: 90)
    let panel = NSBezierPath(roundedRect: panelRect, xRadius: 10, yRadius: 10)
    panelColor.setFill()
    panel.fill()
    panelBorderColor.setStroke()
    panel.lineWidth = 1
    panel.stroke()

    let x = panelRect.minX + 20
    var top = windowSize.height - panelRect.maxY + 14
    let body = NSFont.systemFont(ofSize: 11.5)
    let bold = NSFont.boldSystemFont(ofSize: 11.5)
    let mono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    func line(_ parts: [(String, NSFont, NSColor)]) {
        let string = NSMutableAttributedString()
        for (text, font, color) in parts {
            string.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        top += drawLeft(string, x: x, top: top) + 3
    }

    line([("First launch after each install or upgrade:", NSFont.boldSystemFont(ofSize: 12), textColor)])
    line([("macOS 14: ", bold, textColor),
          ("Control-click \(appName) in Applications, choose Open", body, textColor)])
    line([("macOS 15 or later: ", bold, textColor),
          ("open it, then System Settings > Privacy & Security > Open Anyway", body, textColor)])
    line([("or run: ", body, secondaryTextColor),
          ("xattr -dr com.apple.quarantine /Applications/\(appName).app", mono, textColor)])
}

func render(scale: CGFloat) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(windowSize.width * scale),
        pixelsHigh: Int(windowSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("cannot create bitmap")
    }
    rep.size = windowSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    backgroundColor.setFill()
    NSRect(origin: .zero, size: windowSize).fill()

    drawCentered("Drag \(appName) to Applications",
                 font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                 color: textColor,
                 centerX: windowSize.width / 2,
                 top: 34)
    drawArrow()
    drawFirstLaunchSteps()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode PNG")
    }
    return png
}

// The notarized artwork (dmg-settings.py LAYOUTS): 836 x 470 pt, with the
// title centered where the painted one was, measured on the original artwork
// as the glyph box x 200 to 631, y 79 to 108 at 1x.
let notarizedSize = NSSize(width: 836, height: 470)
let notarizedTitleCenter = NSPoint(x: 415.5, y: 93.5)
// The teal of the painted title, sampled from the 2x artwork.
let notarizedTitleColor = NSColor(srgbRed: 2 / 255, green: 65 / 255, blue: 64 / 255, alpha: 1)

/// The rounded bold system font, closest to the painted title's weight.
/// 29.2 pt makes the original title's text as wide as the painted one
/// (431 pt), measured once when the artwork lost its painted title.
func notarizedTitleFont() -> NSFont {
    let size: CGFloat = 29.2
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func renderNotarized(scale: CGFloat, base: URL) -> Data {
    guard let image = NSImage(contentsOf: base) else { fatalError("cannot read \(base.path)") }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(notarizedSize.width * scale),
        pixelsHigh: Int(notarizedSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("cannot create bitmap")
    }
    rep.size = notarizedSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: notarizedSize))

    let title = NSAttributedString(string: "Drag \(appName) to Applications",
                                   attributes: [.font: notarizedTitleFont(), .foregroundColor: notarizedTitleColor])
    let glyphs = title.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    // Center the glyph box (not the line box) on the painted title's center.
    let origin = NSPoint(x: notarizedTitleCenter.x - glyphs.width / 2 - glyphs.minX,
                         y: notarizedSize.height - notarizedTitleCenter.y - glyphs.height / 2 - glyphs.minY)
    title.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode PNG")
    }
    return png
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/dmg")
let baseDirectory = URL(fileURLWithPath: "Resources/dmg")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    let url = outputDirectory.appendingPathComponent("background-unnotarized\(suffix).png")
    try render(scale: CGFloat(scale)).write(to: url)
    print("wrote \(url.path)")
    let notarized = outputDirectory.appendingPathComponent("background-notarized\(suffix).png")
    let base = baseDirectory.appendingPathComponent("background-notarized-base\(suffix).png")
    try renderNotarized(scale: CGFloat(scale), base: base).write(to: notarized)
    print("wrote \(notarized.path)")
}
