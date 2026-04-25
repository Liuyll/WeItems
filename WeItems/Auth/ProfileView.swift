//
//  ProfileView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

// 物品排序方式
enum ItemSortMode: String, CaseIterable {
    case addedDate = "添加时间"
    case ownedDate = "拥有时间"
    case price = "按价值"
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var itemStore: ItemStore
    @EnvironmentObject var sharedWishlistStore: SharedWishlistStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var groupStore: GroupStore
    @EnvironmentObject var wishlistGroupStore: WishlistGroupStore
    
    var onBack: (() -> Void)? = nil
    
    @State private var showingLogoutConfirm = false
    @State private var isSyncing = false
    @State private var isICloudSyncing = false
    @State private var toastMessage: String?
    @State private var showToast = false
    @AppStorage("remoteNeedsSync") private var remoteNeedsSync = false
    @AppStorage("iCloudNeedsSync") private var iCloudNeedsSync = false
    @AppStorage("assetFaceIDLock") private var assetFaceIDLock = false
    @AppStorage("itemSortMode") private var itemSortMode: ItemSortMode = .addedDate
    
    @State private var showingProUpgrade = false
    @State private var selectedPhoto: PhotosPickerItem?
    @ObservedObject private var avatarStore = AvatarStore.shared
    @ObservedObject private var iapManager = IAPManager.shared
    
    @State private var showingLogin = false
    
    private var firstRecordInfo: (dateStr: String, days: Int) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        
        // 已登录时优先用注册时间
        if authManager.isAuthenticated, let registerDate = TokenStorage.shared.getRegisterDate() {
            let days = max(Calendar.current.dateComponents([.day], from: registerDate, to: Date()).day ?? 0, 0)
            return (fmt.string(from: registerDate), days)
        }
        
        // 兜底：用最早的记录时间
        let allDates: [Date] = itemStore.items.map { $0.createdAt } + financeStore.records.map { $0.date }
        guard let earliest = allDates.min() else { return ("今天", 0) }
        let days = max(Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0, 0)
        return (fmt.string(from: earliest), days)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    // 头像区域
                    Section {
                        if authManager.isAuthenticated {
                            HStack(spacing: 14) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    if let img = avatarStore.avatarImage {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundStyle(.gray.opacity(0.4))
                                            .frame(width: 48, height: 48)
                                    }
                                }
                                .onChange(of: selectedPhoto) { _, newValue in
                                    Task {
                                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                                           let uiImage = UIImage(data: data) {
                                            avatarStore.saveAvatar(uiImage)
                                        }
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    let info = firstRecordInfo
                                    Text("从 \(info.dateStr) 开始记录")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(info.days < 7 ? "才加入我们没多久" : "已经过去 \(info.days) 天")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .listRowSeparator(.hidden)
                        } else {
                            Button {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showingLogin = true
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(width: 48, height: 48)
                                    
                                    Text("登录开始记录生涯")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .listRowBackground(Color.blue)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    // Pro 会员
                    Section {
                        if iapManager.isPro {
                            HStack {
                                if iapManager.vipLevel == .grantedVIP {
                                    Text("lyl 的朋友，您好")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                } else if iapManager.vipLevel == .masterVIP {
                                    Text("尊贵的终生会员")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                } else {
                                    Text("已经是 Pro 版本")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(iapManager.vipLevel == .grantedVIP || iapManager.vipLevel == .masterVIP ? Color.pink : Color.green)
                            .listRowSeparator(.hidden)
                        } else {
                            Button {
                                showingProUpgrade = true
                            } label: {
                                HStack {
                                    Text("升级 Pro 版本")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(
                                Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0)
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    // 同步设置
                    Section {
                        if iapManager.isVIPActive {
                            // 远端同步
                            Button {
                                performSync()
                            } label: {
                                HStack {
                                    Label {
                                        Text("远端同步")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                            .foregroundStyle(.green)
                                    }
                                    if remoteNeedsSync {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                    }
                                    Spacer()
                                    if isSyncing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(isSyncing)
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            
                            // iCloud 同步
                            Button {
                                performICloudSync()
                            } label: {
                                HStack {
                                    Label {
                                        Text("iCloud 同步")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: isICloudSyncing ? "icloud.and.arrow.up.fill" : "icloud.fill")
                                            .foregroundStyle(.cyan)
                                    }
                                    if iCloudNeedsSync {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                    }
                                    Spacer()
                                    if isICloudSyncing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(isICloudSyncing)
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            
                            // 同步历史
                            NavigationLink(destination: SyncHistoryView()) {
                                Label {
                                    Text("同步历史")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.blue)
                                }
                                .foregroundStyle(.primary)
                            }
                            .listRowSeparator(.hidden)
                        } else {
                            // 远端同步
                            Button {
                                showingProUpgrade = true
                            } label: {
                                HStack {
                                    Label {
                                        Text("远端同步")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(.green)
                                    }
                                    Spacer()
                                    ProBadge(fontSize: 11, paddingH: 6, paddingV: 2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            
                            // iCloud 同步
                            Button {
                                showingProUpgrade = true
                            } label: {
                                HStack {
                                    Label {
                                        Text("iCloud 同步")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "icloud.fill")
                                            .foregroundStyle(.cyan)
                                    }
                                    Spacer()
                                    ProBadge(fontSize: 11, paddingH: 6, paddingV: 2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            
                            // 同步历史
                            Button {
                                showingProUpgrade = true
                            } label: {
                                HStack {
                                    Label {
                                        Text("同步历史")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    ProBadge(fontSize: 11, paddingH: 6, paddingV: 2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("同步设置")
                    }
                    
                    // 功能设置
                    Section("功能设置") {
                        // 物品排序
                        Picker(selection: $itemSortMode) {
                            ForEach(ItemSortMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        } label: {
                            Label {
                                Text("物品排序")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                        .listRowSeparator(.hidden)
                        
                        if iapManager.isVIPActive {
                            Toggle(isOn: $assetFaceIDLock) {
                                Label {
                                    Text("资产面容解锁")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "faceid")
                                }
                            }
                            .tint(.orange)
                            .listRowSeparator(.hidden)
                            if assetFaceIDLock {
                                HStack {
                                    Image(systemName: "info.circle").foregroundStyle(.blue)
                                    Text("进入个人资产页面时需要 Face ID 验证")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .listRowSeparator(.hidden)
                            }
                        } else {
                            Button {
                                showingProUpgrade = true
                            } label: {
                                HStack {
                                    Label {
                                        Text("资产面容解锁")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "faceid")
                                            .foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    ProBadge(fontSize: 11, paddingH: 6, paddingV: 2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    // 关于
                    Section("关于") {
                        // iCloud 自动同步
                        NavigationLink {
                            PrivacySettingsView()
                        } label: {
                            Label {
                                Text("功能设置")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundStyle(.blue)
                            }
                            .foregroundStyle(.primary)
                        }
                        .listRowSeparator(.hidden)
                        
                        HStack {
                            Label {
                                Text("版本")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2")\(AppEnvironment.versionSuffix)")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                    }
                    
                    #if DEBUG
                    Section("Debug 测试") {
                        NavigationLink {
                            DebugTestView()
                                .environmentObject(authManager)
                        } label: {
                            Label {
                                Text("调试工具")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "hammer.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    #endif
                    
                    // 账号管理（始终在最底部）
                    if authManager.isAuthenticated {
                        Section("账号管理") {
                            NavigationLink {
                                AccountManagementView()
                                    .environmentObject(authManager)
                            } label: {
                                Label {
                                    Text("我的账号")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "person.text.rectangle")
                                        .foregroundStyle(.purple)
                                }
                                .foregroundStyle(.primary)
                            }
                            .listRowSeparator(.hidden)
                            
                            Button {
                                showingLogoutConfirm = true
                            } label: {
                                Label {
                                    Text("退出登录")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                } icon: {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                                .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onBack != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            onBack?()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView()
            }
            .customBlueConfirmAlert(
                isPresented: $showingLogoutConfirm,
                message: "退出登录后，数据将不再自动同步到云端。确定要退出吗？",
                confirmText: "退出",
                cancelText: "取消",
                isDestructive: true,
                onConfirm: {
                    authManager.logout()
                    onBack?()
                }
            )
        }
        .overlay {
            if showingLogin {
                ProfileAuthView(onClose: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingLogin = false
                    }
                })
                .environmentObject(authManager)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showingLogin)
    }
    private func showToastMessage(_ message: String, autoDismiss: Bool = true) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        if autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showToast = false
                }
            }
        }
    }
    
    /// 执行数据同步（物品、心愿、共享清单）
    private func performSync() {
        guard IAPManager.shared.isVIPActive else {
            showingProUpgrade = true
            return
        }
        
        isSyncing = true
        showToastMessage("远端同步 ing", autoDismiss: false)
        
        Task {
            await performSyncTask()
        }
    }
    
    /// 同步核心逻辑（可被 performSync 和登录后自动同步调用）
    private func performSyncTask() async {
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
            
            // 同时同步物品、心愿清单、获取 userinfo 和储蓄投资
            let deletedRecords = itemStore.deletedItemRecords
            async let itemsResult = client.syncItems(items: itemStore.items, deletedItemRecords: deletedRecords)
            async let wishesResult = client.syncWishes(items: itemStore.items, deletedItemRecords: deletedRecords)
            async let userInfoResult = client.fetchUserInfo()
            
            // 储蓄投资+分组同步：上传到 savinginfo 模型
            let nonSalaryRecords = financeStore.records.filter { $0.incomePeriod != .salary }
            let salaryRec = financeStore.salaryRecord
            let largeItemsPrice = itemStore.items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let normalItemsPrice = itemStore.items.filter { $0.listType == .items && !$0.isArchived && !$0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let allItemsPrice = largeItemsPrice + normalItemsPrice
            async let savingResult = client.syncSavingInfo(
                records: nonSalaryRecords,
                salaryRecord: salaryRec,
                goal: financeStore.savingsGoal,
                totalAssets: financeStore.calculatedTotalAssets(itemsTotalPrice: allItemsPrice),
                groups: groupStore.groups,
                wishlistGroups: wishlistGroupStore.groups,
                userSettings: UserSettings.fromLocal(),
                deletedRecordIDs: financeStore.deletedRecordIDs
            )
            
            let (itemsSyncResult, wishesSyncResult, userInfoResponse) = await (itemsResult, wishesResult, userInfoResult)
            let savingSyncResult = await savingResult
            let savingSuccess = savingSyncResult != nil
            print("[手动同步] 储蓄投资同步: \(savingSuccess ? "成功" : "失败")")
            
            // 回写远端储蓄数据到本地
            if let result = savingSyncResult {
                await MainActor.run {
                    financeStore.suppressUnsyncFlag = true
                    financeStore.applyRemoteData(records: result.records, salaryRecord: result.salaryRecord, goal: result.goal)
                    if let remoteGroups = result.groups {
                        groupStore.applyRemoteGroups(remoteGroups)
                    }
                    if let remoteWG = result.wishlistGroups {
                        wishlistGroupStore.applyRemoteGroups(remoteWG)
                    }
                    result.userSettings?.applyToLocal()
                    financeStore.clearDeletedRecordIDs()
                }
            }
            
            // 从 userinfo 读取 VIP 信息
            if let records = userInfoResponse?.data?.records, let record = records.first {
                if let vipInfo = record.vip_type, let vipType = vipInfo.type {
                    await MainActor.run {
                        IAPManager.shared.applyRemoteVIPInfo(
                            type: vipType,
                            startDate: vipInfo.startDate,
                            expireDate: vipInfo.expireDate
                        )
                    }
                    print("[手动同步] 从云端获取 VIP 信息: type=\(vipType)")
                }
                
                // 如果本地有 VIP 但云端没有，同步到云端
                if record.vip_type == nil && IAPManager.shared.isPro {
                    await IAPManager.shared.syncVIPToCloud()
                }
            }
            
            // 从 userinfo 的 share_wish_list 同步共享清单
            if let records = userInfoResponse?.data?.records, let record = records.first,
               let shareWishList = record.share_wish_list, !shareWishList.isEmpty {
                print("[手动同步] 从 userinfo 获取到 \(shareWishList.count) 个共享清单 ID")
                
                for wishGroupId in shareWishList {
                    let response = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                    
                    guard let sharedRecord = response?.data?.records?.first else {
                        continue
                    }
                    
                    let listName = sharedRecord.effectiveName ?? "好朋友的清单"
                    let listEmoji = sharedRecord.effectiveEmoji ?? "🎁"
                    let ownerName = sharedRecord.effectiveOwnerName
                    let remoteItems = sharedRecord.wishinfo?.items ?? []
                    
                    let sharedItems: [SharedWishItem] = remoteItems.compactMap { remote in
                        guard let idStr = remote.id, !idStr.isEmpty,
                              let remoteUUID = UUID(uuidString: idStr) else { return nil }
                        var remoteImageData: Data? = nil
                        if let base64Str = remote.imageBase64, !base64Str.isEmpty {
                            remoteImageData = Data(base64Encoded: base64Str)
                        }
                        return SharedWishItem(
                            id: remoteUUID,
                            sourceItemId: remote.sourceItemId.flatMap { UUID(uuidString: $0) },
                            name: remote.name ?? "未知心愿",
                            price: remote.price ?? 0,
                            isCompleted: remote.isCompleted ?? false,
                            displayType: remote.displayType,
                            imageUrl: remote.imageUrl,
                            imageData: remoteImageData,
                            purchaseLink: remote.purchaseLink,
                            details: remote.details,
                            completedBy: remote.completedBy,
                            addedBy: remote.addedBy
                        )
                    }
                    
                    // 从远端 number_list 中提取当前用户的昵称
                    let currentUserId = TokenStorage.shared.getSub() ?? ""
                    let numberList = sharedRecord.numbers?.number_list ?? []
                    let myRemoteNickname: String? = {
                        if !currentUserId.isEmpty,
                           let myEntry = numberList.first(where: { $0.number_id == currentUserId }),
                           let name = myEntry.number_name, !name.isEmpty {
                            return name
                        }
                        return nil
                    }()
                    
                    // 判断当前用户是否是该清单的 owner
                    // owner 是创建清单时第一个加入 number_list 的人，或者 owner_name 与自己的昵称匹配
                    let isOwner: Bool = {
                        if !currentUserId.isEmpty {
                            // 如果 number_list 第一个条目的 number_id 是自己，则是 owner
                            if let firstMember = numberList.first,
                               firstMember.number_id == currentUserId {
                                return true
                            }
                            // 或者 owner_name 与自己在清单中的昵称一致
                            if let on = ownerName, !on.isEmpty,
                               let mn = myRemoteNickname, !mn.isEmpty,
                               on == mn {
                                return true
                            }
                        }
                        return false
                    }()
                    
                    let remoteLinkedGroupId: UUID? = {
                        if let lgIdStr = sharedRecord.baseinfo?.linked_group_id, !lgIdStr.isEmpty {
                            return UUID(uuidString: lgIdStr)
                        }
                        return nil
                    }()
                    
                    await MainActor.run {
                        // 过滤本地已删除的心愿
                        let deletedNames = sharedWishlistStore.deletedItemNames[wishGroupId] ?? []
                        let filteredItems = deletedNames.isEmpty ? sharedItems : sharedItems.filter { !deletedNames.contains($0.name) }
                        
                        if let existingIndex = sharedWishlistStore.lists.firstIndex(where: { $0.wishGroupId == wishGroupId }) {
                            // 本地已有该清单，用远端数据更新
                            sharedWishlistStore.applyMergedResult(
                                listId: sharedWishlistStore.lists[existingIndex].id,
                                mergedItems: filteredItems,
                                isSynced: true,
                                remoteName: listName,
                                remoteEmoji: listEmoji,
                                remoteOwnerName: ownerName
                            )
                            // 从远端 number_list 同步自己的昵称
                            if let nickname = myRemoteNickname {
                                sharedWishlistStore.setMyNickname(sharedWishlistStore.lists[existingIndex].id, nickname: nickname)
                            }
                            // 从远端恢复 linkedGroupId
                            if sharedWishlistStore.lists[existingIndex].linkedGroupId == nil, let lgId = remoteLinkedGroupId {
                                sharedWishlistStore.lists[existingIndex].linkedGroupId = lgId
                            }
                            sharedWishlistStore.clearDeletedItemNames(for: wishGroupId)
                        } else {
                            // 本地没有该清单，从远端创建
                            let newList = SharedWishlist(
                                name: listName,
                                emoji: listEmoji,
                                items: filteredItems,
                                isSynced: true,
                                wishGroupId: wishGroupId,
                                isOwner: isOwner,
                                ownerName: ownerName,
                                myNickname: myRemoteNickname,
                                linkedGroupId: remoteLinkedGroupId
                            )
                            sharedWishlistStore.add(newList)
                        }
                    }
                }
            } else {
                print("[手动同步] userinfo 无 share_wish_list 或为空")
            }
            
            // 将本地共享清单 ID 同步到 userinfo（本地有但远端没有的）
            let remoteWishIds = Set(userInfoResponse?.data?.records?.first?.share_wish_list ?? [])
            let localWishIds = sharedWishlistStore.lists.compactMap { $0.wishGroupId }
            let missingIds = localWishIds.filter { !remoteWishIds.contains($0) }
            if !missingIds.isEmpty {
                print("[手动同步] 本地有 \(missingIds.count) 个共享清单未同步到 userinfo，开始上传...")
                for wishGroupId in missingIds {
                    await client.syncUserInfoShareWishList(wishGroupId: wishGroupId, action: "push")
                }
            }
            
            // 将 owner 共享清单的名字和 emoji 推送到远端（修复远端 name 为空的问题）
            for list in sharedWishlistStore.lists where list.isOwner {
                guard let wishGroupId = list.wishGroupId else { continue }
                let _ = await client.updateSharedWishlist(
                    wishGroupId: wishGroupId,
                    sharedItems: list.items,
                    listName: list.name,
                    listEmoji: list.emoji,
                    linkedGroupId: list.linkedGroupId?.uuidString
                )
            }
            
            // 收集需要下载图片的远端物品
            var allRemoteItems: [Item] = []
            if let result = itemsSyncResult {
                allRemoteItems.append(contentsOf: result.remoteOnlyItems)
            }
            if let result = wishesSyncResult {
                allRemoteItems.append(contentsOf: result.remoteOnlyItems)
            }
            
            var imageUrlsToDownload: [String: String] = [:]
            for item in allRemoteItems {
                if let remoteUrl = item.imageUrl, !remoteUrl.isEmpty {
                    imageUrlsToDownload[item.id.uuidString] = remoteUrl
                }
            }
            
            // 先添加数据（不等图片下载），让列表立即展示
            await MainActor.run {
                isSyncing = false
                itemStore.suppressUnsyncFlag = true
                financeStore.suppressUnsyncFlag = true
                
                var allSuccess = true
                var message = ""
                
                // 处理物品同步结果
                if let result = itemsSyncResult {
                    for deletedItemId in result.deletedLocalItemIds {
                        if let item = itemStore.items.first(where: { $0.itemId == deletedItemId && $0.listType == .items }) {
                            itemStore.delete(item)
                        }
                    }
                    for var remoteItem in result.remoteOnlyItems {
                        guard !remoteItem.itemId.isEmpty else { continue }
                        if !itemStore.items.contains(where: { $0.itemId == remoteItem.itemId }) {
                            remoteItem.isSynced = true
                            itemStore.add(remoteItem)
                        }
                    }
                } else {
                    allSuccess = false
                }
                
                // 处理心愿清单同步结果
                if let result = wishesSyncResult {
                    for deletedItemId in result.deletedLocalItemIds {
                        if let item = itemStore.items.first(where: { $0.itemId == deletedItemId && $0.listType == .wishlist }) {
                            itemStore.delete(item)
                        }
                    }
                    for var remoteItem in result.remoteOnlyItems {
                        guard !remoteItem.itemId.isEmpty else { continue }
                        if !itemStore.items.contains(where: { $0.itemId == remoteItem.itemId }) {
                            remoteItem.isSynced = true
                            itemStore.add(remoteItem)
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
                    itemStore.markAllItemsSynced()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    financeStore.hasUnsyncedChanges = false
                    remoteNeedsSync = false
                    // 清理已同步的删除记录
                    var syncedDeleteIds = itemsSyncResult?.deletedRemoteItemIds ?? []
                    syncedDeleteIds.append(contentsOf: wishesSyncResult?.deletedRemoteItemIds ?? [])
                    if !syncedDeleteIds.isEmpty {
                        itemStore.clearDeletedRecords(itemIds: syncedDeleteIds)
                    }
                    message = "同步成功"
                } else if itemsSyncResult != nil || wishesSyncResult != nil {
                    itemStore.markSyncCompleted()
                    itemStore.markAllItemsSynced()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    financeStore.hasUnsyncedChanges = false
                    remoteNeedsSync = false
                    var syncedDeleteIds = itemsSyncResult?.deletedRemoteItemIds ?? []
                    syncedDeleteIds.append(contentsOf: wishesSyncResult?.deletedRemoteItemIds ?? [])
                    if !syncedDeleteIds.isEmpty {
                        itemStore.clearDeletedRecords(itemIds: syncedDeleteIds)
                    }
                    message = "部分同步成功"
                } else {
                    message = "同步失败，请检查网络连接"
                }
                
                // 物品已同步完成，恢复共享清单的 linkedGroupId
                for i in sharedWishlistStore.lists.indices {
                    guard sharedWishlistStore.lists[i].isOwner,
                          sharedWishlistStore.lists[i].linkedGroupId == nil else { continue }
                    for si in sharedWishlistStore.lists[i].items {
                        if let sid = si.sourceItemId,
                           let localItem = itemStore.items.first(where: { $0.id == sid }),
                           let gid = localItem.wishlistGroupId {
                            sharedWishlistStore.lists[i].linkedGroupId = gid
                            break
                        }
                    }
                }
                sharedWishlistStore.forceSave()
                
                // 记录同步历史
                let record = SyncRecord(
                    id: UUID(),
                    date: Date(),
                    trigger: .manual,
                    itemsUploaded: itemsSyncResult?.uploadedCount ?? 0,
                    itemsUpdated: itemsSyncResult?.updatedCount ?? 0,
                    itemsDeletedLocal: itemsSyncResult?.deletedLocalItemIds.count ?? 0,
                    itemsFailed: itemsSyncResult?.failedIds.count ?? 0,
                    wishesUploaded: wishesSyncResult?.uploadedCount ?? 0,
                    wishesUpdated: wishesSyncResult?.updatedCount ?? 0,
                    wishesDeletedLocal: wishesSyncResult?.deletedLocalItemIds.count ?? 0,
                    wishesFailed: wishesSyncResult?.failedIds.count ?? 0,
                    savingInfoSynced: savingSuccess,
                    success: allSuccess || itemsSyncResult != nil || wishesSyncResult != nil,
                    message: message
                )
                SyncHistoryStore.shared.addRecord(record)
                
                itemStore.suppressUnsyncFlag = false
                financeStore.suppressUnsyncFlag = false
                showToastMessage(message)
            }
            
            // 后台异步下载远端图片（不阻塞 UI）
            if !imageUrlsToDownload.isEmpty {
                Task {
                    print("[手动同步] 后台下载 \(imageUrlsToDownload.count) 张远端图片...")
                    let downloadedImages = await client.downloadRemoteImages(imageUrls: imageUrlsToDownload)
                    await MainActor.run {
                        for (itemIdStr, imageData) in downloadedImages {
                            guard let uuid = UUID(uuidString: itemIdStr) else { continue }
                            if let index = itemStore.items.firstIndex(where: { $0.id == uuid }) {
                                itemStore.items[index].imageData = imageData
                                _ = itemStore.saveImage(imageData, for: uuid)
                            }
                        }
                        if !downloadedImages.isEmpty {
                            print("[手动同步] 后台图片下载完成: \(downloadedImages.count) 张")
                        }
                    }
                }
            }
        }
    
    /// 执行 iCloud 同步（物品、心愿、储蓄投资）
    /// 逻辑与远端同步一致，但读写 iCloud 存储，图片直接存 iCloud 无需上传 COS
    private func performICloudSync() {
        guard IAPManager.shared.isVIPActive else {
            showingProUpgrade = true
            return
        }
        
        isICloudSyncing = true
        
        Task {
            // 让出一帧，确保 UI 先刷新显示 loading
            await Task.yield()
            
            // 检查 iCloud 可用性
            guard ICloudSyncManager.shared.isICloudAvailable,
                  ICloudSyncManager.shared.iCloudDocumentsURL != nil else {
                await MainActor.run {
                    isICloudSyncing = false
                    showToastMessage("iCloud 不可用，请检查是否已登录 iCloud")
                }
                return
            }
            
            let items = itemStore.items
            let deletedRecords = itemStore.deletedItemRecords
            let nonSalaryRecords = financeStore.records.filter { $0.incomePeriod != .salary }
            let salaryRec = financeStore.salaryRecord
            let savingsGoal = financeStore.savingsGoal
            let largeItemsPrice = items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let normalItemsPrice = items.filter { $0.listType == .items && !$0.isArchived && !$0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let allItemsPrice = largeItemsPrice + normalItemsPrice
            let calcTotalAssets = financeStore.calculatedTotalAssets(itemsTotalPrice: allItemsPrice)
            
            // 并发同步物品、心愿和储蓄投资
            async let itemsResult = ICloudSyncManager.shared.syncItems(
                items: items,
                deletedItemRecords: deletedRecords
            )
            async let wishesResult = ICloudSyncManager.shared.syncWishes(
                items: items,
                deletedItemRecords: deletedRecords
            )
            
            async let savingResult = ICloudSyncManager.shared.syncSavingInfo(
                records: nonSalaryRecords,
                salaryRecord: salaryRec,
                goal: savingsGoal,
                totalAssets: calcTotalAssets,
                groups: groupStore.groups,
                wishlistGroups: wishlistGroupStore.groups,
                userSettings: UserSettings.fromLocal()
            )
            
            let (icloudItemsResult, icloudWishesResult) = await (itemsResult, wishesResult)
            let icloudSavingSyncResult = await savingResult
            let icloudSavingSuccess = icloudSavingSyncResult.success
            print("[iCloud 同步] 储蓄投资: \(icloudSavingSuccess ? "成功" : "失败")")
            
            // 回写 iCloud 储蓄数据到本地
            if icloudSavingSuccess {
                await MainActor.run {
                    financeStore.suppressUnsyncFlag = true
                    if let records = icloudSavingSyncResult.records {
                        financeStore.applyRemoteData(records: records, salaryRecord: icloudSavingSyncResult.salaryRecord, goal: icloudSavingSyncResult.goal)
                    }
                    if let remoteGroups = icloudSavingSyncResult.groups {
                        groupStore.applyRemoteGroups(remoteGroups)
                    }
                    if let remoteWG = icloudSavingSyncResult.wishlistGroups {
                        wishlistGroupStore.applyRemoteGroups(remoteWG)
                    }
                    icloudSavingSyncResult.userSettings?.applyToLocal()
                }
            }
            
            await MainActor.run {
                isICloudSyncing = false
                itemStore.suppressUnsyncFlag = true
                financeStore.suppressUnsyncFlag = true
                
                var allSuccess = true
                var message = ""
                
                // 处理物品同步结果
                if let result = icloudItemsResult {
                    for deletedItemId in result.deletedLocalItemIds {
                        if let item = itemStore.items.first(where: { $0.itemId == deletedItemId && $0.listType == .items }) {
                            itemStore.delete(item)
                        }
                    }
                    for var remoteItem in result.remoteOnlyItems {
                        guard !remoteItem.itemId.isEmpty else { continue }
                        if !itemStore.items.contains(where: { $0.itemId == remoteItem.itemId }) {
                            remoteItem.isSynced = true
                            itemStore.add(remoteItem)
                        }
                    }
                } else {
                    allSuccess = false
                }
                
                // 处理心愿同步结果
                if let result = icloudWishesResult {
                    for deletedItemId in result.deletedLocalItemIds {
                        if let item = itemStore.items.first(where: { $0.itemId == deletedItemId && $0.listType == .wishlist }) {
                            itemStore.delete(item)
                        }
                    }
                    for var remoteItem in result.remoteOnlyItems {
                        guard !remoteItem.itemId.isEmpty else { continue }
                        if !itemStore.items.contains(where: { $0.itemId == remoteItem.itemId }) {
                            remoteItem.isSynced = true
                            itemStore.add(remoteItem)
                        }
                    }
                } else {
                    allSuccess = false
                }
                
                if allSuccess {
                    itemStore.markSyncCompleted()
                    itemStore.markAllItemsSynced()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    financeStore.hasUnsyncedChanges = false
                    iCloudNeedsSync = false
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "iCloudLastSyncTime")
                    message = "iCloud 同步成功"
                } else if icloudItemsResult != nil || icloudWishesResult != nil {
                    itemStore.markSyncCompleted()
                    itemStore.markAllItemsSynced()
                    itemStore.rebuildCustomDisplayTypesFromWishes()
                    financeStore.hasUnsyncedChanges = false
                    iCloudNeedsSync = false
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "iCloudLastSyncTime")
                    message = "iCloud 部分同步成功"
                } else {
                    message = "iCloud 同步失败"
                }
                
                // 记录同步历史
                let record = SyncRecord(
                    id: UUID(),
                    date: Date(),
                    trigger: .icloud,
                    itemsUploaded: icloudItemsResult?.uploadedCount ?? 0,
                    itemsUpdated: icloudItemsResult?.updatedCount ?? 0,
                    itemsDeletedLocal: icloudItemsResult?.deletedLocalItemIds.count ?? 0,
                    itemsFailed: icloudItemsResult?.failedCount ?? 0,
                    wishesUploaded: icloudWishesResult?.uploadedCount ?? 0,
                    wishesUpdated: icloudWishesResult?.updatedCount ?? 0,
                    wishesDeletedLocal: icloudWishesResult?.deletedLocalItemIds.count ?? 0,
                    wishesFailed: icloudWishesResult?.failedCount ?? 0,
                    savingInfoSynced: icloudSavingSuccess,
                    success: allSuccess || icloudItemsResult != nil || icloudWishesResult != nil,
                    message: message
                )
                SyncHistoryStore.shared.addRecord(record)
                
                itemStore.suppressUnsyncFlag = false
                financeStore.suppressUnsyncFlag = false
                showToastMessage(message)
            }
        }
    }
}

// MARK: - 登录页 overlay 包装器
private struct ProfileAuthView: View {
    @EnvironmentObject var authManager: AuthManager
    var onClose: () -> Void
    
    var body: some View {
        AuthView(onLoginSuccess: { _ in
            onClose()
        }, onSkip: {
            onClose()
        })
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager.shared)
        .environmentObject(ItemStore())
        .environmentObject(SharedWishlistStore())
        .environmentObject(FinanceStore())
        .environmentObject(GroupStore())
        .environmentObject(WishlistGroupStore())
}
