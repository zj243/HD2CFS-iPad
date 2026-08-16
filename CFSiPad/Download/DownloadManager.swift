//
// DownloadManager.swift
// 网络下载（M3）：URLSession 实现的文本与文件下载
// 文件下载行为对照安卓版 DownloadService：先写 .download 临时文件、完成后改名，进度回调节流 200ms
// 作者: ZJ
//

import Foundation

/// 远程获取接口。DatabaseUpdater 依赖此协议而非具体实现，单元测试注入假实现即可覆盖完整更新流程
protocol RemoteFetcher {
    /// 下载文本内容（index.json / 数据库 dump）
    func fetchString(_ url: URL) async throws -> String

    /// 下载文件到指定路径。progress 参数为（已下载字节，总字节；总长未知时为 -1）
    func downloadFile(_ url: URL, to destination: URL, progress: @escaping (Int64, Int64) -> Void) async throws
}

/// URLSession 实现
final class DownloadManager: RemoteFetcher {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchString(_ url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw DownloadError.emptyBody
        }
        return text
    }

    /// 流式下载到 <destination>.download 临时文件，完成后改名为正式文件；
    /// 中途失败或取消时留下的临时文件会在下次下载同一目标前被清理
    func downloadFile(_ url: URL, to destination: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = destination.appendingPathExtension("download")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }

        let (bytes, response) = try await session.bytes(from: url)
        try Self.checkStatus(response)
        let totalLength = response.expectedContentLength // 未知时为 -1，与安卓版语义一致

        fileManager.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        // 按 64KB 缓冲落盘，进度回调节流 200ms（末尾必回调一次）
        var buffer = Data(capacity: 64 * 1024)
        var downloaded: Int64 = 0
        var lastReportTime = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReportTime) >= 0.2 {
                    progress(downloaded, totalLength)
                    lastReportTime = now
                }
            }
            try Task.checkCancellation()
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }
        try handle.close()
        progress(downloaded, totalLength)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.httpStatus(http.statusCode)
        }
    }
}
