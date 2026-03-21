//
//  SharedWishlistView.swift
//  WeItems
//

import SwiftUI

// MARK: - 共享清单列表页
struct SharedWishlistListView: View {
    @ObservedObject var sharedStore: SharedWishlistStore
    @ObservedObject var itemStore: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    @State private var showingCreate = false
    @State private var editingList: SharedWishlist? = nil
    
    var body: some View {
        List {
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
                            sharedStore.delete(list)
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
        .navigationTitle("共享清单")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateSharedWishlistView(sharedStore: sharedStore, itemStore: itemStore, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(item: $editingList) { list in
            EditSharedWishlistView(list: list, sharedStore: sharedStore, itemStore: itemStore, wishlistGroupStore: wishlistGroupStore)
        }
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
                Text(list.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
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
    @State private var isSyncing = false
    
    private var currentList: SharedWishlist {
        sharedStore.lists.first(where: { $0.id == list.id }) ?? list
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
            // 概览
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总金额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(String(format: "%.2f", currentList.totalPrice))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("进度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(currentList.completedCount)/\(currentList.items.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                syncStatusBlock
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.bottom, 14)
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
                                    withAnimation(.spring(duration: 0.25)) {
                                        sharedStore.toggleItemCompleted(listId: currentList.id, itemId: item.id)
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
                                    Text("¥\(String(format: "%.0f", item.price))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(currentList.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private var syncStatusBlock: some View {
        if currentList.isSynced {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("已远端同步")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                    Text("数据已同步到云端")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green)
            )
        } else {
            Button {
                syncToCloud()
            } label: {
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isSyncing ? "正在同步..." : "未同步")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                        Text(isSyncing ? "请稍候" : "点击同步到云端")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    if !isSyncing {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue)
                )
            }
            .disabled(isSyncing)
        }
    }
    
    private func syncToCloud() {
        isSyncing = true
        let listId = currentList.id
        let wishGroupId = currentList.wishGroupId ?? CloudBaseClient.generateWishGroupId()
        let items = currentList.items
        let name = currentList.name
        let emoji = currentList.emoji
        
        Task {
            if let client = AuthManager.shared.getCloudBaseClient() {
                let result = await client.createSharedWishlistFromSharedItems(
                    wishGroupId: wishGroupId,
                    sharedItems: items,
                    listName: name,
                    listEmoji: emoji
                )
                if result?.code == "SUCCESS" || result?.data?.id != nil {
                    await MainActor.run {
                        sharedStore.markSynced(listId, wishGroupId: wishGroupId)
                    }
                }
            } else {
                print("[共享心愿] 未登录或 CloudBaseClient 不可用")
            }
            await MainActor.run {
                isSyncing = false
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
    @State private var selectedItemIds: Set<UUID> = []
    @State private var filterGroupId: UUID? = nil
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
        !name.isEmpty && !isSaving
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
                                }
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
                        
                        // 全选/取消当前筛选的心愿
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
            .map { SharedWishItem(sourceItemId: $0.id, name: $0.name, price: $0.price, displayType: $0.effectiveDisplayType) }
        
        // 生成 16 位随机数 ID
        let wishGroupId = CloudBaseClient.generateWishGroupId()
        
        let newList = SharedWishlist(name: name, emoji: emoji, items: sharedItems, wishGroupId: wishGroupId)
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
                        listEmoji: emoji
                    )
                    if result?.code == "SUCCESS" || result?.data?.id != nil {
                        await MainActor.run {
                            sharedStore.markSynced(listId, wishGroupId: wishGroupId)
                        }
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
                                }
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
                    displayType: item.effectiveDisplayType
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
