import Foundation

/// 一次行情快照。字段以「能显示出来」为准，涨跌幅缺失时用价格反算兜底。
struct Quote {
    var price: Double = 0          // 当前点位
    var change: Double = 0         // 涨跌点数
    var changePct: Double = 0      // 涨跌幅 %
    var open: Double = 0
    var prevClose: Double = 0
    var high: Double = 0
    var low: Double = 0
    var volumeHand: Double = 0     // 成交量（手）
    var amountWan: Double = 0      // 成交额（万元）
    var amplitudePct: Double = 0   // 振幅 %
    var quoteTime: Date?           // 行情时间（交易所口径）
    var source: String = ""
    var fetchedAt: Date = Date()

    var direction: Direction {
        if change > 0 { return .up }
        if change < 0 { return .down }
        return .flat
    }

    enum Direction { case up, down, flat }

    var amountYi: Double { amountWan / 10_000.0 }
    var volumeYiShou: Double { volumeHand / 100_000_000.0 }

    /// 补齐服务端没给全的派生字段
    mutating func fillDerived() {
        if prevClose > 0 {
            if change == 0, price > 0 { change = price - prevClose }
            if changePct == 0, price > 0 { changePct = (price - prevClose) / prevClose * 100 }
            if amplitudePct == 0, high > 0, low > 0 {
                amplitudePct = (high - low) / prevClose * 100
            }
        }
    }
}

// MARK: - 解析

enum QuoteParser {

    /// 腾讯行情（全量字段）
    /// v_sh000001="1~上证指数~000001~3734.02~3735.37~3740.57~...~20261021101745~-1.35~-0.04~3743.08~3729.12~..."
    /// 索引：3 现价 / 4 昨收 / 5 今开 / 6 成交量(手) / 30 时间 / 31 涨跌 / 32 涨跌幅
    ///      33 最高 / 34 最低 / 37 成交额(万) / 43 振幅
    static func parseTencent(_ raw: String) -> Quote? {
        guard let first = raw.firstIndex(of: "\""),
              let last = raw.lastIndex(of: "\""),
              first < last else { return nil }
        let body = String(raw[raw.index(after: first)..<last])
        let f = body.components(separatedBy: "~")
        guard f.count > 5 else { return nil }

        func str(_ i: Int) -> String { i >= 0 && i < f.count ? f[i] : "" }
        func num(_ i: Int) -> Double { Double(str(i)) ?? 0 }

        guard let price = Double(str(3)), price > 0 else { return nil }

        var q = Quote()
        q.price = price
        q.prevClose = num(4)
        q.open = num(5)
        q.volumeHand = num(6)
        q.change = num(31)
        q.changePct = num(32)
        q.high = num(33)
        q.low = num(34)
        q.amountWan = num(37)
        q.amplitudePct = num(43)
        q.quoteTime = parseTencentTime(str(30))
        q.source = "腾讯行情"
        q.fetchedAt = Date()
        q.fillDerived()
        return q
    }

    /// 新浪行情（精简字段，作为腾讯不通时的备份）
    /// var hq_str_s_sh000001="上证指数,3732.8523,-2.5181,-0.07,1627886,28682272";
    /// 成交量口径与腾讯不同，故只取价格 / 涨跌 / 涨跌幅 / 成交额。
    static func parseSina(_ raw: String) -> Quote? {
        guard let first = raw.firstIndex(of: "\""),
              let last = raw.lastIndex(of: "\""),
              first < last else { return nil }
        let body = String(raw[raw.index(after: first)..<last])
        let f = body.components(separatedBy: ",")
        guard f.count >= 4, let price = Double(f[1]), price > 0 else { return nil }

        var q = Quote()
        q.price = price
        q.change = Double(f[2]) ?? 0
        q.changePct = Double(f[3]) ?? 0
        if f.count >= 6 { q.amountWan = Double(f[5]) ?? 0 }
        q.source = "新浪行情"
        q.fetchedAt = Date()
        q.quoteTime = Date()
        q.fillDerived()
        return q
    }

    private static let tencentTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        df.timeZone = TradingClock.beijing
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    static func parseTencentTime(_ s: String) -> Date? {
        guard s.count >= 14 else { return nil }
        return tencentTimeFormatter.date(from: String(s.prefix(14)))
    }
}

// MARK: - 数字格式化

enum Fmt {
    private static let grouped2: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.groupingSeparator = ","
        nf.usesGroupingSeparator = true
        nf.locale = Locale(identifier: "en_US_POSIX")   // 别让系统区域设置改掉千分位
        return nf
    }()

    static func price(_ v: Double) -> String {
        v > 0 ? (grouped2.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) : "—"
    }

    /// 带符号涨跌幅：+0.35% / -0.02% / 0.00%
    static func pct(_ v: Double) -> String {
        if abs(v) < 0.0001 { return "0.00%" }
        return String(format: "%+.2f%%", v)
    }

    /// 带符号涨跌点数
    static func signed(_ v: Double) -> String {
        if abs(v) < 0.0001 { return "0.00" }
        return String(format: "%+.2f", v)
    }

    /// 成交额（亿）
    static func amount(_ wan: Double) -> String {
        guard wan > 0 else { return "—" }
        let yi = wan / 10_000.0
        if yi >= 10_000 { return String(format: "%.2f 万亿", yi / 10_000.0) }
        return String(format: "%.0f 亿", yi)
    }

    static func plainPct(_ v: Double) -> String {
        v > 0 ? String(format: "%.2f%%", v) : "—"
    }
}
