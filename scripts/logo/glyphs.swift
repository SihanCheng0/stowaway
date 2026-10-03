// Usage: xcrun swift glyphs.swift <fontfile> <text> [wght]
// Emits JSON with per-glyph outlines in font units (y-up, baseline at 0).
import Foundation
import CoreText
import CoreGraphics

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]) as CFURL
let text = args[2]
let wght: Double? = args.count > 3 ? Double(args[3]) : nil

guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor], let d0 = descs.first else {
    fatalError("cannot load font")
}
var desc = d0
let probe = CTFontCreateWithFontDescriptor(d0, 100, nil)
let upm = Double(CTFontGetUnitsPerEm(probe))
if let w = wght {
    // 'wght' tag = 0x77676874
    let vari: [NSNumber: NSNumber] = [NSNumber(value: 0x77676874): NSNumber(value: w)]
    desc = CTFontDescriptorCreateCopyWithAttributes(d0, [kCTFontVariationAttribute: vari] as CFDictionary)
}
let font = CTFontCreateWithFontDescriptor(desc, CGFloat(upm), nil)

func r(_ v: CGFloat) -> String {
    let x = (Double(v) * 100).rounded() / 100
    if x == x.rounded() { return String(Int(x)) }
    return String(format: "%.2f", x).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
}

func svgPath(_ p: CGPath) -> String {
    var s = ""
    p.applyWithBlock { ep in
        let e = ep.pointee
        let pts = e.points
        switch e.type {
        case .moveToPoint: s += "M\(r(pts[0].x)) \(r(pts[0].y))"
        case .addLineToPoint: s += "L\(r(pts[0].x)) \(r(pts[0].y))"
        case .addQuadCurveToPoint: s += "Q\(r(pts[0].x)) \(r(pts[0].y)) \(r(pts[1].x)) \(r(pts[1].y))"
        case .addCurveToPoint: s += "C\(r(pts[0].x)) \(r(pts[0].y)) \(r(pts[1].x)) \(r(pts[1].y)) \(r(pts[2].x)) \(r(pts[2].y))"
        case .closeSubpath: s += "Z"
        @unknown default: break
        }
    }
    return s
}

var chars = Array(text.utf16)
var glyphs = [CGGlyph](repeating: 0, count: chars.count)
CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)

var out: [[String: Any]] = []
for (i, g) in glyphs.enumerated() {
    let p = CTFontCreatePathForGlyph(font, g, nil)
    let bb = p?.boundingBoxOfPath ?? .zero
    out.append([
        "char": String(utf16CodeUnits: [chars[i]], count: 1),
        "advance": Double(advances[i].width),
        "d": p.map(svgPath) ?? "",
        "bbox": [Double(bb.minX), Double(bb.minY), Double(bb.maxX), Double(bb.maxY)],
    ])
}
let result: [String: Any] = [
    "upm": upm,
    "xHeight": Double(CTFontGetXHeight(font)),
    "capHeight": Double(CTFontGetCapHeight(font)),
    "ascent": Double(CTFontGetAscent(font)),
    "descent": Double(CTFontGetDescent(font)),
    "name": CTFontCopyPostScriptName(font) as String,
    "glyphs": out,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
