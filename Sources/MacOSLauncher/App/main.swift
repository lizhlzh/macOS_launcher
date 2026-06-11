import AppKit

// 进程入口调用方向：
// 可执行文件 -> NSApplication -> AppDelegate -> AppLifecycleCoordinator。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
