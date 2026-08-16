//
// GroupView.swift
// 编组浏览页（M4），对应安卓版 ViewGroupFragment
// 作者: ZJ
//

import SwiftUI

struct GroupView: View {
    /// 传编组 id 而非值：编辑保存后 onAppear 重载可拿到最新内容
    let groupId: Int64

    private let settings = AppSettings.shared

    @Environment(\.dismiss) private var dismiss
    @State private var group: StratagemGroup?
    @State private var stratagemsById: [Int: Stratagem] = [:]
    @State private var selectedInfo: Stratagem?
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let group {
                content(group)
            } else {
                ContentUnavailableView("编组不存在", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(group?.title ?? "编组")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("编辑") {
                    isEditing = true
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $isEditing) {
            if let group {
                EditGroupView(editing: group, onSaved: reload)
            }
        }
        .sheet(item: $selectedInfo) { stratagem in
            StratagemInfoSheet(stratagem: stratagem, dbName: settings.dbName, lang: settings.ctrlLang)
        }
        .confirmationDialog("删除编组", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive, action: deleteGroup)
        } message: {
            Text("删除后无法恢复。")
        }
        .errorAlert($errorMessage)
    }

    private func content(_ group: StratagemGroup) -> some View {
        VStack(spacing: 0) {
            // 编组所属战备库与当前库不一致时告警（图标与 id 可能对不上）
            if group.dbName != settings.dbName {
                Label("该编组创建于其他战备数据库（\(group.dbName)），内容可能与当前库不匹配", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.12))
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(group.list, id: \.self) { stratagemId in
                        if let stratagem = stratagemsById[stratagemId] {
                            Button {
                                selectedInfo = stratagem
                            } label: {
                                StratagemCell(stratagem: stratagem, dbName: settings.dbName, lang: settings.ctrlLang)
                            }
                            .buttonStyle(.plain)
                        } else {
                            UnknownStratagemCell(id: stratagemId)
                        }
                    }
                }
                .padding()
            }

            NavigationLink(value: RootRoute.play(group)) {
                Label("开始游玩", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func reload() {
        do {
            group = try AppDatabase.shared.groupStore.fetch(id: groupId)
            let all = try AppDatabase.shared.stratagemStore.fetchAll()
            stratagemsById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        } catch {
            errorMessage = "读取编组失败：\(error.localizedDescription)"
        }
    }

    private func deleteGroup() {
        do {
            try AppDatabase.shared.groupStore.delete(id: groupId)
            dismiss()
        } catch {
            errorMessage = "删除编组失败：\(error.localizedDescription)"
        }
    }
}
