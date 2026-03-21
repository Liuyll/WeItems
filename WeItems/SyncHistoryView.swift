//
//  SyncHistoryView.swift
//  WeItems
//

import SwiftUI

struct SyncHistoryView: View {
    @ObservedObject private var historyStore = SyncHistoryStore.shared
    @State private var showingClearConfirm = false
    
    var body: some View {
        Group {
            if historyStore.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text("暂无同步记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(historyStore.records) { record in
                        SyncRecordRow(record: record)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
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
        .alert("清空同步历史", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                historyStore.clearAll()
            }
        } message: {
            Text("确定要清空所有同步历史记录吗？")
        }
    }
}

// MARK: - 单条记录行

struct SyncRecordRow: View {
    let record: SyncRecord
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 摘要行
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // 状态图标
                    Image(systemName: record.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(record.success ? .green : .orange)
                    
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
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
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
