import Cocoa

/// 显示模式：菜单栏状态项，或右上角悬浮窗（状态项排不上位时的降级方案）
enum DisplayMode: String {
    case menuBar
    case floating
}

enum Prefs {
    private static let modeKey = "displayMode"

    static var current: DisplayMode {
        get { DisplayMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .menuBar }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }
}

/// 重启自己：先把单实例锁放掉，再拉一份新进程，然后退出。
/// 不这么做的话新进程会被自己的锁挡在门外。
func relaunchApp() {
    SingleInstance.release()
    if let path = Bundle.main.executablePath {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        try? p.run()
    }
    NSApp.terminate(nil)
}
