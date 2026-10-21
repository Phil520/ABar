import Cocoa

/// 环境变量 IDXBAR_DEBUG=1 时把关键状态打到 stderr。
/// 菜单栏工具最难查的就是「图标看不见」——分不清是没建、没上屏、还是上屏了没人看见。
enum Dbg {
    static let on = ProcessInfo.processInfo.environment["IDXBAR_DEBUG"] == "1"
        || CommandLine.arguments.contains("--verbose")
    /// 用 open 启动时拿不到 stderr，所以开启调试时一律另外落一份文件
    private static let filePath: String? = on ? "/tmp/indexbar-debug.log" : nil

    static func log(_ s: String) {
        guard on else { return }
        let line = "[IDXBAR] " + s + "\n"
        if let path = filePath {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(line.data(using: .utf8)!)
                fh.closeFile()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        } else {
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    /// 排查用：--probe-item 时额外挂一个「只用纯文字」的最简状态项。
    /// 它能不能出现，直接分出问题是「某项配置」还是「整个 App 拿不到菜单栏窗口」。
    private var probeItem: NSStatusItem?
    private let service = QuoteService()
    private var timer: Timer?

    private var quote: Quote?
    private var failStreak = 0
    private var inFlight = false
    private var lastAttempt: Date = .distantPast

    private var popover: NSPopover?
    private var detailVC: DetailViewController?
    private var floating: FloatingBarController?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 排查开关：--bare 抢在一切逻辑之前建项，用来判断问题是否出在「建项之前」的初始化
        if CommandLine.arguments.contains("--bare") {
            let p = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            p.button?.title = "BARE1"
            probeItem = p
            return
        }

        // 自检入口：验证 LaunchAgent 真的能加载（不弹界面）
        if CommandLine.arguments.contains("--check-autostart") {
            exit(runAutostartSelfCheck())
        }

        guard SingleInstance.claim() else {
            // 已有实例在跑，静默退出（不弹窗打扰）
            NSApp.terminate(nil)
            return
        }

        // 和 CodexO 对齐：激活策略放在应用跑起来之后再设。
        // 在 NSApp.run() 之前设，菜单栏状态项在 macOS 26 上可能拿不到渲染场景。
        NSApp.setActivationPolicy(.accessory)

        if Prefs.current == .floating {
            // 降级模式：菜单栏状态项排不上位时，改用右上角悬浮窗
            let bar = FloatingBarController()
            bar.onRefresh = { [weak self] in self?.fetch(force: true) }
            bar.show()
            floating = bar
            Dbg.log("已启用悬浮窗模式")
        } else {
            setupMenuBarItem()
        }

        if CommandLine.arguments.contains("--no-net") {
            // 排查开关：只建状态项，不起取数、定时和监听，用来隔离「建项配置」和「取数链路」
            Dbg.log("--no-net：跳过取数、定时、监听")
            return
        }

        fetch(force: true)
        scheduleNext()
        installObservers()
    }

    private func setupMenuBarItem() {
        // 排查开关：--min 只建一个最简状态项，不设 autosaveName、不挂 target/action、不设 toolTip。
        // 它能上屏就说明是后面那几行配置里的某一行把状态项挡在了控制中心门外。
        if CommandLine.arguments.contains("--min") {
            let p = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            p.button?.attributedTitle = NSAttributedString(
                string: "11111.11",
                attributes: [.font: MenuBarUI.font(), .foregroundColor: NSColor.labelColor])
            probeItem = p
            Dbg.log("--min 最简项已创建: \(String(describing: p))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let b = p.button
                Dbg.log("--min 2 秒后 frame=\(String(describing: b?.window?.frame)) "
                        + "screen=\(String(describing: b?.window?.screen?.frame))")
            }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 记住位置：系统会把位置存进本 App 的偏好，用户 ⌘ 拖动过一次后下次就固定在原地
        statusItem.autosaveName = "IndexBarItem"
        Dbg.log("statusItem 已创建: \(String(describing: statusItem))")
        if let button = statusItem.button {
            // 首次上屏就用和真实读数等宽（8 个字符）的占位文字。
            // 用「—」这种窄字会让系统按 32pt 的默认宽度先定好槽位，
            // 等真实读数下来，窗口变宽了槽位却不重新让位，右边就被切到屏幕外。
            button.attributedTitle = MenuBarUI.attributedTitle(for: nil, stale: false, placeholder: "00000.00")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "上证指数 · 点击看详情，右键更多"
            Dbg.log("按钮已就绪 window=\(String(describing: button.window?.frame))")
        } else {
            Dbg.log("⚠️ statusItem.button 为 nil")
        }

        // 上屏自检：菜单栏图标看不见时，先看这行日志分清「没建」「没上屏」「上屏了没画」
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let b = self.statusItem.button else { return }
            Dbg.log("2 秒后 frame=\(String(describing: b.window?.frame)) "
                    + "screen=\(String(describing: b.window?.screen?.frame)) "
                    + "visible=\(b.window?.isVisible ?? false) "
                    + "itemVisible=\(self.statusItem.isVisible) "
                    + "title=\(b.attributedTitle.string)")
            if let p = self.probeItem {
                let pb = p.button
                Dbg.log("对照项 frame=\(String(describing: pb?.window?.frame)) "
                        + "screen=\(String(describing: pb?.window?.screen?.frame)) "
                        + "visible=\(pb?.window?.isVisible ?? false) "
                        + "len=\(p.length) title=\(pb?.title ?? "nil")")
            }
        }

        // 对照项：最简写法，只放一行纯文字，不设 autosave、不设 attributedTitle、不挂菜单
        if CommandLine.arguments.contains("--probe-item") {
            let p = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            p.button?.title = "ZZZ"
            p.button?.font = MenuBarUI.font()
            probeItem = p
            Dbg.log("对照项已创建: \(String(describing: p))")
        }
    }

    private func installObservers() {
        // --preview 或 /tmp/indexbar-preview 文件：启动后自动弹一次详情面板，
        // 供截图/验收用。文件开关是给 open 启动用的——open 传不进参数。
        if CommandLine.arguments.contains("--preview")
            || FileManager.default.fileExists(atPath: "/tmp/indexbar-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self else { return }
                if let bar = self.floating { bar.openPopover() } else { self.togglePopover() }
            }
        }

        let wsc = NSWorkspace.shared.notificationCenter
        wsc.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged),
                                               name: Notification.Name.NSSystemClockDidChange, object: nil)
        // 深浅色切换后要重画：颜色是渲染时按外观现算的静态色，不重画就还留着上一套
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        SingleInstance.release()
    }

    // MARK: - 取数

    private func fetch(force: Bool = false) {
        if inFlight { return }
        if !force, Date().timeIntervalSince(lastAttempt) < 1.5 { return }
        inFlight = true
        lastAttempt = Date()

        service.fetch { [weak self] result in
            // 必须回主线程：URLSession 的回调在线程池里，直接改
            // attributedTitle / 触发布局会让 Auto Layout 跨线程，macOS 26 上
            // 轻则状态项 scene 不提交（图标空白），重则整进程崩。
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlight = false
                switch result {
                case .success(let q):
                    self.quote = q
                    self.failStreak = 0
                case .failure:
                    self.failStreak += 1
                }
                self.render()
                if let bar = self.floating {
                    bar.refreshPanel()
                } else if let pop = self.popover, pop.isShown {
                    self.detailVC?.update(quote: self.quote, staleNote: self.staleNote)
                }
            }
        }
    }

    /// 连续两次拿不到数，就把菜单栏文字变灰，但不擦掉最后已知值——
    /// 空着比显示旧数更容易让人误判
    private var staleNote: String? {
        if failStreak >= 2 { return "连接失败 · 重试中" }
        return nil
    }

    private func render() {
        if let bar = floating {
            bar.update(quote: quote, stale: failStreak >= 2)
            return
        }
        guard let button = statusItem?.button else { return }
        // 深浅色在渲染时按按钮当前外观现算，产出的是普通静态色。
        // 这样既不依赖带闭包的动态色（那种色过不了进程边界），又能随外观切换变色。
        statusItem.button?.attributedTitle = MenuBarUI.attributedTitle(
            for: quote, stale: failStreak >= 2, appearance: button.effectiveAppearance)
    }

    // MARK: - 节奏

    private func scheduleNext() {
        timer?.invalidate()
        let interval = TradingClock.refreshInterval()
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.fetch(force: true)
            self.scheduleNext()
        }
        t.tolerance = min(3.0, interval * 0.15)
        RunLoop.main.add(t, forMode: .common)   // .common：菜单/弹窗打开时也照常走
        timer = t
    }

    @objc private func systemDidWake() {
        fetch(force: true)
        scheduleNext()
    }

    @objc private func clockChanged() {
        scheduleNext()
    }

    @objc private func appearanceChanged() {
        // 外观通知落地的瞬间外观可能还没定，稍等一拍再重画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.render()
        }
    }

    // MARK: - 交互

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard statusItem != nil else { return }
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }

        let vc: DetailViewController
        if let existing = detailVC {
            vc = existing
        } else {
            vc = DetailViewController()
            vc.onRefresh = { [weak self] in self?.fetch(force: true) }
            detailVC = vc
        }
        vc.update(quote: quote, staleNote: staleNote)

        let pop = popover ?? NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.animates = true
        popover = pop

        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        fetch(force: true)   // 打开面板顺手拉一次最新数
    }

    private func showMenu() {
        let menu = NSMenu()

        let head = NSMenuItem(title: quote.map { "上证指数 \(Fmt.price($0.price))  \(Fmt.pct($0.changePct))" } ?? "上证指数 —",
                              action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let auto = NSMenuItem(title: "开机自启", action: #selector(menuToggleLoginItem), keyEquivalent: "")
        auto.target = self
        auto.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(auto)

        let modeItem = NSMenuItem(title: "改用悬浮窗显示", action: #selector(menuSwitchToFloating), keyEquivalent: "")
        modeItem.target = self
        menu.addItem(modeItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 借用系统菜单的弹出机制：临时挂上、点完即摘掉，
        // 这样左键仍然归弹窗，右键才出菜单
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuRefresh() {
        fetch(force: true)
    }

    @objc private func menuToggleLoginItem() {
        let message: String?
        if LoginItem.isEnabled {
            message = LoginItem.disable()
        } else {
            message = LoginItem.enable()
        }
        if let message = message {
            let alert = NSAlert()
            alert.messageText = "开机自启设置未生效"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func menuSwitchToFloating() {
        Prefs.current = .floating
        relaunchApp()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - 自检

    /// --check-autostart：开一次、验一次、关掉，把结果打到 stdout
    private func runAutostartSelfCheck() -> Int32 {
        let before = LoginItem.isEnabled
        if let err = LoginItem.enable() {
            print("ENABLE_FAIL \(err)")
            _ = LoginItem.disable()
            return 1
        }
        let loaded = LoginItem.isEnabled
        let err = LoginItem.disable()
        let after = LoginItem.isEnabled
        print("enable_ok=\(loaded) enable_err=\(err ?? "nil") disabled_ok=\(!after) before=\(before)")
        return (loaded && !after) ? 0 : 1
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
