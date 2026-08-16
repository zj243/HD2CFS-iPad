//
// PlayPlaceholderView.swift
// Play 面板占位（M4 临时）：M5 完成后由正式游玩界面整体替换
// 作者: ZJ
//

import SwiftUI

struct PlayPlaceholderView: View {
    let group: StratagemGroup

    var body: some View {
        ContentUnavailableView {
            Label("Play 面板尚未就绪", systemImage: "gamecontroller")
        } description: {
            Text("编组「\(group.title)」共 \(group.list.count) 个战备。游玩界面将在 M5 实现。")
        }
        .navigationTitle(group.title)
    }
}
