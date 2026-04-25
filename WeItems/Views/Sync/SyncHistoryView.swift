//
//  SyncHistoryView.swift
//  WeItems
//

import SwiftUI

struct SyncHistoryView: View {
    @ObservedObject private var historyStore = SyncHistoryStore.shared
    @State private var showingClearConfirm = false
    @State private var expandedIds: Set<UUID> = []
    
    var body: some View {
        List {
            // 查看 iCloud 数据入口
            Section {
                NavigationLink(destination: ICloudDataView()) {
                    Label {
                        Text("查看 iCloud 数据")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "externaldrive.fill.badge.icloud")
                            .foregroundStyle(.cyan)
                    }
                }
                NavigationLink(destination: RemoteDataView()) {
                    Label {
                        Text("查看远端数据")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            
            // 同步记录
            if historyStore.records.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 36))
                                .foregroundStyle(.gray.opacity(0.4))
                            Text("暂无同步记录")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                }
            } else {
                Section {
                    ForEach(historyStore.records) { record in
                        SyncRecordRow(record: record, isExpanded: Binding(
                            get: { expandedIds.contains(record.id) },
                            set: { newValue in
                                if newValue {
                                    expandedIds.insert(record.id)
                                } else {
                                    expandedIds.remove(record.id)
                                }
                            }
                        ))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("同步历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !historyStore.records.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        showingClearConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .customConfirmAlert(
            isPresented: $showingClearConfirm,
            title: "清空同步历史",
            message: "确定要清空所有同步历史记录吗？",
            confirmText: "清空",
            isDestructive: true,
            onConfirm: {
                historyStore.clearAll()
            }
        )
    }
}

// MARK: - 单条记录行

struct SyncRecordRow: View {
    let record: SyncRecord
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 摘要行
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    // 状态图标
                    Image(systemName: record.success ? (record.trigger == .icloud ? "icloud.circle.fill" : "checkmark.circle.fill") : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(record.success ? (record.trigger == .icloud ? .cyan : .green) : .orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.trigger.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(record.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(formatDate(record.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // 展开详情
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 6)
                    
                    // 物品同步详情
                    DetailSection(
                        title: "物品同步",
                        icon: "cube.fill",
                        color: .blue,
                        uploaded: record.itemsUploaded,
                        updated: record.itemsUpdated,
                        deletedLocal: record.itemsDeletedLocal,
                        failed: record.itemsFailed
                    )
                    
                    // 心愿清单同步详情
                    DetailSection(
                        title: "心愿清单",
                        icon: "heart.fill",
                        color: .pink,
                        uploaded: record.wishesUploaded,
                        updated: record.wishesUpdated,
                        deletedLocal: record.wishesDeletedLocal,
                        failed: record.wishesFailed
                    )
                    
                    // 收入储蓄同步状态
                    if let synced = record.savingInfoSynced {
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("收入储蓄")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            Spacer()
                            Text(synced ? "已同步" : "同步失败")
                                .font(.caption)
                                .foregroundStyle(synced ? .green : .red)
                            Image(systemName: synced ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(synced ? .green : .red)
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - 详情 Section

struct DetailSection: View {
    let title: String
    let icon: String
    let color: Color
    let uploaded: Int
    let updated: Int
    let deletedLocal: Int
    let failed: Int
    
    private var hasActivity: Bool {
        uploaded + updated + deletedLocal + failed > 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            if hasActivity {
                HStack(spacing: 16) {
                    if uploaded > 0 {
                        StatBadge(label: "上传", value: uploaded, color: .green)
                    }
                    if updated > 0 {
                        StatBadge(label: "更新", value: updated, color: .blue)
                    }
                    if deletedLocal > 0 {
                        StatBadge(label: "删除本地", value: deletedLocal, color: .orange)
                    }
                    if failed > 0 {
                        StatBadge(label: "失败", value: failed, color: .red)
                    }
                }
            } else {
                Text("无变化")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }
}

struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    NavigationStack {
        SyncHistoryView()
    }
}
