// Draws the PopNote app icon ("Sticky": a tilted yellow note on a dark tile) and writes
// icon/AppIcon.icns plus docs/icon.png. Run from the repo root:
//   swift icon/make-icon.swift && iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns
import AppKit

/// The design lives in a 100×100 box (the tile spans 4…96); this maps it onto the macOS
/// icon grid, where the tile is 824 px inside a 1024 px canvas.
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    let k = CGFloat(px) / 1024
    let s = 824.0 / 92.0 * k
    // Flip to SVG-style coordinates (origin top-left) in design units.
    cg.translateBy(x: 0, y: CGFloat(px))
    cg.scaleBy(x: 1, y: -1)
    cg.translateBy(x: 100 * k - 4 * s, y: 100 * k - 4 * s)
    cg.scaleBy(x: s, y: s)

    func hex(_ v: UInt32) -> CGColor {
        CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    func fill(_ path: CGPath, _ color: UInt32) { cg.addPath(path); cg.setFillColor(hex(color)); cg.fillPath() }
    func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath(); p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath(); return p
    }

    // Shadow offsets ignore the transform, so they are given in pixels (downward = negative).
    // Tile, with a soft shadow under it like other macOS icons.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -1.2 * s), blur: 2.4 * s, color: CGColor(gray: 0, alpha: 0.3))
    fill(CGPath(roundedRect: CGRect(x: 4, y: 4, width: 92, height: 92), cornerWidth: 20.5, cornerHeight: 20.5, transform: nil), 0x2C2C2A)
    cg.restoreGState()

    // Note, rotated -6° around (50, 52).
    cg.translateBy(x: 50, y: 52)
    cg.rotate(by: -6 * .pi / 180)
    cg.translateBy(x: -50, y: -52)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -1.5 * s), blur: 3 * s, color: CGColor(gray: 0, alpha: 0.35))
    fill(poly([(24, 24), (76, 24), (76, 62), (62, 76), (24, 76)]), 0xFAC775)
    cg.restoreGState()
    fill(poly([(76, 62), (62, 62), (62, 76)]), 0xEF9F27)
    for (y, w) in [(36.0, 34.0), (46.0, 28.0), (56.0, 20.0)] {
        fill(CGPath(roundedRect: CGRect(x: 32, y: y, width: w, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil), 0x854F0B)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: "icon/AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(256).write(to: URL(fileURLWithPath: "docs/icon.png"))
print("Wrote icon/AppIcon.iconset and docs/icon.png")
