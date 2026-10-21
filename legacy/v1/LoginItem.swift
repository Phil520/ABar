import Foundation

/// 开机自启：写一个 LaunchAgent，登录时拉起 App 里的可执行文件。
///
/// 踩过的坑（project028）：「直接指向 .app 目录」会让 launchd 报 EX_CONFIG(78)，
/// 必须指向 App 内部的 Contents/MacOS/<可执行文件>。
enum LoginItem {

    static let label = "com.bean.index-bar-menubar.autostart"

    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    static var executablePath: String {
        Bundle.main.executablePath ?? (Bundle.main.bundlePath + "/Contents/MacOS/IndexBar")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// 返回 nil 表示成功，否则是一句人话的失败原因
    @discardableResult
    static func enable() -> String? {
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,           // 用户手动退出后别再拉起来
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": "/tmp/index-bar.out.log",
            "StandardErrorPath": "/tmp/index-bar.err.log",
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath))
        } catch {
            return "写 LaunchAgent 失败：\(error.localizedDescription)"
        }

        // 已加载过就先卸掉，否则 bootstrap 会报 Input/output error
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
        if run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == 0 {
            return nil
        }
        return "launchctl 未能加载，可在「系统设置 › 通用 › 登录项」里手动添加"
    }

    @discardableResult
    static func disable() -> String? {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        do {
            if FileManager.default.fileExists(atPath: plistPath) {
                try FileManager.default.removeItem(atPath: plistPath)
            }
            return nil
        } catch {
            return "移除 LaunchAgent 失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

/// 单实例保护。菜单栏工具最常见的翻车是「开了两份，两个图标」。
/// 规矩：只删自己那把锁——顺手删别人的会让第三个进程畅通无阻。
enum SingleInstance {

    private static var lockPath: String {
        let base = NSHomeDirectory() + "/Library/Application Support/IndexBar"
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base + "/instance.pid"
    }

    static func claim() -> Bool {
        if let text = try? String(contentsOfFile: lockPath, encoding: .utf8),
           let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid != getpid(), kill(pid, 0) == 0 {
            return false
        }
        try? String(getpid()).write(toFile: lockPath, atomically: true, encoding: .utf8)
        return true
    }

    static func release() {
        guard let text = try? String(contentsOfFile: lockPath, encoding: .utf8),
              pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) == getpid() else { return }
        try? FileManager.default.removeItem(atPath: lockPath)
    }
}
