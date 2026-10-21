import Cocoa

// 菜单栏上屏自检。
// 判据不是「进程起来了」，而是「控制中心的菜单栏层里有没有我们的状态项窗口」。
// 这台机器上踩过的坑就是：进程正常、标题也设上了，窗口却被挤到屏幕左侧之外。

let names = ["IndexBarItem", "指数条"]

guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("    拿不到窗口列表")
    exit(1)
}

var found = false
for w in raw {
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    guard layer == 25 else { continue }
    let name = (w[kCGWindowName as String] as? String) ?? ""
    guard names.contains(name) else { continue }
    guard let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = (b["X"] as? CGFloat) ?? 0
    let wd = (b["Width"] as? CGFloat) ?? 0
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"

    // 屏幕范围按所有显示器的并集算，别写死一块屏的宽度
    let maxX = NSScreen.screens.map { $0.frame.maxX }.max() ?? 0
    let onScreen = x >= 0 && (x + wd) <= maxX + 1
    if onScreen {
        print("    ✅ 已在菜单栏上屏：x=\(Int(x)) 宽=\(Int(wd)) 归属=\(owner)")
        found = true
    } else {
        print("    ⚠️ 状态项存在但在屏幕外：x=\(Int(x)) 宽=\(Int(wd))，屏幕右边界 \(Int(maxX))")
        print("       常见原因：菜单栏管理工具（Hidden Bar 等）把它归进了隐藏区。")
        print("       处理：把 NSStatusItem Preferred Position 调小，或点开折叠箭头后 ⌘ 拖到可见区。")
    }
}

if !found {
    print("    ⚠️ 菜单栏层里没有指数条的状态项")
    exit(1)
}
