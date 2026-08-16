//
// StratagemIconView.swift
// 战备图标渲染（M3，M4 真机验收后修订）：SwiftDraw 光栅化本地 SVG + 内存缓存
// 图标文件由 DatabaseUpdater 下载到 icons/<dbName>/<icon>.svg
// 作者: ZJ
//

import SwiftUI
import SwiftDraw

/// 战备图标内存缓存：首次访问时从本地 SVG 文件光栅化，NSCache 自动响应内存压力回收。
/// 图标为几 KB 的小文件，同步光栅化耗时可忽略（安卓版同样在列表绑定时同步渲染）
final class StratagemIconCache {
    static let shared = StratagemIconCache()

    private let cache = NSCache<NSString, UIImage>()

    /// 取图标位图；本地文件缺失或解析失败返回 nil，由视图层显示占位符
    func image(icon: String, dbName: String) -> UIImage? {
        let key = "\(dbName)/\(icon)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let fileURL = AppDatabase.shared
            .iconsDirectory(dbName: dbName)
            .appendingPathComponent(icon + ".svg")
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let svg = loadSVG(at: fileURL) else {
            return nil
        }
        let image = svg.rasterize()
        cache.setObject(image, forKey: key)
        return image
    }

    /// 清空缓存（清除数据库缓存或更新完成后调用，强制重新读盘）
    func clear() {
        cache.removeAllObjects()
    }

    /// 加载 SVG，必要时先做兼容性修补：
    /// 部分图标（如 hmg_emplacement）用 SVG2 的 <use href="#id"> 写法，SwiftDraw 解析失败，
    /// 改写为 xlink:href 后可正常渲染。修补结果写回原文件（幂等；重新下载覆盖后会再次修补）
    private func loadSVG(at fileURL: URL) -> SVG? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return SVG(fileURL: fileURL)
        }
        let patched = Self.patchUseHref(raw)
        if patched == raw {
            return SVG(fileURL: fileURL)
        }
        if (try? patched.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
            return SVG(fileURL: fileURL)
        }
        // 写回失败（磁盘异常等）：落到临时文件渲染，保证本次仍可显示
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".svg")
        guard (try? patched.write(to: tempURL, atomically: true, encoding: .utf8)) != nil else {
            return SVG(fileURL: fileURL)
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return SVG(fileURL: tempURL)
    }

    /// 把 <use href="..."> 改写为 <use xlink:href="...">，并补齐 xlink 命名空间声明。
    /// 已是 xlink 写法或不含 <use> 的文件原样返回
    static func patchUseHref(_ svgText: String) -> String {
        guard svgText.contains("<use"),
              svgText.contains(" href="),
              !svgText.contains("xlink:href") else {
            return svgText
        }
        var patched = svgText.replacingOccurrences(of: " href=", with: " xlink:href=")
        if !patched.contains("xmlns:xlink") {
            patched = patched.replacingOccurrences(
                of: "<svg ",
                with: "<svg xmlns:xlink=\"http://www.w3.org/1999/xlink\" "
            )
        }
        return patched
    }
}

/// 战备图标视图。
/// 图标主体多为纯白（fill="#fff"，原设计面向深色界面），必须垫深色底板才可见——
/// 这也还原了原 App 的军事风视觉；图标缺失时在同一底板上显示问号占位
struct StratagemIconView: View {
    /// 图标文件名（不含 .svg 后缀），来自战备表 icon 列
    let icon: String
    /// 图标所属战备库标识（icons 子目录名）
    let dbName: String

    /// 深灰蓝底色，浅色/深色模式统一
    private static let backdrop = Color(red: 0.12, green: 0.13, blue: 0.15)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Self.backdrop)
            if let image = StratagemIconCache.shared.image(icon: icon, dbName: dbName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(10)
            }
        }
    }
}
