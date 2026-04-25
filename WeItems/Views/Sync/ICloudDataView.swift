//
//  ICloudDataView.swift
//  WeItems
//

import SwiftUI

struct ICloudDataView: View {
    @State private var overview: ICloudSyncManager.ICloudDataOverview?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在读取 iCloud 数据...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = overview {
                List {
                    // 同步数据
                    Section {
                        CloudDataRow(icon: "cube.fill", color: .blue, title: "我的物品", value: "\(data.itemsCount) 件")
                        CloudDataRow(icon: "heart.fill", color: .pink, title: "心愿清单", value: "\(data.wishesCount) 个")
                    } header: {
                        Text("同步数据")
                    }
                    
                    // 资产状况
                    Section {
                        CloudDataRow(icon: "banknote.fill", color: .green, title: "储蓄记录", value: data.savingRecordsCount > 0 ? "已同步（\(data.savingRecordsCount) 条）" : "未同步")
                        CloudDataRow(icon: "briefcase.fill", color: .orange, title: "工资配置", value: data.hasSalaryRecord ? "已同步" : "未同步")
                        CloudDataRow(icon: "target", color: .red, title: "储蓄目标", value: data.savingsGoalAmount > 0 ? "已同步" : "未同步")
                    } header: {
                        Text("资产状况")
                    }
                    
                    // 个人设置
                    Section {
                        CloudDataRow(icon: "gearshape.fill", color: .purple, title: "个人设置", value: data.userSettings != nil ? "已同步" : "未同步")
                    } header: {
                        Text("个人设置")
                    }
                    
                    #if DEBUG
                    // Debug 同步详情
                    Section {
                        if data.totalAssets > 0 {
                            CloudDataRow(icon: "chart.bar.fill", color: .purple, title: "总资产", value: "¥\(formatNumber(data.totalAssets))")
                        }
                        if data.savingsGoalAmount > 0 {
                            CloudDataRow(icon: "target", color: .red, title: data.savingsGoalName, value: "¥\(formatNumber(data.savingsGoalAmount))")
                        }
                        if data.savingsAmount > 0 {
                            CloudDataRow(icon: "leaf.fill", color: .mint, title: "储蓄记录", value: "\(data.savingsAmount) 条")
                        }
                        if data.groupsCount > 0 {
                            CloudDataRow(icon: "folder.fill", color: .blue, title: "物品分组", value: "\(data.groupsCount) 个")
                        }
                        if data.wishlistGroupsCount > 0 {
                            CloudDataRow(icon: "folder.fill", color: .pink, title: "心愿分组", value: "\(data.wishlistGroupsCount) 个")
                        }
                        if let settings = data.userSettings {
                            CloudDataRow(icon: "faceid", color: .orange, title: "资产面容解锁", value: settings.assetFaceIDLock ? "已开启" : "未开启")
                            CloudDataRow(icon: "doc.on.clipboard", color: .blue, title: "剪贴板权限", value: settings.clipboardReadEnabled ? "已开启" : "未开启")
                            CloudDataRow(icon: "arrow.up.arrow.down", color: .purple, title: "物品排序", value: settings.itemSortMode)
                        }
                        CloudDataRow(icon: "photo.fill", color: .cyan, title: "图片文件", value: "\(data.imageCount) 张")
                        CloudDataRow(icon: "internaldrive.fill", color: .gray, title: "图片占用", value: formatFileSize(data.imagesTotalSize))
                    } header: {
                        Text("Debug 同步详情")
                    }
                    #endif
                    
                    // 说明
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                                .font(.caption)
                                .padding(.top, 2)
                            Text("数据由 Apple iCloud 存储和加密")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("iCloud 数据")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadData()
        }
    }
    
    private func loadData() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard ICloudSyncManager.shared.isICloudAvailable else {
                DispatchQueue.main.async {
                    errorMessage = "iCloud 不可用\n请检查是否已登录 iCloud"
                    isLoading = false
                }
                return
            }
            
            let result = ICloudSyncManager.shared.fetchDataOverview()
            
            DispatchQueue.main.async {
                if let result = result {
                    overview = result
                } else {
                    errorMessage = "无法读取 iCloud 数据"
                }
                isLoading = false
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", value / 10000)
        }
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

#Preview {
    NavigationStack {
        ICloudDataView()
    }
}
