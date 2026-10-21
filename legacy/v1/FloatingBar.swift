import Cocoa

/// 悬浮窗模式：菜单栏状态项排不上位时的降级方案。
/// 贴在屏幕右上角、菜单栏正下方，显示同一串数字，点开同一个详情面板。
/// 用普通窗口实现——菜单栏那层坏了也照样能画出来。
final class FloatingBarController: NSObject {

    private var panel: NSPanel?
    private var barView: BarView?
    private var popover: NSPopover?
    private var detailVC: DetailViewController?
    private var currentQuote: Quote?

    var onRefresh: (() -> Void)?

    /// 数字区宽度。等宽字体 + 固定两位小数，宽度基本恒定，
    /// 留 86 是为了 5 位点位（万点级）也不截断。
    private let barWidth: CGFloat = 86
    private let barHeight: CGFloat = 22

    // MARK: - 显示

    func show() {
        guard panel == nil else { return }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: barWidth, height: barHeight),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true          // 按住就能拖，位置自己定
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.animationBehavior = .none

        let view = BarView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        view.onLeftClick = { [weak self] in self?.togglePopover() }
        view.onRightClick = { [weak self] in self?.showMenu() }
        p.contentView = view
        barView = view

        p.setFrameOrigin(anchorOrigin())
        p.orderFrontRegardless()
        panel = p
    }

    /// 右上角，紧贴菜单栏下沿
    private func anchorOrigin() -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let f = screen.frame
        let visible = screen.visibleFrame
        let menuBarH = f.maxY - visible.maxY
        return NSPoint(x: f.maxX - barWidth - 10,
                       y: f.maxY - menuBarH - barHeight - 4)
    }

    func update(quote: Quote?, stale: Bool) {
        currentQuote = quote
        barView?.attributedTitle = MenuBarUI.attributedTitle(for: quote, stale: stale,
                                                           appearance: NSApp.effectiveAppearance)
        // 让窗口宽度跟着数字走，不留白
        if let view = barView {
            let w = max(barWidth, view.fittingSize.width + 4)
            if let p = panel, abs(p.frame.width - w) > 0.5 {
                var frame = p.frame
                frame.size.width = w
                frame.origin.x = (NSScreen.main?.frame.maxX ?? frame.maxX) - w - 10
                p.setFrame(frame, display: false)
            }
        }
    }

    // MARK: - 交互

    /// 给 --preview 用的公开入口
    func openPopover() { togglePopover() }

    private func togglePopover() {
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            return
        }
        guard let anchor = barView else { return }

        let vc: DetailViewController
        if let existing = detailVC {
            vc = existing
        } else {
            vc = DetailViewController()
            vc.onRefresh = { [weak self] in self?.onRefresh?() }
            detailVC = vc
        }
        vc.update(quote: currentQuote, staleNote: nil)

        let pop = popover ?? NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.animates = true
        popover = pop

        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        onRefresh?()
    }

    /// 详情面板跟着数据更新
    func refreshPanel() {
        guard let pop = popover, pop.isShown else { return }
        detailVC?.update(quote: currentQuote, staleNote: nil)
    }

    private func showMenu() {
        guard let view = barView else { return }
        let menu = NSMenu()

        let head = NSMenuItem(title: currentQuote.map { "上证指数 \(Fmt.price($0.price))  \(Fmt.pct($0.changePct))" } ?? "上证指数 —",
                              action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let mode = NSMenuItem(title: "切回菜单栏显示", action: #selector(menuSwitchToMenuBar), keyEquivalent: "")
        mode.target = self
        menu.addItem(mode)

        let auto = NSMenuItem(title: "开机自启", action: #selector(menuToggleLoginItem), keyEquivalent: "")
        auto.target = self
        auto.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }

    @objc private func menuRefresh() { onRefresh?() }

    @objc private func menuSwitchToMenuBar() {
        Prefs.current = .menuBar
        relaunchApp()
    }

    @objc private func menuToggleLoginItem() {
        let message = LoginItem.isEnabled ? LoginItem.disable() : LoginItem.enable()
        if let message = message {
            let alert = NSAlert()
            alert.messageText = "开机自启设置未生效"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }
}

// MARK: - 承载视图

private final class BarView: NSView {

    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    var attributedTitle: NSAttributedString? {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let t = attributedTitle else { return NSSize(width: 86, height: 22) }
        return NSSize(width: t.size().width + 16, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 半透明底 + 圆角，像是从菜单栏掉下来的一小块
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard let t = attributedTitle else { return }
        let size = t.size()
        t.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
