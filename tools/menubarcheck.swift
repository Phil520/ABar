import Cocoa

// 菜单栏上屏自检。
//
// 判据不是「进程起来了」，而是「控制中心的菜单栏层里有没有我们的状态项窗口」。
// 这台机器上踩过的坑是：进程正常、标题也设上了，窗口却压根没被托管，
// 菜单栏上什么都看不见。
//
// 两路证据一起看：
//   一、窗口服务器里那块窗口的 x 落在屏幕范围内；
//   二、窗口高度 33。33 才是控制中心托管的真窗口，20 出头是进程自己的占位窗口。
//
// 注意窗口名。刚注册上去时控制中心先记成 Item-N，过一阵才归一见
// Info.plist 里的 bundle id，所以不能只靠名字认，还得配合 App 自己写进日志的自检行。

/// 期望的窗口名：以项目里的 Info.plist 为准，改 bundle id 之后不用回来改这份脚本
var names = ["IndexBarItem", "指数条"]
if let d = NSDictionary(contentsOfFile: "src/Info.plist"),
   let bid = d["CFBundleIdentifier"] as? String {
    names.insert(bid, at: 0)
}

/// App 起来两秒半后写的那行自检。它读的是 button.window 的真实高度，比从外面猜得准。
func appVerdict() -> String? {
    guard let text = try? String(contentsOfFile: "/tmp/indexbar-v2.log", encoding: .utf8) else { return nil }
    for line in text.split(separator: "\n").reversed() where line.contains("自检") {
        return String(line)
    }
    return nil
}

guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("    拿不到窗口列表")
    exit(1)
}

// 屏幕范围按所有显示器的并集算，别写死一块屏的宽度
let minX = NSScreen.screens.map { $0.frame.minX }.min() ?? 0
let maxX = NSScreen.screens.map { $0.frame.maxX }.max() ?? 0

var found = false
for w in raw {
    guard ((w[kCGWindowLayer as String] as? Int) ?? 0) == 25 else { continue }
    let name = (w[kCGWindowName as String] as? String) ?? ""
    guard names.contains(name) else { continue }
    guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = (b["X"] as? CGFloat) ?? 0
    let width = (b["Width"] as? CGFloat) ?? 0
    let height = (b["Height"] as? CGFloat) ?? 0
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"

    let inScreen = x >= minX - 1 && (x + width) <= maxX + 1
    if inScreen && height >= 30 {
        print("    ✅ 已在菜单栏上屏：x=\(Int(x)) 宽=\(Int(width)) 高=\(Int(height)) 归属=\(owner)")
        found = true
    } else if !inScreen {
        print("    ⚠️ 状态项存在但在屏幕外：x=\(Int(x)) 宽=\(Int(width))，屏幕范围 \(Int(minX))…\(Int(maxX))")
        print("       常见原因：菜单栏管理工具（Hidden Bar 等）把它归进了隐藏区。")
        print("       处理：见 README「踩过的坑」第二条。")
    } else {
        print("    ⚠️ 状态项还在占位阶段：高\(Int(height))，控制中心没有托管它")
        print("       常见原因：这个 bundle id 的状态被控制中心记坏了，只能换 id。")
    }
}

if !found {
    if let line = appVerdict() {
        // 自检行里写着「已上屏」就算过——窗口名还没归一，不代表没上屏
        let ok = line.contains("已上屏")
        print(ok ? "    ✅ 已上屏（窗口名仍记为 Item-N，按 App 自检判定）"
                 : "    ⚠️ App 自检回报未上屏，原文：")
        print("      \(line)")
        exit(ok ? 0 : 1)
    } else {
        print("    ⚠️ 菜单栏层里没有指数条的状态项，日志里也没有自检行——App 大概没在跑")
        exit(1)
    }
}
