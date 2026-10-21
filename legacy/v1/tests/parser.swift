import Foundation

// 回归测试：解析 / 格式化 / 交易时段。真实响应样本直接抄下来当夹具，
// 免得接口改字段时测试还「绿着」。

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { failures += 1; print("  FAIL \(msg)") }
}

func bjDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    c.timeZone = TradingClock.beijing
    return TradingClock.calendar.date(from: c)!
}

// 1. 腾讯全量字段
let tencent = #"v_sh000001="1~上证指数~000001~3734.02~3735.37~3740.57~161421522~0~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~0.00~0~~20261021101745~-1.35~-0.04~3743.08~3729.12~3734.02/161421522/284350252920~161421522~28435025~0.33~16.17~~3743.08~3729.12~0.37~584841.40~652385.26~0.00~-1~-1~1.79~0~3734.79";"#
if let q = QuoteParser.parseTencent(tencent) {
    check(abs(q.price - 3734.02) < 0.001, "price")
    check(abs(q.prevClose - 3735.37) < 0.001, "prevClose")
    check(abs(q.open - 3740.57) < 0.001, "open")
    check(abs(q.high - 3743.08) < 0.001, "high")
    check(abs(q.low - 3729.12) < 0.001, "low")
    check(abs(q.change - (-1.35)) < 0.001, "change")
    check(abs(q.changePct - (-0.04)) < 0.001, "changePct")
    check(abs(q.amountWan - 28435025) < 0.5, "amount")
    check(abs(q.amplitudePct - 0.37) < 0.001, "amplitude")
    check(q.direction == .down, "direction down")
    check(q.source == "腾讯行情", "source")
    check(q.quoteTime != nil, "quoteTime")
} else {
    check(false, "腾讯样本解析失败")
}

// 2. 新浪精简字段（价格/涨跌/成交额在，开高低没有）
let sina = #"var hq_str_s_sh000001="上证指数,3732.8523,-2.5181,-0.07,1627886,28682272";"#
if let q = QuoteParser.parseSina(sina) {
    check(abs(q.price - 3732.8523) < 0.0001, "sina price")
    check(abs(q.change - (-2.5181)) < 0.001, "sina change")
    check(abs(q.changePct - (-0.07)) < 0.001, "sina pct")
    check(q.open == 0 && q.high == 0, "sina 无开高低")
    check(q.direction == .down, "sina direction")
} else {
    check(false, "新浪样本解析失败")
}

// 3. 格式化
check(Fmt.price(3734.021) == "3,734.02", "price 千分位: \(Fmt.price(3734.021))")
check(Fmt.pct(0.351) == "+0.35%", "pct 正号: \(Fmt.pct(0.351))")
check(Fmt.pct(-0.02) == "-0.02%", "pct 负号: \(Fmt.pct(-0.02))")
check(Fmt.pct(0) == "0.00%", "pct 零: \(Fmt.pct(0))")
check(Fmt.signed(-1.35) == "-1.35", "signed: \(Fmt.signed(-1.35))")
check(Fmt.amount(28435025).contains("亿"), "成交额单位: \(Fmt.amount(28435025))")

// 4. 菜单栏文字：点位整数 + 涨跌幅两位小数，直接相连；
//    不带「上证指数」、不带逗号、不带百分号、不带正负号
if let q = QuoteParser.parseTencent(tencent) {
    let title = MenuBarUI.title(for: q)
    check(title == "37340.04", "菜单栏文案: \(title)")
    check(!title.contains("上证"), "菜单栏不该出现指数名")
    check(!title.contains(","), "菜单栏不该有千分位逗号")
    check(!title.contains("%"), "菜单栏不该有百分号")
    check(!title.contains("-"), "菜单栏不该有负号")
    // 涨的时候也不能出现 +，方向只靠颜色
    var up = q
    up.price = 3812.77
    up.change = 78.75
    up.changePct = 2.11
    check(MenuBarUI.title(for: up) == "38122.11", "涨时文案: \(MenuBarUI.title(for: up))")
    check(MenuBarUI.color(for: .up) != MenuBarUI.color(for: .down), "涨跌颜色必须不同")
}

// 5. 交易时段（北京时间，硬编码具体时刻，不受跑测试的当天影响）
check(TradingClock.isTrading(now: bjDate(2026, 10, 21, 10, 0)) == true, "上午盘中")
check(TradingClock.isTrading(now: bjDate(2026, 10, 21, 14, 30)) == true, "下午盘中")
check(TradingClock.isTrading(now: bjDate(2026, 10, 21, 12, 0)) == false, "午休")
check(TradingClock.isTrading(now: bjDate(2026, 10, 21, 15, 30)) == false, "收盘后")
check(TradingClock.isTrading(now: bjDate(2026, 10, 21, 9, 0)) == false, "开盘前")
check(TradingClock.isTrading(now: bjDate(2026, 10, 24, 10, 0)) == false, "周六")
check(TradingClock.refreshInterval(now: bjDate(2026, 10, 21, 10, 0)) == 10, "盘中 10 秒")
check(TradingClock.refreshInterval(now: bjDate(2026, 10, 21, 20, 0)) == 60, "盘后 60 秒")

if failures == 0 {
    print("all checks passed")
    exit(0)
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
