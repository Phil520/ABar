# legacy · 早期版本

这里放的是已经不参与构建的旧代码，保留只为留个对照。

## v1 · 多文件实现

`src/` 曾经是这一版：拆成 `Quote` / `QuoteService` / `TradingClock` / `MenuBarUI` /
`DetailPanel` / `FloatingBar` / `Prefs` / `LoginItem` 八个文件，编译打包都正常，进程也跑得起来，
**但状态项就是不在菜单栏显示**。

排查到最后确认：包和配置都是干净的——把一段独立写的探针二进制塞进同样的 `.app` 包里，
六个状态项全部正常上屏；换成这套二进制，一个都不出现。

于是放弃修补，改成单文件重写（现在的 `src/main.swift`），一次就上屏了。
v1 也在运行时段、休眠、自检这些方面都没有实现。

`tests/` 是 v1 的断言测试，依赖已删除的类型，跟着一起停用。
现在的验收方式是 `tools/menubarcheck.swift`（查窗口服务器里有没有这块窗口）
和 `--session-check`（查时段判定）。

具体排查过程和结论见 `docs/开发笔记.md`。
