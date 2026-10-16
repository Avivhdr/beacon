// Dark drag-to-Applications backdrop: ink field, a faint radar, a hairline.
// Usage: swift Tools/generate-dmg-background.swift <output.png> [width] [height]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/beacon-dmg-background.png"
let width = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 660 : 660
let height = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 400 : 400

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let w = CGFloat(width)
let h = CGFloat(height)

ctx.setFillColor(CGColor(red: 12.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

let center = CGPoint(x: w * 0.5, y: h * 0.46)
let radius = min(w, h) * 0.28
for ring in 1...4 {
    let r = radius * CGFloat(ring) / 4
    ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: ring == 4 ? 0.08 : 0.04))
    ctx.setLineWidth(1)
    ctx.strokePath()
}

var x: CGFloat = 0
var index = 0
let tickY = h - 28
while x < w {
    let long = index % 5 == 0
    let tickH: CGFloat = long ? 10 : 5
    ctx.setFillColor(CGColor(gray: 1, alpha: long ? 0.10 : 0.05))
    ctx.fill(CGRect(x: x, y: tickY, width: 1, height: tickH))
    x += 6
    index += 1
}

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
