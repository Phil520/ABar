import Cocoa

// 菜单栏样式预览图生成器（仅开发用，不打包进 App）
// 用法：swiftc -O -framework Cocoa -o /tmp/preview tools/main.swift src/Quote.swift \
//        src/TradingClock.swift src/MenuBarUI.swift && /tmp/preview output/菜单栏预览.png

func quote(price: Double, pct: Double) -> Quote {
    var q = Quote()
    q.price = price
    q.change = price * pct / 100
    q.changePct = pct
    q.source = "腾讯行情"
    return q
}

let cases: [(String, Double, Double, Bool)] = [
    ("浅色 · 涨", 3812.77, 2.11, false),
    ("浅色 · 跌", 3725.48, -0.26, false),
    ("深色 · 涨", 3812.77, 2.11, true),
    ("深色 · 跌", 3725.48, -0.26, true),
]

let stripW: CGFloat = 300
let stripH: CGFloat = 26
let pad: CGFloat = 14
let gap: CGFloat = 10
let labelH: CGFloat = 16
let totalH = pad + CGFloat(cases.count) * (labelH + stripH + gap) + pad + 26

let size = NSSize(width: stripW + pad * 2, height: totalH)
let image = NSImage(size: size)
image.lockFocus()

// 画布底色
NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

var y = totalH - pad

// 标题
let titleAttr = NSAttributedString(string: "指数条 · 菜单栏样式", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.15, green: 0.16, blue: 0.2, alpha: 1),
])
titleAttr.draw(at: NSPoint(x: pad, y: y - 16))
y -= 26

for (label, price, pct, dark) in cases {
    NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)!

    // 小标签
    let labAttr = NSAttributedString(string: label, attributes: [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor(srgbRed: 0.45, green: 0.46, blue: 0.5, alpha: 1),
    ])
    labAttr.draw(at: NSPoint(x: pad, y: y - labelH + 3))
    y -= labelH

    // 菜单栏条
    let barRect = NSRect(x: pad, y: y - stripH, width: stripW, height: stripH)
    if dark {
        NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill()
    } else {
        NSColor(srgbRed: 0.88, green: 0.92, blue: 0.97, alpha: 1).setFill()
    }
    let bar = NSBezierPath(roundedRect: barRect, xRadius: 6, yRadius: 6)
    bar.fill()

    // 右侧放两个“系统图标”示意，说明图标区在右、读数在左
    NSColor(srgbRed: 0.55, green: 0.56, blue: 0.6, alpha: 0.55).setFill()
    for i in 0..<3 {
        let r = NSRect(x: barRect.maxX - 20 - CGFloat(i) * 18, y: barRect.midY - 4, width: 8, height: 8)
        NSBezierPath(ovalIn: r).fill()
    }

    let attr = MenuBarUI.attributedTitle(for: quote(price: price, pct: pct), stale: false)
    let ts = attr.size()
    attr.draw(at: NSPoint(x: barRect.minX + 12, y: barRect.midY - ts.height / 2))

    // 宽度参考线：说明数字宽度稳定
    NSColor(srgbRed: 0.9, green: 0.3, blue: 0.3, alpha: 0.35).setStroke()
    let wLine = NSBezierPath()
    wLine.move(to: NSPoint(x: barRect.minX + 12, y: barRect.minY + 4))
    wLine.line(to: NSPoint(x: barRect.minX + 12 + ts.width, y: barRect.minY + 4))
    wLine.lineWidth = 1
    wLine.stroke()

    y -= stripH + gap
}

NSAppearance.current = NSAppearance(named: .aqua)!

let noteAttr = NSAttributedString(string: "点位整数 + 涨跌幅两位小数 · 无逗号 / 百分号 / 正负号 · 涨红跌绿", attributes: [
    .font: NSFont.systemFont(ofSize: 9),
    .foregroundColor: NSColor(srgbRed: 0.45, green: 0.46, blue: 0.5, alpha: 1),
])
noteAttr.draw(at: NSPoint(x: pad, y: 10))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "菜单栏预览.png"
do {
    try png.write(to: URL(fileURLWithPath: out))
    print("已生成 \(out)")
} catch {
    FileHandle.standardError.write("写入失败：\(error)\n".data(using: .utf8)!)
    exit(1)
}
