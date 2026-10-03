// GitHub social preview, 1280 x 640: the dark lockup centred on #141110, the tagline in SF Pro
// (AppKit's system font) and the repo URL in Geist Mono.
// Usage: social <logo-dark rendered PNG> <out.png> [url colour hex]
import AppKit

let args = CommandLine.arguments
let W = 1280, H = 640
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}
func load(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

/// Bounding box of pixels with any alpha, in top-left image coordinates.
func inkBox(_ img: CGImage) -> CGRect {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where buf[(y * w + x) * 4 + 3] > 0 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)   // buffer rows are top-down
}

let lockup = load(args[1])
let ink = inkBox(lockup)
let urlHex = args.count > 3 ? UInt32(args[3], radix: 16)! : 0xF0A07E

let tagFont = NSFont.systemFont(ofSize: 40, weight: .medium)
let monoURL = URL(fileURLWithPath: NSString(string: "~/Library/Fonts/GeistMono-Regular.otf").expandingTildeInPath) as CFURL
let monoDesc = (CTFontManagerCreateFontDescriptorsFromURL(monoURL) as! [CTFontDescriptor])[0]
let urlFont = CTFontCreateWithFontDescriptor(monoDesc, 22, nil)

func line(_ s: String, _ font: CTFont, _ color: CGColor, kern: CGFloat = 0) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color, .kern: kern]))
}
let tag = line("Keeps working in your bag.", tagFont as CTFont, rgb(0xE6DCD5))
let url = line("github.com/SihanCheng0/stowaway", urlFont, rgb(urlHex))
let tagW = CTLineGetTypographicBounds(tag, nil, nil, nil)
let urlW = CTLineGetTypographicBounds(url, nil, nil, nil)
let tagCap = CTFontGetCapHeight(tagFont as CTFont)
let urlCap = CTFontGetCapHeight(urlFont)

// Vertical stack, measured on ink: lockup | 54 | tagline caps | 34 | URL caps
let gapA: CGFloat = 54, gapB: CGFloat = 34
let stackH = ink.height + gapA + tagCap + gapB + urlCap
let top = ((CGFloat(H) - stackH) / 2 - 6).rounded()          // a touch above centre, optically
let lockX = ((CGFloat(W) - ink.width) / 2 - ink.minX).rounded()
let lockY = top - ink.minY
let tagBase = top + ink.height + gapA + tagCap
let urlBase = tagBase + gapB + urlCap

// Opaque output (no alpha channel): some link unfurlers mishandle transparent previews.
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(rgb(0x141110))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
// CoreGraphics is y-up; convert top-left layout coordinates when drawing.
ctx.interpolationQuality = .none
ctx.draw(lockup, in: CGRect(x: lockX, y: CGFloat(H) - lockY - CGFloat(lockup.height),
                            width: CGFloat(lockup.width), height: CGFloat(lockup.height)))
ctx.setShouldSmoothFonts(false)
ctx.setAllowsFontSubpixelPositioning(true)
ctx.setShouldSubpixelPositionFonts(true)
for (l, w, base) in [(tag, tagW, tagBase), (url, urlW, urlBase)] {
    ctx.textPosition = CGPoint(x: ((CGFloat(W) - CGFloat(w)) / 2).rounded(), y: CGFloat(H) - base)
    CTLineDraw(l, ctx)
}
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("""
{"tagline_font": "\(CTFontCopyPostScriptName(tagFont as CTFont) as String)", "url_font": "\(CTFontCopyPostScriptName(urlFont) as String)", \
"lockup_ink": [\(Int(lockX + ink.minX)), \(Int(top)), \(Int(ink.width)), \(Int(ink.height))], \
"tagline_baseline": \(tagBase), "url_baseline": \(urlBase), "tagline_width": \(Int(tagW)), "url_width": \(Int(urlW))}
""")
