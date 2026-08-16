//
// SettingsView.swift
// 设置主页（M6）：连接/测试、配置同步入口、控制、数据库更新、备份、关于
// 对应安卓版 SettingsFragment（ASR 区已按决策砍掉），替换 M4 的临时占位页
// 作者: ZJ
//

import SwiftUI
import UniformTypeIdentifiers

/// 一次性连接器：独立于 Play 页的常驻客户端，走完整"连接 → 状态 → 认证"流程，
/// 用于测试连接与配置推送（对应安卓版设置页复用 AppClient 全流程的行为）
enum ConnectionTester {
    /// 返回面向用户的结果文案；传入 pushConfig 时在认证成功后整包发送配置（opt=4）
    static func run(
        address: String,
        port: UInt16,
        sid: String,
        pushConfig: SyncConfigData? = nil
    ) async -> String {
        let connection = LineFramedConnection()
        defer { connection.close() }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        func send<T: Encodable>(_ packet: T) async throws {
            let data = try encoder.encode(packet)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ConnectionError.sendFailed("报文编码失败")
            }
            try await connection.send(json)
        }

        do {
            try await connection.connect(host: address, port: port, timeout: CFSConstants.defaultTimeout)
            try await send(RequestStatusPacket(api: CFSConstants.apiVersion))
            let status = try decoder.decode(
                ReceiveStatusData.self,
                from: Data(try await connection.receiveMessage().utf8)
            )
            guard status.api == CFSConstants.apiVersion else {
                return "服务器协议版本不匹配（服务器 api \(status.api)，客户端 api \(CFSConstants.apiVersion)）。"
            }
            guard status.status == 0 || status.status == 2 else {
                return "服务器状态异常（status \(status.status)）。"
            }
            // 统一走认证换取本连接令牌；新 sid 需在电脑端按 Y 确认（期间关闭读超时）
            try await send(RequestAuthPacket(sid: sid))
            connection.setReadTimeoutEnabled(false)
            let auth = try decoder.decode(
                ReceiveAuthData.self,
                from: Data(try await connection.receiveMessage().utf8)
            )
            connection.setReadTimeoutEnabled(true)
            guard auth.auth else {
                return "认证被拒绝：请在电脑端按 Y 确认后重试。"
            }
            if let config = pushConfig {
                try await send(RequestSyncPacket(config: config, token: auth.token))
                // 配置包无回包；稍等片刻保证发出后再断开
                try? await Task.sleep(for: .milliseconds(500))
                return "配置已发送。请到电脑端按 Y 确认应用（整包替换服务器配置）。"
            }
            return "连接并认证成功。"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }
}

/// 备份文件文档（导出用）
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    private let settings = AppSettings.shared

    @Environment(\.dismiss) private var dismiss

    /// 表单镜像（AppSettings 非可观察对象），变更即写回
    private struct FormState {
        var address = ""
        var portText = ""
        var retry = 5
        var simplified = false
        var iconSize = 100
        var fastboot = false
        var sfx = false
        var sdt = 100
        var svt = 50
        var lang = "auto"
        var dbChannel = 0
        var dbCustom = ""
    }

    @State private var form = FormState()
    @State private var isFormLoaded = false

    // 连接测试与扫码
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showScanner = false

    // 数据库更新进度
    @State private var showUpdateSheet = false
    @State private var updatePhase = ""
    @State private var updateCurrent = 0
    @State private var updateTotal = 0
    @State private var updateFile = ""
    @State private var updateVersion = ""
    @State private var updateFinished = false
    @State private var updateFailed: String?
    @State private var updateTask: Task<Void, Never>?
    @State private var showClearConfirm = false

    // 备份
    @State private var showExporter = false
    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false

    @State private var infoMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                Section("服务器配置") {
                    NavigationLink("服务器配置同步") {
                        SyncSettingsView()
                    }
                }
                controlSection
                databaseSection
                backupSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard saveConnectionFields() else { return }
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { infoMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        infoMessage = nil
                    }
                }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
        }
        .onAppear(perform: loadForm)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet(onResult: handleScannedCode)
        }
        .sheet(isPresented: $showUpdateSheet) {
            updateSheet
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "cfs_backup"
        ) { result in
            switch result {
            case .success:
                infoMessage = "备份已导出（与安卓版 cfs_backup.json 互通）。"
            case .failure(let error):
                errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                errorMessage = "选择文件失败：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("清除数据库缓存", isPresented: $showClearConfirm) {
            Button("清除图标与战备数据", role: .destructive, action: clearCache)
        } message: {
            Text("将删除已下载的全部图标并清空战备表，需重新更新数据库。编组不受影响。")
        }
        .errorAlert($errorMessage)
    }

    // MARK: - 分区

    private var connectionSection: some View {
        Section {
            TextField("服务器地址（PC 局域网 IP）", text: $form.address)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("端口（默认 23333）", text: $form.portText)
                .keyboardType(.numberPad)
            Stepper(value: binding(\.retry) { settings.connRetry = $0 }, in: 0...10) {
                LabeledContent("断线重试次数", value: "\(form.retry)")
            }
            Button {
                showScanner = true
            } label: {
                Label("扫描服务器二维码", systemImage: "qrcode.viewfinder")
            }
            Button(action: testConnection) {
                if isTesting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("测试中…（认证时请到电脑端按 Y）")
                            .font(.footnote)
                    }
                } else {
                    Label("测试连接", systemImage: "bolt.horizontal")
                }
            }
            .disabled(isTesting)
            .alert("测试结果", isPresented: Binding(
                get: { testResult != nil },
                set: { isPresented in
                    if !isPresented {
                        testResult = nil
                    }
                }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(testResult ?? "")
            }
        } header: {
            Text("连接")
        } footer: {
            Text("二维码由 PC 端服务器启动时在控制台打印。")
        }
    }

    private var controlSection: some View {
        Section("控制") {
            Toggle("简化模式（游玩页仅网格点击呼叫）", isOn: binding(\.simplified) { settings.ctrlSimplified = $0 })
            Stepper(value: binding(\.iconSize) { settings.ctrlStratagemSize = $0 }, in: 60...200, step: 10) {
                LabeledContent("简化模式图标尺寸", value: "\(form.iconSize)")
            }
            Toggle("快速启动（点击编组直接进入游玩）", isOn: binding(\.fastboot) { settings.ctrlFastboot = $0 })
            Toggle("音效", isOn: binding(\.sfx) { settings.ctrlSfx = $0 })
            Stepper(value: binding(\.sdt) { settings.ctrlSwipeDistanceThreshold = $0 }, in: 40...300, step: 10) {
                LabeledContent("滑动距离阈值", value: "\(form.sdt)")
            }
            Stepper(value: binding(\.svt) { settings.ctrlSwipeVelocityThreshold = $0 }, in: 0...500, step: 10) {
                LabeledContent("滑动速度阈值", value: "\(form.svt)")
            }
            Picker("战备名语言", selection: binding(\.lang) { settings.ctrlLang = $0 }) {
                Text("跟随系统").tag("auto")
                Text("English").tag("en")
                Text("简体中文").tag("zh-CN")
            }
        }
    }

    private var databaseSection: some View {
        Section {
            Picker("数据源", selection: binding(\.dbChannel) { settings.dbChannel = $0 }) {
                Text("HD2 官方源").tag(0)
                Text("HD1 官方源").tag(1)
                Text("自定义 URL").tag(2)
            }
            if form.dbChannel == 2 {
                TextField("自定义 index.json 地址", text: $form.dbCustom)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            LabeledContent("当前数据库", value: settings.dbDisplayName)
            LabeledContent("版本", value: databaseVersionText)
            Button {
                saveDatabaseFields()
                startDatabaseUpdate()
            } label: {
                Label("更新数据库", systemImage: "arrow.down.circle")
            }
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清除缓存", systemImage: "trash")
            }
        } header: {
            Text("战备数据库")
        } footer: {
            Text("大陆网络访问官方源异常时，可自建镜像并使用自定义 URL。")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("导出备份", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("导入备份", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("备份")
        } footer: {
            Text("备份含连接/同步/控制设置与全部编组，与安卓版 cfs_backup.json 双向互通（语音设置除外）。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("App 版本", value: appVersion)
            if let repoURL = URL(string: "https://github.com/WisteFinch/Helldivers2CallForStratagemsOnPhone") {
                Link("原项目：Helldivers2CallForStratagemsOnPhone", destination: repoURL)
            }
            Text("本 App 为原项目的非官方 iPad 移植（MIT 许可），与 PC 端服务器（API 6）配合使用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// 数据库更新进度弹窗：总进度（文件计数）+ 当前文件名，完成/失败/取消三态收尾
    private var updateSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let failed = updateFailed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(failed)
                        .multilineTextAlignment(.center)
                    Button("关闭") {
                        showUpdateSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                } else if updateFinished {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("更新完成，版本：\(updateVersion)")
                    Button("完成") {
                        showUpdateSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                    Text(updatePhase)
                    if updateTotal > 0 {
                        ProgressView(value: Double(updateCurrent), total: Double(updateTotal))
                            .frame(maxWidth: 360)
                        Text("\(updateCurrent)/\(updateTotal)  \(updateFile)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("取消", role: .destructive) {
                        updateTask?.cancel()
                    }
                }
            }
            .padding(32)
            .navigationTitle("更新战备数据库")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(updateFailed == nil && !updateFinished)
        .presentationDetents([.medium])
    }

    // MARK: - 表单读写

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
        guard !isFormLoaded else { return } // 从子页/弹窗返回时不重置
        isFormLoaded = true
        form = FormState(
            address: settings.connAddress,
            portText: String(settings.connPort),
            retry: settings.connRetry,
            simplified: settings.ctrlSimplified,
            iconSize: settings.ctrlStratagemSize,
            fastboot: settings.ctrlFastboot,
            sfx: settings.ctrlSfx,
            sdt: settings.ctrlSwipeDistanceThreshold,
            svt: settings.ctrlSwipeVelocityThreshold,
            lang: settings.ctrlLang,
            dbChannel: settings.dbChannel,
            dbCustom: settings.dbCustomURL
        )
    }

    /// 校验并保存连接文本字段；端口非法时报错并阻止关闭
    private func saveConnectionFields() -> Bool {
        let trimmedAddress = form.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(form.portText.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port) else {
            errorMessage = "端口号无效：\(form.portText)（应为 1-65535）"
            return false
        }
        settings.connAddress = trimmedAddress.isEmpty ? "127.0.0.1" : trimmedAddress
        settings.connPort = port
        saveDatabaseFields()
        return true
    }

    private func saveDatabaseFields() {
        settings.dbCustomURL = form.dbCustom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var databaseVersionText: String {
        switch settings.dbVersion {
        case "0": return "未下载（仅内置占位数据）"
        case "1": return "不完整（上次更新未完成）"
        default: return settings.dbVersion
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "?"
    }

    // MARK: - 扫码与测试连接

    /// 解析二维码内容 {"add":"IP","port":23333} 并回填连接设置
    private func handleScannedCode(_ code: String) {
        do {
            let address = try JSONDecoder().decode(AddressData.self, from: Data(code.utf8))
            form.address = address.add
            form.portText = String(address.port)
            _ = saveConnectionFields()
            infoMessage = "已填入服务器地址 \(address.add):\(address.port)。"
        } catch {
            errorMessage = "二维码内容无法识别（应为服务器控制台打印的连接码）。"
        }
    }

    private func testConnection() {
        guard saveConnectionFields(), let port = UInt16(exactly: settings.connPort) else { return }
        isTesting = true
        let address = settings.connAddress
        let sid = AppClient.loadOrCreateSid()
        Task {
            let result = await ConnectionTester.run(address: address, port: port, sid: sid)
            await MainActor.run {
                isTesting = false
                testResult = result
            }
        }
    }

    // MARK: - 数据库更新与缓存

    private func startDatabaseUpdate() {
        updatePhase = "正在获取索引…"
        updateCurrent = 0
        updateTotal = 0
        updateFile = ""
        updateFinished = false
        updateFailed = nil
        showUpdateSheet = true
        updateTask = Task {
            do {
                let version = try await DatabaseUpdater().update(channel: settings.dbChannel) { event in
                    Task { @MainActor in
                        switch event {
                        case .fetchingIndex:
                            updatePhase = "正在获取索引…"
                        case .fetchingDatabase(let displayName):
                            updatePhase = "正在下载数据库：\(displayName)"
                        case .downloadingIcon(let current, let total, let fileName):
                            updatePhase = "正在下载图标"
                            updateCurrent = current
                            updateTotal = total
                            updateFile = fileName
                        case .iconProgress:
                            break
                        case .finished:
                            break
                        }
                    }
                }
                await MainActor.run {
                    StratagemIconCache.shared.clear()
                    updateVersion = version
                    updateFinished = true
                }
            } catch is CancellationError {
                await MainActor.run {
                    updateFailed = "已取消。已下载的部分会保留，重试时自动跳过。"
                }
            } catch {
                await MainActor.run {
                    updateFailed = "更新失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func clearCache() {
        do {
            try DatabaseUpdater().clearCache()
            StratagemIconCache.shared.clear()
            infoMessage = "缓存已清除，请重新更新数据库。"
        } catch {
            errorMessage = "清除缓存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 备份

    private func exportBackup() {
        do {
            let groups = try AppDatabase.shared.groupStore.fetchAllOrdered()
            let file = BackupFile.export(settings: settings, groups: groups)
            exportDocument = BackupDocument(data: try file.encodeJSON())
            showExporter = true
        } catch {
            errorMessage = "生成备份失败：\(error.localizedDescription)"
        }
    }

    private func importBackup(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let file = try BackupFile.decode(data)
            try file.apply(settings: settings, groupStore: AppDatabase.shared.groupStore)
            // 设置已被导入覆盖，刷新表单镜像
            isFormLoaded = false
            loadForm()
            infoMessage = "导入成功：设置已应用，追加 \(file.groups.count) 个编组。"
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}
