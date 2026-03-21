//
//  ProfileView.swift
//  WeItems
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var itemStore: ItemStore
    
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
                                Label("自动同步", systemImage: isSyncing ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
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
    
    /// 执行数据同步
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
            
            // 同时同步物品和心愿清单
            async let itemsResult = client.syncItems(items: itemStore.items)
            async let wishesResult = client.syncWishes(items: itemStore.items)
            
            let (itemsSyncResult, wishesSyncResult) = await (itemsResult, wishesResult)
            
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
                } else {
                    allSuccess = false
                }
                
                if allSuccess {
                    itemStore.markSyncCompleted()
                    message = "同步成功"
                } else if itemsSyncResult != nil || wishesSyncResult != nil {
                    itemStore.markSyncCompleted()
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
}
