#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDirectory = root.appendingPathComponent("Pinny/Resources/Assets.xcassets/AppIcon.appiconset")
let runtimeDirectory = root.appendingPathComponent("Pinny/Resources/RuntimeAssets")

func bitmap(size: Int, draw: (CGFloat) -> Void) throws -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "PinnyIconGenerator", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current = context
    context?.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context?.cgContext.setShouldAntialias(true)
    draw(CGFloat(size))
    context?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PinnyIconGenerator", code: 2)
    }
    return data
}

func drawAppIcon(canvas: CGFloat) {
    let scale = canvas / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    NSColor(calibratedRed: 0.341, green: 0.337, blue: 0.902, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect(48, 48, 928, 928), xRadius: 214 * scale, yRadius: 214 * scale).fill()

    NSColor(calibratedRed: 0.439, green: 0.435, blue: 0.941, alpha: 0.52).setFill()
    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: 80 * scale, y: 708 * scale))
    highlight.curve(
        to: NSPoint(x: 956 * scale, y: 770 * scale),
        controlPoint1: NSPoint(x: 210 * scale, y: 930 * scale),
        controlPoint2: NSPoint(x: 760 * scale, y: 1020 * scale)
    )
    highlight.line(to: NSPoint(x: 956 * scale, y: 976 * scale))
    highlight.line(to: NSPoint(x: 80 * scale, y: 976 * scale))
    highlight.close()
    highlight.fill()

    NSColor(calibratedRed: 0.161, green: 0.153, blue: 0.498, alpha: 0.28).setFill()
    NSBezierPath(ovalIn: rect(294, 229, 436, 112)).fill()

    NSColor(calibratedRed: 1, green: 0.992, blue: 0.969, alpha: 1).setFill()
    let cap = NSBezierPath(roundedRect: rect(275, 646, 474, 136), xRadius: 56 * scale, yRadius: 56 * scale)
    cap.fill()

    let body = NSBezierPath()
    body.move(to: NSPoint(x: 317 * scale, y: 646 * scale))
    body.line(to: NSPoint(x: 255 * scale, y: 394 * scale))
    body.line(to: NSPoint(x: 451 * scale, y: 394 * scale))
    body.line(to: NSPoint(x: 451 * scale, y: 322 * scale))
    body.line(to: NSPoint(x: 512 * scale, y: 168 * scale))
    body.line(to: NSPoint(x: 573 * scale, y: 322 * scale))
    body.line(to: NSPoint(x: 573 * scale, y: 394 * scale))
    body.line(to: NSPoint(x: 769 * scale, y: 394 * scale))
    body.line(to: NSPoint(x: 707 * scale, y: 646 * scale))
    body.close()
    body.fill()

    NSColor(calibratedRed: 0.851, green: 0.847, blue: 1, alpha: 1).setStroke()
    let divider = NSBezierPath()
    divider.lineWidth = 24 * scale
    divider.move(to: NSPoint(x: 275 * scale, y: 646 * scale))
    divider.line(to: NSPoint(x: 749 * scale, y: 646 * scale))
    divider.stroke()
}

func drawMenuIcon(canvas: CGFloat, filled: Bool) {
    let scale = canvas / 18
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 6.15 * scale, y: 15.55 * scale))
    path.line(to: NSPoint(x: 11.85 * scale, y: 15.55 * scale))
    path.line(to: NSPoint(x: 11.85 * scale, y: 13.15 * scale))
    path.line(to: NSPoint(x: 12.8 * scale, y: 8.3 * scale))
    path.line(to: NSPoint(x: 9.85 * scale, y: 8.3 * scale))
    path.line(to: NSPoint(x: 9.85 * scale, y: 5.4 * scale))
    path.line(to: NSPoint(x: 9 * scale, y: 2.35 * scale))
    path.line(to: NSPoint(x: 8.15 * scale, y: 5.4 * scale))
    path.line(to: NSPoint(x: 8.15 * scale, y: 8.3 * scale))
    path.line(to: NSPoint(x: 5.2 * scale, y: 8.3 * scale))
    path.line(to: NSPoint(x: 6.15 * scale, y: 13.15 * scale))
    path.close()

    NSColor.black.setStroke()
    NSColor.black.setFill()
    path.lineJoinStyle = .round
    if filled {
        path.fill()
    } else {
        path.lineWidth = 1.45 * scale
        path.stroke()
        let divider = NSBezierPath()
        divider.lineWidth = 1.45 * scale
        divider.move(to: NSPoint(x: 5.65 * scale, y: 13.15 * scale))
        divider.line(to: NSPoint(x: 12.35 * scale, y: 13.15 * scale))
        divider.stroke()
    }
}

try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let data = try bitmap(size: size, draw: drawAppIcon)
    try data.write(to: appIconDirectory.appendingPathComponent("AppIcon-\(size).png"), options: .atomic)
}

for (name, isFilled) in [("MenuBarIdle", false), ("MenuBarPinned", true)] {
    let data = try bitmap(size: 36) { drawMenuIcon(canvas: $0, filled: isFilled) }
    try data.write(to: runtimeDirectory.appendingPathComponent("\(name).png"), options: .atomic)
}

let iconsetDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("Pinny-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetDirectory) }

let iconsetFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]
for (fileName, size) in iconsetFiles {
    try FileManager.default.copyItem(
        at: appIconDirectory.appendingPathComponent("AppIcon-\(size).png"),
        to: iconsetDirectory.appendingPathComponent(fileName)
    )
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconsetDirectory.path,
    "-o", runtimeDirectory.appendingPathComponent("Pinny.icns").path
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "PinnyIconGenerator", code: Int(iconutil.terminationStatus))
}

print("Generated Pinny icon PNG assets.")
