import Cocoa

/// 点开菜单栏看到的详情面板。纯 AppKit 手写布局，不用 SwiftUI——
/// SwiftUI 会额外拉起一套运行时，空载内存要多十几兆，这工具就靠轻。
final class DetailViewController: NSViewController {

    var onRefresh: (() -> Void)?

    private static let panelWidth: CGFloat = 296

    private let nameLabel = DetailViewController.label("上证指数", size: 11, color: .secondaryLabelColor)
    private let statusLabel = DetailViewController.label("", size: 10.5, color: .secondaryLabelColor)
    private let priceLabel = DetailViewController.label("—", size: 26, weight: .semibold, color: .labelColor)
    private let changeLabel = DetailViewController.label("", size: 12, color: .labelColor)
    private let timeLabel = DetailViewController.label("", size: 10.5, color: .tertiaryLabelColor)
    private lazy var refreshButton: NSButton = {
        let b = NSButton(title: "刷新", target: self, action: #selector(refreshTapped))
        b.bezelStyle = .inline
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        return b
    }()

    /// 六个指标的数值标签，顺序与 metricRows 一致
    private var valueLabels: [NSTextField] = []

    private static let metricRows: [(String, String)] = [
        ("今开", ""), ("昨收", ""),
        ("最高", ""), ("最低", ""),
        ("成交额", ""), ("振幅", ""),
    ]

    // MARK: - 视图搭建

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addConstraint(NSLayoutConstraint(item: root, attribute: .width, relatedBy: .equal,
                                             toItem: nil, attribute: .notAnAttribute,
                                             multiplier: 1, constant: Self.panelWidth))
        view = root

        let sep1 = Self.separator()
        let sep2 = Self.separator()
        let grid = makeGrid()

        for v in [nameLabel, statusLabel, priceLabel, changeLabel, sep1, sep2, grid, timeLabel, refreshButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        statusLabel.alignment = .right

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            statusLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),

            priceLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            priceLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            changeLabel.firstBaselineAnchor.constraint(equalTo: priceLabel.firstBaselineAnchor),
            changeLabel.leadingAnchor.constraint(equalTo: priceLabel.trailingAnchor, constant: 8),
            changeLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),

            sep1.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 12),
            sep1.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sep1.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            grid.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),

            sep2.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            sep2.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sep2.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 10),
            timeLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            timeLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),

            refreshButton.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            refreshButton.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 8),
        ])
    }

    private func makeGrid() -> NSGridView {
        var rows: [[NSView]] = []
        valueLabels = []
        for (label, _) in Self.metricRows {
            let l = Self.label(label, size: 11, color: .secondaryLabelColor)
            let v = Self.label("—", size: 12, color: .labelColor, mono: true)
            valueLabels.append(v)
            rows.append([l, v])
        }
        // 两列拼成 4 列：今开/昨收 一行，最高/最低 一行，成交额/振幅 一行
        let gridRows: [[NSView]] = [
            [rows[0][0], rows[0][1], rows[1][0], rows[1][1]],
            [rows[2][0], rows[2][1], rows[3][0], rows[3][1]],
            [rows[4][0], rows[4][1], rows[5][0], rows[5][1]],
        ]
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 7
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        // 第 1、3 列（标签列）与数值列之间留一道空隙，读起来不糊成一片
        if grid.numberOfColumns == 4 {
            grid.column(at: 1).xPlacement = .trailing
            grid.column(at: 3).xPlacement = .trailing
        }
        return grid
    }

    // MARK: - 刷新内容

    func update(quote: Quote?, staleNote: String?) {
        guard isViewLoaded else { return }

        let status = staleNote ?? TradingClock.statusText(for: quote)
        statusLabel.stringValue = status
        statusLabel.textColor = staleNote == nil ? .secondaryLabelColor : .systemOrange

        guard let q = quote else {
            priceLabel.stringValue = "—"
            priceLabel.textColor = .labelColor
            changeLabel.stringValue = ""
            timeLabel.stringValue = "正在获取行情…"
            for l in valueLabels { l.stringValue = "—" }
            resize()
            return
        }

        let color = MenuBarUI.color(for: q.direction)
        priceLabel.stringValue = Fmt.price(q.price)
        priceLabel.textColor = color
        changeLabel.stringValue = "\(Fmt.signed(q.change))  \(Fmt.pct(q.changePct))"
        changeLabel.textColor = color

        valueLabels[0].stringValue = Fmt.price(q.open)
        valueLabels[1].stringValue = Fmt.price(q.prevClose)
        valueLabels[2].stringValue = Fmt.price(q.high)
        valueLabels[3].stringValue = Fmt.price(q.low)
        valueLabels[4].stringValue = Fmt.amount(q.amountWan)
        valueLabels[5].stringValue = Fmt.plainPct(q.amplitudePct)

        let t = q.quoteTime.map { TradingClock.timeFormatter.string(from: $0) } ?? "--:--:--"
        timeLabel.stringValue = "\(t) 更新 · \(q.source)"
        resize()
    }

    /// 内容变了宽度会变（成交额位数、涨跌幅符号），面板尺寸跟着算一次
    private func resize() {
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        preferredContentSize = NSSize(width: Self.panelWidth, height: max(150, fitting.height))
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let h = view.fittingSize.height
        if h > 0, abs(preferredContentSize.height - h) > 0.5 {
            preferredContentSize = NSSize(width: Self.panelWidth, height: h)
        }
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }

    // MARK: - 小工具

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                              color: NSColor, mono: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                      : .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byClipping
        return l
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
