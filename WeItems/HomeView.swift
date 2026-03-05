//
//  HomeView.swift
//  WeItems
//

import SwiftUI

struct HomeView: View {
    @StateObject private var store = ItemStore()
    @StateObject private var groupStore = GroupStore()
    @StateObject private var wishlistGroupStore = WishlistGroupStore()

    @State private var showingAddItem = false
    @State private var showingAddGroup = false
    @State private var currentMode: AppMode = .items
    
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
        NavigationStack {
            Group {
                switch currentMode {
                case .items:
                    ItemsView(store: store, groupStore: groupStore, showingAddGroup: $showingAddGroup)
                case .wishlist:
                    WishlistView(store: store, wishlistGroupStore: wishlistGroupStore)
                case .daily:
                    DailyExpenseView(store: store, groupStore: groupStore)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
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
                } else if currentMode == .wishlist {
                    AddWishlistItemView(store: store, wishlistGroupStore: wishlistGroupStore, defaultGroupId: nil)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
        }
    }
}

// 我的物品视图
struct ItemsView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    @Binding var showingAddGroup: Bool
    
    @State private var selectedGroupId: UUID?
    @State private var editingItem: Item? = nil
    @State private var showingItemDetail: Item? = nil
    
    private var currentItems: [Item] {
        store.itemsForGroup(selectedGroupId, listType: .items)
    }
    
    private var currentTotalPrice: Double {
        store.totalPrice(forGroup: selectedGroupId, listType: .items)
    }
    
    private var currentItemCount: Int {
        store.itemCount(forGroup: selectedGroupId, listType: .items)
    }
    
    private var currentTitle: String {
        selectedGroupId == nil ? "我的物品" : (groupStore.group(for: selectedGroupId)?.name ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 分组选择器
            GroupSelectorView(
                groupStore: groupStore,
                itemStore: store,
                selectedGroupId: $selectedGroupId,
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
            
            // 物品列表
            List {
                ForEach(currentItems) { item in
                    ItemCard(item: item, group: groupStore.group(for: item.groupId), showGroup: selectedGroupId == nil)
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
                        icon: "tray",
                        title: "暂无物品",
                        subtitle: selectedGroupId == nil ? "点击 + 添加你的第一个物品" : "该分组还没有物品"
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
    }
    
    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { currentItems[$0] }
        for item in itemsToDelete {
            store.delete(item)
        }
    }
}

// 分组选择器
struct GroupSelectorView: View {
    @ObservedObject var groupStore: GroupStore
    @ObservedObject var itemStore: ItemStore
    @Binding var selectedGroupId: UUID?
    let onAddGroup: () -> Void
    
    @State private var editingGroupId: UUID? = nil
    @State private var groupToDelete: ItemGroup? = nil
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 全部
                GroupChip(
                    name: "全部",
                    icon: "square.grid.2x2",
                    color: .blue,
                    isSelected: selectedGroupId == nil,
                    isEditing: false
                )
                .onTapGesture {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedGroupId = nil
                        editingGroupId = nil
                    }
                }
                
                // 各个分组
                ForEach(groupStore.groups) { group in
                    GroupChip(
                        name: group.name,
                        icon: group.icon,
                        color: group.color.swiftUIColor,
                        isSelected: selectedGroupId == group.id,
                        isEditing: editingGroupId == group.id
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedGroupId = group.id
                            editingGroupId = nil
                        }
                    }
                    .onLongPressGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            editingGroupId = group.id
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if editingGroupId == group.id {
                            Button {
                                groupToDelete = group
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red)
                                    .background(Circle().fill(.white))
                            }
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
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
            
            // 图片展示
            if let image = item.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.gray)
                    )
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

#Preview {
    HomeView()
}
