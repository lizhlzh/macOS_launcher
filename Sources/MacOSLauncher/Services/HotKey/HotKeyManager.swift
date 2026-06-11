import Carbon
import Foundation

/// 持有一个 Carbon 全局快捷键及其事件处理器。
///
/// 调用方向：
/// `AppLifecycleCoordinator` -> `HotKeyManager` -> Carbon 回调
/// -> 主线程 -> 协调器提供的动作闭包。
final class HotKeyManager: @unchecked Sendable {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: EventHandlerUPP?

    /// 创建全局快捷键管理器。
    ///
    /// - Parameters:
    ///   - keyCode: Carbon 虚拟按键码。
    ///   - modifiers: Carbon 修饰键位掩码。
    ///   - handler: 快捷键触发后在主线程执行的动作。
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    /// 替换已有注册，并检查每个 Carbon API 的状态码。
    ///
    /// - Throws: 安装事件处理器或注册快捷键失败时抛出 `HotKeyRegistrationError`。
    func register() throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        callback = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let manager = Unmanaged<HotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                manager.handler()
            }

            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            eventHandler = nil
            throw HotKeyRegistrationError.failedToInstallEventHandler(status: handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4C4E43), id: 1)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            hotKeyRef = nil
            throw HotKeyRegistrationError.failedToRegisterHotKey(status: registrationStatus)
        }
    }

    /// 注销快捷键和事件处理器；清理失败只写入日志。
    func unregister() {
        if let hotKeyRef {
            let status = UnregisterEventHotKey(hotKeyRef)
            if status != noErr {
                LumaEventLog.shared.write(
                    "hotkey.unregister.failed",
                    HotKeyRegistrationError.failedToUnregister(status: status).localizedDescription
                )
            }
            self.hotKeyRef = nil
        }

        if let eventHandler {
            let status = RemoveEventHandler(eventHandler)
            if status != noErr {
                LumaEventLog.shared.write(
                    "hotkey.handler.remove.failed",
                    "OSStatus \(status)"
                )
            }
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
