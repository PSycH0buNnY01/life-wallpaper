// Draws the app icon (a glider on a grid) into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset

import Cocoa

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let glider: Set<[Int]> = [[2, 1], [3, 2], [1, 3], [2, 3], [3, 3]]

func draw(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor(srgbRed: 0.043, green: 0.055, blue: 0.067, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.width * 0.22).fill()

    let n = 5
    let cell = tile.width * 0.76 / CGFloat(n)
    let origin = tile.minX + (tile.width - cell * CGFloat(n)) / 2
    for gx in 0..<n {
        for gy in 0..<n {
            let alive = glider.contains([gx, gy])
            (alive ? NSColor(srgbRed: 0.40, green: 0.92, blue: 0.75, alpha: 1)
                   : NSColor(srgbRed: 0.40, green: 0.92, blue: 0.75, alpha: 0.07)).setFill()
            let r = NSRect(x: origin + CGFloat(gx) * cell, y: origin + CGFloat(n - 1 - gy) * cell,
                           width: cell * 0.86, height: cell * 0.86)
            NSBezierPath(roundedRect: r, xRadius: cell * 0.12, yRadius: cell * 0.12).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
