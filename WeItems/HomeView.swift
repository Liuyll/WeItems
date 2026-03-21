//
//  HomeView.swift
//  WeItems
//

import SwiftUI

struct HomeView: View {
    @StateObject private var store = ItemStore()
    @StateObject private var groupStore = GroupStore()
    @StateObject private var wishlistGroupStore = WishlistGroupStore()
    @StateObject private var sharedWishlistStore = SharedWishlistStore()
    @EnvironmentObject var authManager: AuthManager

    @State private var showingAddItem = false
    @State private var addItemId = UUID()
    @State private var showingAddGroup = false
    @State private var currentMode: AppMode = .items
    @State private var showingProfile = false
    @State private var autoSyncToast: String?
    @State private var showAutoSyncToast = false
    @State private var wishlistSelectedGroupId: UUID? = nil
    
    enum AppMode: String, CaseIterable {
        case items = "我的物品"
        case wishlist = "心愿清单"
        case daily = "日常消费"
        
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
        ZStack {
            NavigationStack {
                Group {
                    switch currentMode {
                    case .items:
                        ItemsView(store: store, groupStore: groupStore, showingAddGroup: $showingAddGroup)
                    case .wishlist:
                        WishlistView(store: store, wishlistGroupStore: wishlistGroupStore, sharedWishlistStore: sharedWishlistStore, selectedGroupId: $wishlistSelectedGroupId)
                    case .daily:
                        DailyExpenseView(store: store, groupStore: groupStore)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 12) {
                            // 皮卡丘头像（已登录时显示在最顶部）
                            if authManager.isAuthenticated {
                                Button {
                                    showingProfile = true
                                } label: {
                                    Image(systemName: "bolt.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.yellow)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // 模式选择器
                            Menu {
                                ForEach(AppMode.allCases, id: \.self) { mode in
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) {
                                            currentMode = mode
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
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
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
                                .foregroundStyle(currentMode.color)
                        }
                    }
                }
                .sheet(isPresented: $showingAddItem) {
                    if currentMode == .items {
                        AddItemView(store: store, groupStore: groupStore, defaultGroupId: nil)
                            .id(addItemId)
                    } else if currentMode == .wishlist {
                        AddWishlistItemView(store: store, wishlistGroupStore: wishlistGroupStore, defaultGroupId: wishlistSelectedGroupId)
                            .id(addItemId)
                    }
                }
                .sheet(isPresented: $showingAddGroup) {
                    AddGroupView(groupStore: groupStore)
                }
                .sheet(isPresented: $showingProfile) {
                    ProfileView()
                        .environmentObject(store)
                }
                .onReceive(NotificationCenter.default.publisher(for: AuthManager.userDidChangeNotification)) { _ in
                    store.reloadForCurrentUser()
                    groupStore.reloadForCurrentUser()
                    wishlistGroupStore.reloadForCurrentUser()
                }
                .onAppear {
                    checkAutoSync()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    checkAutoSync()
                }
            }
            
            // 自动同步 Toast
            if showAutoSyncToast, let message = autoSyncToast {
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
                .animation(.easeInOut(duration: 0.3), value: showAutoSyncToast)
            }
        }
    }
    
    /// 检查是否需要自动同步
    private func checkAutoSync() {
        guard authManager.isAuthenticated, store.needsAutoSync else { return }
        
        print("[自动同步] 满足条件：已登录、有变更、距上次同步超过1天，开始自动同步...")
        
        Task {
            let tokenValid = await authManager.ensureValidToken()
            guard tokenValid else {
                print("[自动同步] Token 无效，跳过自动同步")
                return
            }
            guard let client = authManager.getCloudBaseClient() else {
                print("[自动同步] 无法获取云客户端，跳过自动同步")
                return
            }
            
            // 同时同步物品和心愿清单
            async let itemsResult = client.syncItems(items: store.items)
            async let wishesResult = client.syncWishes(items: store.items)
            
            let (itemsSyncResult, wishesSyncResult) = await (itemsResult, wishesResult)
            
            await MainActor.run {
                var anySuccess = false
                
                if let result = itemsSyncResult {
                    for name in result.deletedLocalNames {
                        if let item = store.items.first(where: { $0.name == name && $0.listType == .items }) {
                            store.delete(item)
                            print("[自动同步] 已删除本地物品: \(name)")
                        }
                    }
                    anySuccess = true
                }
                
                if let result = wishesSyncResult {
                    for name in result.deletedLocalNames {
                        if let item = store.items.first(where: { $0.name == name && $0.listType == .wishlist }) {
                            store.delete(item)
                            print("[自动同步] 已删除本地心愿: \(name)")
                        }
                    }
                    anySuccess = true
                }
                
                let message = anySuccess ? "自动同步成功" : "自动同步失败"
                
                // 记录同步历史
                let record = SyncRecord(
                    id: UUID(),
                    date: Date(),
                    trigger: .auto,
                    itemsUploaded: itemsSyncResult?.uploadedCount ?? 0,
                    itemsUpdated: itemsSyncResult?.updatedCount ?? 0,
                    itemsDeletedLocal: itemsSyncResult?.deletedLocalNames.count ?? 0,
                    itemsFailed: itemsSyncResult?.failedIds.count ?? 0,
                    wishesUploaded: wishesSyncResult?.uploadedCount ?? 0,
                    wishesUpdated: wishesSyncResult?.updatedCount ?? 0,
                    wishesDeletedLocal: wishesSyncResult?.deletedLocalNames.count ?? 0,
                    wishesFailed: wishesSyncResult?.failedIds.count ?? 0,
                    success: anySuccess,
                    message: message
                )
                SyncHistoryStore.shared.addRecord(record)
                
                if anySuccess {
                    store.markSyncCompleted()
                    showAutoSyncToastMessage(message)
                } else {
                    print("[自动同步] 同步失败")
                }
            }
        }
    }
    
    private func showAutoSyncToastMessage(_ message: String) {
        autoSyncToast = message
        withAnimation {
            showAutoSyncToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showAutoSyncToast = false
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
    @State private var showingItemDetail: Item? = nil
    @State private var showArchived: Bool = false
    @State private var showingAccountSync = false
    @State private var selectedType: ItemType? = nil
    
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
        return result
    }
    
    private var currentTotalPrice: Double {
        currentItems.reduce(0) { $0 + $1.price }
    }
    
    private var currentItemCount: Int {
        currentItems.count
    }
    
    private var currentTitle: String {
        if showArchived {
            return "归档"
        }
        return selectedGroupId == nil ? "我的物品" : (groupStore.group(for: selectedGroupId)?.name ?? "")
    }
    
    private var archivedCount: Int {
        store.items.filter { $0.listType == .items && $0.isArchived }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 账号与同步入口 - 仅在未登录时显示（在下拉栏下方）
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
                .padding(.horizontal)
                .padding(.top, 8)
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
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 总价统计卡片
            TotalPriceCard(
                totalPrice: currentTotalPrice,
                itemCount: currentItemCount,
                title: currentTitle
            )
            .padding()
            
            // 物品类型筛选
            TypeFilterView(selectedType: $selectedType, store: store)
            
            // 物品列表
            List {
                ForEach(currentItems) { item in
                    ItemCard(item: item, group: groupStore.group(for: item.groupId), showGroup: selectedGroupId == nil && !showArchived)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .onTapGesture {
                            showingItemDetail = item
                        }
                        .onLongPressGesture {
                            editingItem = item
                        }
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.plain)
            .overlay {
                if currentItems.isEmpty {
                    EmptyStateView(
                        icon: showArchived ? "archivebox" : "tray",
                        title: showArchived ? "暂无归档物品" : "暂无物品",
                        subtitle: showArchived ? "" : (selectedGroupId == nil ? "点击 + 添加你的第一个物品" : "该分组还没有物品")
                    )
                }
            }
        }
        .sheet(item: $editingItem) { item in
            EditItemView(item: item, store: store, groupStore: groupStore)
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
    
    /// 当前未归档物品中实际存在的类型
    private var activeTypes: [ItemType] {
        let myItems = store.items.filter { $0.listType == .items && !$0.isArchived }
        let typeSet = Set(myItems.compactMap { ItemType(rawValue: $0.type) })
        return ItemType.allCases.filter { typeSet.contains($0) }
    }
    
    var body: some View {
        if !activeTypes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeTypes, id: \.self) { type in
                        let color = Self.typeColors[type] ?? .gray
                        let isSelected = selectedType == type
                        let count = store.items.filter { $0.listType == .items && !$0.isArchived && $0.type == type.rawValue }.count
                        
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                selectedType = isSelected ? nil : type
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
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
                
                // 归档标签（有归档物品时才显示）
                if archivedCount > 0 {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            showArchived = true
                            selectedGroupId = nil
                            editingGroupId = nil
                        }
                    } label: {
                        GroupChip(
                            name: "归档",
                            icon: "archivebox",
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
            .padding(.vertical, 12)
        }
        .alert("删除分组", isPresented: .constant(groupToDelete != nil)) {
            Button("取消", role: .cancel) {
                groupToDelete = nil
                editingGroupId = nil
            }
            Button("删除", role: .destructive) {
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
            }
        } message: {
            Text("删除分组后，该分组下的物品将变为无分组状态。确定要删除吗？")
        }
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
            // 顶部：名称 + 价格（左右展示）
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Spacer()
                
                Text("¥\(String(format: "%.2f", item.price))")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            
            // 类型和分组标签
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: typeIcon(for: item.type))
                        .font(.caption)
                    Text(item.type)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
                
                // 在全部视图下显示分组标签
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
                
                Spacer()
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
            
            // 详情
            if !item.details.isEmpty {
                Text(item.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
    
    private func typeIcon(for type: String) -> String {
        if let itemType = ItemType(rawValue: type) {
            return itemType.icon
        }
        return "tag"
    }
}

// 空状态视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AuthView 包装器
struct AuthViewWrapper: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        AuthView(onLoginSuccess: { response in
            // 登录成功后更新 AuthManager
            authManager.loginSuccess(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub
            )
            // 关闭 sheet
            dismiss()
        })
    }
}

#Preview {
    HomeView()
}
