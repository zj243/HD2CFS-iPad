//
// DatabaseUpdater.swift
// 战备库更新编排（M3）：index.json → 数据库 dump → 整表重建 → 逐个下载图标
// 流程与状态语义对照安卓版 SettingsFragment 数据库更新逻辑
// 作者: ZJ
//

import Foundation

/// 更新过程事件，供设置页进度对话框展示（双进度：文件计数 + 单文件字节）
enum DatabaseUpdateEvent {
    case fetchingIndex
    case fetchingDatabase(displayName: String)
    case downloadingIcon(current: Int, total: Int, fileName: String)
    case iconProgress(downloaded: Int64, total: Int64)
    case finished(version: String)
}

final class DatabaseUpdater {
    private let fetcher: RemoteFetcher
    private let database: AppDatabase
    private let settings: AppSettings

    init(
        fetcher: RemoteFetcher = DownloadManager(),
        database: AppDatabase = .shared,
        settings: AppSettings = .shared
    ) {
        self.fetcher = fetcher
        self.database = database
        self.settings = settings
    }

    /// 执行完整更新流程，返回新版本号（index 的 date 字段）。
    /// 版本号语义与安卓版一致："0" 仅内置种子、"1" 更新中/不完整、其余为完成时的 date——
    /// 中途失败或取消会停留在 "1"，界面据此提示"数据库不完整"引导重新更新。
    /// 通过取消调用方 Task 可中止流程；图标逐个下载、已存在的文件跳过，重试时天然断点续传
    @discardableResult
    func update(channel: Int, onEvent: @escaping (DatabaseUpdateEvent) -> Void = { _ in }) async throws -> String {
        // 频道解析：0 HD2 / 1 HD1 / 2 自定义 URL
        let rawUrl: String
        switch channel {
        case 1: rawUrl = CFSConstants.urlDbHD
        case 2: rawUrl = settings.dbCustomURL
        default: rawUrl = CFSConstants.urlDbHD2
        }
        guard !rawUrl.isEmpty else {
            throw DownloadError.invalidURL(rawUrl)
        }
        let parts = try RemoteDatabase.parseUrl(rawUrl)
        guard let indexURL = URL(string: parts.directory + parts.fileName) else {
            throw DownloadError.invalidURL(parts.directory + parts.fileName)
        }
        settings.dbChannel = channel

        // 下载并解析 index.json
        onEvent(.fetchingIndex)
        let indexText = try await fetcher.fetchString(indexURL)
        let index = try RemoteDatabase.parseIndex(Data(indexText.utf8))

        // 进入更新态：版本号先置 "1" 标记不完整，写入库标识与显示名
        settings.dbVersion = "1"
        settings.dbName = index.name
        settings.dbNameEn = index.nameEn
        settings.dbNameZh = index.nameZh

        // 下载数据库 dump 并整表重建
        let prefersChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        onEvent(.fetchingDatabase(displayName: prefersChinese ? index.nameZh : index.nameEn))
        guard let dbURL = URL(string: parts.directory + index.dbPath) else {
            throw DownloadError.invalidURL(parts.directory + index.dbPath)
        }
        let dumpText = try await fetcher.fetchString(dbURL)
        let content = try RemoteDatabase.parseDatabaseDump(Data(dumpText.utf8))
        try database.stratagemStore.replaceAll(content.stratagems)

        // 逐个下载 SVG 图标到 icons/<dbName>/，已存在的跳过（重试即断点续传）
        let iconsDirectory = database.iconsDirectory(dbName: index.name)
        let total = content.icons.count
        for (position, icon) in content.icons.enumerated() {
            try Task.checkCancellation()
            onEvent(.downloadingIcon(current: position + 1, total: total, fileName: icon + ".svg"))
            let destination = iconsDirectory.appendingPathComponent(icon + ".svg")
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }
            let iconAddress = parts.directory + index.iconsPath + icon + ".svg"
            guard let iconURL = URL(string: iconAddress) else {
                throw DownloadError.invalidURL(iconAddress)
            }
            try await fetcher.downloadFile(iconURL, to: destination) { downloaded, totalBytes in
                onEvent(.iconProgress(downloaded: downloaded, total: totalBytes))
            }
        }

        // 全部完成才写入正式版本号（对应安卓版在最后一个图标 onComplete 里写 date）
        settings.dbVersion = index.date
        onEvent(.finished(version: index.date))
        return index.date
    }

    /// 清除缓存（M6 设置页调用）：删除全部图标目录、清空战备表、版本号回退 "0"。
    /// 调用方需同时清空 StratagemIconCache 内存缓存
    func clearCache() throws {
        let iconsRoot = database.directory.appendingPathComponent("icons", isDirectory: true)
        if FileManager.default.fileExists(atPath: iconsRoot.path) {
            try FileManager.default.removeItem(at: iconsRoot)
        }
        try database.stratagemStore.replaceAll([])
        settings.dbVersion = "0"
    }
}
