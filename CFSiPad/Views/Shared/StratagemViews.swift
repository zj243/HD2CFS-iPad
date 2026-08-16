//
// StratagemViews.swift
// 共享小组件（M4）：步骤箭头、战备网格单元、战备详情弹窗、统一错误弹窗
// 作者: ZJ
//

import SwiftUI

/// 呼叫步骤箭头序列（1上 2下 3左 4右，未知值显示问号）
struct StepArrowsView: View {
    let steps: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                Image(systemName: Self.symbol(for: step))
            }
        }
    }

    static func symbol(for step: Int) -> String {
        switch step {
        case 1: return "arrow.up"
        case 2: return "arrow.down"
        case 3: return "arrow.left"
        case 4: return "arrow.right"
        default: return "questionmark"
        }
    }
}

/// 战备网格单元：图标 + 名称，可带选中态（编辑编组时用）
struct StratagemCell: View {
    let stratagem: Stratagem
    let dbName: String
    let lang: String
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            StratagemIconView(icon: stratagem.icon, dbName: dbName)
                .frame(width: 64, height: 64)
            Text(stratagem.displayName(lang: lang))
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

/// 编组引用了当前库中不存在的战备 id 时的占位单元（对应安卓版 "Unknown [id]"）
struct UnknownStratagemCell: View {
    let id: Int

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .padding(8)
            Text("未知 [\(id)]")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
    }
}

/// 战备详情弹窗：图标 + 名称 + 步骤箭头序列
struct StratagemInfoSheet: View {
    let stratagem: Stratagem
    let dbName: String
    let lang: String

    var body: some View {
        VStack(spacing: 20) {
            StratagemIconView(icon: stratagem.icon, dbName: dbName)
                .frame(width: 110, height: 110)
            Text(stratagem.displayName(lang: lang))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            StepArrowsView(steps: stratagem.steps)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}

extension View {
    /// 统一错误弹窗：message 非空即弹出，确认后自动清空
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("操作失败", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    message.wrappedValue = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
