//
//  HomeView.swift
//  WeItems
//

import SwiftUI
import Combine
import LocalAuthentication

// MARK: - 滚动检测通知
extension Notification.Name {
    static let scrollDidChange = Notification.Name("scrollDidChange")
}

// MARK: - 滚动偏移检测 PreferenceKey
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 滚动检测修饰符
struct ScrollDetectorModifier: ViewModifier {
    let coordinateSpace: String
    @State private var lastOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    let offset = proxy.frame(in: .named(coordinateSpace)).minY
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: offset)
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                if abs(newOffset - lastOffset) > 1 {
                    lastOffset = newOffset
                    NotificationCenter.default.post(name: .scrollDidChange, object: nil)
                }
            }
    }
}

extension View {
    func detectScroll(coordinateSpace: String = "scrollDetector") -> some View {
        modifier(ScrollDetectorModifier(coordinateSpace: coordinateSpace))
    }
}

// MARK: - 底部 Tab 类型
enum BottomTab: String, CaseIterable {
    case items = "物品"
    case trend = "趋势"
    case settings = "设置"
    
    var icon: String {
        switch self {
        case .items: return "cube.fill"
        case .trend: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        }
    }
    
    var color: Color {
        switch self {
        case .items: return .blue
        case .trend: return .orange
        case .settings: return .gray
        }
    }
}

struct HomeView: View {
    @StateObject private var store = ItemStore()
    @StateObject private var groupStore = GroupStore()
    @StateObject private var wishlistGroupStore = WishlistGroupStore()
    @StateObject private var sharedWishlistStore = SharedWishlistStore()
    @StateObject private var financeStore = FinanceStore()
    @ObservedObject private var avatarStore = AvatarStore.shared
    @ObservedObject private var iapManager = IAPManager.shared
    @EnvironmentObject var authManager: AuthManager

    @State private var showingAddItem = false
    @State private var addItemId = UUID()
    @State private var showingAddGroup = false
    @State private var currentMode: AppMode = .items
    @State private var showingProfile = false
    @State private var wishlistSelectedGroupId: UUID? = nil
    @State private var selectedTab: BottomTab = .items
    @AppStorage("assetFaceIDLock") private var assetFaceIDLock = false
    @State private var assetUnlocked = false
    
    // TabBar 显示/隐藏控制
    @State private var isTabBarVisible: Bool = true
    @State private var tabBarHideTimer: Timer? = nil
    
    // 剪贴板检测相关
    @State private var detectedClipboardGroupId: String? = nil
    @State private var showingClipboardImportAlert = false
    @State private var isClipboardImporting = false
    @State private var clipboardImportSuccess = false
    @State private var clipboardImportedName = ""
    @State private var clipboardImportError: String? = nil
    @State private var showingClipboardImportError = false
    
    // Pro 升级页面
    @State private var showingProUpgrade = false
    
    // 登录后自动同步
    @State private var isAutoSyncing = false
    @State private var syncToastMessage: String? = nil
    @State private var showSyncToast = false
    
    // 昵称输入弹窗相关
    @State private var showingNicknameInput = false
    @State private var nicknameInput = ""
    @State private var pendingDocId: String? = nil
    @State private var pendingNumberList: [[String: String]] = []
    @State private var pendingUserId: String = ""
    
    enum AppMode: String, CaseIterable {
        case items = "我的物品"
        case wishlist = "心愿清单"
        case daily = "个人资产"
        
        var icon: String {
            switch self {
            case .items: return "cube"
            case .wishlist: return "heart"
            case .daily: return "creditcard"
            }
        }
        
        var color: Color {
            switch self {
            case .items: return .blue
            case .wishlist: return .pink
            case .daily: return .orange
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 主内容区域
            Group {
                switch selectedTab {
                case .items:
                    itemsTabContent
                case .trend:
                    NavigationStack {
                        TrendView(store: store)
                    }
                    .transition(.opacity)
                case .settings:
                    ProfileView(onBack: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            selectedTab = .items
                        }
                    })
                        .environmentObject(store)
                        .environmentObject(sharedWishlistStore)
                        .environmentObject(financeStore)
                        .environmentObject(groupStore)
                        .environmentObject(wishlistGroupStore)
                        .transition(.move(edge: .leading))
                }
            }
            
            // 底部固定 TabBar（滚动时出现，停止 2s 后消失）
            CustomTabBar(selectedTab: $selectedTab)
                .offset(y: isTabBarVisible ? 0 : 100)
                .opacity(isTabBarVisible ? 1 : 0)
                .animation(.spring(duration: 0.35, bounce: 0.3), value: isTabBarVisible)
            
            // 剪贴板导入加载遮罩
            if isClipboardImporting {
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
            
            // 同步 toast
            if showSyncToast, let message = syncToastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: showSyncToast)
            }
        }
        .ignoresSafeArea(.keyboard) // 键盘弹出时不影响 TabBar
        .onReceive(NotificationCenter.default.publisher(for: .scrollDidChange)) { _ in
            showTabBarTemporarily()
        }
        .onChange(of: selectedTab) { _, _ in
            showTabBarTemporarily()
        }
        .onAppear {
            // 初始显示后 2 秒自动隐藏
            scheduleTabBarHide()
            // 后台预加载趋势页数据
            TrendDataCache.shared.preload(store: store)
        }
    }
    
    /// 显示 TabBar 并在 2 秒后自动隐藏
    private func showTabBarTemporarily() {
        // 取消之前的定时器
        tabBarHideTimer?.invalidate()
        
        // 显示 TabBar
        if !isTabBarVisible {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                isTabBarVisible = true
            }
        }
        
        // 2 秒后隐藏
        scheduleTabBarHide()
    }
    
    /// 安排 2 秒后隐藏 TabBar
    private func scheduleTabBarHide() {
        tabBarHideTimer?.invalidate()
        tabBarHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                    isTabBarVisible = false
                }
            }
        }
    }
    
    // MARK: - 登录后自动同步
    
    private func showSyncToastMessage(_ message: String, autoDismiss: Bool = true) {
        syncToastMessage = message
        withAnimation { showSyncToast = true }
        if autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { showSyncToast = false }
            }
        }
    }
    
    private func performAutoSync() async {
        let tokenValid = await authManager.ensureValidToken()
        guard tokenValid, let client = authManager.getCloudBaseClient() else {
            await MainActor.run {
                isAutoSyncing = false
                showSyncToastMessage("同步失败，请重试")
            }
            return
        }
        
        let deletedRecords = store.deletedItemRecords
        async let itemsResult = client.syncItems(items: store.items, deletedItemRecords: deletedRecords)
        async let wishesResult = client.syncWishes(items: store.items, deletedItemRecords: deletedRecords)
        async let userInfoResult = client.fetchUserInfo()
        
        let nonSalaryRecords = financeStore.records.filter { $0.incomePeriod != .salary }
        let salaryRec = financeStore.salaryRecord
        let largeItemsPrice = store.items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
        let normalItemsPrice = store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
        let allItemsPrice = largeItemsPrice + normalItemsPrice
        async let savingResult = client.syncSavingInfo(
            records: nonSalaryRecords,
            salaryRecord: salaryRec,
            goal: financeStore.savingsGoal,
            totalAssets: financeStore.calculatedTotalAssets(itemsTotalPrice: allItemsPrice),
            groups: groupStore.groups,
            wishlistGroups: wishlistGroupStore.groups,
            userSettings: UserSettings.fromLocal()
        )
        
        let (itemsSyncResult, wishesSyncResult, userInfoResponse) = await (itemsResult, wishesResult, userInfoResult)
        let savingSyncResult = await savingResult
        
        // 回写远端储蓄数据到本地
        if let result = savingSyncResult {
            await MainActor.run {
                financeStore.applyRemoteData(records: result.records, salaryRecord: result.salaryRecord, goal: result.goal)
                if let remoteGroups = result.groups { groupStore.applyRemoteGroups(remoteGroups) }
                if let remoteWG = result.wishlistGroups { wishlistGroupStore.applyRemoteGroups(remoteWG) }
                result.userSettings?.applyToLocal()
            }
        }
        
        // 从 userinfo 读取 VIP 信息
        if let records = userInfoResponse?.data?.records, let record = records.first {
            if let vipInfo = record.vip_type, let vipType = vipInfo.type {
                await MainActor.run {
                    IAPManager.shared.applyRemoteVIPInfo(type: vipType, startDate: vipInfo.startDate, expireDate: vipInfo.expireDate)
                }
            }
            if record.vip_type == nil && IAPManager.shared.isPro {
                await IAPManager.shared.syncVIPToCloud()
            }
        }
        
        // 从 userinfo 同步共享清单
        if let records = userInfoResponse?.data?.records, let record = records.first,
           let shareWishList = record.share_wish_list, !shareWishList.isEmpty {
            for wishGroupId in shareWishList {
                let response = await client.fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
                guard let sharedRecord = response?.data?.records?.first else { continue }
                
                let listName = sharedRecord.effectiveName ?? "好朋友的清单"
                let listEmoji = sharedRecord.effectiveEmoji ?? "🎁"
                let ownerName = sharedRecord.effectiveOwnerName
                let remoteItems = sharedRecord.wishinfo?.items ?? []
                
                let sharedItems: [SharedWishItem] = remoteItems.map { remote in
                    SharedWishItem(
                        sourceItemId: remote.sourceItemId.flatMap { UUID(uuidString: $0) },
                        name: remote.name ?? "未知心愿",
                        price: remote.price ?? 0,
                        isCompleted: remote.isCompleted ?? false,
                        displayType: remote.displayType,
                        imageUrl: remote.imageUrl,
                        imageData: remote.imageBase64.flatMap { Data(base64Encoded: $0) },
                        purchaseLink: remote.purchaseLink,
                        details: remote.details,
                        completedBy: remote.completedBy,
                        addedBy: remote.addedBy
                    )
                }
                
                let currentUserId = TokenStorage.shared.getSub() ?? ""
                let numberList = sharedRecord.numbers?.number_list ?? []
                let myRemoteNickname = numberList.first(where: { $0.number_id == currentUserId })?.number_name
                let isOwner: Bool = {
                    if !currentUserId.isEmpty {
                        if let first = numberList.first, first.number_id == currentUserId { return true }
                        if let on = ownerName, let mn = myRemoteNickname, !on.isEmpty, !mn.isEmpty, on == mn { return true }
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
                    if let idx = sharedWishlistStore.lists.firstIndex(where: { $0.wishGroupId == wishGroupId }) {
                        sharedWishlistStore.applyMergedResult(listId: sharedWishlistStore.lists[idx].id, mergedItems: sharedItems, isSynced: true, remoteName: listName, remoteEmoji: listEmoji, remoteOwnerName: ownerName)
                        if let nickname = myRemoteNickname { sharedWishlistStore.setMyNickname(sharedWishlistStore.lists[idx].id, nickname: nickname) }
                        // 从远端恢复 linkedGroupId
                        if sharedWishlistStore.lists[idx].linkedGroupId == nil, let lgId = remoteLinkedGroupId {
                            sharedWishlistStore.lists[idx].linkedGroupId = lgId
                        }
                    } else {
                        sharedWishlistStore.add(SharedWishlist(name: listName, emoji: listEmoji, items: sharedItems, isSynced: true, wishGroupId: wishGroupId, isOwner: isOwner, ownerName: ownerName, myNickname: myRemoteNickname, linkedGroupId: remoteLinkedGroupId))
                    }
                }
            }
        }
        
        // 将 owner 共享清单的名字和 emoji 推送到远端
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
        
        // 下载远端物品/心愿的图片
        var allRemoteItems: [Item] = []
        if let result = itemsSyncResult { allRemoteItems.append(contentsOf: result.remoteOnlyItems) }
        if let result = wishesSyncResult { allRemoteItems.append(contentsOf: result.remoteOnlyItems) }
        
        var imageUrlsToDownload: [String: String] = [:]
        for item in allRemoteItems {
            if let remoteUrl = item.imageUrl, !remoteUrl.isEmpty {
                imageUrlsToDownload[item.id.uuidString] = remoteUrl
            }
        }
        var downloadedImages: [String: Data] = [:]
        if !imageUrlsToDownload.isEmpty {
            print("[自动同步] 开始下载 \(imageUrlsToDownload.count) 张远端图片...")
            downloadedImages = await client.downloadRemoteImages(imageUrls: imageUrlsToDownload)
        }
        
        // 处理物品/心愿同步结果
        await MainActor.run {
            if let result = itemsSyncResult {
                for deletedId in result.deletedLocalItemIds {
                    if let item = store.items.first(where: { $0.itemId == deletedId && $0.listType == .items }) { store.delete(item) }
                }
                for var remoteItem in result.remoteOnlyItems {
                    guard !remoteItem.itemId.isEmpty, !store.items.contains(where: { $0.itemId == remoteItem.itemId }) else { continue }
                    if let imageData = downloadedImages[remoteItem.id.uuidString] { remoteItem.imageData = imageData }
                    remoteItem.isSynced = true; store.add(remoteItem)
                }
            }
            if let result = wishesSyncResult {
                for deletedId in result.deletedLocalItemIds {
                    if let item = store.items.first(where: { $0.itemId == deletedId && $0.listType == .wishlist }) { store.delete(item) }
                }
                for var remoteItem in result.remoteOnlyItems {
                    guard !remoteItem.itemId.isEmpty, !store.items.contains(where: { $0.itemId == remoteItem.itemId }) else { continue }
                    if let imageData = downloadedImages[remoteItem.id.uuidString] { remoteItem.imageData = imageData }
                    remoteItem.isSynced = true; store.add(remoteItem)
                }
            }
            
            if itemsSyncResult != nil || wishesSyncResult != nil {
                store.markSyncCompleted()
                store.markAllItemsSynced()
                store.rebuildCustomDisplayTypesFromWishes()
                UserDefaults.standard.set(false, forKey: "remoteNeedsSync")
            }
            
            // 物品已同步完成，现在恢复共享清单的 linkedGroupId
            print("[自动同步] 开始恢复 linkedGroupId, 共享清单数量: \(sharedWishlistStore.lists.count), 本地心愿数量: \(store.items.filter { $0.listType == .wishlist }.count)")
            for i in sharedWishlistStore.lists.indices {
                let list = sharedWishlistStore.lists[i]
                print("[自动同步] 检查清单[\(i)]「\(list.name)」: isOwner=\(list.isOwner), linkedGroupId=\(list.linkedGroupId?.uuidString ?? "nil"), items=\(list.items.count)")
                guard list.isOwner, list.linkedGroupId == nil else {
                    if list.linkedGroupId != nil {
                        print("[自动同步]   → 已有 linkedGroupId，跳过")
                    } else if !list.isOwner {
                        print("[自动同步]   → 非 owner，跳过")
                    }
                    continue
                }
                var found = false
                for si in list.items {
                    let sidStr = si.sourceItemId?.uuidString ?? "nil"
                    if let sid = si.sourceItemId {
                        let localItem = store.items.first(where: { $0.id == sid })
                        if let item = localItem {
                            let gid = item.wishlistGroupId
                            print("[自动同步]   心愿「\(si.name)」sourceItemId=\(sidStr) → 本地匹配 item「\(item.name)」wishlistGroupId=\(gid?.uuidString ?? "nil")")
                            if let gid = gid {
                                sharedWishlistStore.lists[i].linkedGroupId = gid
                                print("[自动同步]   ✅ 恢复 linkedGroupId: \(gid)")
                                found = true
                                break
                            }
                        } else {
                            print("[自动同步]   心愿「\(si.name)」sourceItemId=\(sidStr) → 本地未找到匹配 item")
                        }
                    } else {
                        print("[自动同步]   心愿「\(si.name)」sourceItemId=nil，跳过")
                    }
                }
                if !found {
                    print("[自动同步]   ❌ 未能恢复 linkedGroupId")
                }
            }
            // 持久化恢复的 linkedGroupId
            sharedWishlistStore.forceSave()
            
            isAutoSyncing = false
            showSyncToastMessage("同步完成")
        }
    }
    
    // MARK: - 资产面容锁
    
    private var assetLockedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 60))
                .foregroundStyle(.orange.opacity(0.6))
            Text("个人资产已锁定")
                .font(.title3)
                .fontWeight(.medium)
            Text("请验证 Face ID 查看")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                authenticateForAssets()
            } label: {
                Text("验证解锁")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.orange))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            authenticateForAssets()
        }
    }
    
    private func authenticateForAssets() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // 设备不支持生物识别，直接解锁
            assetUnlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "验证身份以查看个人资产") { success, _ in
            DispatchQueue.main.async {
                if success {
                    assetUnlocked = true
                }
            }
        }
    }
    
    // MARK: - 物品 Tab 内容
    private var itemsTabContent: some View {
        NavigationStack {
            Group {
                switch currentMode {
                case .items:
                    ItemsView(store: store, groupStore: groupStore, showingAddGroup: $showingAddGroup)
                case .wishlist:
                    WishlistView(store: store, wishlistGroupStore: wishlistGroupStore, sharedWishlistStore: sharedWishlistStore, selectedGroupId: $wishlistSelectedGroupId)
                case .daily:
                    if assetFaceIDLock && !assetUnlocked {
                        assetLockedView
                    } else {
                        DailyExpenseView(store: store, groupStore: groupStore, financeStore: financeStore)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 60) // 为底部 TabBar 留出空间
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 10) {
                        // 用户头像
                        Button {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                selectedTab = .settings
                            }
                        } label: {
                            if let avatar = avatarStore.avatarImage {
                                Image(uiImage: avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 30, height: 30)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.gray.opacity(0.5))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 模式选择器
                        Menu {
                            ForEach(AppMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        currentMode = mode
                                    }
                                    if mode != .daily {
                                        assetUnlocked = false
                                    }
                                } label: {
                                    Label(mode.rawValue, systemImage: mode.icon)
                                    if currentMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(currentMode.rawValue)
                                    .font(.system(.headline, design: .rounded))
                                    .fontWeight(.bold)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addItemId = UUID()
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(currentMode.color)
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                if currentMode == .items {
                    AddItemView(store: store, groupStore: groupStore, defaultGroupId: nil)
                        .id(addItemId)
                } else if currentMode == .wishlist {
                    AddWishlistItemView(store: store, wishlistGroupStore: wishlistGroupStore, sharedWishlistStore: sharedWishlistStore, defaultGroupId: wishlistSelectedGroupId)
                        .id(addItemId)
                } else if currentMode == .daily {
                    AddFinanceRecordView(financeStore: financeStore)
                        .id(addItemId)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView()
            }
            .onReceive(NotificationCenter.default.publisher(for: AuthManager.userDidChangeNotification)) { _ in
                store.reloadForCurrentUser()
                groupStore.reloadForCurrentUser()
                wishlistGroupStore.reloadForCurrentUser()
                sharedWishlistStore.reloadForCurrentUser()
                financeStore.reloadForCurrentUser()
                TrendDataCache.shared.preload(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: AuthManager.userDidLoginNotification)) { _ in
                print("[HomeView] 收到 userDidLoginNotification, isAuthenticated=\(authManager.isAuthenticated), isAutoSyncing=\(isAutoSyncing)")
                guard authManager.isAuthenticated && !isAutoSyncing else { return }
                isAutoSyncing = true
                showSyncToastMessage("正在同步中...", autoDismiss: false)
                Task {
                    await performAutoSync()
                }
            }
            .onAppear {
                checkClipboardForSharedWishlist()
                checkICloudAutoSync()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                checkClipboardForSharedWishlist()
                checkICloudAutoSync()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AddItemFromSharedWish"))) { notification in
                if let item = notification.object as? Item {
                    store.add(item)
                }
            }
            .customConfirmAlert(
                isPresented: $showingClipboardImportAlert,
                title: "检测到共享清单",
                message: "剪贴板中包含共享清单 ID：\(detectedClipboardGroupId ?? "")，是否导入好朋友的清单？",
                confirmText: "立即导入",
                onConfirm: {
                    if let groupId = detectedClipboardGroupId {
                        importFromClipboard(groupId: groupId)
                    }
                }
            )
            .customInfoAlert(
                isPresented: $clipboardImportSuccess,
                title: "导入成功",
                message: "已成功导入「\(clipboardImportedName)」"
            )
            .customInfoAlert(
                isPresented: $showingClipboardImportError,
                title: "导入失败",
                message: clipboardImportError ?? "未知错误"
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
                                clipboardImportSuccess = true
                            } else {
                                clipboardImportError = "云函数调用失败，请重试"
                                showingClipboardImportError = true
                            }
                        }
                    }
                }
            )
        }
    }
    

    
    // MARK: - iCloud 自动同步
    @State private var isICloudAutoSyncing = false
    
    /// 检查是否需要 iCloud 自动同步：VIP + 开关开启 + 上次同步超过 1 小时 + 有需要同步的变更
    private func checkICloudAutoSync() {
        guard iapManager.isVIPActive else { return }
        guard isICloudAutoSyncEnabled else { return }
        guard !isICloudAutoSyncing else { return }
        guard ICloudSyncManager.shared.isICloudAvailable else { return }
        
        // 检查上次 iCloud 同步时间
        let lastSync = UserDefaults.standard.double(forKey: "iCloudLastSyncTime")
        let hourAgo = Date().timeIntervalSince1970 - 3600
        guard lastSync < hourAgo else { return }
        
        // 检查是否有未同步的变更（距离上次已超过 1 小时，直接同步即可）
        guard store.hasUnsyncedChanges else { return }
        
        print("[iCloud 自动同步] 距上次同步超过 1 小时，开始自动同步")
        isICloudAutoSyncing = true
        
        Task {
            let deletedRecords = store.deletedItemRecords
            
            async let itemsResult = ICloudSyncManager.shared.syncItems(items: store.items, deletedItemRecords: deletedRecords)
            async let wishesResult = ICloudSyncManager.shared.syncWishes(items: store.items, deletedItemRecords: deletedRecords)
            
            let largeItemsPrice = store.items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let normalItemsPrice = store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
            let allItemsPrice = largeItemsPrice + normalItemsPrice
            
            let nonSalaryRecords = financeStore.records.filter { $0.incomePeriod != .salary }
            let savingResult = await ICloudSyncManager.shared.syncSavingInfo(
                records: nonSalaryRecords,
                salaryRecord: financeStore.salaryRecord,
                goal: financeStore.savingsGoal,
                totalAssets: financeStore.calculatedTotalAssets(itemsTotalPrice: allItemsPrice),
                groups: groupStore.groups,
                wishlistGroups: wishlistGroupStore.groups,
                userSettings: UserSettings.fromLocal()
            )
            
            let (icloudItemsResult, icloudWishesResult) = await (itemsResult, wishesResult)
            
            let allSuccess = icloudItemsResult != nil && icloudWishesResult != nil && savingResult.success
            
            await MainActor.run {
                if allSuccess || icloudItemsResult != nil || icloudWishesResult != nil {
                    store.markSyncCompleted()
                    store.markAllItemsSynced()
                }
                
                // 记录同步时间
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "iCloudLastSyncTime")
                isICloudAutoSyncing = false
                print("[iCloud 自动同步] 完成: \(allSuccess ? "全部成功" : "部分成功")")
            }
        }
    }
    
    private var isICloudAutoSyncEnabled: Bool {
        if UserDefaults.standard.object(forKey: "iCloudAutoSyncEnabled") == nil {
            return iapManager.isVIPActive // VIP 默认开启
        }
        return UserDefaults.standard.bool(forKey: "iCloudAutoSyncEnabled")
    }
    
    /// 检查剪贴板是否包含 sharewish_ 开头的共享清单 ID
    private func checkClipboardForSharedWishlist() {
        guard authManager.isAuthenticated else { return }
        // 非 VIP 用户不检测剪贴板
        guard iapManager.isVIPActive else { return }
        // 异步读取剪贴板，用户拒绝粘贴不影响后续逻辑
        DispatchQueue.main.async {
            guard let text = PrivacySettings.readFromClipboard(), !text.isEmpty else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("sharewish_") else { return }
            if sharedWishlistStore.lists.contains(where: { $0.wishGroupId == trimmed }) { return }
            
            // 切换到心愿清单页面
            withAnimation(.spring(duration: 0.3)) {
                selectedTab = .items
                currentMode = .wishlist
            }
            
            detectedClipboardGroupId = trimmed
            showingClipboardImportAlert = true
        }
    }
    
    /// 从剪贴板检测到的清单 ID 执行导入
    private func importFromClipboard(groupId: String) {
        isClipboardImporting = true
        
        Task {
            guard let client = AuthManager.shared.getCloudBaseClient() else {
                await MainActor.run {
                    isClipboardImporting = false
                    clipboardImportError = "未登录，请先登录后再导入"
                    showingClipboardImportError = true
                }
                return
            }
            
            let response = await client.fetchSharedWishlistByGroupId(wishGroupId: groupId)
            
            await MainActor.run {
                isClipboardImporting = false
                
                guard let records = response?.data?.records, let record = records.first else {
                    clipboardImportError = "未找到该清单，请检查 ID 是否正确"
                    showingClipboardImportError = true
                    return
                }
                
                let listName = record.effectiveName ?? "好朋友的清单"
                let listEmoji = record.effectiveEmoji ?? "🎁"
                let ownerName = record.effectiveOwnerName
                let remoteItems = record.wishinfo?.items ?? []
                
                let sharedItems: [SharedWishItem] = remoteItems.map { remote in
                    SharedWishItem(
                        name: remote.name ?? "未知心愿",
                        price: remote.price ?? 0,
                        isCompleted: remote.isCompleted ?? false,
                        displayType: remote.displayType,
                        imageUrl: remote.imageUrl,
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
                sharedWishlistStore.add(newList)
                
                // 暂存数据，弹出昵称输入框
                let currentUserId = TokenStorage.shared.getSub() ?? ""
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
                
                // 清除剪贴板中的清单 ID，避免重复检测
                UIPasteboard.general.string = ""
                
                if let ownerName = ownerName, !ownerName.isEmpty {
                    clipboardImportedName = "来自\(ownerName)的心愿清单"
                } else {
                    clipboardImportedName = listName
                }
                // 先弹昵称输入框，输入完成后再显示导入成功
                showingNicknameInput = true
            }
        }
    }
}

// 我的物品视图
struct ItemsView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    @Binding var showingAddGroup: Bool
    @EnvironmentObject var authManager: AuthManager
    
    @State private var selectedGroupId: UUID?
    @State private var editingItem: Item? = nil
    @State private var editingSoldItem: Item? = nil
    @State private var showingItemDetail: Item? = nil
    @State private var showArchived: Bool = false
    @State private var showingAccountSync = false
    @State private var selectedType: ItemType? = nil
    @AppStorage("itemSortMode") private var itemSortMode: ItemSortMode = .addedDate
    
    private var currentItems: [Item] {
        var result: [Item]
        if showArchived {
            result = store.items.filter { $0.listType == .items && $0.isArchived }
        } else {
            var filtered = store.itemsForGroup(selectedGroupId, listType: .items)
            filtered = filtered.filter { !$0.isArchived }
            result = filtered
        }
        if let type = selectedType {
            result = result.filter { $0.type == type.rawValue }
        }
        // 排序
        switch itemSortMode {
        case .addedDate:
            result.sort { $0.createdAt > $1.createdAt }
        case .ownedDate:
            result.sort { ($0.ownedDate ?? $0.createdAt) > ($1.ownedDate ?? $1.createdAt) }
        case .price:
            result.sort { $0.price > $1.price }
        }
        return result
    }
    
    private var currentTotalPrice: Double {
        currentItems.filter { !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    private var currentItemCount: Int {
        currentItems.count
    }
    
    private var currentTitle: String {
        if showArchived {
            return "售出物品"
        }
        return selectedGroupId == nil ? "我的物品" : (groupStore.group(for: selectedGroupId)?.name ?? "")
    }
    
    private var archivedCount: Int {
        store.items.filter { $0.listType == .items && $0.isArchived }.count
    }
    
    var body: some View {
        List {
            // 账号与同步入口 - 仅在未登录时显示
            if !authManager.isAuthenticated {
                Button {
                    showingAccountSync = true
                } label: {
                    HStack {
                        Text("登录即可多端同步")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
            }
            
            // 分组选择器（包含归档标签）
            GroupSelectorView(
                groupStore: groupStore,
                itemStore: store,
                selectedGroupId: $selectedGroupId,
                showArchived: $showArchived,
                archivedCount: archivedCount,
                onAddGroup: { showingAddGroup = true }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            
            // 总价统计卡片
            TotalPriceCard(
                totalPrice: currentTotalPrice,
                itemCount: currentItemCount,
                title: currentTitle,
                soldTotalPrice: showArchived ? currentItems.compactMap({ $0.soldPrice }).reduce(0, +) : nil,
                usageCost: showArchived ? (currentTotalPrice - currentItems.compactMap({ $0.soldPrice }).reduce(0, +)) : nil
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            
            // 物品类型筛选
            TypeFilterView(selectedType: $selectedType, store: store, showArchived: showArchived)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            
            // 物品列表
            ForEach(currentItems) { item in
                ItemCard(item: item, group: groupStore.group(for: item.groupId), showGroup: selectedGroupId == nil && !showArchived)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingItemDetail = item
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                if showArchived {
                                    editingSoldItem = item
                                } else {
                                    editingItem = item
                                }
                            }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            if abs(newValue - oldValue) > 1 {
                NotificationCenter.default.post(name: .scrollDidChange, object: nil)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                // 点击空白区域也显示 TabBar（物品不够多无法滚动时）
                NotificationCenter.default.post(name: .scrollDidChange, object: nil)
            }
        )
        .overlay {
            if currentItems.isEmpty {
                EmptyStateView(
                    icon: showArchived ? "archivebox" : "tray",
                    title: showArchived ? "暂无售出物品" : "暂无物品",
                    subtitle: showArchived ? "" : (selectedGroupId == nil ? "点击 + 添加你的第一个物品" : "该分组还没有物品")
                )
            }
        }
        .sheet(item: $editingItem) { item in
            EditItemView(item: item, store: store, groupStore: groupStore)
        }
        .sheet(item: $editingSoldItem) { item in
            EditSoldInfoSheet(item: item, store: store)
        }
        .sheet(item: $showingItemDetail) { item in
            ItemDetailView(store: store, item: item, group: groupStore.group(for: item.groupId))
        }
        .sheet(isPresented: $showingAccountSync, onDismiss: {
            // Sheet 关闭后，如果已登录则不需要再次显示
            if authManager.isAuthenticated {
                print("[ItemsView] 用户已登录，账号与同步入口已隐藏")
            }
        }) {
            AuthViewWrapper()
        }
        .onChange(of: authManager.isAuthenticated) { oldValue, newValue in
            if newValue {
                // 登录成功后关闭 sheet
                showingAccountSync = false
            }
        }
        .onChange(of: showArchived) { _, _ in
            // 切换售出/非售出模式时清除类型筛选
            selectedType = nil
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { currentItems[$0] }
        for item in itemsToDelete {
            store.delete(item)
        }
    }
}

// 物品类型筛选视图
struct TypeFilterView: View {
    @Binding var selectedType: ItemType?
    @ObservedObject var store: ItemStore
    var showArchived: Bool = false
    
    private static let typeColors: [ItemType: Color] = [
        .digital: .blue,
        .fashion: .pink,
        .appliance: .cyan,
        .largeItem: .purple,
        .lifeGood: .red,
        .edc: .brown,
        .outdoor: .green,
        .other: .gray
    ]
    
    /// 根据当前模式（售出/未售出）获取实际存在的类型
    private var activeTypes: [ItemType] {
        let myItems: [Item]
        if showArchived {
            myItems = store.items.filter { $0.listType == .items && $0.isArchived }
        } else {
            myItems = store.items.filter { $0.listType == .items && !$0.isArchived }
        }
        let typeSet = Set(myItems.compactMap { ItemType(rawValue: $0.type) })
        return ItemType.allCases.filter { typeSet.contains($0) }
    }
    
    /// 总物品数（用于"全部"标签）
    private var totalCount: Int {
        if showArchived {
            return store.items.filter { $0.listType == .items && $0.isArchived }.count
        } else {
            return store.items.filter { $0.listType == .items && !$0.isArchived }.count
        }
    }
    
    var body: some View {
        if !activeTypes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "全部"标签
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedType = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 10))
                            Text("全部")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text("\(totalCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(selectedType == nil ? .white.opacity(0.8) : Color.blue.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedType == nil ? Color.blue : Color.blue.opacity(0.1))
                        )
                        .foregroundStyle(selectedType == nil ? .white : .blue)
                        .overlay(
                            Capsule()
                                .stroke(Color.blue.opacity(0.3), lineWidth: selectedType == nil ? 0 : 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    ForEach(activeTypes, id: \.self) { type in
                        let color = Self.typeColors[type] ?? .gray
                        let isSelected = selectedType == type
                        let count: Int = {
                            if showArchived {
                                return store.items.filter { $0.listType == .items && $0.isArchived && $0.type == type.rawValue }.count
                            } else {
                                return store.items.filter { $0.listType == .items && !$0.isArchived && $0.type == type.rawValue }.count
                            }
                        }()
                        
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                selectedType = isSelected ? nil : type
                            }
                        } label: {
                            HStack(spacing: 4) {
                                type.iconImage(size: 14)
                                    .font(.system(size: 10))
                                Text(type.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : color.opacity(0.7))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? color : color.opacity(0.1))
                            )
                            .foregroundStyle(isSelected ? .white : color)
                            .overlay(
                                Capsule()
                                    .stroke(color.opacity(0.3), lineWidth: isSelected ? 0 : 0.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 4)
        }
    }
}

// 分组选择器
struct GroupSelectorView: View {
    @ObservedObject var groupStore: GroupStore
    @ObservedObject var itemStore: ItemStore
    @Binding var selectedGroupId: UUID?
    @Binding var showArchived: Bool
    let archivedCount: Int
    let onAddGroup: () -> Void
    
    @State private var editingGroupId: UUID? = nil
    @State private var groupToDelete: ItemGroup? = nil
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 全部
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedGroupId = nil
                        showArchived = false
                        editingGroupId = nil
                    }
                } label: {
                    GroupChip(
                        name: "全部",
                        icon: "square.grid.2x2",
                        color: .blue,
                        isSelected: selectedGroupId == nil && !showArchived,
                        isEditing: false
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // 各个分组
                ForEach(groupStore.groups) { group in
                    ZStack {
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedGroupId = group.id
                                showArchived = false
                                editingGroupId = nil
                            }
                        } label: {
                            GroupChip(
                                name: group.name,
                                icon: group.icon,
                                color: group.color.swiftUIColor,
                                isSelected: selectedGroupId == group.id && !showArchived,
                                isEditing: editingGroupId == group.id
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(
                            LongPressGesture()
                                .onEnded { _ in
                                    withAnimation(.spring(duration: 0.3)) {
                                        editingGroupId = group.id
                                    }
                                }
                        )
                        
                        // 删除按钮
                        if editingGroupId == group.id {
                            VStack {
                                HStack {
                                    Spacer()
                                    Button {
                                        groupToDelete = group
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.red)
                                            .background(Circle().fill(.white))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                
                // 售出物品标签
                if archivedCount > 0 {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            showArchived = true
                            selectedGroupId = nil
                            editingGroupId = nil
                        }
                    } label: {
                        GroupChip(
                            name: "售出",
                            icon: "tag",
                            color: .purple,
                            isSelected: showArchived,
                            isEditing: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 添加分组按钮
                Button {
                    onAddGroup()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("新增分组")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .customConfirmAlert(
            isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil; editingGroupId = nil } }
            ),
            title: "删除分组",
            message: "删除分组后，该分组下的物品将变为无分组状态。确定要删除吗？",
            confirmText: "删除",
            isDestructive: true,
            onConfirm: {
                if let group = groupToDelete {
                    let itemsInGroup = itemStore.itemsForGroup(group.id, listType: .items)
                    itemStore.moveItems(toGroup: nil, items: itemsInGroup.map { $0.id })
                    groupStore.delete(group)
                    if selectedGroupId == group.id {
                        selectedGroupId = nil
                    }
                    editingGroupId = nil
                    groupToDelete = nil
                }
            },
            onCancel: {
                groupToDelete = nil
                editingGroupId = nil
            }
        )
    }
}

// 分组芯片
struct GroupChip: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let isEditing: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ? color : color.opacity(0.1))
        )
        .foregroundStyle(isSelected ? .white : color)
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
        )
        .scaleEffect(isEditing ? 0.95 : 1.0)
        .animation(.spring(duration: 0.2), value: isEditing)
    }
}

// 总价统计卡片
struct TotalPriceCard: View {
    let totalPrice: Double
    let itemCount: Int
    let title: String
    var soldTotalPrice: Double? = nil  // 售出总价
    var usageCost: Double? = nil       // 使用成本（原始 - 售出）
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title) - 总计价值")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("¥\(String(format: "%.2f", totalPrice))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("物品数量")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(itemCount) 件")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
            
            // 售出统计
            if let soldTotal = soldTotalPrice, let cost = usageCost {
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("售出总额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(String(format: "%.0f", soldTotal))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().frame(height: 30)
                    
                    VStack(spacing: 2) {
                        Text(cost >= 0 ? "使用成本" : "总盈利")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(cost >= 0 ? "" : "+")¥\(String(format: "%.0f", abs(cost)))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(cost >= 0 ? .red : .green)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// 物品卡片
struct ItemCard: View {
    let item: Item
    let group: ItemGroup?
    let showGroup: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.details.isEmpty {
                // 无描述：名称+价格，标签在下方
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if item.isPriceless {
                        Text("无价之物")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    } else {
                        Text("¥\(String(format: "%.2f", item.price))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                }
                
                // 标签
                tagsView
            } else {
                // 有描述：名称+价格第一行，描述第二行，标签紧跟价格下方右侧
                // 第一行：名称 + 价格（顶部对齐）
                HStack(alignment: .top) {
                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if item.isPriceless {
                        Text("无价之物")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    } else {
                        Text("¥\(String(format: "%.2f", item.price))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                }
                
                // 第二行：描述 + 标签（中线对齐）
                HStack(alignment: .center) {
                    Text(item.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    tagsView
                }
            }
            
            // 图片展示（无图片时不显示）
            if let image = item.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // 售出信息（仅售出物品显示）
            if item.isArchived, let soldPrice = item.soldPrice {
                VStack(spacing: 6) {
                    Divider()
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("售出价")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.0f", soldPrice))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 2) {
                            let loss = item.soldLoss ?? 0
                            Text(loss >= 0 ? "亏损" : "盈利")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(loss >= 0 ? "-" : "+")¥\(String(format: "%.0f", abs(loss)))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(loss >= 0 ? .red : .green)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 2) {
                            Text("持有")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(item.daysSinceCreated)天")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 2) {
                            Text("日均")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(String(format: "%.2f", item.dailyCost))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var tagsView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                typeIconImage(for: item.type)
                    .font(.caption)
                Text(item.type)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
            
            if showGroup, let group = group {
                HStack(spacing: 4) {
                    Image(systemName: group.icon)
                        .font(.caption)
                    Text(group.name)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(group.color.swiftUIColor.opacity(0.1))
                .foregroundStyle(group.color.swiftUIColor)
                .clipShape(Capsule())
            }
        }
    }
    
    @ViewBuilder
    private func typeIconImage(for type: String) -> some View {
        if let itemType = ItemType(rawValue: type) {
            itemType.iconImage(size: 16)
        } else {
            Image(systemName: "tag")
        }
    }
}

// 空状态视图
// MARK: - 自定义底部 TabBar（液态玻璃风格）
struct CustomTabBar: View {
    @Binding var selectedTab: BottomTab
    
    var body: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+：液态玻璃
            liquidGlassTabBar
                .padding(.bottom, 16)
        } else {
            // iOS 26 以下：毛玻璃胶囊
            fallbackTabBar
                .padding(.bottom, 16)
        }
    }
    
    // MARK: - iOS 26+ 液态玻璃版本
    @available(iOS 26.0, *)
    private var liquidGlassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(BottomTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolEffect(.bounce, value: selectedTab == tab)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? tab.color : .secondary)
                    .frame(minWidth: 80, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
    
    // MARK: - iOS 26 以下毛玻璃版本
    private var fallbackTabBar: some View {
        HStack(spacing: 0) {
            ForEach(BottomTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolEffect(.bounce, value: selectedTab == tab)
                        
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? tab.color : .secondary)
                    .frame(minWidth: 80, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - 编辑售出信息 Sheet
struct EditSoldInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @ObservedObject var store: ItemStore
    
    @State private var priceText: String = ""
    @State private var soldDate: Date = Date()
    @State private var recycleMethod: String = ""
    
    private var isValid: Bool {
        !priceText.isEmpty && Double(priceText) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("「\(item.name)」的售出信息")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .listRowSeparator(.hidden)
                    
                    HStack {
                        Text("¥")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        TextField("售出价格", text: $priceText)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .keyboardType(.decimalPad)
                    }
                    .listRowSeparator(.hidden)
                    
                    DatePicker(selection: $soldDate, displayedComponents: .date) {
                        Text("售出时间")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .listRowSeparator(.hidden)
                    
                    HStack {
                        Text("回收方式")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                        Spacer()
                        TextField("可选", text: $recycleMethod)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("编辑售出信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let price = Double(priceText) ?? 0
                        let method = recycleMethod.trimmingCharacters(in: .whitespaces).isEmpty ? nil : recycleMethod.trimmingCharacters(in: .whitespaces)
                        if var updated = store.items.first(where: { $0.id == item.id }) {
                            updated.soldPrice = price
                            updated.soldDate = soldDate
                            updated.recycleMethod = method
                            store.update(updated)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                priceText = item.soldPrice != nil ? String(format: "%.2f", item.soldPrice!) : ""
                soldDate = item.soldDate ?? Date()
                recycleMethod = item.recycleMethod ?? ""
            }
        }
    }
}

#Preview {
    HomeView()
}
