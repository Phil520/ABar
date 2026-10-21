import Cocoa

/// 菜单栏文字的生成规则。
/// 只放两样东西：点位整数 + 涨跌幅两位小数，直接连成一串。
/// 不写「上证指数」，不带千分位逗号、不带百分号、不带正负号——方向只靠颜色。
enum MenuBarUI {

    /// 涨红跌绿（A 股口径）。不用裸的 systemRed/systemGreen：
    /// systemGreen 在浅色菜单栏上偏淡，深色一字更压得住底色。
    ///
    /// 这里必须是**普通静态色**，不能用 NSColor(name:dynamicProvider:) 那种带闭包的动态色。
    /// 菜单栏状态项在 macOS 26 上要跨进程交给控制中心去画，带闭包的动态色无法序列化，
    /// 会导致整个 scene 提交失败——表现就是「进程在跑、标题也有、菜单栏上看不见」。
    /// 深浅色适配改由渲染时按按钮当前的 effectiveAppearance 现算，见 color(for:appearance:)。
    static func color(for direction: Quote.Direction, appearance: NSAppearance? = nil) -> NSColor {
        let dark = appearance.map { isDark($0) } ?? false
        switch direction {
        case .up:
            return dark
                ? NSColor(srgbRed: 1.00, green: 0.36, blue: 0.34, alpha: 1)
                : NSColor(srgbRed: 0.84, green: 0.09, blue: 0.11, alpha: 1)
        case .down:
            return dark
                ? NSColor(srgbRed: 0.20, green: 0.82, blue: 0.42, alpha: 1)
                : NSColor(srgbRed: 0.00, green: 0.47, blue: 0.24, alpha: 1)
        case .flat:
            return .labelColor
        }
    }

    /// NSAppearance 没有 isDark，要自己判——别用 bestMatch 之外的猜想
    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func font() -> NSFont {
        // 等宽数字：数字跳动时整块宽度不抖
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    /// 正常态：37340.04（点位取整数部分 + 涨跌幅绝对值两位小数）
    static func title(for quote: Quote?) -> String {
        guard let q = quote, q.price > 0 else { return "—" }
        let point = String(Int(q.price))            // 3734.02 → 3734
        let pct = String(format: "%.2f", abs(q.changePct))   // -0.04 → 0.04
        return point + pct
    }

    /// placeholder 用于首次上屏：给一个和真实读数等宽的占位串，
    /// 免得系统先按窄字定好槽位、之后读数变宽却不让位（右边会被切出屏幕）。
    static func attributedTitle(for quote: Quote?, stale: Bool,
                               placeholder: String? = nil,
                               appearance: NSAppearance? = nil) -> NSAttributedString {
        let text = placeholder ?? title(for: quote)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(),
            .foregroundColor: stale ? NSColor.secondaryLabelColor : color(for: quote?.direction ?? .flat, appearance: appearance),
        ]
        if stale {
            // 断线时仍然显示最后已知值，只是变灰，避免误以为是实时数
            attrs[.baselineOffset] = 0
        }
        return NSAttributedString(string: text, attributes: attrs)
    }
}
