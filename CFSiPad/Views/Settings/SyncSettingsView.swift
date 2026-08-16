//
// SyncSettingsView.swift
// 服务器配置同步子页（M6）：编辑 opt=4 的完整配置并推送到服务器
// 对应安卓版 SettingsFragment 同步区 + SettingsSyncFragment 高级区。
// AppSettings 非可观察对象，界面用本地表单状态镜像，变更即写回持久化
// 作者: ZJ
//

import SwiftUI

struct SyncSettingsView: View {
    private let settings = AppSettings.shared

    /// 表单镜像：初值来自 AppSettings，控件变更同步写回
    private struct FormState {
        var portText = ""
        var listenIP = ""
        var delay = 25
        var openKey = "ctrl_left"
        var openType = "hold"
        var upKey = "w"
        var downKey = "s"
        var leftKey = "a"
        var rightKey = "d"
        var authEnabled = true
        var authTimeout = 3
        var debug = false
        var loaded = false
    }

    @State private var form = FormState()
    @State private var isPushing = false
    @State private var pushResult: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("端口（默认 23333）", text: $form.portText)
                    .keyboardType(.numberPad)
                TextField("监听地址（留空自动获取）", text: $form.listenIP)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("服务器")
            } footer: {
                Text("修改端口后服务器会用新端口重新监听，连接设置里的端口需同步修改。")
            }

            Section("按键映射") {
                Stepper(value: binding(\.delay) { settings.syncInputDelay = $0 }, in: 5...200, step: 5) {
                    LabeledContent("按键延迟", value: "\(form.delay) 毫秒")
                }
                keyPicker("打开战备列表", binding: binding(\.openKey) { settings.syncInputOpen = $0 })
                Picker("按法", selection: binding(\.openType) { settings.syncInputOpenType = $0 }) {
                    ForEach(KeyValues.keyTypes) { option in
                        Text(option.display).tag(option.value)
                    }
                }
                keyPicker("上", binding: binding(\.upKey) { settings.syncInputUp = $0 })
                keyPicker("下", binding: binding(\.downKey) { settings.syncInputDown = $0 })
                keyPicker("左", binding: binding(\.leftKey) { settings.syncInputLeft = $0 })
                keyPicker("右", binding: binding(\.rightKey) { settings.syncInputRight = $0 })
            }

            Section {
                Toggle("启用认证", isOn: binding(\.authEnabled) { settings.syncAuthEnabled = $0 })
                Stepper(value: binding(\.authTimeout) { settings.syncAuthTimeout = $0 }, in: 1...30) {
                    LabeledContent("认证有效期", value: "\(form.authTimeout) 天")
                }
                Toggle("服务器调试模式", isOn: binding(\.debug) { settings.syncDebug = $0 })
            } header: {
                Text("认证")
            } footer: {
                Text("认证有效期内同一设备重连无需再到电脑端确认。")
            }

            Section {
                Button(action: pushConfig) {
                    if isPushing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在连接并发送…（认证时请到电脑端按 Y）")
                                .font(.footnote)
                        }
                    } else {
                        Label("应用配置到服务器", systemImage: "arrow.up.doc")
                    }
                }
                .disabled(isPushing)
            } footer: {
                Text("配置整包发送（opt=4），服务器端需按 Y 确认后生效。")
            }
        }
        .navigationTitle("服务器配置同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadForm)
        .onDisappear(perform: saveTextFields)
        .alert("配置同步", isPresented: Binding(
            get: { pushResult != nil },
            set: { isPresented in
                if !isPresented {
                    pushResult = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(pushResult ?? "")
        }
        .errorAlert($errorMessage)
    }

    /// 键位选择（键值较多，用导航式 Picker）
    private func keyPicker(_ title: String, binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(KeyValues.keys) { option in
                Text(option.display).tag(option.value)
            }
        }
        .pickerStyle(.navigationLink)
    }

    /// 表单绑定：改本地镜像的同时写回 AppSettings
    private func binding<T>(
        _ keyPath: WritableKeyPath<FormState, T>,
        apply: @escaping (T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { form[keyPath: keyPath] },
            set: { newValue in
                form[keyPath: keyPath] = newValue
                apply(newValue)
            }
        )
    }

    private func loadForm() {
        guard !form.loaded else { return } // 从键位子页返回时不重置
        form = FormState(
            portText: String(settings.syncServerPort),
            listenIP: settings.syncServerIp,
            delay: settings.syncInputDelay,
            openKey: settings.syncInputOpen,
            openType: settings.syncInputOpenType,
            upKey: settings.syncInputUp,
            downKey: settings.syncInputDown,
            leftKey: settings.syncInputLeft,
            rightKey: settings.syncInputRight,
            authEnabled: settings.syncAuthEnabled,
            authTimeout: settings.syncAuthTimeout,
            debug: settings.syncDebug,
            loaded: true
        )
    }

    /// 校验并写回文本字段；端口非法时保留原值并回弹显示
    private func saveTextFields() {
        settings.syncServerIp = form.listenIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(form.portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) {
            settings.syncServerPort = port
        } else {
            form.portText = String(settings.syncServerPort)
        }
    }

    /// 连接 + 认证 + 整包推送配置
    private func pushConfig() {
        saveTextFields()
        guard let port = UInt16(exactly: settings.connPort) else {
            errorMessage = "连接端口无效：\(settings.connPort)，请回连接设置修正"
            return
        }
        isPushing = true
        let address = settings.connAddress
        let sid = AppClient.loadOrCreateSid()
        let config = settings.syncConfigData()
        Task {
            let result = await ConnectionTester.run(
                address: address,
                port: port,
                sid: sid,
                pushConfig: config
            )
            await MainActor.run {
                isPushing = false
                pushResult = result
            }
        }
    }
}
