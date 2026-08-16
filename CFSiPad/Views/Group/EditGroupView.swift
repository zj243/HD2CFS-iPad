//
// EditGroupView.swift
// 新建/编辑编组（M4），对应安卓版 EditGroupFragment
// 作者: ZJ
//

import SwiftUI

struct EditGroupView: View {
    /// nil 表示新建
    let editing: StratagemGroup?
    var onSaved: () -> Void

    private let settings = AppSettings.shared

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedIds: [Int]
    @State private var allStratagems: [Stratagem] = []
    @State private var errorMessage: String?

    init(editing: StratagemGroup?, onSaved: @escaping () -> Void) {
        self.editing = editing
        self.onSaved = onSaved
        _title = State(initialValue: editing?.title ?? "")
        // 新建时默认勾选 id 1/2/3（增援、求救信标、补给），与安卓版一致
        _selectedIds = State(initialValue: editing?.list ?? [1, 2, 3])
    }

    private var stratagemsById: [Int: Stratagem] {
        Dictionary(uniqueKeysWithValues: allStratagems.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("编组名称") {
                    TextField("新编组", text: $title)
                }

                Section("已选战备（点击右上角「编辑」可拖动排序）") {
                    if selectedIds.isEmpty {
                        Text("尚未选择战备")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(selectedIds, id: \.self) { stratagemId in
                        selectedRow(stratagemId)
                    }
                    .onMove { source, destination in
                        selectedIds.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        selectedIds.remove(atOffsets: offsets)
                    }
                }

                Section("全部战备（点击选择 / 取消）") {
                    ForEach(allStratagems) { stratagem in
                        toggleRow(stratagem)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新建编组" : "编辑编组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(selectedIds.isEmpty)
                }
            }
            .onAppear(perform: load)
            .errorAlert($errorMessage)
        }
    }

    private func selectedRow(_ stratagemId: Int) -> some View {
        HStack(spacing: 12) {
            if let stratagem = stratagemsById[stratagemId] {
                StratagemIconView(icon: stratagem.icon, dbName: settings.dbName)
                    .frame(width: 32, height: 32)
                Text(stratagem.displayName(lang: settings.ctrlLang))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                Text("未知 [\(stratagemId)]")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleRow(_ stratagem: Stratagem) -> some View {
        Button {
            toggle(stratagem.id)
        } label: {
            HStack(spacing: 12) {
                StratagemIconView(icon: stratagem.icon, dbName: settings.dbName)
                    .frame(width: 32, height: 32)
                Text(stratagem.displayName(lang: settings.ctrlLang))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedIds.contains(stratagem.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// 勾选/取消：新选中的追加到已选末尾（顺序即 Play 页展示顺序）
    private func toggle(_ stratagemId: Int) {
        if selectedIds.contains(stratagemId) {
            selectedIds.removeAll { $0 == stratagemId }
        } else {
            selectedIds.append(stratagemId)
        }
    }

    private func load() {
        do {
            allStratagems = try AppDatabase.shared.stratagemStore.fetchAll()
        } catch {
            errorMessage = "读取战备列表失败：\(error.localizedDescription)"
        }
    }

    /// 保存：组名留空用默认名；dbName 写入当前战备库标识（与安卓版一致）
    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "新编组" : trimmedTitle
        do {
            if var group = editing {
                group.title = finalTitle
                group.list = selectedIds
                group.dbName = settings.dbName
                try AppDatabase.shared.groupStore.update(group)
            } else {
                try AppDatabase.shared.groupStore.insert(
                    StratagemGroup(title: finalTitle, list: selectedIds, dbName: settings.dbName)
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = "保存编组失败：\(error.localizedDescription)"
        }
    }
}
