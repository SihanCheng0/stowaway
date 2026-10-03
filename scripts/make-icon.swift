// Renders the Stowaway app icon: a glowing terracotta power orb on a warm near-black body.
//
//   xcrun swift scripts/make-icon.swift Stowaway/Assets.xcassets/AppIcon.appiconset [assets/app-icon-source.png]
//
// Writes the ten macOS icon_<pt>x<pt>[@2x].png slots plus an asset-catalog Contents.json into
// the output directory (point it at a *.iconset folder for `iconutil -c icns` instead). The
// optional second argument also writes the 1024px master. Every size is drawn natively rather
// than downscaled, and 16/32px get a simplified, pixel-snapped variant so they stay crisp.

import AppKit

let canvas: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

let emberLight: UInt32 = 0xF0A07E
let ember: UInt32 = 0xD97757
let emberDeep: UInt32 = 0x9C4A31

/// A square with Apple-style continuous corners (Figma corner smoothing 0.6, the iOS/macOS icon curve).
func squircle(_ rect: CGRect, radius r: CGFloat, smoothing: CGFloat = 0.6) -> CGPath {
    let p = (1 + smoothing) * r
    let arcDegrees = 90 * (1 - smoothing)
    let arcLength = sin(arcDegrees / 2 * .pi / 180) * r * 2.squareRoot()
    let alpha = (90 - arcDegrees) / 2 * .pi / 180
    let beta = 45 * smoothing * .pi / 180
    let c = r * tan(alpha / 2) * cos(beta)
    let d = c * tan(beta)
    let b = (p - arcLength - c - d) / 3
    let a = 2 * b
    let k = 4 / 3 * tan((.pi / 2 - 2 * alpha) / 4) * r

    // Top-right corner in y-down coordinates relative to the square's center, then rotated 90° per corner.
    let h = rect.width / 2
    func pt(_ insetX: CGFloat, _ insetY: CGFloat) -> CGPoint { CGPoint(x: h - insetX, y: -h + insetY) }
    let arcCenter = pt(r, r)
    let arcStart = -.pi / 2 + alpha, arcEnd = -alpha
    func onArc(_ t: CGFloat) -> CGPoint { CGPoint(x: arcCenter.x + r * cos(t), y: arcCenter.y + r * sin(t)) }
    func tangent(_ t: CGFloat) -> CGPoint { CGPoint(x: -sin(t) * k, y: cos(t) * k) }
    let p1 = onArc(arcStart), p2 = onArc(arcEnd)
    let corner: [[CGPoint]] = [
        [pt(p, 0)],
        [pt(p - a, 0), pt(p - a - b, 0), p1],
        [CGPoint(x: p1.x + tangent(arcStart).x, y: p1.y + tangent(arcStart).y),
         CGPoint(x: p2.x - tangent(arcEnd).x, y: p2.y - tangent(arcEnd).y), p2],
        [pt(0, p - a - b), pt(0, p - a), pt(0, p)],
    ]

    let path = CGMutablePath()
    for quarter in 0..<4 {
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: CGFloat(quarter) * .pi / 2)
        let first = corner[0][0].applying(t)
        if quarter == 0 { path.move(to: first) } else { path.addLine(to: first) }
        for curve in corner.dropFirst() {
            path.addCurve(to: curve[2], control1: curve[0], control2: curve[1], transform: t)
        }
    }
    path.closeSubpath()
    return path
}

func powerGlyph(center c: CGPoint, radius g: CGFloat, gapDegrees: CGFloat) -> (arc: CGPath, stem: CGPath) {
    let arc = CGMutablePath()
    let half = gapDegrees / 2 * .pi / 180
    arc.addArc(center: c, radius: g, startAngle: -.pi / 2 + half, endAngle: 3 * .pi / 2 - half, clockwise: false)
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: c.x, y: c.y - g * 1.14))
    stem.addLine(to: CGPoint(x: c.x, y: c.y - g * 0.14))
    return (arc, stem)
}

struct Style {
    var bodySide: CGFloat
    var shadow: (offset: CGFloat, blur: CGFloat, alpha: CGFloat)?
    var orbRadius: CGFloat
    var glow: CGFloat
    var rings: Bool
    var glyphRadius: CGFloat
    var glyphWidth: CGFloat
    var stemWidth: CGFloat
    var gapDegrees: CGFloat

    /// Apple's grid: an 824px body in a 1024px canvas. At 16/32px the body grows to fill the canvas
    /// like Apple's own small icons, the orb and glyph get bolder, and the glyph is snapped so the
    /// ring's extremes and the stem land on whole pixels.
    init(pixels: Int) {
        let unit = canvas / CGFloat(pixels)
        switch pixels {
        case ...16:
            bodySide = 14 * unit
            shadow = nil
            orbRadius = 5.6 * unit
            glow = 0
            rings = false
            glyphRadius = 3.5 * unit
            glyphWidth = 1.25 * unit
            stemWidth = 2 * unit
            gapDegrees = 90
        case ...32:
            bodySide = 28 * unit
            shadow = (0.5 * unit, 1 * unit, 0.3)
            orbRadius = 10.25 * unit
            glow = 2 * unit
            rings = false
            glyphRadius = 5 * unit
            glyphWidth = 2 * unit
            stemWidth = 2 * unit
            gapDegrees = 80
        default:
            // Whole pixels at every size so the outline stays sharp (824 at 1024).
            bodySide = (824 / unit / 2).rounded() * 2 * unit
            shadow = (12, 28, 0.35)
            orbRadius = 236
            glow = 110
            rings = true
            // 6px at 64px lands the ring on whole pixels; 88 elsewhere.
            glyphRadius = pixels == 64 ? 6 * unit : 88
            glyphWidth = max(20, 2 * unit)
            stemWidth = glyphWidth
            gapDegrees = 62
        }
    }
}

func drawIcon(_ ctx: CGContext, pixels: Int) {
    let style = Style(pixels: pixels)
    let unit = canvas / CGFloat(pixels)
    let toPixels = CGFloat(pixels) / canvas
    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    let side = style.bodySide
    let body = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    let bodyPath = squircle(body, radius: side * 0.225)

    if let shadow = style.shadow {
        ctx.saveGState()
        // Shadow offsets live in device space, which stays y-up under our flipped CTM.
        ctx.setShadow(offset: CGSize(width: 0, height: -shadow.offset * toPixels), blur: shadow.blur * toPixels,
                      color: color(0x000000, shadow.alpha))
        ctx.addPath(bodyPath)
        ctx.setFillColor(color(0x141110))
        ctx.fillPath()
        ctx.restoreGState()
    }

    let r = style.orbRadius
    let orb = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(color(0x2B2421), 0), (color(0x141110), 1)]),
                           start: CGPoint(x: center.x, y: body.minY), end: CGPoint(x: center.x, y: body.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.drawRadialGradient(gradient([(color(0xFFFFFF, 0.05), 0), (color(0xFFFFFF, 0), 1)]),
                           startCenter: CGPoint(x: center.x, y: body.minY), startRadius: 0,
                           endCenter: CGPoint(x: center.x, y: body.minY), endRadius: side * 0.55, options: [])
    // Warm light the orb spills onto the body.
    ctx.drawRadialGradient(gradient([(color(ember, 0.26), 0), (color(ember, 0.09), 0.35), (color(ember, 0.025), 0.7),
                                     (color(ember, 0), 1)]),
                           startCenter: center, startRadius: r * 0.95, endCenter: center, endRadius: r * 2.0,
                           options: [])
    if style.glow > 0 {
        ctx.setShadow(offset: .zero, blur: style.glow * toPixels, color: color(ember, 0.9))
        ctx.setFillColor(color(ember))
        ctx.fillEllipse(in: orb)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }
    // Rim light along the top edge of the body.
    ctx.addPath(bodyPath)
    ctx.setLineWidth(max(4, 1.5 * unit))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(color(0xFFFFFF, 0.16), 0), (color(0xFFFFFF, 0), 0.45)]),
                           start: CGPoint(x: center.x, y: body.minY), end: CGPoint(x: center.x, y: body.maxY), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: orb)
    ctx.clip()
    // Small sizes use a darker orb and no sheen so the white glyph keeps its contrast.
    let orbColors: [(CGColor, CGFloat)] = style.rings ? [(color(emberLight), 0), (color(ember), 1)] : [(color(ember), 0), (color(emberDeep), 1)]
    ctx.drawLinearGradient(gradient(orbColors),
                           start: CGPoint(x: center.x - r * 0.7, y: center.y - r * 0.7),
                           end: CGPoint(x: center.x + r * 0.7, y: center.y + r * 0.7), options: [])
    let shade = CGPoint(x: center.x - r * 0.15, y: center.y - r * 0.2)
    ctx.drawRadialGradient(gradient([(color(emberDeep, 0), 0), (color(emberDeep, 0), 0.55), (color(emberDeep, 0.55), 1)]),
                           startCenter: shade, startRadius: 0, endCenter: shade, endRadius: r * 1.2,
                           options: [.drawsAfterEndLocation])
    if style.rings {
        let sheen = CGPoint(x: center.x - r * 0.28, y: center.y - r * 0.5)
        ctx.drawRadialGradient(gradient([(color(0xFFFFFF, 0.22), 0), (color(0xFFFFFF, 0), 1)]),
                               startCenter: sheen, startRadius: 0, endCenter: sheen, endRadius: r * 0.85, options: [])
    }
    ctx.restoreGState()

    if style.rings {
        let rim = max(3, unit)
        ctx.setLineWidth(rim)
        ctx.setStrokeColor(color(0xFFFFFF, 0.30))
        ctx.strokeEllipse(in: orb.insetBy(dx: rim / 2, dy: rim / 2))
        let inner = max(2.5, unit)
        ctx.setLineWidth(inner)
        ctx.setStrokeColor(color(0xFFFFFF, 0.16))
        ctx.strokeEllipse(in: orb.insetBy(dx: r * 0.22, dy: r * 0.22))
    }

    ctx.saveGState()
    if style.rings {
        ctx.setShadow(offset: CGSize(width: 0, height: -3 * toPixels), blur: 10 * toPixels, color: color(0x6B2A16, 0.45))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let glyph = powerGlyph(center: center, radius: style.glyphRadius, gapDegrees: style.gapDegrees)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF))
    for (path, width) in [(glyph.arc, style.glyphWidth), (glyph.stem, style.stemWidth)] {
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(ctx, pixels: pixels)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL, dpi: Int) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard let outPath = arguments.first, arguments.count <= 2 else {
    FileHandle.standardError.write("usage: xcrun swift scripts/make-icon.swift <outdir> [<source-png>]\n".data(using: .utf8)!)
    exit(64)
}

let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(render(pixels: points * scale), to: outDir.appendingPathComponent(name), dpi: 72 * scale)
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}

if outDir.pathExtension != "iconset" {
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try (json + Data("\n".utf8)).write(to: outDir.appendingPathComponent("Contents.json"))
}

if let sourcePath = arguments.dropFirst().first {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writePNG(render(pixels: 1024), to: sourceURL, dpi: 72)
}

print("Wrote \(images.count) icons to \(outDir.path)")
