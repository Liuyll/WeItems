//
//  WishlistView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

// 流式布局组件
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

struct WishlistView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    
    @State private var showingAddItem = false
    @State private var editingItem: Item? = nil
    @State private var showingItemDetail: Item? = nil
    @State private var showingAddGroup = false
    @State private var selectedGroupId: UUID? = nil
    
    private var currentItems: [Item] {
        var filtered = store.items.filter { $0.listType == .wishlist }
        if let selectedGroupId = selectedGroupId {
            filtered = filtered.filter { $0.wishlistGroupId == selectedGroupId }
        }
        return filtered
    }
    
    private var itemsByType: [String: [Item]] {
        Dictionary(grouping: currentItems, by: { $0.effectiveDisplayType })
    }
    
    private var totalPrice: Double {
        currentItems.filter { $0.isSelected }.reduce(0) { $0 + $1.price }
    }
    
    private var itemCount: Int {
        currentItems.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 分组选择器
            WishlistGroupSelectorView(
                groupStore: wishlistGroupStore,
                selectedGroupId: $selectedGroupId,
                onAddGroup: { showingAddGroup = true }
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // 总价统计
                    WishlistTotalCard(totalPrice: totalPrice, itemCount: itemCount)
                        .padding(.horizontal)
                    
                    // 按分类展示（包括自定义类型）
                    let allDisplayTypes = Array(itemsByType.keys).sorted()
                    ForEach(allDisplayTypes, id: \.self) { typeName in
                        if let items = itemsByType[typeName], !items.isEmpty {
                            TypeSection(
                                typeName: typeName,
                                items: items,
                                store: store,
                                onTap: { item in
                                    showingItemDetail = item
                                },
                                onLongPress: { item in
                                    editingItem = item
                                }
                            )
                        }
                    }
                    
                    if itemCount == 0 {
                        EmptyStateView(
                            icon: "heart",
                            title: selectedGroupId == nil ? "暂无心愿" : "该分组还没有心愿",
                            subtitle: selectedGroupId == nil ? "点击 + 添加你的心愿物品" : ""
                        )
                        .padding(.top, 100)
                    }
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddWishlistItemView(store: store, wishlistGroupStore: wishlistGroupStore, defaultGroupId: selectedGroupId)
        }
        .sheet(item: $editingItem) { item in
            EditWishlistItemView(item: item, store: store, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(item: $showingItemDetail) { item in
            ItemDetailView(store: store, item: item, group: wishlistGroupStore.group(for: item.wishlistGroupId))
        }
        .sheet(isPresented: $showingAddGroup) {
            AddWishlistGroupView(groupStore: wishlistGroupStore)
        }
    }
}

// 分组按钮组件
struct GroupButton: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? color : .primary)
            .frame(width: 70, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
        }
    }
}

// 心愿清单分组选择器
struct WishlistGroupSelectorView: View {
    @ObservedObject var groupStore: WishlistGroupStore
    @Binding var selectedGroupId: UUID?
    let onAddGroup: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 全部分组按钮
                GroupButton(
                    name: "全部",
                    icon: "square.grid.2x2",
                    color: Color.pink,
                    isSelected: selectedGroupId == nil
                ) {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedGroupId = nil
                    }
                }
                
                // 各分组按钮
                ForEach(groupStore.groups) { group in
                    GroupButton(
                        name: group.name,
                        icon: group.icon,
                        color: group.color.swiftUIColor,
                        isSelected: selectedGroupId == group.id
                    ) {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedGroupId = group.id
                        }
                    }
                }
                
                // 添加分组按钮
                Button(action: onAddGroup) {
                    VStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 24))
                        Text("新建")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.green)
                    .frame(width: 70, height: 60)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.2)),
            alignment: .bottom
        )
    }
}

// 心愿清单总价卡片
struct WishlistTotalCard: View {
    let totalPrice: Double
    let itemCount: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("心愿清单 - 预计花费")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("¥\(String(format: "%.2f", totalPrice))")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.pink)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("心愿数量")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(itemCount) 个")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.pink.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.pink.opacity(0.2), lineWidth: 1)
        )
    }
}

// 分类区块
struct TypeSection: View {
    let typeName: String
    let items: [Item]
    @ObservedObject var store: ItemStore
    let onTap: (Item) -> Void
    let onLongPress: (Item) -> Void
    
    private var typeIcon: String {
        if let itemType = ItemType(rawValue: typeName) {
            return itemType.icon
        }
        return "tag"  // 自定义类型使用默认图标
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分类标题
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.title3)
                    .foregroundStyle(.pink)
                Text(typeName)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("(\(items.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            // 小卡网格
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items) { item in
                    WishlistCard(
                        item: item,
                        store: store,
                        onTap: { onTap(item) },
                        onLongPress: { onLongPress(item) }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

// 心愿小卡
struct WishlistCard: View {
    let item: Item
    @ObservedObject var store: ItemStore
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, maxHeight: 34, alignment: .topLeading)
                
                Text("¥\(String(format: "%.0f", item.price))")
                    .font(.system(size: 12))
                    .foregroundStyle(.pink)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 选中/取消选中按钮
            Button {
                withAnimation(.spring(duration: 0.2)) {
                    store.toggleItemSelection(itemId: item.id)
                }
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isSelected ? .green : .gray.opacity(0.3))
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 74)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.isSelected ? Color.green.opacity(0.4) : Color.pink.opacity(0.2), lineWidth: item.isSelected ? 2 : 1)
        )
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}

// 添加心愿物品视图
struct AddWishlistItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    
    var defaultGroupId: UUID?
    
    @State private var name = ""
    @State private var price = ""
    @State private var purchaseLink = ""
    @State private var selectedGroupId: UUID?
    
    // 展示类型
    @State private var isCustomDisplayType = false
    @State private var customDisplayType = ""
    @State private var selectedDisplayType: ItemType = .other
    
    // 归属类型（实现心愿后）
    @State private var selectedTargetType: ItemType = .other
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    private var isValid: Bool {
        !name.isEmpty && !price.isEmpty && Double(price) != nil
    }
    
    private var finalDisplayType: String {
        isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("物品名称", text: $name)
                    
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("价格", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    
                    // 分组选择
                    if wishlistGroupStore.groups.isEmpty {
                        Text("暂无分组")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("所属分组", selection: $selectedGroupId) {
                            Text("无分组")
                                .tag(nil as UUID?)
                            
                            ForEach(wishlistGroupStore.groups) { group in
                                Label(group.name, systemImage: group.icon)
                                    .tag(group.id as UUID?)
                            }
                        }
                    }
                }
                
                // 展示类型（心愿清单中显示的分类）
                Section("展示类型") {
                    Toggle("自定义类型", isOn: $isCustomDisplayType)
                    
                    if isCustomDisplayType {
                        // 历史自定义类型选择
                        if !store.customDisplayTypes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("历史类型（点击选择）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(store.customDisplayTypes, id: \.self) { type in
                                        Button {
                                            customDisplayType = type
                                        } label: {
                                            Text(type)
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    customDisplayType == type 
                                                    ? Color.pink.opacity(0.2)
                                                    : Color.gray.opacity(0.1)
                                                )
                                                .foregroundStyle(
                                                    customDisplayType == type
                                                    ? .pink
                                                    : .primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        TextField("输入新的展示类型名称", text: $customDisplayType)
                        
                        // 自定义类型时才需要选择归属类型
                        Menu {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                Button {
                                    selectedTargetType = type
                                } label: {
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                        if selectedTargetType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("归属类型")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: selectedTargetType.icon)
                                        .foregroundStyle(.pink)
                                    Text(selectedTargetType.rawValue)
                                        .foregroundStyle(.pink)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Text("实现心愿后将归类到\(selectedTargetType.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                Button {
                                    selectedDisplayType = type
                                } label: {
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                        if selectedDisplayType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("选择展示类型")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: selectedDisplayType.icon)
                                        .foregroundStyle(.pink)
                                    Text(selectedDisplayType.rawValue)
                                        .foregroundStyle(.pink)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // 图片选择
                Section("图片") {
                    VStack(spacing: 16) {
                        if let imageData = selectedImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.gray)
                                        Text("选择图片")
                                            .foregroundStyle(.secondary)
                                    }
                                )
                        }
                        
                        PhotosPicker(selection: $selectedPhoto,
                                   matching: .images) {
                            Label(selectedImageData == nil ? "选择照片" : "更换照片",
                                  systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                }
                            }
                        }
                        
                        if selectedImageData != nil {
                            Button(role: .destructive) {
                                selectedImageData = nil
                                selectedPhoto = nil
                            } label: {
                                Label("删除图片", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 购买链接
                Section("购买链接") {
                    TextField("输入链接地址", text: $purchaseLink)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("添加心愿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveItem() {
        guard let priceValue = Double(price) else { return }
        
        let finalType = isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
        
        let newItem = Item(
            name: name,
            details: "",
            purchaseLink: purchaseLink,
            imageData: selectedImageData,
            price: priceValue,
            type: finalType,
            listType: .wishlist,
            displayType: finalType,
            targetType: isCustomDisplayType ? selectedTargetType.rawValue : nil,
            wishlistGroupId: selectedGroupId
        )
        
        store.add(newItem)
        
        // 如果是自定义类型，添加到历史记录
        if isCustomDisplayType && !customDisplayType.isEmpty {
            store.addCustomDisplayType(customDisplayType)
        }
        
        dismiss()
    }
}

// 编辑心愿物品视图
struct EditWishlistItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var wishlistGroupStore: WishlistGroupStore
    
    let originalItem: Item
    @State private var name: String
    @State private var price: Double
    @State private var purchaseLink: String
    
    // 展示类型
    @State private var isCustomDisplayType: Bool
    @State private var customDisplayType: String
    @State private var selectedDisplayType: ItemType
    
    // 归属类型（实现心愿后）
    @State private var selectedTargetType: ItemType
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedGroupId: UUID?
    
    init(item: Item, store: ItemStore, wishlistGroupStore: WishlistGroupStore) {
        self.originalItem = item
        self.store = store
        self.wishlistGroupStore = wishlistGroupStore
        _name = State(initialValue: item.name)
        _price = State(initialValue: item.price)
        _purchaseLink = State(initialValue: item.purchaseLink)
        _selectedImageData = State(initialValue: item.imageData)
        _selectedGroupId = State(initialValue: item.wishlistGroupId)
        
        // 判断展示类型是否为自定义
        let displayType = item.displayType ?? item.type
        let displayItemType = ItemType(rawValue: displayType)
        _isCustomDisplayType = State(initialValue: displayItemType == nil)
        _customDisplayType = State(initialValue: displayItemType == nil ? displayType : "")
        _selectedDisplayType = State(initialValue: displayItemType ?? .other)
        
        // 归属类型（targetType 或默认的 displayType）
        let target = item.targetType ?? displayType
        _selectedTargetType = State(initialValue: ItemType(rawValue: target) ?? .other)
    }
    
    private var finalDisplayType: String {
        isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("物品名称", text: $name)
                    
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("价格", value: $price, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    
                    // 分组选择
                    if wishlistGroupStore.groups.isEmpty {
                        Text("暂无分组")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("所属分组", selection: $selectedGroupId) {
                            Text("无分组")
                                .tag(nil as UUID?)
                            
                            ForEach(wishlistGroupStore.groups) { group in
                                Label(group.name, systemImage: group.icon)
                                    .tag(group.id as UUID?)
                            }
                        }
                    }
                }
                
                // 展示类型（心愿清单中显示的分类）
                Section("展示类型") {
                    Toggle("自定义类型", isOn: $isCustomDisplayType)
                    
                    if isCustomDisplayType {
                        // 历史自定义类型选择
                        if !store.customDisplayTypes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("历史类型（点击选择）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(store.customDisplayTypes, id: \.self) { type in
                                        Button {
                                            customDisplayType = type
                                        } label: {
                                            Text(type)
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    customDisplayType == type 
                                                    ? Color.pink.opacity(0.2)
                                                    : Color.gray.opacity(0.1)
                                                )
                                                .foregroundStyle(
                                                    customDisplayType == type
                                                    ? .pink
                                                    : .primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        TextField("输入新的展示类型名称", text: $customDisplayType)
                        
                        // 自定义类型时才需要选择归属类型
                        Menu {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                Button {
                                    selectedTargetType = type
                                } label: {
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                        if selectedTargetType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("归属类型")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: selectedTargetType.icon)
                                        .foregroundStyle(.pink)
                                    Text(selectedTargetType.rawValue)
                                        .foregroundStyle(.pink)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Text("实现心愿后将归类到\(selectedTargetType.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(ItemType.allCases, id: \.self) { type in
                                Button {
                                    selectedDisplayType = type
                                } label: {
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                        if selectedDisplayType == type {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("选择展示类型")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: selectedDisplayType.icon)
                                        .foregroundStyle(.pink)
                                    Text(selectedDisplayType.rawValue)
                                        .foregroundStyle(.pink)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // 图片选择
                Section("图片") {
                    VStack(spacing: 16) {
                        if let imageData = selectedImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.gray)
                                        Text("选择图片")
                                            .foregroundStyle(.secondary)
                                    }
                                )
                        }
                        
                        PhotosPicker(selection: $selectedPhoto,
                                   matching: .images) {
                            Label(selectedImageData == nil ? "选择照片" : "更换照片",
                                  systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                }
                            }
                        }
                        
                        if selectedImageData != nil {
                            Button(role: .destructive) {
                                selectedImageData = nil
                                selectedPhoto = nil
                            } label: {
                                Label("删除图片", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 购买链接
                Section("购买链接") {
                    TextField("输入链接地址", text: $purchaseLink)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section {
                    Button("删除", role: .destructive) {
                        store.delete(originalItem)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑心愿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveItem() {
        var updatedItem = originalItem
        updatedItem.name = name
        updatedItem.price = price
        updatedItem.purchaseLink = purchaseLink
        updatedItem.imageData = selectedImageData
        updatedItem.displayType = finalDisplayType
        updatedItem.targetType = isCustomDisplayType ? selectedTargetType.rawValue : nil
        updatedItem.type = isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
        updatedItem.wishlistGroupId = selectedGroupId
        store.update(updatedItem)
        
        // 如果是自定义类型，添加到历史记录
        if isCustomDisplayType && !customDisplayType.isEmpty {
            store.addCustomDisplayType(customDisplayType)
        }
        
        dismiss()
    }
}

// 添加心愿清单分组视图
struct AddWishlistGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var groupStore: WishlistGroupStore
    
    @State private var name = ""
    @State private var selectedIcon = "folder"
    @State private var selectedColor: GroupColor = .pink
    
    private let icons = ["folder", "star", "heart", "bag", "cart", "gift", "house", "car", "airplane", "gamecontroller", "books.vertical", "tv", "headphones", "watch", "shoe", "tshirt", "laptopcomputer", "iphone", "camera", "bicycle"]
    
    private var isValid: Bool {
        !name.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("分组名称") {
                    TextField("输入分组名称", text: $name)
                }
                
                Section("图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        selectedIcon == icon
                                        ? selectedColor.swiftUIColor.opacity(0.2)
                                        : Color.gray.opacity(0.1)
                                    )
                                    .foregroundStyle(
                                        selectedIcon == icon
                                        ? selectedColor.swiftUIColor
                                        : .primary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(GroupColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                            .padding(2)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(color.swiftUIColor.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("新建分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveGroup()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveGroup() {
        let newGroup = ItemGroup(name: name, icon: selectedIcon, color: selectedColor)
        groupStore.add(newGroup)
        dismiss()
    }
}

#Preview {
    WishlistView(store: ItemStore(), wishlistGroupStore: WishlistGroupStore())
}
