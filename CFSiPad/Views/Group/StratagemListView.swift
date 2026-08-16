//
// StratagemListView.swift
// 战备总表（M4），对应安卓版 StratagemsListFragment（已按决策去掉语音关键词编辑）
// 作者: ZJ
//

import SwiftUI

struct StratagemListView: View {
    private let settings = AppSettings.shared

    @State private var stratagems: [Stratagem] = []
    @State private var selectedInfo: Stratagem?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(stratagems) { stratagem in
                    Button {
                        selectedInfo = stratagem
                    } label: {
                        StratagemCell(stratagem: stratagem, dbName: settings.dbName, lang: settings.ctrlLang)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(settings.dbDisplayName)
        .onAppear(perform: reload)
        .sheet(item: $selectedInfo) { stratagem in
            StratagemInfoSheet(stratagem: stratagem, dbName: settings.dbName, lang: settings.ctrlLang)
        }
        .errorAlert($errorMessage)
    }

    private func reload() {
        do {
            stratagems = try AppDatabase.shared.stratagemStore.fetchAll()
        } catch {
            errorMessage = "读取战备列表失败：\(error.localizedDescription)"
        }
    }
}
