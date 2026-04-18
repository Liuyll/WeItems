//
//  SharedWishlistView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

// MARK: - 共享清单列表页
struct SharedWishlistListView: View {
    @ObservedObject var sharedStore: SharedWishlistStore
    @ObservedObject var itemStore: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    @State private var showingCreate = false
    @State private var editingList: SharedWishlist? = nil
    @State private var showingImportAlert = false
    @State private var importGroupId = ""
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var showingImportError = false
    @State private var showingImportSuccess = false
    @State private var importedListName = ""
    
    // 昵称输入弹窗相关
    @State private var showingNicknameInput = false
    @State private var nicknameInput = ""
    @State private var pendingDocId: String? = nil
    @State private var pendingNumberList: [[String: String]] = []
    @State private var pendingUserId: String = ""
    @State private var pendingListId: UUID? = nil  // 导入清单的本地 ID
    
    @State private var showingProUpgrade = false
    
    var body: some View {
        Group {
            if IAPManager.shared.isVIPActive {
                vipContentView
            } else {
                nonVipView
            }
        }
        .navigationTitle("共享清单")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if IAPManager.shared.isVIPActive {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateSharedWishlistView(sharedStore: sharedStore, itemStore: itemStore, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(item: $editingList) { list in
            EditSharedWishlistView(list: list, sharedStore: sharedStore, itemStore: itemStore, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView()
        }
        .sheet(isPresented: $showingImportAlert) {
            ImportFriendSheet(groupId: $importGroupId) {
                importFriendWishlist()
            }
            .presentationDetents([.medium])
        }
        .customInfoAlert(
            isPresented: $showingImportError,
            title: "导入失败",
            message: importError ?? "未知错误"
        )
        .customInfoAlert(
            isPresented: $showingImportSuccess,
            title: "导入成功",
            message: "已成功导入「\(importedListName)」"
        )
        .customInputAlert(
            isPresented: $showingNicknameInput,
            title: "在此心愿清单中，希望大家叫你什么？",
            message: "这个名字会显示给清单中的其他小伙伴",
            placeholder: "输入你的昵称",
            text: $nicknameInput,
            onConfirm: {
                let nickname = nicknameInput.trimmingCharacters(in: .whitespaces)
                guard !nickname.isEmpty, let docId = pendingDocId else { return }
                var numberList = pendingNumberList
                if let index = numberList.firstIndex(where: { $0["number_id"] == pendingUserId }) {
                    numberList[index]["number_name"] = nickname
                }
                if let listId = pendingListId {
                    sharedStore.setMyNickname(listId, nickname: nickname)
                }
                Task {
                    guard let client = AuthManager.shared.getCloudBaseClient() else { return }
                    let result = await client.callFunction(
                        functionName: "update_sharewish",
                        data: [
                            "docId": docId,
                            "modelName": "sharewish",
                            "updateData": ["numbers": ["number_list": numberList]]
                        ]
                    )
                    await MainActor.run {
                        if result != nil {
                            showingImportSuccess = true
                        } else {
                            importError = "云函数调用失败，请重试"
                            showingImportError = true
                        }
                    }
                }
            }
        )
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在导入...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
            }
        }
    }
    
    // MARK: - VIP 用户视图（正常共享清单）
    
    private var vipContentView: some View {
        List {
            // 导入好朋友清单 block
            Section {
                ImportFriendWishlistBlock {
                    importGroupId = ""
                    showingImportAlert = true
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            if sharedStore.lists.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green.opacity(0.5))
                        Text("还没有共享清单")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("创建一个清单，分享给朋友一起实现心愿")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                ForEach(sharedStore.lists) { list in
                    NavigationLink(destination: SharedWishlistDetailView(list: list, sharedStore: sharedStore)) {
                        SharedWishlistRow(list: list)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            let wishGroupId = list.wishGroupId
                            sharedStore.delete(list)
                            if let gid = wishGroupId {
                                Task {
                                    if let client = AuthManager.shared.getCloudBaseClient() {
                                        await client.syncUserInfoShareWishList(wishGroupId: gid, action: "delete")
                                    }
                                }
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        
                        Button {
                            editingList = list
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }
    
    // MARK: - 非 VIP 用户视图（升级提示）
    
    private var nonVipView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("升级 Pro 版本，与好朋友们共享心愿")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingProUpgrade = true
            } label: {
                Text("升级 Pro 版本")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.blue))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private func importFriendWishlist() {
        let groupId = importGroupId.trimmingCharacters(in: .whitespaces)
        guard !groupId.isEmpty else { return }
        
        // 检查是否已导入过
        if sharedStore.lists.contains(where: { $0.wishGroupId == groupId }) {
            importError = "该清单已存在，无需重复导入"
            showingImportError = true
            return
        }
        
        isImporting = true
        
        Task {
            guard let client = AuthManager.shared.getCloudBaseClient() else {
                await MainActor.run {
                    isImporting = false
                    importError = "未登录，请先登录后再导入"
                    showingImportError = true
                }
                return
            }
            
            let response = await client.fetchSharedWishlistByGroupId(wishGroupId: groupId)
            
            await MainActor.run {
                isImporting = false
                
                guard let records = response?.data?.records, let record = records.first else {
                    importError = "未找到该清单，请检查 ID 是否正确"
                    showingImportError = true
                    return
                }
                
                let listName = record.name ?? "好朋友的清单"
                let listEmoji = record.emoji ?? "🎁"
                let ownerName = record.owner_name
                let remoteItems = record.wishinfo?.items ?? []
                
                let sharedItems: [SharedWishItem] = remoteItems.map { remote in
                    var remoteImageUrl: String? = nil
                    var remoteImageData: Data? = nil
                    if let url = remote.imageUrl, !url.isEmpty {
                        remoteImageUrl = url
                    } else if let base64Str = remote.imageBase64, !base64Str.isEmpty {
                        remoteImageData = Data(base64Encoded: base64Str)
                    }
                    return SharedWishItem(
                        name: remote.name ?? "未知心愿",
                        price: remote.price ?? 0,
                        isCompleted: remote.isCompleted ?? false,
                        displayType: remote.displayType,
                        imageUrl: remoteImageUrl,
                        imageData: remoteImageData,
                        purchaseLink: remote.purchaseLink,
                        details: remote.details,
                        completedBy: remote.completedBy,
                        addedBy: remote.addedBy
                    )
                }
                
                let newList = SharedWishlist(
                    name: listName,
                    emoji: listEmoji,
                    items: sharedItems,
                    isSynced: true,
                    wishGroupId: groupId,
                    isOwner: false,
                    ownerName: ownerName
                )
                sharedStore.add(newList)
                
                // 暂存数据，弹出昵称输入框
                let currentUserId = TokenStorage.shared.getSub() ?? ""
                pendingListId = newList.id
                if let docId = record._id {
                    var numberList: [[String: String]] = record.numbers?.number_list?.map { item in
                        ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
                    } ?? []
                    if !numberList.contains(where: { $0["number_id"] == currentUserId }) {
                        numberList.append(["number_name": "", "number_id": currentUserId])
                    }
                    pendingDocId = docId
                    pendingNumberList = numberList
                    pendingUserId = currentUserId
                    nicknameInput = ""
                }
                
                if let ownerName = ownerName, !ownerName.isEmpty {
                    importedListName = "来自\(ownerName)的心愿清单"
                } else {
                    importedListName = listName
                }
                // 先弹昵称输入框，输入完成后再显示导入成功
                showingNicknameInput = true
            }
        }
    }
}

// MARK: - 导入好朋友清单 Block（绿色背景 + 冒泡泡动画）
struct ImportFriendWishlistBlock: View {
    let action: () -> Void
    
    @State private var bubbles: [(id: UUID, x: CGFloat, size: CGFloat, delay: Double)] = []
    @State private var animating = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 冒泡泡动画层
                ForEach(bubbles, id: \.id) { bubble in
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: bubble.size, height: bubble.size)
                        .offset(x: bubble.x)
                        .offset(y: animating ? -80 : 40)
                        .opacity(animating ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 2.5)
                            .repeatForever(autoreverses: false)
                            .delay(bubble.delay),
                            value: animating
                        )
                }
                
                // 内容层
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导入好朋友的清单")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("输入清单 ID，一起实现心愿")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            generateBubbles()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animating = true
            }
        }
    }
    
    private func generateBubbles() {
        bubbles = (0..<6).map { _ in
            (
                id: UUID(),
                x: CGFloat.random(in: -120...120),
                size: CGFloat.random(in: 6...16),
                delay: Double.random(in: 0...2)
            )
        }
    }
}

// MARK: - 导入好朋友清单 Sheet（粉色背景）
struct ImportFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var groupId: String
    var onImport: () -> Void
    
    var body: some View {
        ZStack {
            Color.pink.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("请输入好朋友分享的清单 ID")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.8))
                
                TextField("输入清单 ID", text: $groupId)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )
                    .tint(.green)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 8)
                
                Button {
                    dismiss()
                    onImport()
                } label: {
                    Text("导入")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(groupId.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.45) : Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(groupId.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 8)
            }
            .padding(24)
        }
        .presentationBackground(Color.pink)
    }
}

// MARK: - 清单行
struct SharedWishlistRow: View {
    let list: SharedWishlist
    
    private var progressText: String {
        "\(list.completedCount)/\(list.items.count) 已实现"
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Text(list.emoji)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Text(list.isOwner ? "ME" : "From \(list.ownerName ?? "?")")
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(list.isOwner ? .blue : .pink))
                }
                
                HStack(spacing: 8) {
                    Text("\(list.items.count) 个心愿")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !list.items.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(progressText)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            Text("¥\(String(format: "%.0f", list.totalPrice))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 清单详情页
struct SharedWishlistDetailView: View {
    let list: SharedWishlist
    @ObservedObject var sharedStore: SharedWishlistStore
    @Environment(\.dismiss) private var dismiss
    @State private var isSyncing = false
    @State private var editingItem: SharedWishItem? = nil
    @State private var viewingItem: SharedWishItem? = nil
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var members: [String] = []
    @State private var isLoadingMembers = false
    
    // 同步时检测自己不在 number_list 中，弹出昵称输入框
    @State private var showingSyncNicknameInput = false
    @State private var syncNicknameInput = ""
    @State private var syncPendingDocId: String? = nil
    @State private var syncPendingNumberList: [[String: String]] = []
    @State private var syncPendingUserId: String = ""
    
    // 修改自己在清单中的昵称
    @State private var showingEditNickname = false
    @State private var editNicknameInput = ""
    @State private var editPendingDocId: String? = nil
    @State private var editPendingNumberList: [[String: String]] = []
    @State private var editPendingUserId: String = ""
    
    // 快照：进入时保存一份清单数据，用于判断用户是否做了本地修改
    @State private var snapshotItems: [SharedWishItem]? = nil
    @State private var wasAlreadyUnsynced = false
    
    // 远端清单是否已被创建者删除
    @State private var isRemoteDeleted = false
    @State private var showingDeletedAlert = false
    @State private var isCheckingRemote = true
    @State private var showingAddWish = false
    
    private var currentList: SharedWishlist {
        sharedStore.lists.first(where: { $0.id == list.id }) ?? list
    }
    
    /// 判断是否应该显示"未同步"状态
    /// - 如果进入时就是未同步的，直接显示"未同步"（忽略快照对比）
    /// - 如果进入时是已同步的，只有用户做了本地修改后，才显示"未同步"
    private var shouldShowUnsynced: Bool {
        // 如果底层数据本身就是 synced，不需要显示未同步
        if currentList.isSynced {
            return false
        }
        // 底层数据 isSynced == false 的情况
        // 如果进入时就已经是未同步，直接显示
        if wasAlreadyUnsynced {
            return true
        }
        // 进入时是已同步的，需要对比快照判断是否有本地修改
        guard let snapshot = snapshotItems else {
            return true // 快照未初始化，兜底显示
        }
        return !itemsAreEqual(currentList.items, snapshot)
    }
    
    /// 按 displayType 分组后的心愿列表，保持类型顺序稳定
    private var groupedItems: [(type: String, items: [SharedWishItem])] {
        var dict: [String: [SharedWishItem]] = [:]
        var order: [String] = []
        for item in currentList.items {
            let key = item.effectiveDisplayType
            if dict[key] == nil {
                order.append(key)
            }
            dict[key, default: []].append(item)
        }
        return order.map { (type: $0, items: dict[$0]!) }
    }
    
    var body: some View {
        List {
            // 分享给朋友们（绿色背景块）
            if let wishGroupId = currentList.wishGroupId, !wishGroupId.isEmpty {
                Section {
                    ShareToFriendsBlock(wishGroupId: wishGroupId)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSpacing(2)
            }
            
            // 标签行（独立块，无白色背景）
            Section {
                HStack {
                    if let ownerName = currentList.ownerName, !ownerName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text("来自\(ownerName)的心愿")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue))
                    }
                    
                    Spacer()
                    
                    if isCheckingRemote {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                            Text("同步中")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue))
                    } else if isRemoteDeleted {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.caption2)
                            Text("心愿已删除")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                    } else if !shouldShowUnsynced {
                        Button {
                            syncFromRemote()
                        } label: {
                            HStack(spacing: 4) {
                                if isSyncing {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.icloud.fill")
                                        .font(.caption2)
                                }
                                Text(isSyncing ? "同步中..." : "已远端同步")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(isSyncing ? Color.orange : Color.green))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isSyncing)
                    } else {
                        Button {
                            syncToCloud()
                        } label: {
                            HStack(spacing: 4) {
                                if isSyncing {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "icloud.and.arrow.up.fill")
                                        .font(.caption2)
                                }
                                Text(isSyncing ? "同步中..." : "未同步")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(isSyncing ? Color.orange : Color.yellow))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isSyncing)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listSectionSpacing(2)
            
            // 概览（总金额 + 进度）
            Section {
                HStack {
                    // 左侧：总金额 + 已实现
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("总金额")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", currentList.totalPrice))")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已实现")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", currentList.completedPrice))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Spacer()
                    
                    // 右侧：进度
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("进度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(currentList.completedCount)/\(currentList.items.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            // 按类型分组的心愿列表
            if currentList.items.isEmpty {
                Section("心愿列表") {
                    Text("暂无心愿")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                ForEach(groupedItems, id: \.type) { group in
                    Section(group.type) {
                        ForEach(group.items) { item in
                            HStack(spacing: 12) {
                                Button {
                                    if isRemoteDeleted {
                                        showingDeletedAlert = true
                                    } else {
                                        withAnimation(.spring(duration: 0.25)) {
                                            sharedStore.toggleItemCompleted(listId: currentList.id, itemId: item.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(item.isCompleted ? .green : .gray.opacity(0.3))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    HStack(spacing: 4) {
                                        Text("¥\(String(format: "%.0f", item.price))")
                                            .font(.system(.caption, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundStyle(.pink)
                                        if let addedBy = item.addedBy, !addedBy.isEmpty {
                                            Text("·")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(addedBy)的心愿")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                        if item.isCompleted, let completedBy = item.completedBy, !completedBy.isEmpty {
                                            Text("·")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("已被\(completedBy)满足愿望")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isRemoteDeleted {
                                    showingDeletedAlert = true
                                } else {
                                    viewingItem = item
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                let itemCanDelete: Bool = {
                                    if let addedBy = item.addedBy, !addedBy.isEmpty {
                                        return addedBy == currentList.myNickname
                                    }
                                    return currentList.isOwner
                                }()
                                if itemCanDelete {
                                    Button(role: .destructive) {
                                        sharedStore.deleteItem(listId: currentList.id, itemId: item.id)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // 添加心愿按钮
            if !isRemoteDeleted {
                Section {
                    Button {
                        showingAddWish = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("添加心愿")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 已加入清单的朋友列表
            if let wishGroupId = currentList.wishGroupId, !wishGroupId.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("已加入的朋友")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            if isLoadingMembers {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Text("\(members.count) 人")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if !members.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(members, id: \.self) { member in
                                    Text(member)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(memberColor(for: member).opacity(0.15))
                                        .foregroundStyle(memberColor(for: member))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // 修改自己在清单中的名字
                        Button {
                            editMyNickname()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                Text("修改我的名字")
                                    .font(.caption)
                            }
                            .foregroundStyle(.green)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // 移除/退出按钮
            Section {
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(currentList.isOwner ? "删除清单" : "退出分享")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isDeleting)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(currentList.name)
        .navigationBarTitleDisplayMode(.inline)
        .customBlueConfirmAlert(
            isPresented: $showingDeleteAlert,
            message: currentList.isOwner
                ? "删除后将同时删除远端数据，此操作不可撤销"
                : "退出后将从本地移除该清单，远端数据不受影响",
            confirmText: currentList.isOwner ? "删除" : "退出",
            cancelText: "取消",
            confirmColor: .blue,
            cancelColor: .green,
            backgroundColor: .red,
            width: 260,
            onConfirm: {
                performDelete()
            }
        )
        .customBlueInfoAlert(
            isPresented: $showingDeletedAlert,
            message: "该心愿清单已经被创建者删除",
            buttonText: "知道了",
            backgroundColor: .yellow
        )
        .onAppear {
            let l = currentList
            
            // 记录进入时的快照
            if snapshotItems == nil {
                snapshotItems = l.items
                wasAlreadyUnsynced = !l.isSynced
            }
            
            // 从远端检查清单是否还存在
            if let gid = l.wishGroupId, !gid.isEmpty {
                Task {
                    if let client = AuthManager.shared.getCloudBaseClient() {
                        let response = await client.fetchSharedWishlistByGroupId(wishGroupId: gid)
                        let exists = response?.data?.records?.first != nil
                        await MainActor.run {
                            isRemoteDeleted = !exists
                            isCheckingRemote = false
                        }
                    } else {
                        await MainActor.run {
                            isCheckingRemote = false
                        }
                    }
                }
            } else {
                isCheckingRemote = false
            }
            
            print("========== 共享清单详情 ==========")
            print("id: \(l.id)")
            print("name: \(l.name)")
            print("emoji: \(l.emoji)")
            print("owner_name: \(l.ownerName ?? "nil")")
            print("isOwner: \(l.isOwner)")
            print("wish_group_id: \(l.wishGroupId ?? "nil")")
            print("isSynced: \(l.isSynced)")
            print("createdAt: \(l.createdAt)")
            print("updatedAt: \(l.updatedAt)")
            print("totalPrice: \(l.totalPrice)")
            print("items count: \(l.items.count)")
            for (i, item) in l.items.enumerated() {
                let imgInfo = item.imageUrl ?? "nil"
                print("  [\(i)] name: \(item.name), price: \(item.price), isCompleted: \(item.isCompleted), displayType: \(item.displayType ?? "nil"), imageUrl: \(imgInfo)")
            }
            print("==================================")
            loadMembers()
        }
        .sheet(isPresented: $showingAddWish) {
            AddSharedWishItemView(listId: currentList.id, sharedStore: sharedStore)
        }
        .sheet(item: $viewingItem) { item in
            SharedWishItemDetailView(
                item: item,
                listId: currentList.id,
                isOwner: currentList.isOwner,
                sharedStore: sharedStore
            )
        }
        .sheet(item: $editingItem) { item in
            let myNickname = currentList.myNickname
            let itemCanEdit: Bool = {
                if let addedBy = item.addedBy, !addedBy.isEmpty {
                    return addedBy == myNickname
                }
                return currentList.isOwner
            }()
            EditSharedWishItemView(
                item: item,
                listId: currentList.id,
                isOwner: itemCanEdit,
                sharedStore: sharedStore
            )
        }
        .customInputAlert(
            isPresented: $showingSyncNicknameInput,
            title: "在此心愿清单中，希望大家叫你什么？",
            message: "这个名字会显示给清单中的其他小伙伴",
            placeholder: "输入你的昵称",
            text: $syncNicknameInput,
            onConfirm: {
                let nickname = syncNicknameInput.trimmingCharacters(in: .whitespaces)
                guard !nickname.isEmpty, let docId = syncPendingDocId else { return }
                var numberList = syncPendingNumberList
                if let index = numberList.firstIndex(where: { $0["number_id"] == syncPendingUserId }) {
                    numberList[index]["number_name"] = nickname
                }
                sharedStore.setMyNickname(currentList.id, nickname: nickname)
                Task {
                    guard let client = AuthManager.shared.getCloudBaseClient() else { return }
                    _ = await client.callFunction(
                        functionName: "update_sharewish",
                        data: [
                            "docId": docId,
                            "modelName": "sharewish",
                            "updateData": ["numbers": ["number_list": numberList]]
                        ]
                    )
                    await MainActor.run {
                        loadMembers()
                    }
                }
            }
        )
        .customInputAlert(
            isPresented: $showingEditNickname,
            title: "修改我在清单中的名字",
            message: "修改后其他小伙伴会看到你的新名字",
            placeholder: "输入新的昵称",
            text: $editNicknameInput,
            onConfirm: {
                let nickname = editNicknameInput.trimmingCharacters(in: .whitespaces)
                guard !nickname.isEmpty, let docId = editPendingDocId else { return }
                var numberList = editPendingNumberList
                if let index = numberList.firstIndex(where: { $0["number_id"] == editPendingUserId }) {
                    numberList[index]["number_name"] = nickname
                }
                sharedStore.setMyNickname(currentList.id, nickname: nickname)
                Task {
                    guard let client = AuthManager.shared.getCloudBaseClient() else { return }
                    _ = await client.callFunction(
                        functionName: "update_sharewish",
                        data: [
                            "docId": docId,
                            "modelName": "sharewish",
                            "updateData": ["numbers": ["number_list": numberList]]
                        ]
                    )
                    await MainActor.run {
                        loadMembers()
                    }
                }
            }
        )
    }
    
    private func performDelete() {
        let wishGroupId = currentList.wishGroupId
        let isOwner = currentList.isOwner
        isDeleting = true
        
        Task {
            if let gid = wishGroupId, let client = AuthManager.shared.getCloudBaseClient() {
                // 从 userinfo 的 share_wish_list 中移除
                await client.syncUserInfoShareWishList(wishGroupId: gid, action: "delete")
                
                if isOwner {
                    // 如果是创建人，同时删除远端清单数据
                    let _ = await client.deleteSharedWishlist(wishGroupId: gid)
                } else {
                    // 非创建人退出分享：从远端 number_list 中移除自己
                    let currentUserId = TokenStorage.shared.getSub() ?? ""
                    if !currentUserId.isEmpty {
                        let response = await client.fetchSharedWishlistByGroupId(wishGroupId: gid)
                        if let record = response?.data?.records?.first, let docId = record._id {
                            let numberList = record.numbers?.number_list ?? []
                            // 过滤掉自己
                            let newNumberList: [[String: String]] = numberList.compactMap { item in
                                guard item.number_id != currentUserId else { return nil }
                                return ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
                            }
                            // 调用云函数更新 number_list
                            _ = await client.callFunction(
                                functionName: "update_sharewish",
                                data: [
                                    "docId": docId,
                                    "modelName": "sharewish",
                                    "updateData": ["numbers": ["number_list": newNumberList]]
                                ]
                            )
                        }
                    }
                }
            }
            await MainActor.run {
                sharedStore.delete(currentList)
                isDeleting = false
                dismiss()
            }
        }
    }
    
    /// 加载共享清单的成员列表
    private func loadMembers() {
        guard let wishGroupId = currentList.wishGroupId, !wishGroupId.isEmpty else { return }
        isLoadingMembers = true
        Task {
            if let client = AuthManager.shared.getCloudBaseClient() {
                let result = await client.fetchSharedWishlistMembers(wishGroupId: wishGroupId)
                await MainActor.run {
                    members = result
                    isLoadingMembers = false
                }
            } else {
                await MainActor.run {
                    isLoadingMembers = false
                }
            }
        }
    }
    
    /// 对比两个 SharedWishItem 数组是否内容相同
    private func itemsAreEqual(_ a: [SharedWishItem], _ b: [SharedWishItem]) -> Bool {
        guard a.count == b.count else { return false }
        for (itemA, itemB) in zip(a, b) {
            if itemA.id != itemB.id
                || itemA.name != itemB.name
                || itemA.price != itemB.price
                || itemA.isCompleted != itemB.isCompleted
                || itemA.displayType != itemB.displayType
                || itemA.purchaseLink != itemB.purchaseLink
                || itemA.details != itemB.details
                || itemA.completedBy != itemB.completedBy
                || itemA.addedBy != itemB.addedBy
                || itemA.imageUrl != itemB.imageUrl
                || itemA.imageData != itemB.imageData {
                return false
            }
        }
        return true
    }
    
    /// 根据成员名称生成稳定的头像颜色
    private func memberColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
    
    /// 修改自己在清单中的昵称
    private func editMyNickname() {
        guard let wishGroupId = currentList.wishGroupId else { return }
        let currentUserId = TokenStorage.shared.getSub() ?? ""
        guard !currentUserId.isEmpty else { return }
        
        Task {
            guard let client = AuthManager.shared.getCloudBaseClient() else { return }
            let response = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
            guard let record = response?.data?.records?.first, let docId = record._id else { return }
            
            let numberList = record.numbers?.number_list ?? []
            let newNumberList: [[String: String]] = numberList.map { item in
                ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
            }
            
            // 找到自己当前的名字，填入输入框
            let currentName = numberList.first(where: { $0.number_id == currentUserId })?.number_name ?? ""
            
            await MainActor.run {
                editPendingDocId = docId
                editPendingNumberList = newNumberList
                editPendingUserId = currentUserId
                editNicknameInput = currentName
                showingEditNickname = true
            }
        }
    }
    
    
    
    private func syncToCloud() {
        if isRemoteDeleted { showingDeletedAlert = true; return }
        isSyncing = true
        let listId = currentList.id
        let existingWishGroupId = currentList.wishGroupId
        var items = currentList.items
        let name = currentList.name
        let emoji = currentList.emoji
        let ownerName = currentList.ownerName ?? currentList.myNickname
        let isOwner = currentList.isOwner
        
        Task {
            var syncSucceeded = false
            
            if let client = AuthManager.shared.getCloudBaseClient() {
                // 先上传没有 imageUrl 但有 imageData 的心愿图片到 COS
                let itemsNeedingUpload = items.filter { $0.imageData != nil && (($0.imageUrl ?? "").isEmpty) }
                if !itemsNeedingUpload.isEmpty {
                    print("[共享心愿] 发现 \(itemsNeedingUpload.count) 个心愿需要上传图片到 COS")
                    let uploadItems = itemsNeedingUpload.compactMap { item -> CloudBaseClient.UploadItem? in
                        guard let imageData = item.imageData else { return nil }
                        let objectId = "shared_wishes/\(item.id.uuidString).jpg"
                        return CloudBaseClient.UploadItem(data: imageData, objectId: objectId)
                    }
                    let results = await client.uploadFiles(items: uploadItems)
                    for (index, item) in itemsNeedingUpload.enumerated() {
                        guard index < results.count, results[index].success else { continue }
                        let downloadUrl = results[index].downloadUrl
                        if let itemIndex = items.firstIndex(where: { $0.id == item.id }) {
                            items[itemIndex].imageUrl = downloadUrl
                            print("[共享心愿] 图片上传成功: \(item.name) -> \(downloadUrl)")
                        }
                    }
                    // 更新本地 store 中的 imageUrl（只更新刚上传的）
                    let uploadedItemIds = Set(itemsNeedingUpload.map { $0.id })
                    await MainActor.run {
                        for item in items where uploadedItemIds.contains(item.id) && item.imageUrl != nil {
                            sharedStore.updateItemImageUrl(listId: listId, itemId: item.id, imageUrl: item.imageUrl!)
                        }
                    }
                }
                
                // 确定 wishGroupId：已有就用已有的，没有就生成新的
                let wishGroupId = existingWishGroupId ?? CloudBaseClient.generateWishGroupId()
                let ownerNameStr = ownerName ?? ""
                
                // 先检查远端是否已有该 wishGroupId 的数据
                let existingResponse = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                let hasRemoteData = existingResponse?.data?.records?.first != nil
                print("[共享心愿] existingResponse==nil?\(existingResponse == nil), hasRemoteData=\(hasRemoteData)")
                
                if hasRemoteData {
                    // 远端已有数据，走完整同步流程：pull -> merge -> push
                    print("[共享心愿] 走 hasRemoteData 分支，调用 syncSharedWishlist")
                    let syncResult = await client.syncSharedWishlist(
                        wishGroupId: wishGroupId,
                        localItems: items,
                        listName: name,
                        listEmoji: emoji,
                        isOwner: isOwner
                    )
                    print("[共享心愿] syncResult==nil?\(syncResult == nil), pushSuccess=\(syncResult?.pushSuccess ?? false)")
                    if let syncResult = syncResult, syncResult.pushSuccess {
                        syncSucceeded = true
                        await MainActor.run {
                            sharedStore.applyMergedResult(
                                listId: listId,
                                mergedItems: syncResult.remoteItems,
                                isSynced: true,
                                remoteName: syncResult.remoteName,
                                remoteEmoji: syncResult.remoteEmoji,
                                remoteOwnerName: syncResult.remoteOwnerName
                            )
                        }
                    } else if let syncResult = syncResult {
                        await MainActor.run {
                            sharedStore.applyMergedResult(
                                listId: listId,
                                mergedItems: syncResult.remoteItems,
                                isSynced: false,
                                remoteName: syncResult.remoteName,
                                remoteEmoji: syncResult.remoteEmoji,
                                remoteOwnerName: syncResult.remoteOwnerName
                            )
                        }
                    }
                } else {
                    // 远端无数据，走 create 流程
                    let result = await client.createSharedWishlistFromSharedItems(
                        wishGroupId: wishGroupId,
                        sharedItems: items,
                        listName: name,
                        listEmoji: emoji,
                        ownerName: ownerNameStr.isEmpty ? nil : ownerNameStr
                    )
                    if result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || result?.data?.id != nil {
                        syncSucceeded = true
                        await MainActor.run {
                            sharedStore.markSynced(listId, wishGroupId: wishGroupId)
                        }
                        await client.syncUserInfoShareWishList(wishGroupId: wishGroupId, action: "push")
                    }
                }
                
                // 同步完成后，确保自己在 number_list 中 + 标记已实现心愿的 isArchived
                let currentUserId = TokenStorage.shared.getSub() ?? ""
                let savedNickname = currentList.myNickname ?? ownerName
                let latestResponse = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                if let record = latestResponse?.data?.records?.first, let docId = record._id {
                    // 确保自己在 number_list 中
                    let numberList = record.numbers?.number_list ?? []
                    if !currentUserId.isEmpty {
                        let isMember = numberList.contains { $0.number_id == currentUserId }
                        if isMember {
                            // 已在列表中，从远端提取自己的昵称确保本地 myNickname 最新
                            if let myEntry = numberList.first(where: { $0.number_id == currentUserId }),
                               let remoteName = myEntry.number_name, !remoteName.isEmpty {
                                await MainActor.run {
                                    sharedStore.setMyNickname(listId, nickname: remoteName)
                                }
                            }
                        } else if let nickname = savedNickname, !nickname.isEmpty {
                            var newNumberList: [[String: String]] = numberList.map { item in
                                ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
                            }
                            newNumberList.append(["number_name": nickname, "number_id": currentUserId])
                            _ = await client.callFunction(
                                functionName: "update_sharewish",
                                data: [
                                    "docId": docId,
                                    "modelName": "sharewish",
                                    "updateData": ["numbers": ["number_list": newNumberList]]
                                ]
                            )
                        }
                    }
                    
                    // 对已实现的心愿，通过点路径设置 isArchived: true + archiveBy: userId
                    var archivedUpdateData: [String: Any] = [:]
                    for (idx, item) in items.enumerated() {
                        if item.isCompleted {
                            archivedUpdateData["wishinfo.items.\(idx).isArchived"] = true
                            archivedUpdateData["wishinfo.items.\(idx).archiveBy"] = currentUserId
                        }
                    }
                    if !archivedUpdateData.isEmpty {
                        _ = await client.callFunction(
                            functionName: "update_sharewish",
                            data: [
                                "docId": docId,
                                "modelName": "sharewish",
                                "updateData": archivedUpdateData
                            ]
                        )
                        print("[共享心愿] 已标记 \(archivedUpdateData.count / 2) 个已实现心愿为 isArchived")
                    }
                }
            } else {
                print("[共享心愿] 未登录或 CloudBaseClient 不可用")
            }
            await MainActor.run {
                // 同步完成后更新快照和状态
                if syncSucceeded {
                    // 强制确保 isSynced = true，避免中间状态干扰
                    sharedStore.markSynced(listId, wishGroupId: currentList.wishGroupId)
                    wasAlreadyUnsynced = false
                }
                snapshotItems = currentList.items
                isSyncing = false
                print("[共享心愿] syncToCloud 完成: syncSucceeded=\(syncSucceeded), isSynced=\(currentList.isSynced), wasAlreadyUnsynced=\(wasAlreadyUnsynced), shouldShowUnsynced=\(shouldShowUnsynced)")
            }
        }
    }
    
    /// 点击"已远端同步"标签时触发的手动同步：pull -> merge -> push -> 本地展示
    /// 点击"已远端同步"标签时触发：直接拉取远端数据覆盖本地（以远端为准）
    private func syncFromRemote() {
        if isRemoteDeleted { showingDeletedAlert = true; return }
        guard let wishGroupId = currentList.wishGroupId else { return }
        isSyncing = true
        let listId = currentList.id
        let savedNickname = currentList.myNickname
        
        Task {
            var syncSucceeded = false
            
            if let client = AuthManager.shared.getCloudBaseClient() {
                // 直接拉取远端数据
                let response = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                let record = response?.data?.records?.first
                
                if let record = record {
                    // 将远端数据转为本地模型，完全覆盖本地
                    let remoteWishItems = record.wishinfo?.items ?? []
                    // 获取本地 items 的 imageData 映射，用于保留本地图片
                    let localItems = currentList.items
                    let localImageDataMap: [String: Data] = Dictionary(uniqueKeysWithValues:
                        localItems.compactMap { item -> (String, Data)? in
                            guard let data = item.imageData else { return nil }
                            return (item.id.uuidString, data)
                        }
                    )
                    let remoteItems: [SharedWishItem] = remoteWishItems.map { remote in
                        var remoteImageUrl: String? = nil
                        var remoteImageData: Data? = nil
                        if let url = remote.imageUrl, !url.isEmpty {
                            remoteImageUrl = url
                        } else if let base64Str = remote.imageBase64, !base64Str.isEmpty {
                            remoteImageData = Data(base64Encoded: base64Str)
                        }
                        // 保留本地 imageData（远端没有图片数据时）
                        if remoteImageData == nil, let remoteId = remote.id,
                           let localData = localImageDataMap[remoteId] {
                            remoteImageData = localData
                        }
                        return SharedWishItem(
                            name: remote.name ?? "未知心愿",
                            price: remote.price ?? 0,
                            isCompleted: remote.isCompleted ?? false,
                            displayType: remote.displayType,
                            imageUrl: remoteImageUrl,
                            imageData: remoteImageData,
                            purchaseLink: remote.purchaseLink,
                            details: remote.details,
                            completedBy: remote.completedBy,
                            addedBy: remote.addedBy
                        )
                    }
                    
                    syncSucceeded = true
                    print("[共享心愿] syncFromRemote 拉取远端成功: \(remoteItems.count) 个心愿")
                    
                    // 用远端数据完全覆盖本地
                    await MainActor.run {
                        sharedStore.applyMergedResult(
                            listId: listId,
                            mergedItems: remoteItems,
                            isSynced: true,
                            remoteName: record.name,
                            remoteEmoji: record.emoji,
                            remoteOwnerName: record.owner_name
                        )
                    }
                    
                    // 对已实现的心愿，标记 isArchived
                    let archiveUserId = TokenStorage.shared.getSub() ?? ""
                    if let docId = record._id {
                        var archivedUpdateData: [String: Any] = [:]
                        for (idx, item) in remoteItems.enumerated() {
                            if item.isCompleted {
                                archivedUpdateData["wishinfo.items.\(idx).isArchived"] = true
                                archivedUpdateData["wishinfo.items.\(idx).archiveBy"] = archiveUserId
                            }
                        }
                        if !archivedUpdateData.isEmpty {
                            _ = await client.callFunction(
                                functionName: "update_sharewish",
                                data: [
                                    "docId": docId,
                                    "modelName": "sharewish",
                                    "updateData": archivedUpdateData
                                ]
                            )
                            print("[共享心愿] 已标记 \(archivedUpdateData.count / 2) 个已实现心愿为 isArchived")
                        }
                    }
                    
                    // 检查自己是否在 number_list 中
                    let currentUserId = TokenStorage.shared.getSub() ?? ""
                    if let docId = record._id, !currentUserId.isEmpty {
                        let numberList = record.numbers?.number_list ?? []
                        let isMember = numberList.contains { $0.number_id == currentUserId }
                        if isMember {
                            // 已在列表中，从远端 number_list 提取自己的昵称，确保本地 myNickname 是最新的
                            if let myEntry = numberList.first(where: { $0.number_id == currentUserId }),
                               let remoteName = myEntry.number_name, !remoteName.isEmpty {
                                await MainActor.run {
                                    sharedStore.setMyNickname(listId, nickname: remoteName)
                                }
                            }
                        } else {
                            var newNumberList: [[String: String]] = numberList.map { item in
                                ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
                            }
                            
                            if let nickname = savedNickname, !nickname.isEmpty {
                                newNumberList.append(["number_name": nickname, "number_id": currentUserId])
                                Task {
                                    guard let client = AuthManager.shared.getCloudBaseClient() else { return }
                                    _ = await client.callFunction(
                                        functionName: "update_sharewish",
                                        data: [
                                            "docId": docId,
                                            "modelName": "sharewish",
                                            "updateData": ["numbers": ["number_list": newNumberList]]
                                        ]
                                    )
                                    await MainActor.run {
                                        loadMembers()
                                    }
                                }
                            } else {
                                await MainActor.run {
                                    newNumberList.append(["number_name": "", "number_id": currentUserId])
                                    syncPendingDocId = docId
                                    syncPendingNumberList = newNumberList
                                    syncPendingUserId = currentUserId
                                    syncNicknameInput = ""
                                    showingSyncNicknameInput = true
                                }
                            }
                        }
                    }
                } else {
                    print("[共享心愿] syncFromRemote 远端无数据")
                }
                
                await MainActor.run {
                    loadMembers()
                }
            } else {
                print("[共享心愿] 未登录或 CloudBaseClient 不可用")
            }
            
            await MainActor.run {
                if syncSucceeded {
                    wasAlreadyUnsynced = false
                }
                snapshotItems = currentList.items
                isSyncing = false
                print("[共享心愿] syncFromRemote 完成: syncSucceeded=\(syncSucceeded), isSynced=\(currentList.isSynced), wasAlreadyUnsynced=\(wasAlreadyUnsynced), shouldShowUnsynced=\(shouldShowUnsynced)")
            }
        }
    }
}

// MARK: - 创建共享清单
struct CreateSharedWishlistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sharedStore: SharedWishlistStore
    @ObservedObject var itemStore: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    
    @State private var name = ""
    @State private var emoji = "🎁"
    @State private var ownerName = ""
    @State private var selectedItemIds: Set<UUID> = []
    @State private var filterGroupId: UUID? = nil
    @State private var syncGroup: Bool = false
    @State private var isSaving = false
    
    private let emojis = ["🎁", "🎂", "🎄", "💝", "🏠", "✈️", "🎮", "📱", "👗", "🎵", "📚", "🍰", "🌟", "💍", "🎯", "🎪"]
    
    private var wishlistItems: [Item] {
        itemStore.items.filter { $0.listType == .wishlist }
    }
    
    private var filteredWishlistItems: [Item] {
        if let groupId = filterGroupId {
            return wishlistItems.filter { $0.wishlistGroupId == groupId }
        }
        return wishlistItems
    }
    
    private var isValid: Bool {
        !name.isEmpty && !ownerName.isEmpty && !isSaving
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("清单信息") {
                    TextField("清单名称", text: $name)
                    
                    TextField("分享给好朋友时展示的名字", text: $ownerName)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择图标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                            ForEach(emojis, id: \.self) { e in
                                Button {
                                    emoji = e
                                } label: {
                                    Text(e)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            emoji == e
                                            ? Color.green.opacity(0.2)
                                            : Color.gray.opacity(0.08)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(emoji == e ? Color.green : Color.clear, lineWidth: 2)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 按分组筛选
                if !wishlistGroupStore.groups.isEmpty {
                    Section("按分组筛选") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                GroupFilterChip(name: "全部", isSelected: filterGroupId == nil) {
                                    filterGroupId = nil
                                }
                                
                                ForEach(wishlistGroupStore.groups) { group in
                                    GroupFilterChip(
                                        name: group.name,
                                        icon: group.icon,
                                        color: group.color.swiftUIColor,
                                        isSelected: filterGroupId == group.id
                                    ) {
                                        filterGroupId = group.id
                                    }
                                }
                            }
                        }
                        
                        // 同步分组开关
                        if filterGroupId != nil && !filteredWishlistItems.isEmpty {
                            Toggle(isOn: $syncGroup) {
                                Text("同步分组")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                            }
                            .tint(.green)
                            .onChange(of: syncGroup) { _, newValue in
                                if newValue {
                                    for item in filteredWishlistItems {
                                        selectedItemIds.insert(item.id)
                                    }
                                }
                            }
                            
                            if syncGroup {
                                Text("该分组后续新增、编辑、删除心愿都会自动同步到此共享清单")
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                Section {
                    if filteredWishlistItems.isEmpty {
                        Text("暂无心愿可添加")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredWishlistItems) { item in
                            WishSelectRow(item: item, isSelected: selectedItemIds.contains(item.id)) {
                                if selectedItemIds.contains(item.id) {
                                    selectedItemIds.remove(item.id)
                                } else {
                                    selectedItemIds.insert(item.id)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("选择心愿")
                        Spacer()
                        Text("已选 \(selectedItemIds.count) 个")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("新建共享清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }
    
    private func save() {
        let selectedItems = wishlistItems.filter { selectedItemIds.contains($0.id) }
        let sharedItems = selectedItems
            .map { SharedWishItem(sourceItemId: $0.id, name: $0.name, price: $0.price, displayType: $0.effectiveDisplayType, imageUrl: $0.imageUrl, purchaseLink: $0.purchaseLink.isEmpty ? nil : $0.purchaseLink, details: $0.details.isEmpty ? nil : $0.details) }
        
        // 生成 16 位随机数 ID
        let wishGroupId = CloudBaseClient.generateWishGroupId()
        
        let newList = SharedWishlist(name: name, emoji: emoji, items: sharedItems, wishGroupId: wishGroupId, ownerName: ownerName, myNickname: ownerName, linkedGroupId: syncGroup ? filterGroupId : nil)
        print("[CreateSharedWishlist] ownerName: \(ownerName), isOwner: \(newList.isOwner), syncGroup: \(syncGroup), filterGroupId: \(filterGroupId?.uuidString ?? "nil"), linkedGroupId: \(newList.linkedGroupId?.uuidString ?? "nil")")
        sharedStore.add(newList)
        
        // 调用 API 上传到云端
        if !selectedItems.isEmpty {
            isSaving = true
            let listId = newList.id
            Task {
                if let client = AuthManager.shared.getCloudBaseClient() {
                    let result = await client.createSharedWishlist(
                        wishGroupId: wishGroupId,
                        selectedItems: selectedItems,
                        listName: name,
                        listEmoji: emoji,
                        ownerName: ownerName
                    )
                    if result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || result?.data?.id != nil {
                        await MainActor.run {
                            sharedStore.markSynced(listId, wishGroupId: wishGroupId)
                        }
                        // 同步 userinfo 的 share_wish_list（push）
                        await client.syncUserInfoShareWishList(wishGroupId: wishGroupId, action: "push")
                    }
                } else {
                    print("[共享心愿] 未登录或 CloudBaseClient 不可用，跳过云端上传")
                }
                await MainActor.run {
                    isSaving = false
                }
            }
        }
        
        dismiss()
    }
}

// MARK: - 编辑共享清单
struct EditSharedWishlistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sharedStore: SharedWishlistStore
    @ObservedObject var itemStore: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    
    let originalList: SharedWishlist
    @State private var name: String
    @State private var emoji: String
    @State private var selectedItemIds: Set<UUID>
    @State private var manualItems: [SharedWishItem]
    @State private var filterGroupId: UUID? = nil
    
    private let emojis = ["🎁", "🎂", "🎄", "💝", "🏠", "✈️", "🎮", "📱", "👗", "🎵", "📚", "🍰", "🌟", "💍", "🎯", "🎪"]
    
    init(list: SharedWishlist, sharedStore: SharedWishlistStore, itemStore: ItemStore, wishlistGroupStore: WishlistGroupStore) {
        self.originalList = list
        self.sharedStore = sharedStore
        self.itemStore = itemStore
        self.wishlistGroupStore = wishlistGroupStore
        _name = State(initialValue: list.name)
        _emoji = State(initialValue: list.emoji)
        
        let linked = Set(list.items.compactMap(\.sourceItemId))
        _selectedItemIds = State(initialValue: linked)
        _manualItems = State(initialValue: list.items.filter { $0.sourceItemId == nil })
    }
    
    private var wishlistItems: [Item] {
        itemStore.items.filter { $0.listType == .wishlist }
    }
    
    private var filteredWishlistItems: [Item] {
        if let groupId = filterGroupId {
            return wishlistItems.filter { $0.wishlistGroupId == groupId }
        }
        return wishlistItems
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("清单信息") {
                    TextField("清单名称", text: $name)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择图标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                            ForEach(emojis, id: \.self) { e in
                                Button {
                                    emoji = e
                                } label: {
                                    Text(e)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            emoji == e
                                            ? Color.green.opacity(0.2)
                                            : Color.gray.opacity(0.08)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(emoji == e ? Color.green : Color.clear, lineWidth: 2)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 按分组筛选
                if !wishlistGroupStore.groups.isEmpty {
                    Section("按分组筛选") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                GroupFilterChip(name: "全部", isSelected: filterGroupId == nil) {
                                    filterGroupId = nil
                                }
                                
                                ForEach(wishlistGroupStore.groups) { group in
                                    GroupFilterChip(
                                        name: group.name,
                                        icon: group.icon,
                                        color: group.color.swiftUIColor,
                                        isSelected: filterGroupId == group.id
                                    ) {
                                        filterGroupId = group.id
                                    }
                                }
                            }
                        }
                        
                        if !filteredWishlistItems.isEmpty {
                            let allFilteredSelected = filteredWishlistItems.allSatisfy { selectedItemIds.contains($0.id) }
                            Button {
                                if allFilteredSelected {
                                    for item in filteredWishlistItems {
                                        selectedItemIds.remove(item.id)
                                    }
                                } else {
                                    for item in filteredWishlistItems {
                                        selectedItemIds.insert(item.id)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: allFilteredSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(allFilteredSelected ? .green : .gray.opacity(0.3))
                                    Text(allFilteredSelected ? "取消全选" : "全选当前分组")
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
                
                Section {
                    if filteredWishlistItems.isEmpty {
                        Text("暂无心愿可添加")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredWishlistItems) { item in
                            WishSelectRow(item: item, isSelected: selectedItemIds.contains(item.id)) {
                                if selectedItemIds.contains(item.id) {
                                    selectedItemIds.remove(item.id)
                                } else {
                                    selectedItemIds.insert(item.id)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("选择心愿")
                        Spacer()
                        Text("已选 \(selectedItemIds.count) 个")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("编辑共享清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        let existingMap = Dictionary(uniqueKeysWithValues: originalList.items.compactMap { item -> (UUID, Bool)? in
            guard let sid = item.sourceItemId else { return nil }
            return (sid, item.isCompleted)
        })
        
        let linkedItems = wishlistItems
            .filter { selectedItemIds.contains($0.id) }
            .map { item in
                SharedWishItem(
                    sourceItemId: item.id,
                    name: item.name,
                    price: item.price,
                    isCompleted: existingMap[item.id] ?? false,
                    displayType: item.effectiveDisplayType,
                    imageUrl: item.imageUrl,
                    purchaseLink: item.purchaseLink.isEmpty ? nil : item.purchaseLink,
                    details: item.details.isEmpty ? nil : item.details
                )
            }
        
        var updated = originalList
        updated.name = name
        updated.emoji = emoji
        updated.items = manualItems + linkedItems
        sharedStore.update(updated)
        dismiss()
    }
}

// MARK: - 编辑单个共享心愿
struct EditSharedWishItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sharedStore: SharedWishlistStore
    
    let listId: UUID
    let originalItem: SharedWishItem
    let isOwner: Bool
    
    @State private var name: String
    @State private var priceText: String
    @State private var displayType: String
    @State private var isCompleted: Bool
    @State private var purchaseLink: String
    @State private var details: String
    @State private var imageData: Data?
    @State private var showingImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var fullScreenImage: UIImage? = nil
    
    init(item: SharedWishItem, listId: UUID, isOwner: Bool, sharedStore: SharedWishlistStore) {
        self.originalItem = item
        self.listId = listId
        self.isOwner = isOwner
        self.sharedStore = sharedStore
        _name = State(initialValue: item.name)
        _priceText = State(initialValue: String(format: "%.0f", item.price))
        _displayType = State(initialValue: item.displayType ?? "")
        _isCompleted = State(initialValue: item.isCompleted)
        _purchaseLink = State(initialValue: item.purchaseLink ?? "")
        _details = State(initialValue: item.details ?? "")
        _imageData = State(initialValue: item.imageData)
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ownerEditView
        }
    }
    
    // MARK: - Owner 编辑视图（与编辑普通心愿一致）
    @State private var isCustomDisplayType: Bool = false
    @State private var customDisplayType: String = ""
    @State private var selectedStandardType: ItemType = .other
    @State private var showingNewTypeInput = false
    @State private var newTypeInput = ""
    
    private var ownerEditView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 📝 心愿详情
                VStack(alignment: .leading, spacing: 10) {
                    CartoonSectionHeader(emoji: "📝", title: "心愿详情", color: .blue)
                    CartoonTextField(placeholder: "心愿名字", text: $name)
                    CartoonTextField(placeholder: "价格", text: $priceText, keyboardType: .decimalPad)
                    CartoonTextField(placeholder: "购买链接", text: $purchaseLink, keyboardType: .URL)
                }
                .cartoonCard()
                
                // 🏷️ 展示类型卡片
                VStack(alignment: .leading, spacing: 14) {
                    CartoonSectionHeader(emoji: "🏷️", title: "展示类型", color: .blue)
                    
                    HStack {
                        Text("自定义类型")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Toggle("", isOn: $isCustomDisplayType)
                            .labelsHidden()
                            .tint(.pink)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    
                    if isCustomDisplayType {
                        FlowLayout(spacing: 8) {
                            // 新增自定义类型 tag
                            Button {
                                newTypeInput = ""
                                showingNewTypeInput = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.caption)
                                    Text("新增")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(.purple)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if !customDisplayType.isEmpty {
                            Text("当前：\(customDisplayType)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.purple)
                        }
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                Button {
                                    selectedStandardType = type
                                    displayType = type.rawValue
                                } label: {
                                    HStack(spacing: 4) {
                                        type.iconImage(size: 20)
                                            .font(.caption)
                                        Text(type.rawValue)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(selectedStandardType == type ? .bold : .medium)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(type.color.opacity(selectedStandardType == type ? 0.2 : 0.08))
                                    )
                                    .foregroundStyle(selectedStandardType == type ? type.color : type.color.opacity(0.7))
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedStandardType == type ? type.color.opacity(0.3) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .cartoonCard()
                
                // 📷 照片 + 描述
                VStack(alignment: .leading, spacing: 14) {
                    CartoonSectionHeader(emoji: "📷", title: "照片", color: .blue)
                    
                    VStack(spacing: 0) {
                        if let imageData = imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 220)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .onTapGesture { fullScreenImage = uiImage }
                            
                            HStack(spacing: 0) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("更换")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                
                                Divider()
                                    .frame(height: 20)
                                
                                Button {
                                    self.imageData = nil
                                    selectedPhoto = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("删除")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if let imageUrl = originalItem.imageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 220)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                case .failure:
                                    RoundedRectangle(cornerRadius: 0)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                        .frame(height: 200)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.secondary)
                                        )
                                default:
                                    RoundedRectangle(cornerRadius: 0)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                        .frame(height: 200)
                                        .overlay(ProgressView())
                                }
                            }
                            
                            HStack(spacing: 0) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("更换")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                
                                Divider()
                                    .frame(height: 20)
                                
                                Button {
                                    self.imageData = nil
                                    selectedPhoto = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("删除")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                                    .frame(height: 200)
                                    .overlay(
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        EmptyView()
                            .onChange(of: selectedPhoto) { _, newValue in
                                Task {
                                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                        imageData = data
                                    }
                                }
                            }
                            .frame(height: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 8)
                    
                    // Say Something
                    CartoonSectionHeader(emoji: "💬", title: "Say Something", color: .blue)
                    TextEditor(text: $details)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("说点什么...")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .cartoonCard()
                
                // ✅ 已实现状态卡片
                VStack(alignment: .leading, spacing: 14) {
                    CartoonSectionHeader(emoji: "✅", title: "实现状态", color: Color(red: 0.3, green: 0.75, blue: 0.45))
                    
                    HStack {
                        Text("🎉 已实现")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Toggle("", isOn: $isCompleted)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    
                    if isCompleted, let completedBy = originalItem.completedBy, !completedBy.isEmpty {
                        HStack(spacing: 6) {
                            Text("🌟")
                            Text("实现者：")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(completedBy)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.45))
                        }
                    }
                }
                .cartoonCard()
                
                // 🗑️ 删除按钮
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Text("删除心愿")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("编辑心愿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .foregroundStyle(.secondary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    save()
                } label: {
                    Text("保存")
                        .fontWeight(.bold)
                        .foregroundStyle(.pink)
                }
                .disabled(!isValid)
            }
        }
        .customBlueConfirmAlert(
            isPresented: $showDeleteConfirm,
            message: "删除后无法恢复，确定要删除「\(name)」吗？",
            confirmText: "删除",
            cancelText: "取消",
            confirmColor: .blue,
            cancelColor: .green,
            backgroundColor: .red,
            width: 260,
            onConfirm: {
                sharedStore.deleteItem(listId: listId, itemId: originalItem.id)
                dismiss()
            }
        )
        .customInputAlert(
            isPresented: $showingNewTypeInput,
            title: "新增展示类型",
            message: "输入新的展示类型名称",
            placeholder: "类型名称",
            text: $newTypeInput,
            onConfirm: {
                let trimmed = newTypeInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    customDisplayType = trimmed
                    displayType = trimmed
                    isCustomDisplayType = true
                }
            }
        )
        .fullScreenImageViewer(uiImage: $fullScreenImage)
        .onAppear {
            // 初始化自定义类型状态
            let dt = originalItem.displayType ?? ""
            if let standardType = ItemType(rawValue: dt) {
                isCustomDisplayType = false
                selectedStandardType = standardType
            } else if !dt.isEmpty {
                isCustomDisplayType = true
                customDisplayType = dt
            }
        }
    }
    
    // MARK: - 非 Owner 详情视图
    private var visitorDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 图片
                if let imageUrl = originalItem.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        case .failure:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 120)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.gray.opacity(0.3))
                                )
                        default:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 120)
                                .overlay(ProgressView())
                        }
                    }
                } else if let imgData = originalItem.imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { fullScreenImage = uiImage }
                }
                
                // 名称和价格
                VStack(alignment: .leading, spacing: 8) {
                    Text(originalItem.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("¥\(String(format: "%.2f", originalItem.price))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
                
                Divider()
                
                // 类型和状态 tag
                HStack(spacing: 8) {
                    if let dType = originalItem.displayType, !dType.isEmpty {
                        HStack(spacing: 4) {
                            if let itemType = ItemType(rawValue: dType) {
                                itemType.iconImage(size: 16)
                                    .font(.caption)
                            } else {
                                Image(systemName: "tag")
                                    .font(.caption)
                            }
                            Text(dType)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 4) {
                        if originalItem.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                        }
                        Text(originalItem.isCompleted ? "已实现" : "未实现")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(originalItem.isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundStyle(originalItem.isCompleted ? .green : .secondary)
                    .clipShape(Capsule())
                    
                    if let addedBy = originalItem.addedBy, !addedBy.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                            Text("\(addedBy)的心愿")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    
                    if originalItem.isCompleted, let by = originalItem.completedBy, !by.isEmpty {
                        Text("被\(by)满足愿望")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                
                // 购买链接
                if let link = originalItem.purchaseLink, !link.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("购买链接")
                            .font(.system(.headline, design: .rounded))
                        Text(link)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.blue)
                            .lineLimit(2)
                    }
                }
                
                // 详情描述
                if let detail = originalItem.details, !detail.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心愿描述")
                            .font(.system(.headline, design: .rounded))
                        Text(detail)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 实现状态切换（非 owner 也可以标记实现）
                VStack(spacing: 12) {
                    HStack {
                        Text("🎉 已实现")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Toggle("", isOn: $isCompleted)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("心愿详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.bold)
            }
        }
        .fullScreenImageViewer(uiImage: $fullScreenImage)
    }
    
    private func save() {
        var updated = originalItem
        if isOwner {
            // Owner 可以修改所有字段
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.price = Double(priceText) ?? originalItem.price
            let finalDisplayType = isCustomDisplayType ? customDisplayType : displayType
            updated.displayType = finalDisplayType.trimmingCharacters(in: .whitespaces).isEmpty ? nil : finalDisplayType.trimmingCharacters(in: .whitespaces)
            updated.purchaseLink = purchaseLink.trimmingCharacters(in: .whitespaces).isEmpty ? nil : purchaseLink.trimmingCharacters(in: .whitespaces)
            updated.details = details.trimmingCharacters(in: .whitespaces).isEmpty ? nil : details.trimmingCharacters(in: .whitespaces)
            updated.imageData = imageData
        }
        // owner 和非 owner 都可以修改已实现状态
        updated.isCompleted = isCompleted
        if isCompleted && originalItem.completedBy == nil {
            updated.completedBy = TokenStorage.shared.getPhoneNumber() ?? "未知用户"
        } else if !isCompleted {
            updated.completedBy = nil
        }
        sharedStore.updateItem(listId: listId, item: updated)
        dismiss()
    }
}

// MARK: - 共享心愿详情页
struct SharedWishItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sharedStore: SharedWishlistStore
    
    let listId: UUID
    let isOwner: Bool
    @State private var item: SharedWishItem
    @State private var showingEdit = false
    @State private var showDeleteConfirm = false
    @State private var fullScreenImage: UIImage? = nil
    @State private var toastMessage: String?
    @State private var showToast = false
    
    init(item: SharedWishItem, listId: UUID, isOwner: Bool, sharedStore: SharedWishlistStore) {
        self.listId = listId
        self.isOwner = isOwner
        self.sharedStore = sharedStore
        _item = State(initialValue: item)
    }
    
    // 从 store 中获取最新数据
    private var currentItem: SharedWishItem {
        if let list = sharedStore.lists.first(where: { $0.id == listId }),
           let found = list.items.first(where: { $0.id == item.id }) {
            return found
        }
        return item
    }
    
    /// 当前用户是否可以编辑此心愿（添加者可编辑，旧数据无 addedBy 时 owner 可编辑）
    private var canEdit: Bool {
        let myNickname = sharedStore.lists.first(where: { $0.id == listId })?.myNickname
        if let addedBy = currentItem.addedBy, !addedBy.isEmpty {
            return addedBy == myNickname
        }
        // 旧数据没有 addedBy，owner 可编辑
        return isOwner
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 图片
                    if let imageUrl = currentItem.imageUrl, !imageUrl.isEmpty {
                        AsyncImage(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            case .failure:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 120)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundStyle(.gray.opacity(0.3))
                                    )
                            default:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 120)
                                    .overlay(ProgressView())
                            }
                        }
                    } else if let imageData = currentItem.imageData,
                              let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture { fullScreenImage = uiImage }
                    }
                    
                    // 名称和价格
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentItem.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("¥\(String(format: "%.2f", currentItem.price))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                        
                        // 状态
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                if currentItem.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                }
                                Text(currentItem.isCompleted ? "已实现" : "未实现")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(currentItem.isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                            .foregroundStyle(currentItem.isCompleted ? .green : .secondary)
                            .clipShape(Capsule())
                            
                            if let addedBy = currentItem.addedBy, !addedBy.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                    Text("\(addedBy)的心愿")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                            }
                            
                            if currentItem.isCompleted, let by = currentItem.completedBy, !by.isEmpty {
                                Text("被\(by)满足愿望")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                    
                    // 类型
                    if let displayType = currentItem.displayType, !displayType.isEmpty {
                        DetailRow(icon: "tag.fill", color: .blue, title: "类型", value: displayType)
                    }
                    
                    // 购买链接
                    if let link = currentItem.purchaseLink, !link.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买链接")
                                .font(.system(.headline, design: .rounded))
                            
                            Button {
                                UIPasteboard.general.string = link
                                toastMessage = "已复制到剪贴板"
                                withAnimation { showToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showToast = false }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 14))
                                    Text(shortenURL(link))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("点击复制")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.blue.opacity(0.8))
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                }
                                .font(.system(.body, design: .rounded))
                                .padding(12)
                                .background(Color.blue.opacity(0.08))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    
                    // 备注
                    if let details = currentItem.details, !details.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "note.text")
                                    .foregroundStyle(.orange)
                                Text("备注")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            Text(details)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    
                    // 删除按钮（owner 可删）
                    if isOwner {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("删除心愿")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("心愿详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("编辑") {
                            showingEdit = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                EditSharedWishItemView(
                    item: currentItem,
                    listId: listId,
                    isOwner: canEdit,
                    sharedStore: sharedStore
                )
            }
            .customBlueConfirmAlert(
                isPresented: $showDeleteConfirm,
                message: "确定删除「\(currentItem.name)」吗？",
                confirmText: "删除",
                cancelText: "取消",
                confirmColor: .blue,
                cancelColor: .green,
                backgroundColor: .red,
                width: 260,
                onConfirm: {
                    sharedStore.deleteItem(listId: listId, itemId: currentItem.id)
                    dismiss()
                }
            )
            .fullScreenImageViewer(uiImage: $fullScreenImage)
            .overlay {
                if showToast, let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .padding(.bottom, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.3), value: showToast)
                }
            }
        }
    }
    
    private func shortenURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString.count > 30 ? String(urlString.prefix(30)) + "..." : urlString
        }
        let path = url.path
        if path.isEmpty || path == "/" {
            return host
        }
        let shortPath = path.count > 15 ? String(path.prefix(15)) + "..." : path
        return host + shortPath
    }
    
    private struct DetailRow: View {
        let icon: String
        let color: Color
        let title: String
        let value: String
        
        var body: some View {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        }
    }
}

// MARK: - 共享清单中添加心愿（复用心愿添加的卡通风格设计）
struct AddSharedWishItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sharedStore: SharedWishlistStore
    
    let listId: UUID
    @State private var name = ""
    @State private var priceText = ""
    @State private var purchaseLink = ""
    @State private var details = ""
    @State private var syncToMyWishlist = false
    
    // 照片
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    
    // 展示类型
    @State private var isCustomDisplayType = false
    @State private var customDisplayType = ""
    @State private var selectedDisplayType: ItemType = .other
    @State private var showingNewTypeInput = false
    @State private var newTypeInput = ""
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var finalType: String {
        isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
    }
    
    init(listId: UUID, sharedStore: SharedWishlistStore) {
        self.listId = listId
        self.sharedStore = sharedStore
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 📝 基本信息
                    VStack(alignment: .leading, spacing: 10) {
                        CartoonSectionHeader(emoji: "📝", title: "心愿详情", color: .green)
                        CartoonTextField(placeholder: "心愿名字", text: $name)
                        CartoonTextField(placeholder: "价格", text: $priceText, keyboardType: .decimalPad)
                        CartoonTextField(placeholder: "购买链接", text: $purchaseLink, keyboardType: .URL)
                    }
                    .cartoonCard()
                    
                    // 🏷️ 展示类型
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "🏷️", title: "展示类型", color: .green)
                        
                        // 自定义切换
                        HStack {
                            Text("自定义类型")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: $isCustomDisplayType)
                                .labelsHidden()
                                .tint(.green)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                        
                        if isCustomDisplayType {
                            // 自定义类型输入 + 新增 tag
                            FlowLayout(spacing: 8) {
                                // 新增 tag
                                Button {
                                    newTypeInput = ""
                                    showingNewTypeInput = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption)
                                        Text("新增")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                    )
                                    .foregroundStyle(.green)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if !customDisplayType.isEmpty {
                                Text("当前：\(customDisplayType)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            // 标准类型选择
                            FlowLayout(spacing: 8) {
                                ForEach(ItemType.allCases, id: \.self) { type in
                                    Button {
                                        selectedDisplayType = type
                                    } label: {
                                        HStack(spacing: 4) {
                                            type.iconImage(size: 20)
                                                .font(.caption)
                                            Text(type.rawValue)
                                                .font(.system(.subheadline, design: .rounded))
                                                .fontWeight(selectedDisplayType == type ? .bold : .medium)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(type.color.opacity(selectedDisplayType == type ? 0.2 : 0.08))
                                        )
                                        .foregroundStyle(selectedDisplayType == type ? type.color : type.color.opacity(0.7))
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedDisplayType == type ? type.color.opacity(0.3) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .cartoonCard()
                    
                    // 📷 照片
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "📷", title: "照片", color: .green)
                        
                        if let imageData = imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            HStack(spacing: 0) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("更换")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundStyle(.blue)
                                
                                Divider()
                                    .frame(height: 20)
                                
                                Button {
                                    self.imageData = nil
                                    selectedPhoto = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("删除")
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundStyle(.red)
                            }
                        } else {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.green.opacity(0.6))
                                    Text("添加照片")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .cartoonCard()
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                await MainActor.run { imageData = data }
                            }
                        }
                    }
                    
                    // 💬 备注
                    VStack(alignment: .leading, spacing: 10) {
                        CartoonSectionHeader(emoji: "💬", title: "Say Something", color: .green)
                        TextEditor(text: $details)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                            .overlay(alignment: .topLeading) {
                                if details.isEmpty {
                                    Text("说点什么...")
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .cartoonCard()
                    
                    // 同步到我的心愿
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $syncToMyWishlist) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("同步到我的心愿")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                Text("同时添加到心愿清单中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                    }
                    .cartoonCard()
                    
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("添加心愿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Text("添加")
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    .disabled(!isValid)
                }
            }
            .customInputAlert(
                isPresented: $showingNewTypeInput,
                title: "新增展示类型",
                message: "输入新的展示类型名称",
                placeholder: "类型名称",
                text: $newTypeInput,
                onConfirm: {
                    let trimmed = newTypeInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        customDisplayType = trimmed
                    }
                }
            )
        }
    }
    
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let price = Double(priceText) ?? 0
        let type = finalType
        let trimmedLink = purchaseLink.trimmingCharacters(in: .whitespaces)
        let trimmedDetails = details.trimmingCharacters(in: .whitespaces)
        
        let newItem = SharedWishItem(
            name: trimmedName,
            price: price,
            displayType: type.isEmpty ? nil : type,
            imageData: imageData,
            purchaseLink: trimmedLink.isEmpty ? nil : trimmedLink,
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            addedBy: sharedStore.lists.first(where: { $0.id == listId })?.myNickname ?? "我"
        )
        
        sharedStore.addItem(listId: listId, item: newItem)
        
        // 同步到我的心愿清单
        if syncToMyWishlist {
            let wishItem = Item(
                name: trimmedName,
                details: trimmedDetails,
                purchaseLink: trimmedLink,
                price: price,
                type: type.isEmpty ? "其他" : type,
                listType: .wishlist,
                displayType: type.isEmpty ? nil : type
            )
            NotificationCenter.default.post(
                name: Notification.Name("AddItemFromSharedWish"),
                object: wishItem
            )
        }
        
        dismiss()
    }
}

// MARK: - 图片选择器
struct SharedWishImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SharedWishImagePicker
        
        init(_ parent: SharedWishImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.imageData = image.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 心愿选择行
struct WishSelectRow: View {
    let item: Item
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .green : .gray.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("¥\(String(format: "%.0f", item.price))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let typeName = item.displayType ?? Optional(item.type) {
                    Text(typeName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pink.opacity(0.1))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 分组筛选标签
struct GroupFilterChip: View {
    let name: String
    var icon: String? = nil
    var color: Color = .green
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(name)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? color : .primary)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// MARK: - 分享给朋友们（绿色背景块）
struct ShareToFriendsBlock: View {
    let wishGroupId: String
    @State private var showingShareSheet = false
    
    var body: some View {
        Button {
            PrivacySettings.copyToClipboard(wishGroupId)
            showingShareSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("分享给我的朋友们")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("点击分享清单给好朋友")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingShareSheet) {
            ShareWishGroupIdSheet(wishGroupId: wishGroupId)
        }
    }
}

// MARK: - 分享清单 ID 弹窗
struct ShareWishGroupIdSheet: View {
    let wishGroupId: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showTitle = false
    @State private var showContent = false
    @State private var showFireworks = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 烟花层
                if showFireworks {
                    FireworksOverlay()
                        .ignoresSafeArea()
                }
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // 标题（1s 渐现）
                    Text("和朋友们一起分享你的心愿吧")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .opacity(showTitle ? 1 : 0)
                        .scaleEffect(showTitle ? 1 : 0.8)
                    
                    // 下方内容（标题出现后再显示）
                    if showContent {
                        VStack(spacing: 20) {
                            // 清单 ID 展示
                            VStack(spacing: 8) {
                                Text("清单 ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(wishGroupId)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .textSelection(.enabled)
                            }
                            
                            // 使用说明
                            VStack(alignment: .leading, spacing: 12) {
                                Text("如何使用")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                
                                ShareStepRow(step: "1", text: "将清单 ID 发送给好朋友")
                                ShareStepRow(step: "2", text: "好朋友打开 App → 共享清单页面")
                                ShareStepRow(step: "3", text: "点击「导入好朋友的清单」")
                                ShareStepRow(step: "4", text: "粘贴清单 ID 即可导入")
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    Spacer()
                    
                    // 复制按钮（带状态提示）
                    if showContent {
                        Button {
                            PrivacySettings.copyToClipboard(wishGroupId)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("已复制到剪贴板")
                            }
                            .fontWeight(.semibold)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // 标题 1s 渐现
            withAnimation(.easeOut(duration: 1.0)) {
                showTitle = true
            }
            // 标题出现后再显示下方内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showContent = true
                }
                withAnimation(.easeInOut) {
                    copied = true
                }
            }
            // 烟花 3s 后消失
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showFireworks = false
                }
            }
        }
    }
}

// MARK: - 分享步骤行
struct ShareStepRow: View {
    let step: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.green))
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

