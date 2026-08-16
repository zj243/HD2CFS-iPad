//
// RootPlaceholderView.swift
// M0 占位根视图
// 作者: ZJ
//

import SwiftUI

/// M0 占位根视图：仅用于验证 "CI 云编译出包 → Sideloadly 侧载 → iPad 启动" 整条链路可用，
/// 界面本身无业务功能，M4 完成后由正式根导航替换。
struct RootPlaceholderView: View {
    /// 展示用版本号，从 Info.plist 读取；读取失败时显示占位符而非中断启动
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (version ?? "?")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("↑ ↓ ← →")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("CFS iPad")
                .font(.largeTitle.bold())
            Text("工程骨架已就绪（M0），等待后续模块。")
                .foregroundStyle(.secondary)
            Text(versionText)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootPlaceholderView()
}
