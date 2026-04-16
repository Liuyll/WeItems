//
//  RemoteDataView.swift
//  WeItems
//

import SwiftUI

struct RemoteDataView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var itemsCount = 0
    @State private var wishesCount = 0
    @State private var savingRecordsCount = 0
    @State private var hasSalaryRecord = false
    @State private var totalAssets: Double = 0
    @State private var savingsGoalName = ""
    @State private var savingsGoalAmount: Double = 0
    #if DEBUG
    @State private var itemImageCount = 0
    @State private var wishImageCount = 0
    #endif
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在读取远端数据...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "xmark.icloud")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        CloudDataRow(icon: "cube.fill", color: .blue, title: "我的物品", value: "\(itemsCount) 件")
                        CloudDataRow(icon: "heart.fill", color: .pink, title: "心愿清单", value: "\(wishesCount) 个")
                    } header: {
                        Text("同步数据")
                    }
                    
                    Section {
                        CloudDataRow(icon: "banknote.fill", color: .green, title: "收入/储蓄记录", value: "\(savingRecordsCount) 条")
                        CloudDataRow(icon: "briefcase.fill", color: .orange, title: "工资配置", value: hasSalaryRecord ? "已同步" : "未同步")
                        if totalAssets > 0 {
                            CloudDataRow(icon: "chart.bar.fill", color: .purple, title: "总资产", value: "¥\(formatNumber(totalAssets))")
                        }
                        if savingsGoalAmount > 0 {
                            CloudDataRow(icon: "target", color: .red, title: savingsGoalName, value: "¥\(formatNumber(savingsGoalAmount))")
                        }
                    } header: {
                        Text("资产状况")
                    }
                    
                    #if DEBUG
                    Section {
                        CloudDataRow(icon: "photo.fill", color: .cyan, title: "物品图片 (COS)", value: "\(itemImageCount) 张")
                        CloudDataRow(icon: "photo.fill", color: .mint, title: "心愿图片 (COS)", value: "\(wishImageCount) 张")
                        CloudDataRow(icon: "doc.fill", color: .indigo, title: "COS 文件总计", value: "\(itemImageCount + wishImageCount) 个")
                    } header: {
                        Text("COS 存储 (Debug)")
                    }
                    #endif
                    
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                                .font(.caption)
                                .padding(.top, 2)
                            Text("数据存储在我们的服务器，但我们不会收集任何个人信息和数据")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("远端数据")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        
        guard let client = authManager.getCloudBaseClient() else {
            errorMessage = "未登录或无法获取云客户端"
            isLoading = false
            return
        }
        
        // 并发获取物品、心愿、储蓄数据
        async let itemsResponse = client.fetchItems()
        async let wishesResponse = client.fetchWishes()
        async let savingResponse = client.fetchSavingInfo()
        
        let (items, wishes, saving) = await (itemsResponse, wishesResponse, savingResponse)
        
        await MainActor.run {
            itemsCount = items?.data?.records?.count ?? 0
            wishesCount = wishes?.data?.records?.count ?? 0
            
            if let savingData = saving {
                savingRecordsCount = savingData.records.count
                hasSalaryRecord = savingData.salaryRecord != nil
                totalAssets = savingData.totalAssets ?? 0
                savingsGoalName = savingData.goal?.name ?? ""
                savingsGoalAmount = savingData.goal?.targetAmount ?? 0
            }
            
            #if DEBUG
            // 统计有图片的物品数量
            itemImageCount = items?.data?.records?.filter { record in
                if let url = record.item_info?.imageUrl, !url.isEmpty { return true }
                return false
            }.count ?? 0
            
            // 统计有图片的心愿数量
            wishImageCount = wishes?.data?.records?.filter { record in
                if let url = record.wishinfo?.imageUrl, !url.isEmpty { return true }
                return false
            }.count ?? 0
            #endif
            
            isLoading = false
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", value / 10000)
        }
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

#Preview {
    NavigationStack {
        RemoteDataView()
            .environmentObject(AuthManager.shared)
    }
}
