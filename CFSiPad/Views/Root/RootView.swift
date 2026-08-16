//
// RootView.swift
// 编组列表首页（M4），对应安卓版 RootFragment
// 作者: ZJ
//

import SwiftUI

/// 根导航路由
enum RootRoute: Hashable {
    case browse(StratagemGroup)
    case play(StratagemGroup)
    case stratagemList
}

struct RootView: View {
    private let settings = AppSettings.shared

    @State private var navigationPath = NavigationPath()
    @State private var groups: [StratagemGroup] = []
    @State private var stratagemsById: [Int: Stratagem] = [:]
    @State private var isCreating = false
    @State private var editingGroup: StratagemGroup?
    @State private var pendingDelete: StratagemGroup?
    @State private var showDeleteConfirm = false
    @State private var showSettings = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            listContent
                .navigationTitle("战备编组")
                // 挂在栈内内容上：从子页返回时重新加载，删除/编辑立即反映到列表
                .onAppear(perform: reload)
                .navigationDestination(for: RootRoute.self) { route in
                    switch route {
                    case .browse(let group):
                        GroupView(groupId: group.id ?? -1)
                    case .play(let group):
                        PlayView(group: group)
                    case .stratagemList:
                        StratagemListView()
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        EditButton()
                        NavigationLink(value: RootRoute.stratagemList) {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        Button {
                            isCreating = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        }
        .sheet(isPresented: $isCreating) {
            EditGroupView(editing: nil, onSaved: reload)
        }
        .sheet(item: $editingGroup) { group in
            EditGroupView(editing: group, onSaved: reload)
        }
        .sheet(isPresented: $showSettings, onDismiss: reload) {
            SettingsView()
        }
        .confirmationDialog("删除编组", isPresented: $showDeleteConfirm, presenting: pendingDelete) { group in
            Button("删除「\(group.title)」", role: .destructive) {
                delete(group)
            }
        } message: { _ in
            Text("删除后无法恢复。")
        }
        .errorAlert($errorMessage)
    }

    // MARK: - 列表内容

    @ViewBuilder
    private var listContent: some View {
        if groups.isEmpty {
            ContentUnavailableView {
                Label("还没有编组", systemImage: "square.grid.2x2")
            } description: {
                Text(databaseHint ?? "点击右上角 + 新建一个战备编组")
            } actions: {
                Button("新建编组") {
                    isCreating = true
                }
            }
        } else {
            List {
                if let hint = databaseHint {
                    Section {
                        Label(hint, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    ForEach(groups) { group in
                        groupRow(group)
                    }
                    .onMove(perform: moveGroups)
                }
            }
        }
    }

    /// 战备数据库状态提示："0" 仅内置种子（无图标），"1" 上次更新未完成
    private var databaseHint: String? {
        switch settings.dbVersion {
        case "0":
            return "战备数据库尚未下载，图标暂以占位符显示，可稍后在设置中更新"
        case "1":
            return "上次数据库更新未完成，请在设置中重新更新"
        default:
            return nil
        }
    }

    /// 编组行：标题 + 图标缩略行 + 溢出计数；fastboot 开启时点击直接进 Play
    private func groupRow(_ group: StratagemGroup) -> some View {
        NavigationLink(value: settings.ctrlFastboot ? RootRoute.play(group) : RootRoute.browse(group)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(group.list.prefix(6), id: \.self) { stratagemId in
                        thumbnail(stratagemId)
                    }
                    if group.list.count > 6 {
                        Text("+\(group.list.count - 6)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button {
                navigationPath.append(RootRoute.browse(group))
            } label: {
                Label("浏览", systemImage: "square.grid.2x2")
            }
            Button {
                navigationPath.append(RootRoute.play(group))
            } label: {
                Label("游玩", systemImage: "play")
            }
            Button {
                editingGroup = group
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = group
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ stratagemId: Int) -> some View {
        if let stratagem = stratagemsById[stratagemId] {
            StratagemIconView(icon: stratagem.icon, dbName: settings.dbName)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - 数据操作

    private func reload() {
        do {
            groups = try AppDatabase.shared.groupStore.fetchAllOrdered()
            let all = try AppDatabase.shared.stratagemStore.fetchAll()
            stratagemsById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        } catch {
            errorMessage = "读取编组数据失败：\(error.localizedDescription)"
        }
    }

    /// 拖拽排序（编辑模式下），移动后立即按新顺序落库
    private func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        do {
            try AppDatabase.shared.groupStore.saveOrder(ids: groups.compactMap(\.id))
        } catch {
            errorMessage = "保存排序失败：\(error.localizedDescription)"
            reload()
        }
    }

    private func delete(_ group: StratagemGroup) {
        guard let id = group.id else { return }
        do {
            try AppDatabase.shared.groupStore.delete(id: id)
            reload()
        } catch {
            errorMessage = "删除编组失败：\(error.localizedDescription)"
        }
    }
}
