//
//  ProfileView.swift
//  WeItems
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var itemStore: ItemStore
    @EnvironmentObject var sharedWishlistStore: SharedWishlistStore
    
    @State private var showingLogoutConfirm = false
    @State private var isSyncing = false
    @State private var toastMessage: String?
    @State private var showToast = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    // 同步设置
                    Section("同步设置") {
                        Button {
                            performSync()
                        } label: {
                            HStack {
                                Label("远端同步", systemImage: isSyncing ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isSyncing)
                        
                        NavigationLink(destination: SyncHistoryView()) {
                            Label("同步历史", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    
                    // 账号管理
                    Section("账号管理") {
                        Button {
                            showingLogoutConfirm = true
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    }
                    
                    // 关于
                    Section("关于") {
                        NavigationLink {
                            PrivacySettingsView()
                        } label: {
                            Label("我的隐私", systemImage: "hand.raised.fill")
                        }
                        
                        HStack {
                            Label("版本", systemImage: "info.circle")
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                // Toast
                if showToast, let message = toastMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.75))
                            )
                            .padding(.bottom, 60)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.3), value: showToast)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("退出登录", isPresented: $showingLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    authManager.logout()
                    dismiss()
                }
            } message: {
                Text("退出登录后，数据将不再自动同步到云端。确定要退出吗？")
            }
        }
    }
    
    /// 显示 Toast 并自动消失
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    /// 执行数据同步（物品、心愿、共享清单）
    private func performSync() {
        isSyncing = true
        
        Task {
            // 同步前先确保 token 有效，过期则自动刷新
            let tokenValid = await authManager.ensureValidToken()
            
            guard tokenValid else {
                await MainActor.run {
                    isSyncing = false
                    showToastMessage("登录已过期，请重新登录")
                }
                return
            }
            
            guard let client = authManager.getCloudBaseClient() else {
                await MainActor.run {
                    isSyncing = false
                    showToastMessage("同步失败：未获取到云客户端")
                }
                return
            }
            
            // 同时同步物品、心愿清单和获取 userinfo
            async let itemsResult = client.syncItems(items: itemStore.items)
            async let wishesResult = client.syncWishes(items: itemStore.items)
            async let userInfoResult = client.fetchUserInfo()
            
            let (itemsSyncResult, wishesSyncResult, userInfoResponse) = await (itemsResult, wishesResult, userInfoResult)
            
            // 从 userinfo 的 share_wish_list 同步共享清单
            if let records = userInfoResponse?.data?.records, let record = records.first,
               let shareWishList = record.share_wish_list, !shareWishList.isEmpty {
                print("[手动同步] 从 userinfo 获取到 \(shareWishList.count) 个共享清单 ID")
                
                for wishGroupId in shareWishList {
                    let response = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                    
                    guard let sharedRecord = response?.data?.records?.first else {
                        print("[手动同步] 共享清单 \(wishGroupId) 远端无数据，跳过")
                        continue
                    }
                    
                    let listName = sharedRecord.name ?? "好朋友的清单"
                    let listEmoji = sharedRecord.emoji ?? "🎁"
                    let ownerName = sharedRecord.owner_name
                    let remoteItems = sharedRecord.wishinfo?.items ?? []
                    
                    let sharedItems: [SharedWishItem] = remoteItems.map { remote in
                        var remoteImageData: Data? = nil
                        if let base64Str = remote.imageBase64, !base64Str.isEmpty {
                            remoteImageData = Data(base64Encoded: base64Str)
                        }
                        return SharedWishItem(
                            name: remote.name ?? "未知心愿",
                            price: remote.price ?? 0,
                            isCompleted: remote.isCompleted ?? false,
                            displayType: remote.displayType,
                            imageData: remoteImageData,
                            purchaseLink: remote.purchaseLink,
                            details: remote.details,
                            completedBy: remote.completedBy
                        )
                    }
                    
                    await MainActor.run {
                        if let existingIndex = sharedWishlistStore.lists.firstIndex(where: { $0.wishGroupId == wishGroupId }) {
                            // 本地已有该清单，用远端数据更新
                            sharedWishlistStore.applyMergedResult(
                                listId: sharedWishlistStore.lists[existingIndex].id,
                                mergedItems: sharedItems,
                                isSynced: true,
                                remoteName: listName,
                                remoteEmoji: listEmoji,
                                remoteOwnerName: ownerName
                            )
                            print("[手动同步] 已更新共享清单: \(listName) (\(wishGroupId))")
                        } else {
                            // 本地没有该清单，作为新的共享清单添加（非 owner）
                            let newList = SharedWishlist(
                                name: listName,
                                emoji: listEmoji,
                                items: sharedItems,
                                isSynced: true,
                                wishGroupId: wishGroupId,
                                isOwner: false,
                                ownerName: ownerName
                            )
                            sharedWishlistStore.add(newList)
                            print("[手动同步] 已添加共享清单: \(listName) (\(wishGroupId))")
                        }
                    }
                }
            } else {
                print("[手动同步] userinfo 无 share_wish_list 或为空")
            }
            
            // 下载远端物品/心愿的图片
            var allRemoteItems: [Item] = []
            if let result = itemsSyncResult {
                allRemoteItems.append(contentsOf: result.remoteOnlyItems)
            }
            if let result = wishesSyncResult {
                allRemoteItems.append(contentsOf: result.remoteOnlyItems)
            }
            
            // 收集需要下载图片的远端物品（有 imageUrl 的）
            var imageUrlsToDownload: [String: String] = [:]  // [item.id.uuidString: imageUrl]
            for item in allRemoteItems {
                if let remoteUrl = item.imageUrl, !remoteUrl.isEmpty {
                    imageUrlsToDownload[item.id.uuidString] = remoteUrl
                }
            }
            
            // 批量下载图片
            var downloadedImages: [String: Data] = [:]
            if !imageUrlsToDownload.isEmpty {
                print("[同步] 开始下载 \(imageUrlsToDownload.count) 张远端图片...")
                downloadedImages = await client.downloadRemoteImages(imageUrls: imageUrlsToDownload)
            }
            
            await MainActor.run {
                isSyncing = false
                
                var allSuccess = true
                var message = ""
                
                // 处理物品同步结果
                if let result = itemsSyncResult {
                    for name in result.deletedLocalNames {
                        if let item = itemStore.items.first(where: { $0.name == name && $0.listType == .items }) {
                            itemStore.delete(item)
                            print("[同步] 已删除本地物品: \(name)")
                        }
                    }
                    // 远端独有或远端更新的物品，添加到本地
                    for var remoteItem in result.remoteOnlyItems {
                        if !itemStore.items.contains(where: { $0.name == remoteItem.name && $0.listType == remoteItem.listType }) {
                            // 如果下载到了图片，设置到 imageData
                            if let imageData = downloadedImages[remoteItem.id.uuidString] {
                                remoteItem.imageData = imageData
                                print("[同步] 已下载远端物品图片: \(remoteItem.name)")
                            }
                            itemStore.add(remoteItem)
                            print("[同步] 已添加远端物品: \(remoteItem.name)")
                        }
                    }
                } else {
                    allSuccess = false
                }
                
                // 处理心愿清单同步结果
                if let result = wishesSyncResult {
                    for name in result.deletedLocalNames {
                        if let item = itemStore.items.first(where: { $0.name == name && $0.listType == .wishlist }) {
                            itemStore.delete(item)
                            print("[同步] 已删除本地心愿: \(name)")
                        }
                    }
                    // 远端独有或远端更新的心愿，添加到本地
                    for var remoteItem in result.remoteOnlyItems {
                        if !itemStore.items.contains(where: { $0.name == remoteItem.name && $0.listType == remoteItem.listType }) {
                            // 如果下载到了图片，设置到 imageData
                            if let imageData = downloadedImages[remoteItem.id.uuidString] {
                                remoteItem.imageData = imageData
                                print("[同步] 已下载远端心愿图片: \(remoteItem.name)")
                            }
                            itemStore.add(remoteItem)
                            print("[同步] 已添加远端心愿: \(remoteItem.name)")
                        }
                    }
                } else {
                    allSuccess = false
                }
                
                // userinfo 获取成功也算同步成功
                if userInfoResponse != nil {
                    allSuccess = true
                }
                
                if allSuccess {
                    itemStore.markSyncCompleted()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    message = "同步成功"
                } else if itemsSyncResult != nil || wishesSyncResult != nil {
                    itemStore.markSyncCompleted()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    message = "部分同步成功"
                } else {
                    message = "同步失败，请检查网络连接"
                }
                
                // 记录同步历史
                let record = SyncRecord(
                    id: UUID(),
                    date: Date(),
                    trigger: .manual,
                    itemsUploaded: itemsSyncResult?.uploadedCount ?? 0,
                    itemsUpdated: itemsSyncResult?.updatedCount ?? 0,
                    itemsDeletedLocal: itemsSyncResult?.deletedLocalNames.count ?? 0,
                    itemsFailed: itemsSyncResult?.failedIds.count ?? 0,
                    wishesUploaded: wishesSyncResult?.uploadedCount ?? 0,
                    wishesUpdated: wishesSyncResult?.updatedCount ?? 0,
                    wishesDeletedLocal: wishesSyncResult?.deletedLocalNames.count ?? 0,
                    wishesFailed: wishesSyncResult?.failedIds.count ?? 0,
                    success: allSuccess || itemsSyncResult != nil || wishesSyncResult != nil,
                    message: message
                )
                SyncHistoryStore.shared.addRecord(record)
                
                showToastMessage(message)
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager.shared)
        .environmentObject(ItemStore())
        .environmentObject(SharedWishlistStore())
}
