// Малює іконку Parallel (1024×1024 PNG). Використання: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Сітка іконок macOS: плитка 824×824 з полем 100 px.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Тінь під плиткою.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0, 0, 0, 0.32))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(40, 30, 120))
ctx.fillPath()
ctx.restoreGState()

// Фон: діагональний градієнт індиго → фіолетовий.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(76, 110, 255), rgb(120, 70, 240), rgb(170, 60, 220)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

// М'який відблиск зверху.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 860), startRadius: 0,
                       endCenter: CGPoint(x: 360, y: 860), endRadius: 620, options: [])

// Три «вікна» каскадом: екземпляри одного застосунку.
let card = CGSize(width: 470, height: 360)
let step = CGPoint(x: 92, y: -82)
let origin = CGPoint(x: 512 - card.width / 2 - step.x, y: 512 - card.height / 2 - step.y)
let alphas: [CGFloat] = [0.30, 0.55, 1.0]

for i in 0..<3 {
    let rect = CGRect(x: origin.x + step.x * CGFloat(i), y: origin.y + step.y * CGFloat(i),
                      width: card.width, height: card.height)
    let path = CGPath(roundedRect: rect, cornerWidth: 48, cornerHeight: 48, transform: nil)
    let front = i == 2

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: front ? 34 : 22, color: rgb(30, 10, 90, front ? 0.45 : 0.25))
    ctx.addPath(path)
    ctx.setFillColor(rgb(255, 255, 255, alphas[i]))
    ctx.fillPath()
    ctx.restoreGState()

    // Смужка заголовка з «світлофором».
    let barH: CGFloat = 70
    let dotY = rect.maxY - barH / 2
    let dots = front ? [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)]
                     : Array(repeating: rgb(255, 255, 255, 0.75), count: 3)
    for (k, c) in dots.enumerated() {
        let d: CGFloat = 26
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: rect.minX + 38 + CGFloat(k) * 40, y: dotY - d / 2, width: d, height: d))
    }

    if front {
        // Розділювач під заголовком.
        ctx.setFillColor(rgb(120, 90, 230, 0.15))
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: 3))

        // Символ запуску: трикутник «play» з градієнтом фону.
        let cx = rect.midX, cy = rect.minY + (rect.height - barH) / 2
        let r: CGFloat = 92
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: cx - r * 0.55, y: cy + r))
        tri.addLine(to: CGPoint(x: cx + r * 1.0, y: cy))
        tri.addLine(to: CGPoint(x: cx - r * 0.55, y: cy - r))
        tri.closeSubpath()
        let rounded = tri.copy(strokingWithWidth: 34, lineCap: .round, lineJoin: .round, miterLimit: 10)
        ctx.saveGState()
        ctx.addPath(tri)
        ctx.addPath(rounded)
        ctx.clip()
        ctx.drawLinearGradient(bg, start: CGPoint(x: cx - r, y: cy + r), end: CGPoint(x: cx + r, y: cy - r), options: [])
        ctx.restoreGState()
    }
}
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Збережено \(out)")
