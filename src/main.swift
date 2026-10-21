import Cocoa

// 指数条 · 第 2 版骨架
// 起点是「已经验证能在本机菜单栏上屏」的最小写法：
//   应用起来 → 建一个状态项 → 设文字 → 开一个定时器取数。
// 每加一块功能都要单独验一次上屏，避免再出现「进程在跑但菜单栏看不见」。

// MARK: - 行情

struct Quote {
    var price: Double = 0
    var changePct: Double = 0
    var open: Double = 0
    var prevClose: Double = 0
    var high: Double = 0
    var low: Double = 0
    var amountWan: Double = 0
    var amplitudePct: Double = 0
    var quoteTime: String = ""

    var direction: Int {          // 1 涨 / -1 跌 / 0 平
        if changePct > 0.0001 { return 1 }
        if changePct < -0.0001 { return -1 }
        return 0
    }
}

enum Fmt {
    static func price(_ v: Double) -> String { String(format: "%.2f", v) }
    static func pct(_ v: Double) -> String { String(format: "%.2f%%", v) }
    static func amount(_ wan: Double) -> String {
        if wan >= 10000 { return String(format: "%.2f 亿", wan / 10000) }
        return String(format: "%.0f 万", wan)
    }
}

// MARK: - 取数

enum Source {
    static let gbk = CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))

    static func fetch(_ done: @escaping (Quote?) -> Void) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)

        func hitTencent(_ fallback: @escaping () -> Void) {
            let url = URL(string: "https://qt.gtimg.cn/q=sh000001")!
            var req = URLRequest(url: url)
            req.setValue("https://finance.qq.com", forHTTPHeaderField: "Referer")
            session.dataTask(with: req) { data, _, _ in
                if let data = data, let text = String(data: data, encoding: String.Encoding(rawValue: gbk)),
                   let q = parseTencent(text) {
                    done(q); return
                }
                fallback()
            }.resume()
        }

        hitTencent {
            let url = URL(string: "https://hq.sinajs.cn/list=s_sh000001")!
            var req = URLRequest(url: url)
            req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
            session.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let text = String(data: data, encoding: String.Encoding(rawValue: gbk)),
                      let q = parseSina(text) else { done(nil); return }
                done(q)
            }.resume()
        }
    }

    /// 腾讯：~ 分隔。3 现价 / 4 昨收 / 5 今开 / 30 时间 / 31 涨跌 / 32 涨跌幅 / 33 最高 / 34 最低 / 37 成交额万 / 43 振幅
    static func parseTencent(_ raw: String) -> Quote? {
        guard let body = raw.split(separator: "\"").dropFirst().first else { return nil }
        let f = body.components(separatedBy: "~")
        guard f.count > 34 else { return nil }
        var q = Quote()
        q.price = Double(f[3]) ?? 0
        q.prevClose = Double(f[4]) ?? 0
        q.open = Double(f[5]) ?? 0
        q.changePct = Double(f[32]) ?? 0
        q.high = Double(f[33]) ?? 0
        q.low = Double(f[34]) ?? 0
        q.quoteTime = f[30]
        if f.count > 37 { q.amountWan = Double(f[37]) ?? 0 }
        if f.count > 43 { q.amplitudePct = Double(f[43]) ?? 0 }
        return q.price > 0 ? q : nil
    }

    /// 新浪：, 分隔。1 现价 / 2 涨跌 / 3 涨跌幅 / 5 成交额万
    static func parseSina(_ raw: String) -> Quote? {
        guard let body = raw.split(separator: "\"").dropFirst().first else { return nil }
        let f = body.components(separatedBy: ",")
        guard f.count >= 6, let price = Double(f[1]), price > 0 else { return nil }
        var q = Quote()
        q.price = price
        q.changePct = Double(f[3]) ?? 0
        q.amountWan = (Double(f[5]) ?? 0) / 10000
        return q
    }
}

// MARK: - 交易时段

enum Clock {
    static var shanghai: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }()

    static var now: DateComponents { shanghai.dateComponents([.hour, .minute, .weekday], from: Date()) }

    static var isTrading: Bool {
        let c = now
        guard let wd = c.weekday, (2...6).contains(wd), let h = c.hour, let m = c.minute else { return false }
        let t = h * 60 + m
        return (570...690).contains(t) || (780...900).contains(t)
    }

    static var interval: TimeInterval { isTrading ? 10 : 60 }

    static var statusText: String {
        if !Session.isTradingDay(Date()) { return "非交易日" }
        let c = now
        guard let h = c.hour, let m = c.minute else { return "" }
        let t = h * 60 + m
        if (570...690).contains(t) { return "交易中" }
        if (690..<780).contains(t) { return "午间休市" }
        if (780...900).contains(t) { return "交易中" }
        if t < 570 { return "未开盘" }
        return "已收盘"
    }
}

// MARK: - 休市日

/// 工作日里的休市日。周末本来就休市，由 Session.isTradingDay 单独处理，这里不必重复列。
/// 数据来源：上海证券交易所《关于上海证券交易所2026年部分节假日休市安排的通知》
///（上证公告〔2025〕45号，2025-12-22）。
/// 每年 12 月交易所会发下一年的安排，届时在这里补一年即可；
/// 也可以不改代码，往 `~/Library/Application Support/IndexBar/holidays.txt`
/// 里按 `YYYY-MM-DD` 一行一个补，优先级高于内置表。
enum Holidays {
    private static let builtin: [Int: [String]] = [
        2026: [
            "01-01", "01-02",                                   // 元旦（1/3、1/4 为周末）
            "02-16", "02-17", "02-18", "02-19", "02-20", "02-23", // 春节（2/15、2/21、2/22 为周末）
            "04-06",                                            // 清明（4/4、4/5 为周末）
            "05-01", "05-04", "05-05",                          // 劳动节（5/2、5/3 为周末）
            "06-19",                                            // 端午（6/20、6/21 为周末）
            "09-25",                                            // 中秋（9/26、9/27 为周末）
            "10-01", "10-02", "10-05", "10-06", "10-07",        // 国庆（10/3、10/4 为周末）
        ]
    ]

    /// 外部补表：一行一个 YYYY-MM-DD，# 开头为注释
    private static let external: Set<String> = {
        let path = NSHomeDirectory() + "/Library/Application Support/IndexBar/holidays.txt"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var set = Set<String>()
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count == 10, !s.hasPrefix("#") else { continue }
            set.insert(s)
        }
        return set
    }()

    static func isClosed(year: Int, monthDay: String) -> Bool {
        if external.contains(String(format: "%04d-%@", year, monthDay)) { return true }
        return builtin[year]?.contains(monthDay) ?? false
    }

    /// 内置表里没有这一年，说明该补表了——退化为「只看周末」，并在日志里提醒
    static var hasSchedule: Bool {
        builtin[Session.parts(Date()).year] != nil || !external.isEmpty
    }
}

// MARK: - 运行时段

/// 只在交易日 08:00–16:00 之间运行，其余时间进程直接退出：
/// 非开盘日整天不开，交易日 16:00 到次日 08:00 也不开。
enum Session {
    static let openMinute = 8 * 60      // 08:00 开
    static let closeMinute = 16 * 60    // 16:00 关

    struct Parts {
        var year: Int
        var monthDay: String
        var weekday: Int
        var minute: Int
        var dateKey: String
    }

    static func parts(_ d: Date) -> Parts {
        let c = Clock.shanghai.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: d)
        let y = c.year ?? 0, m = c.month ?? 0, day = c.day ?? 0
        return Parts(year: y,
                     monthDay: String(format: "%02d-%02d", m, day),
                     weekday: c.weekday ?? 0,
                     minute: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                     dateKey: String(format: "%04d-%02d-%02d", y, m, day))
    }

    /// 周一到周五，且不在休市表里
    static func isTradingDay(_ d: Date) -> Bool {
        let p = parts(d)
        guard (2...6).contains(p.weekday) else { return false }
        return !Holidays.isClosed(year: p.year, monthDay: p.monthDay)
    }

    static func isActive(_ d: Date = Date()) -> Bool {
        // 测试开关：想直接看「关闭态」长什么样，用 IDXBAR_FORCE_OFF=1 或 --force-off 启动即可
        if ProcessInfo.processInfo.environment["IDXBAR_FORCE_OFF"] == "1"
            || CommandLine.arguments.contains("--force-off") { return false }
        guard isTradingDay(d) else { return false }
        let m = parts(d).minute
        return m >= openMinute && m < closeMinute
    }

    /// 当天 16:00 这个时刻（已经过了就返回 nil）
    static func closingTime(after d: Date = Date()) -> Date? {
        var comps = Clock.shanghai.dateComponents([.year, .month, .day], from: d)
        comps.hour = closeMinute / 60
        comps.minute = closeMinute % 60
        comps.second = 0
        guard let t = Clock.shanghai.date(from: comps), t > d else { return nil }
        return t
    }

    /// 下一次开盘的 08:00。往后最多找 14 天，够跨过任何一次长假。
    static func nextOpening(after d: Date = Date()) -> Date? {
        for offset in 0...14 {
            guard let day = Clock.shanghai.date(byAdding: .day, value: offset, to: d) else { continue }
            guard isTradingDay(day) else { continue }
            var comps = Clock.shanghai.dateComponents([.year, .month, .day], from: day)
            comps.hour = openMinute / 60
            comps.minute = openMinute % 60
            comps.second = 0
            guard let t = Clock.shanghai.date(from: comps), t > d else { continue }
            return t
        }
        return nil
    }

    /// --session-check：把几种典型时刻的判定打出来，用来核对逻辑，不影响运行
    static func report() {
        let fmt = DateFormatter()
        fmt.calendar = Clock.shanghai
        fmt.timeZone = Clock.shanghai.timeZone
        fmt.dateFormat = "yyyy-MM-dd HH:mm"

        print("当前时间：\(fmt.string(from: Date()))")
        print("是否该运行：\(isActive() ? "是" : "否")")
        print("离收盘退出还有：\(closingTime().map { "\(Int($0.timeIntervalSinceNow / 60)) 分钟" } ?? "不在运行时段")")
        print("")
        print("时刻                 交易日  该运行")
        let samples: [(String, String)] = [
            ("2026-10-21 07:59", "交易日 · 开盘前1分钟"),
            ("2026-10-21 08:00", "交易日 · 开"),
            ("2026-10-21 11:35", "交易日 · 午休"),
            ("2026-10-21 15:59", "交易日 · 收盘前1分钟"),
            ("2026-10-21 16:00", "交易日 · 关"),
            ("2026-10-21 20:00", "交易日 · 夜里"),
            ("2026-10-24 10:00", "周六"),
            ("2026-10-25 10:00", "周日"),
            ("2026-10-01 10:00", "国庆"),
            ("2026-02-18 10:00", "春节"),
            ("2026-10-08 09:00", "国庆后首个交易日"),
        ]
        for (text, note) in samples {
            guard let d = fmt.date(from: text) else { continue }
            let trading = isTradingDay(d)
            print(String(format: "%@  %@  %@   %@", text, trading ? "是" : "否",
                         isActive(d) ? "是" : "否", note))
        }
        // 顺带把日期分解的结果打一份，排查时区问题用
        let p = parts(Date())
        print("")
        print("今天分解：\(p.dateKey) 星期\(p.weekday) 第\(p.minute)分钟 休市表\(Holidays.hasSchedule ? "已覆盖" : "未覆盖（只看周末）")")
    }
}

// MARK: - 菜单栏外观

enum Look {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 涨红跌绿（A 股口径）。必须是普通静态色——带闭包的动态色过不了进程边界。
    static func color(_ direction: Int, _ appearance: NSAppearance?) -> NSColor {
        let dark = appearance.map(isDark) ?? false
        switch direction {
        case 1:
            return dark ? NSColor(srgbRed: 1.00, green: 0.36, blue: 0.34, alpha: 1)
                        : NSColor(srgbRed: 0.84, green: 0.09, blue: 0.11, alpha: 1)
        case -1:
            return dark ? NSColor(srgbRed: 0.20, green: 0.82, blue: 0.42, alpha: 1)
                        : NSColor(srgbRed: 0.00, green: 0.47, blue: 0.24, alpha: 1)
        default:
            return .labelColor
        }
    }

    static func font() -> NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }

    /// 37340.04 = 点位整数 + 涨跌幅绝对值两位小数。不带逗号、百分号、正负号。
    static func text(_ q: Quote?) -> String {
        guard let q = q, q.price > 0 else { return "00000.00" }
        return String(Int(q.price)) + String(format: "%.2f", abs(q.changePct))
    }

    static func attributed(_ q: Quote?, stale: Bool, appearance: NSAppearance?) -> NSAttributedString {
        NSAttributedString(string: text(q), attributes: [
            .font: font(),
            .foregroundColor: stale ? NSColor.secondaryLabelColor
                                    : color(q?.direction ?? 0, appearance),
        ])
    }
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var quote: Quote?
    private var fails = 0
    private var busy = false
    private var popover: NSPopover?
    private var quitTimer: Timer?
    private var dormantTimer: Timer?
    private let detail = DetailView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 单实例：登录项和休眠心跳有可能同时把它叫起来，两个图标会让人以为软件坏了
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                log("已有实例在跑，本实例退出")
                exit(0)
            }
        }

        observeSystem()
        // 不在运行时段就什么都不建，直接进入休眠
        checkSession()
    }

    /// 起一段工作状态：菜单栏项露出来、取数、定时刷新、排队到 16:00 收工
    private func startWorking() {
        guard item == nil else {
            item?.isVisible = true
            return
        }

        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 位置记忆：Hidden Bar 这类菜单栏管理工具会在栏里插一根超宽占位条，
        // 把「隐藏区」的项整体推到屏幕左边缘之外。新装的项默认就落在那一片。
        // 位置值越小越靠右，钉一个小于它折叠箭头的值，才能落在可见区。
        it.autosaveName = "IndexBarItem"
        it.button?.attributedTitle = Look.attributed(nil, stale: false, appearance: nil)
        it.button?.target = self
        it.button?.action = #selector(clicked(_:))
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item = it

        log("进入运行状态")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // 高度 33 才是被控制中心真正托管的菜单栏窗口；
            // 22 是进程自己的占位窗口，说明没上屏。
            let b = self.item?.button
            let h = b?.window?.frame.height ?? 0
            self.log("自检 窗口高\(Int(h)) " + (h >= 30 ? "已上屏" : "⚠️ 未上屏")
                     + " frame=\(String(describing: b?.window?.frame)) "
                     + "title=\(b?.attributedTitle.string ?? "")")
        }

        refresh()
        schedule()
        scheduleQuit()
    }

    /// 收工：菜单栏项藏起来、不联网、不刷新，只留一个到点再看的心跳。
    /// 这里刻意用 isVisible 而不是 removeStatusItem——反复销毁重建会让控制中心
    /// 把这一份状态记成坏的，之后同一个 bundle id 再也托管不上。
    /// 之所以不退进程，是因为 launchd 在这台机器上装不进去，
    /// 真退掉就没人能在 08:00 把它叫起来——宁可留个空壳，也不能关了叫不醒。
    private func stopWorking() {
        if let it = item, it.isVisible {
            log("进入关闭状态（\(Clock.statusText)）")
            it.isVisible = false
        } else if item == nil && dormantTimer == nil {
            log("启动时不在运行时段，保持关闭（\(Clock.statusText)）")
        }
        timer?.invalidate(); timer = nil
        quitTimer?.invalidate(); quitTimer = nil
        popover?.performClose(nil); popover = nil
        quote = nil
        fails = 0
        busy = false
        scheduleDormantTick()
    }

    /// 休眠期间自己醒来看一眼。离下次开盘还远就每 5 分钟看一眼，
    /// 进入最后 5 分钟后改成按剩余秒数排一次——这样 08:00 是准点起，不是晚五分钟。
    private func scheduleDormantTick() {
        dormantTimer?.invalidate()
        var interval: TimeInterval = 300
        if let opening = Session.nextOpening() {
            let delta = opening.timeIntervalSinceNow
            if delta > 0 && delta <= 300 { interval = max(1, delta) }
        }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkSession()
        }
        t.tolerance = min(30, interval * 0.1)
        RunLoop.main.add(t, forMode: .common)
        dormantTimer = t
    }

    /// 该工作就起、该关就收，两个方向都走这一个入口
    private func checkSession() {
        if Session.isActive() {
            dormantTimer?.invalidate(); dormantTimer = nil
            startWorking()
        } else {
            stopWorking()
        }
    }

    /// 到 16:00 收工。计时器在睡眠期间不跑，所以醒来还要再核对一次，见 checkSession()
    private func scheduleQuit() {
        quitTimer?.invalidate()
        guard let closing = Session.closingTime() else { return }
        let t = Timer(timeInterval: closing.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            self?.log("到收工时刻，收工")
            self?.checkSession()
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        quitTimer = t
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.checkSession()
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil, queue: .main) { [weak self] _ in
            self?.checkSession()
        }
    }

    /// 只记状态切换这种关键节点，量很小，所以不受调试开关控制、始终落文件——
    /// 出问题时第一件事就是看它到底进没进运行时段。
    private func log(_ s: String) {
        let line = "\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) [V2] " + s + "\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/indexbar-v2.log") {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); fh.closeFile()
        } else {
            try? line.write(toFile: "/tmp/indexbar-v2.log", atomically: true, encoding: .utf8)
        }
    }

    private func refresh() {
        guard !busy else { return }
        busy = true
        Source.fetch { [weak self] q in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if let q = q { self.quote = q; self.fails = 0 } else { self.fails += 1 }
                self.render()
            }
        }
    }

    private func render() {
        item?.button?.attributedTitle = Look.attributed(
            quote, stale: fails >= 2, appearance: item?.button?.effectiveAppearance)
        if let pop = popover, pop.isShown { detail.update(quote: quote, status: Clock.statusText) }
    }

    private func schedule() {
        timer?.invalidate()
        // 还没拿到过数据就加密重试，别让人对着占位符干等一分钟
        let base: TimeInterval = (quote == nil && fails > 0) ? 5 : Clock.interval
        let t = Timer(timeInterval: base, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.schedule()
        }
        t.tolerance = min(3, base * 0.15)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = item?.button else { return }
        if let pop = popover, pop.isShown { pop.performClose(nil); return }
        detail.update(quote: quote, status: Clock.statusText)
        let pop = popover ?? NSPopover()
        pop.contentViewController = detail
        pop.behavior = .transient
        popover = pop
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        refresh()
    }

    private func showMenu() {
        let menu = NSMenu()
        let head = NSMenuItem(title: quote.map { "上证指数 \(Fmt.price($0.price))  \(Fmt.pct($0.changePct))" } ?? "上证指数 —",
                              action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())
        let r = NSMenuItem(title: "立即刷新", action: #selector(doRefresh), keyEquivalent: "r")
        r.target = self
        menu.addItem(r)
        let hide = NSMenuItem(title: "现在收起到下次开盘", action: #selector(doHide), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "退出", action: #selector(doQuit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)

        guard let it = item else { return }
        it.menu = menu
        it.button?.performClick(nil)
        it.menu = nil
    }

    @objc private func doRefresh() { refresh() }

    /// 手动收起：立刻撤掉菜单栏项，等下一个运行时段自己回来
    @objc private func doHide() {
        stopWorking()
    }

    @objc private func doQuit() { NSApp.terminate(nil) }
}

// MARK: - 详情面板

final class DetailView: NSViewController {
    private let name = NSTextField(labelWithString: "上证指数")
    private let status = NSTextField(labelWithString: "")
    private let big = NSTextField(labelWithString: "—")
    private let change = NSTextField(labelWithString: "")
    private var rows: [String: NSTextField] = [:]

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 240))

        name.font = .systemFont(ofSize: 13, weight: .semibold)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        big.font = .monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        change.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let head = NSStackView(views: [name, status])
        head.orientation = .horizontal
        head.spacing = 8

        let grid = NSGridView(views: [
            [label("今开"), value("open"), label("昨收"), value("prev")],
            [label("最高"), value("high"), label("最低"), value("low")],
            [label("成交额"), value("amount"), label("振幅"), value("amp")],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        for r in 0..<grid.numberOfRows {
            for c in stride(from: 0, to: grid.numberOfColumns, by: 2) {
                grid.cell(atColumnIndex: c, rowIndex: r).xPlacement = .trailing
            }
        }

        let stack = NSStackView(views: [head, big, change, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        view = root
    }

    private func label(_ s: String) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func value(_ key: String) -> NSTextField {
        let f = NSTextField(labelWithString: "—")
        f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rows[key] = f
        return f
    }

    func update(quote: Quote?, status text: String) {
        _ = view   // 触发 loadView
        status.stringValue = text
        guard let q = quote else {
            big.stringValue = "—"
            change.stringValue = ""
            return
        }
        big.stringValue = Fmt.price(q.price)
        change.stringValue = Fmt.pct(q.changePct)
        let c = Look.color(q.direction, view.effectiveAppearance)
        big.textColor = c
        change.textColor = c
        rows["open"]?.stringValue = q.open > 0 ? Fmt.price(q.open) : "—"
        rows["prev"]?.stringValue = q.prevClose > 0 ? Fmt.price(q.prevClose) : "—"
        rows["high"]?.stringValue = q.high > 0 ? Fmt.price(q.high) : "—"
        rows["low"]?.stringValue = q.low > 0 ? Fmt.price(q.low) : "—"
        rows["amount"]?.stringValue = q.amountWan > 0 ? Fmt.amount(q.amountWan) : "—"
        rows["amp"]?.stringValue = q.amplitudePct > 0 ? Fmt.pct(q.amplitudePct) : "—"
    }
}

// MARK: - 入口

// --session-check：只打印时段判定，不建界面、不常驻，用来核对「该不该运行」
if CommandLine.arguments.contains("--session-check") {
    Session.report()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
