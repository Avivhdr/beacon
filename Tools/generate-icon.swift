// Generates the Beacon app icon: an ink squircle, a radar scope, an amber beam.
// Usage: swift Tools/generate-icon.swift <output-dir>
// The menu bar icon is separate and does not come from these PNGs.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/Beacon/Assets.xcassets/AppIcon.appiconset"

let ink = CGColor(red: 12.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, alpha: 1)
let surface = CGColor(red: 18.0 / 255, green: 22.0 / 255, blue: 29.0 / 255, alpha: 1)
let amber = CGColor(red: 244.0 / 255, green: 169.0 / 255, blue: 59.0 / 255, alpha: 1)

func squircle(in rect: CGRect) -> CGPath {
    // A superellipse (n = 5) reads as the macOS icon shape. A plain rounded rect looks like a button.
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let n: CGFloat = 5
    let steps = max(80, Int(rect.width))
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func makeIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let pad = s * 0.04
    let plate = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let shape = squircle(in: plate)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [surface, ink] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.midX, y: plate.maxY), end: CGPoint(x: plate.midX, y: plate.minY), options: [])
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(max(1, s * 0.008))
    ctx.strokePath()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = plate.width * 0.34
    let small = size <= 32
    let rings = small ? 2 : 4
    let ticks = small ? 8 : 24
    let line = max(1, s * 0.012)

    for ring in 1...rings {
        let r = radius * CGFloat(ring) / CGFloat(rings)
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: ring == rings ? 0.22 : 0.12))
        ctx.setLineWidth(line)
        ctx.strokePath()
    }

    for i in 0..<ticks {
        let angle = CGFloat(i) / CGFloat(ticks) * 2 * .pi - .pi / 2
        let cardinal = i % (ticks / 4) == 0
        let inner = radius - (cardinal ? radius * 0.16 : radius * 0.08)
        ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        ctx.addLine(to: CGPoint(x: center.x + cos(angle) * (radius + line), y: center.y + sin(angle) * (radius + line)))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: cardinal ? 0.45 : 0.2))
        ctx.setLineWidth(max(1, s * (cardinal ? 0.016 : 0.01)))
        ctx.strokePath()
    }

    // Beam points up and to the right. The trail fades behind the sweep.
    let heading = -CGFloat.pi / 5
    let trail: CGFloat = 1.15
    let slices = small ? 10 : 28
    for i in 0..<slices {
        let from = heading - trail * CGFloat(i + 1) / CGFloat(slices)
        let to = heading - trail * CGFloat(i) / CGFloat(slices)
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
        ctx.closePath()
        let fade = 1 - CGFloat(i) / CGFloat(slices)
        ctx.setFillColor(amber.copy(alpha: 0.55 * fade * fade)!)
        ctx.fillPath()
    }
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(heading) * radius, y: center.y + sin(heading) * radius))
    ctx.setStrokeColor(amber)
    ctx.setLineWidth(max(1.5, s * 0.02))
    ctx.setLineCap(.round)
    ctx.strokePath()

    let dot = max(1.5, s * 0.028)
    ctx.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    ctx.setFillColor(amber)
    ctx.fillPath()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let directory = URL(fileURLWithPath: outDir)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in sizes {
    let url = directory.appendingPathComponent("icon_\(size).png")
    try makeIcon(size: size).write(to: url)
    print("wrote \(url.lastPathComponent)")
}
