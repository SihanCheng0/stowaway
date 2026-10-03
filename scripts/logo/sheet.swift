// Verification contact sheets.
//   sheet marks <outdir> <out.png>    16/32/64/128 px marks, nearest-neighbour x16/x8/x4/x2, plus 1x
//   sheet logos <outdir> <work> <out.png>   lockups on #FFFFFF and #0D1117 (1280 px PNGs and README size)
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let mode = CommandLine.arguments[1]
let dir = CommandLine.arguments[2]

func load(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // top-left origin
    return ctx
}
let fontURL = URL(fileURLWithPath: NSString(string: "~/Library/Fonts/GeistMono-Regular.otf").expandingTildeInPath) as CFURL
let fdesc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL) as! [CTFontDescriptor])[0]
let font = CTFontCreateWithFontDescriptor(fdesc, 15, nil)

func label(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, color: CGColor) {
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
func drawImage(_ ctx: CGContext, _ img: CGImage, in r: CGRect, nearest: Bool) {
    ctx.saveGState()
    ctx.interpolationQuality = nearest ? .none : .high
    ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    ctx.restoreGState()
}
func save(_ ctx: CGContext, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
let rows: [(UInt32, UInt32, String)] = [(0xFFFFFF, 0x6E6560, "on #FFFFFF"), (0x0D1117, 0x8B949E, "on #0D1117")]

if mode == "marks" {
    let sizes = [16, 32, 64, 128]
    let cell = 256, pad = 48, labelH = 40
    let actualW = 128 + 24
    let rowH = pad + cell + labelH
    let W = pad + sizes.count * (cell + pad) + actualW + pad
    let H = rowH * 2 + pad
    let ctx = makeContext(W, H)
    for (ri, row) in rows.enumerated() {
        let y0 = CGFloat(ri * rowH)
        ctx.setFillColor(rgb(row.0))
        ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(W), height: CGFloat(rowH + (ri == 1 ? pad : 0))))
        for (i, s) in sizes.enumerated() {
            let img = load("\(dir)/mark-\(s).png")
            let x = CGFloat(pad + i * (cell + pad))
            drawImage(ctx, img, in: CGRect(x: x, y: y0 + CGFloat(pad), width: CGFloat(cell), height: CGFloat(cell)), nearest: true)
            let tag = s <= 32 ? "  hinted" : ""
            label(ctx, "\(s) px  (x\(cell / s))\(tag)", x: x, y: y0 + CGFloat(pad + cell + 28), color: rgb(row.1))
        }
        let ax = CGFloat(pad + sizes.count * (cell + pad))
        drawImage(ctx, load("\(dir)/mark-128.png"), in: CGRect(x: ax, y: y0 + CGFloat(pad), width: 128, height: 128), nearest: true)
        var bx = ax
        let base = y0 + CGFloat(pad + 128 + 16 + 64)
        for s in [64, 32, 16] {
            drawImage(ctx, load("\(dir)/mark-\(s).png"), in: CGRect(x: bx, y: base - CGFloat(s), width: CGFloat(s), height: CGFloat(s)), nearest: true)
            bx += CGFloat(s) + 12
        }
        label(ctx, "1x  " + row.2, x: ax, y: y0 + CGFloat(pad + cell + 28), color: rgb(row.1))
    }
    save(ctx, CommandLine.arguments[3])
} else if mode == "logos" {
    // 1280 px lockups shown at 1x (640 px wide crops are too small to judge), then README size (420 px)
    let work = CommandLine.arguments[3]
    let pad = 40
    let big = 1280, bigH = 320, small = 420, smallH = 105
    let W = pad + big + pad
    let rowH = pad + bigH + 12 + smallH + 40
    let H = rowH * 2 + pad
    let ctx = makeContext(W, H)
    for (ri, (row, name)) in zip(rows, ["logo-light", "logo-dark"]).enumerated() {
        let y0 = CGFloat(ri * rowH)
        ctx.setFillColor(rgb(row.0))
        ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(W), height: CGFloat(rowH + (ri == 1 ? pad : 0))))
        drawImage(ctx, load("\(dir)/\(name).png"), in: CGRect(x: CGFloat(pad), y: y0 + CGFloat(pad), width: CGFloat(big), height: CGFloat(bigH)), nearest: false)
        drawImage(ctx, load("\(work)/\(name)-420.png"), in: CGRect(x: CGFloat(pad), y: y0 + CGFloat(pad + bigH + 12), width: CGFloat(small), height: CGFloat(smallH)), nearest: true)
        label(ctx, "\(name).png 1280 px (top) and \(name).svg at README width 420 px (left), " + row.2,
              x: CGFloat(pad + small + 24), y: y0 + CGFloat(pad + bigH + 12 + smallH / 2), color: rgb(row.1))
    }
    save(ctx, CommandLine.arguments[4])
}
