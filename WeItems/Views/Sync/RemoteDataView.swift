//
//  RemoteDataView.swift
//  WeItems
//

import SwiftUI

struct RemoteDataView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // 基本数据
    @State private var itemsCount = 0
    @State private var wishesCount = 0
    @State private var sharedWishlistCount = 0
    
    // 资产状况
    @State private var savingRecordsCount = 0
    @State private var hasSalaryRecord = false
    @State private var hasSavingsGoal = false
    @State private var hasSavingsSynced = false
    
    // 个人设置
    @State private var hasUserSettings = false
    
    // Debug 详情
    #if DEBUG
    @State private var totalAssets: Double = 0
    @State private var savingsGoalName = ""
    @State private var savingsGoalAmount: Double = 0
    @State private var savingsAmount = 0
    @State private var groupsCount = 0
    @State private var wishlistGroupsCount = 0
    @State private var remoteAssetFaceIDLock = false
    @State private var remoteClipboardEnabled = false
    @State private var remoteSortMode = ""
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
                    // 同步数据
                    Section {
                        CloudDataRow(icon: "cube.fill", color: .blue, title: "我的物品", value: "\(itemsCount) 件")
                        CloudDataRow(icon: "heart.fill", color: .pink, title: "心愿清单", value: "\(wishesCount) 个")
                        CloudDataRow(icon: "person.2.fill", color: .green, title: "共享心愿清单", value: "\(sharedWishlistCount) 个")
                    } header: {
                        Text("同步数据")
                    }
                    
                    // 资产状况
                    Section {
                        CloudDataRow(icon: "banknote.fill", color: .green, title: "储蓄记录", value: savingRecordsCount > 0 ? "已同步（\(savingRecordsCount) 条）" : "未同步")
                        CloudDataRow(icon: "briefcase.fill", color: .orange, title: "工资配置", value: hasSalaryRecord ? "已同步" : "未同步")
                        CloudDataRow(icon: "target", color: .red, title: "储蓄目标", value: hasSavingsGoal ? "已同步" : "未同步")
                    } header: {
                        Text("资产状况")
                    }
                    
                    // 个人设置
                    Section {
                        CloudDataRow(icon: "gearshape.fill", color: .purple, title: "个人设置", value: hasUserSettings ? "已同步" : "未同步")
                    } header: {
                        Text("个人设置")
                    }
                    
                    #if DEBUG
                    // Debug 同步详情
                    Section {
                        CloudDataRow(icon: "chart.bar.fill", color: .purple, title: "总资产", value: totalAssets > 0 ? "¥\(formatNumber(totalAssets))" : "无")
                        if hasSavingsGoal {
                            CloudDataRow(icon: "target", color: .red, title: savingsGoalName, value: "¥\(formatNumber(savingsGoalAmount))")
                        }
                        CloudDataRow(icon: "leaf.fill", color: .mint, title: "储蓄记录", value: "\(savingsAmount) 条")
                        CloudDataRow(icon: "folder.fill", color: .blue, title: "物品分组", value: "\(groupsCount) 个")
                        CloudDataRow(icon: "folder.fill", color: .pink, title: "心愿分组", value: "\(wishlistGroupsCount) 个")
                        if hasUserSettings {
                            CloudDataRow(icon: "faceid", color: .orange, title: "资产面容解锁", value: remoteAssetFaceIDLock ? "已开启" : "未开启")
                            CloudDataRow(icon: "doc.on.clipboard", color: .blue, title: "剪贴板权限", value: remoteClipboardEnabled ? "已开启" : "未开启")
                            CloudDataRow(icon: "arrow.up.arrow.down", color: .purple, title: "物品排序", value: remoteSortMode)
                        }
                        CloudDataRow(icon: "photo.fill", color: .cyan, title: "物品图片 (COS)", value: "\(itemImageCount) 张")
                        CloudDataRow(icon: "photo.fill", color: .mint, title: "心愿图片 (COS)", value: "\(wishImageCount) 张")
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
        
        async let itemsResponse = client.fetchItems()
        async let wishesResponse = client.fetchWishes()
        async let savingResponse = client.fetchSavingInfo()
        async let userInfoResponse = client.fetchUserInfo()
        
        let (items, wishes, saving, userInfo) = await (itemsResponse, wishesResponse, savingResponse, userInfoResponse)
        
        await MainActor.run {
            itemsCount = items?.data?.records?.count ?? 0
            wishesCount = wishes?.data?.records?.count ?? 0
            
            // 共享心愿清单数量
            sharedWishlistCount = userInfo?.data?.records?.first?.share_wish_list?.count ?? 0
            
            if let savingData = saving {
                savingRecordsCount = savingData.records.count
                hasSalaryRecord = savingData.salaryRecord != nil
                hasSavingsGoal = (savingData.goal?.targetAmount ?? 0) > 0
                hasSavingsSynced = savingData.records.count > 0 || savingData.salaryRecord != nil
                
                if let settings = savingData.userSettings, !settings.isDefault {
                    hasUserSettings = true
                }
                
                #if DEBUG
                totalAssets = savingData.totalAssets ?? 0
                savingsGoalName = savingData.goal?.name ?? ""
                savingsGoalAmount = savingData.goal?.targetAmount ?? 0
                savingsAmount = savingData.records.filter { $0.type == .income && $0.incomePeriod == .savings }.count
                groupsCount = savingData.groups?.count ?? 0
                wishlistGroupsCount = savingData.wishlistGroups?.count ?? 0
                if let settings = savingData.userSettings {
                    remoteAssetFaceIDLock = settings.assetFaceIDLock
                    remoteClipboardEnabled = settings.clipboardReadEnabled
                    remoteSortMode = settings.itemSortMode
                }
                #endif
            }
            
            #if DEBUG
            itemImageCount = items?.data?.records?.filter { record in
                if let url = record.item_info?.imageUrl, !url.isEmpty { return true }
                return false
            }.count ?? 0
            
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
