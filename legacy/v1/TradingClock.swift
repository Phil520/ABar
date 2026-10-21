import Foundation

/// 交易时段判断。一律按北京时间算，不跟随系统时区——
/// 用户出差把电脑时区改到别处时，刷新节奏不该跟着乱。
enum TradingClock {

    static let beijing: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = beijing
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private static func minutesOfDay(_ now: Date) -> Int? {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute else { return nil }
        return h * 60 + m
    }

    private static func isWeekend(_ now: Date) -> Bool {
        let wd = calendar.component(.weekday, from: now)
        return wd == 1 || wd == 7
    }

    /// 连续竞价：9:30–11:30、13:00–15:00（工作日）
    static func isTrading(now: Date = Date()) -> Bool {
        if isWeekend(now) { return false }
        guard let t = minutesOfDay(now) else { return false }
        return (t >= 9 * 60 + 30 && t <= 11 * 60 + 30) || (t >= 13 * 60 && t <= 15 * 60)
    }

    /// 交易时段 10 秒，其余 60 秒
    static func refreshInterval(now: Date = Date()) -> TimeInterval {
        isTrading(now: now) ? 10 : 60
    }

    /// 面板里那行状态说明
    static func statusText(for quote: Quote?, now: Date = Date()) -> String {
        guard let q = quote, let t = q.quoteTime else { return "等待数据" }
        if !calendar.isDate(t, inSameDayAs: now) { return "非交易日 · 最近收盘" }
        if isTrading(now: now) { return "交易中" }
        guard let m = minutesOfDay(now) else { return "" }
        if m < 9 * 60 + 30 { return "未开盘" }
        if m > 15 * 60 { return "已收盘" }
        return "午间休市"
    }

    static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        df.timeZone = beijing
        return df
    }()
}
