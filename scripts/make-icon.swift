#!/usr/bin/env swift
// Draws the app icon (a wooden crate full of apples) and writes the AppIcon.appiconset.
//   swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let out = URL(filePath: "Apfelkiste/Resources/Assets.xcassets/AppIcon.appiconset")

func apple(center: CGPoint, radius r: CGFloat, hue: CGFloat, tilt: CGFloat = 0) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: tilt)
    // Body: two overlapping lobes give the apple dip at the top.
    let body = NSBezierPath()
    body.move(to: CGPoint(x: 0, y: r * 0.62))
    body.curve(to: CGPoint(x: r, y: r * 0.05), controlPoint1: CGPoint(x: r * 0.35, y: r * 0.98), controlPoint2: CGPoint(x: r * 1.02, y: r * 0.72))
    body.curve(to: CGPoint(x: 0, y: -r), controlPoint1: CGPoint(x: r * 0.98, y: -r * 0.62), controlPoint2: CGPoint(x: r * 0.48, y: -r))
    body.curve(to: CGPoint(x: -r, y: r * 0.05), controlPoint1: CGPoint(x: -r * 0.48, y: -r), controlPoint2: CGPoint(x: -r * 0.98, y: -r * 0.62))
    body.curve(to: CGPoint(x: 0, y: r * 0.62), controlPoint1: CGPoint(x: -r * 1.02, y: r * 0.72), controlPoint2: CGPoint(x: -r * 0.35, y: r * 0.98))
    body.close()
    NSGradient(starting: NSColor(hue: hue, saturation: 0.7, brightness: 1, alpha: 1),
               ending: NSColor(hue: hue, saturation: 0.9, brightness: 0.72, alpha: 1))!
        .draw(in: body, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))
    // Highlight.
    NSColor.white.withAlphaComponent(0.35).setFill()
    NSBezierPath(ovalIn: CGRect(x: -r * 0.62, y: r * 0.05, width: r * 0.32, height: r * 0.42)).fill()
    // Stem and leaf.
    let stem = NSBezierPath()
    stem.move(to: CGPoint(x: 0, y: r * 0.55))
    stem.curve(to: CGPoint(x: -r * 0.12, y: r * 1.08), controlPoint1: CGPoint(x: 0, y: r * 0.8), controlPoint2: CGPoint(x: -r * 0.05, y: r))
    stem.lineWidth = r * 0.11
    stem.lineCapStyle = .round
    NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.12, alpha: 1).setStroke()
    stem.stroke()
    let leaf = NSBezierPath()
    leaf.move(to: CGPoint(x: r * 0.02, y: r * 0.82))
    leaf.curve(to: CGPoint(x: r * 0.62, y: r * 1.12), controlPoint1: CGPoint(x: r * 0.12, y: r * 1.18), controlPoint2: CGPoint(x: r * 0.42, y: r * 1.25))
    leaf.curve(to: CGPoint(x: r * 0.02, y: r * 0.82), controlPoint1: CGPoint(x: r * 0.5, y: r * 0.82), controlPoint2: CGPoint(x: r * 0.22, y: r * 0.72))
    NSColor(calibratedRed: 0.3, green: 0.68, blue: 0.25, alpha: 1).setFill()
    leaf.fill()
    ctx.restoreGState()
}

func plank(_ rect: CGRect, shade: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    NSGradient(starting: NSColor(calibratedRed: 0.86 * shade, green: 0.62 * shade, blue: 0.36 * shade, alpha: 1),
               ending: NSColor(calibratedRed: 0.7 * shade, green: 0.46 * shade, blue: 0.24 * shade, alpha: 1))!
        .draw(in: path, angle: -90)
    // Wood grain.
    NSColor(calibratedRed: 0.5, green: 0.3, blue: 0.14, alpha: 0.25).setStroke()
    for i in 1...2 {
        let y = rect.minY + rect.height * CGFloat(i) / 3
        let grain = NSBezierPath()
        grain.move(to: CGPoint(x: rect.minX + 40, y: y))
        grain.curve(to: CGPoint(x: rect.maxX - 40, y: y + 4), controlPoint1: CGPoint(x: rect.midX - 80, y: y + 10), controlPoint2: CGPoint(x: rect.midX + 80, y: y - 8))
        grain.lineWidth = 4
        grain.stroke()
    }
}

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    // Squircle-ish tile on Apple's 824 pt grid.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let background = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.88, alpha: 1),
               ending: NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.7, alpha: 1))!
        .draw(in: background, angle: -90)
    background.addClip()

    // Apples piled in the crate (drawn first, the crate front covers their lower half).
    apple(center: CGPoint(x: 330, y: 560), radius: 120, hue: 0.0, tilt: 0.15)
    apple(center: CGPoint(x: 694, y: 560), radius: 120, hue: 0.02, tilt: -0.2)
    apple(center: CGPoint(x: 512, y: 610), radius: 135, hue: 0.22)
    // Crate front: three planks and two posts.
    plank(CGRect(x: 170, y: 418, width: 684, height: 118), shade: 1)
    plank(CGRect(x: 170, y: 292, width: 684, height: 118), shade: 0.94)
    plank(CGRect(x: 170, y: 166, width: 684, height: 118), shade: 0.88)
    for x in [170.0, 794.0] {
        let post = NSBezierPath(roundedRect: CGRect(x: x, y: 150, width: 60, height: 404), xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.18, alpha: 1).setFill()
        post.fill()
    }
    // A windfall apple next to the crate.
    apple(center: CGPoint(x: 770, y: 196), radius: 60, hue: 0.07, tilt: -1.7)
    return true
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
    entries.append("""
        { "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)", "filename" : "\(name)" }
    """)
}
let json = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(to: out.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("✓ \(out.path)")
