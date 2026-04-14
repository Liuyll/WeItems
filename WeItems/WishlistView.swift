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
    @ObservedObject var sharedWishlistStore: SharedWishlistStore
    @EnvironmentObject var authManager: AuthManager
    
    @State private var showingAddItem = false
    @State private var editingItem: Item? = nil
    @State private var showingItemDetail: Item? = nil
    @State private var showingAddGroup = false
    @State private var showingLogin = false
    @Binding var selectedGroupId: UUID?
    @State private var lastScrollOffset: CGFloat = 0
    
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
                    // 滚动检测锚点
                    Color.clear
                        .frame(height: 0)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self,
                                                value: proxy.frame(in: .global).minY)
                            }
                        )
                    
                    // 分享邀请
                    if authManager.isAuthenticated {
                        NavigationLink(destination: SharedWishlistListView(sharedStore: sharedWishlistStore, itemStore: store, wishlistGroupStore: wishlistGroupStore)) {
                            HStack {
                                Text(sharedWishlistStore.lists.isEmpty ? "让朋友们一起来实现心愿" : "查看共享心愿清单")
                                    .font(.system(.subheadline, design: .rounded))
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
                                            colors: [Color.green, Color.green.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    } else {
                        Button {
                            showingLogin = true
                        } label: {
                            HStack {
                                Text("登录分享心愿")
                                    .font(.system(.subheadline, design: .rounded))
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
                                            colors: [Color.pink, Color.pink.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }
                    
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
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                if abs(newOffset - lastScrollOffset) > 2 {
                    lastScrollOffset = newOffset
                    NotificationCenter.default.post(name: .scrollDidChange, object: nil)
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddWishlistItemView(store: store, wishlistGroupStore: wishlistGroupStore, defaultGroupId: selectedGroupId)
        }
        .sheet(item: $editingItem) { item in
            EditWishlistItemView(item: item, store: store, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(item: $showingItemDetail) { item in
            ItemDetailView(store: store, item: item, group: wishlistGroupStore.group(for: item.wishlistGroupId), sharedStore: sharedWishlistStore, wishlistGroupStore: wishlistGroupStore)
        }
        .sheet(isPresented: $showingAddGroup) {
            AddWishlistGroupView(groupStore: wishlistGroupStore)
        }
        .sheet(isPresented: $showingLogin) {
            AuthViewWrapper()
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
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("¥\(String(format: "%.2f", totalPrice))")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("心愿数量")
                    .font(.system(.subheadline, design: .rounded))
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
                    .font(.system(.subheadline, design: .rounded))
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
                    .foregroundStyle(.orange)
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

// MARK: - 卡通卡片背景修饰器
struct CartoonCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .shadow(color: Color.pink.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func cartoonCard() -> some View {
        modifier(CartoonCardModifier())
    }
}

// MARK: - 卡通区块标题
struct CartoonSectionHeader: View {
    let emoji: String
    let title: String
    let color: Color
    
    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.bottom, 2)
    }
}

// MARK: - 卡通输入框
struct CartoonTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var leadingIcon: String? = nil
    var iconColor: Color = .pink
    var showDivider: Bool = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = leadingIcon {
                Text(icon)
                    .font(.body)
            }
            Text(placeholder)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.heavy)
                .foregroundStyle(.cyan.opacity(0.8))
            
            Spacer()
            
            TextField("", text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
    @State private var details = ""
    @State private var selectedGroupId: UUID?
    
    // 彩蛋动画状态（20%概率触发）
    @State private var isEasterEgg = false
    @State private var showTitle = false
    @State private var showFireworks = false
    @State private var showingNewTypeInput = false
    @State private var newTypeInput = ""
    
    init(store: ItemStore, wishlistGroupStore: WishlistGroupStore, defaultGroupId: UUID? = nil) {
        self.store = store
        self.wishlistGroupStore = wishlistGroupStore
        self.defaultGroupId = defaultGroupId
        _selectedGroupId = State(initialValue: defaultGroupId)
    }
    
    // 展示类型
    @State private var isCustomDisplayType = false
    @State private var customDisplayType = ""
    @State private var selectedDisplayType: ItemType = .other
    
    // 归属类型（实现心愿后）
    @State private var selectedTargetType: ItemType = .other
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var compressedImageData: Data?
    
    private var isValid: Bool {
        !name.isEmpty && !price.isEmpty && Double(price) != nil
    }
    
    private var finalDisplayType: String {
        isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 📝 基本信息
                    VStack(alignment: .leading, spacing: 10) {
                        CartoonTextField(placeholder: "心愿名字", text: $name)
                        CartoonTextField(placeholder: "价格", text: $price, keyboardType: .decimalPad)
                        CartoonTextField(placeholder: "购买链接", text: $purchaseLink, keyboardType: .URL)
                    }
                    
                    // 🏷️ 展示类型卡片
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "🏷️", title: "展示类型", color: .secondary)
                        
                        // 分组选择
                        if !wishlistGroupStore.groups.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        Button {
                                            selectedGroupId = nil
                                        } label: {
                                            Text("无分组")
                                                .font(.system(.subheadline, design: .rounded))
                                                .fontWeight(selectedGroupId == nil ? .bold : .medium)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule()
                                                        .fill(selectedGroupId == nil ? Color.pink.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                                                )
                                                .foregroundStyle(selectedGroupId == nil ? .pink : .primary)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(selectedGroupId == nil ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        ForEach(wishlistGroupStore.groups) { group in
                                            Button {
                                                selectedGroupId = group.id
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: group.icon)
                                                        .font(.caption)
                                                    Text(group.name)
                                                        .font(.system(.subheadline, design: .rounded))
                                                        .fontWeight(selectedGroupId == group.id ? .bold : .medium)
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule()
                                                        .fill(selectedGroupId == group.id ? group.color.swiftUIColor.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                                                )
                                                .foregroundStyle(selectedGroupId == group.id ? group.color.swiftUIColor : .primary)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(selectedGroupId == group.id ? group.color.swiftUIColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                        }
                        
                        // 自定义切换
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
                            // 历史自定义类型
                            if !store.customDisplayTypes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("历史类型")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    FlowLayout(spacing: 8) {
                                        ForEach(store.customDisplayTypes, id: \.self) { type in
                                            Button {
                                                customDisplayType = type
                                            } label: {
                                                Text(type)
                                                    .font(.system(.subheadline, design: .rounded))
                                                    .fontWeight(customDisplayType == type ? .bold : .medium)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 7)
                                                    .background(
                                                        Capsule()
                                                            .fill(customDisplayType == type
                                                                  ? Color.purple.opacity(0.18)
                                                                  : Color(.tertiarySystemGroupedBackground))
                                                    )
                                                    .foregroundStyle(customDisplayType == type ? .purple : .primary)
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(customDisplayType == type ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                            
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
                            
                            if !customDisplayType.isEmpty {
                                Text("当前：\(customDisplayType)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.purple)
                            }
                            
                            // 归属类型
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
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: selectedTargetType.icon)
                                            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75))
                                        Text(selectedTargetType.rawValue)
                                            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75))
                                    }
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                            }
                            
                            Text("✨ 实现心愿后将归类到「\(selectedTargetType.rawValue)」")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75).opacity(0.8))
                        } else {
                            // 标准类型选择 - 用胶囊标签网格
                            FlowLayout(spacing: 8) {
                                ForEach(ItemType.allCases, id: \.self) { type in
                                    Button {
                                        selectedDisplayType = type
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: type.icon)
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
                    
                    // 📷 图片卡片
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "📷", title: "心愿美照", color: .secondary)
                        
                        ZStack {
                            if let imageData = selectedImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.pink.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        HStack(spacing: 8) {
                                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.caption)
                                                    Text("更换")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                }
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button {
                                                selectedImageData = nil
                                                compressedImageData = nil
                                                selectedPhoto = nil
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "trash")
                                                        .font(.caption)
                                                    Text("删除")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                }
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.red.opacity(0.7)))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(10)
                                    }
                            } else {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                        .frame(height: 140)
                                        .overlay(
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 32))
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                    // 生成 0.7 压缩版，仅用于同步上传
                                    if let uiImage = UIImage(data: data) {
                                        compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                    }
                                }
                            }
                        }
                    }
                    .cartoonCard()
                    
                    // 📝 心愿描述
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心愿描述")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(.cyan.opacity(0.8))
                        TextEditor(text: $details)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                // 20% 概率触发烟花彩蛋
                isEasterEgg = Int.random(in: 1...5) == 1
                if isEasterEgg {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showFireworks = true
                    }
                }
            }
            .navigationTitle("许下一个新心愿")
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
                        saveItem()
                    } label: {
                        Text("保存")
                            .fontWeight(.bold)
                            .foregroundStyle(isValid ? .pink : .gray.opacity(0.35))
                    }
                    .disabled(!isValid)
                }
            }
                
                // 烟花覆盖层（仅彩蛋模式）
                if isEasterEgg && showFireworks {
                    FireworksOverlay()
                        .ignoresSafeArea()
                        .onAppear {
                            // 烟花持续约2s后自动消失
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                showFireworks = false
                            }
                        }
                }
            } // ZStack
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
    
    private func saveItem() {
        guard let priceValue = Double(price) else { return }
        
        let finalType = isCustomDisplayType ? customDisplayType : selectedDisplayType.rawValue
        
        let newItem = Item(
            name: name,
            details: details,
            purchaseLink: purchaseLink,
            imageData: selectedImageData,
            compressedImageData: compressedImageData,
            imageChanged: selectedImageData != nil,  // 新建心愿：有图片即需上传
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
    @State private var priceText: String
    @State private var purchaseLink: String
    @State private var details: String
    
    // 展示类型
    @State private var isCustomDisplayType: Bool
    @State private var customDisplayType: String
    @State private var selectedDisplayType: ItemType
    
    // 归属类型（实现心愿后）
    @State private var selectedTargetType: ItemType
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var compressedImageData: Data?
    @State private var imageChanged: Bool = false  // 标记图片是否被用户编辑过
    @State private var selectedGroupId: UUID?
    
    @State private var showDeleteConfirm = false
    @State private var showingNewTypeInput = false
    @State private var newTypeInput = ""
    
    init(item: Item, store: ItemStore, wishlistGroupStore: WishlistGroupStore) {
        self.originalItem = item
        self.store = store
        self.wishlistGroupStore = wishlistGroupStore
        _name = State(initialValue: item.name)
        _price = State(initialValue: item.price)
        _priceText = State(initialValue: item.price == 0 ? "" : String(format: "%.2f", item.price))
        _purchaseLink = State(initialValue: item.purchaseLink)
        _details = State(initialValue: item.details)
        _selectedImageData = State(initialValue: item.imageData)
        _compressedImageData = State(initialValue: item.compressedImageData)
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
            ScrollView {
                VStack(spacing: 18) {
                    // 📝 基本信息
                    VStack(alignment: .leading, spacing: 10) {
                        CartoonTextField(placeholder: "心愿名字", text: $name)
                        CartoonTextField(placeholder: "价格", text: $priceText, keyboardType: .decimalPad)
                            .onChange(of: priceText) { _, newValue in
                                price = Double(newValue) ?? 0
                            }
                        CartoonTextField(placeholder: "购买链接", text: $purchaseLink, keyboardType: .URL)
                    }
                    
                    // 🏷️ 展示类型卡片
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "🏷️", title: "展示类型", color: .secondary)
                        
                        // 分组选择
                        if !wishlistGroupStore.groups.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        Button {
                                            selectedGroupId = nil
                                        } label: {
                                            Text("无分组")
                                                .font(.system(.subheadline, design: .rounded))
                                                .fontWeight(selectedGroupId == nil ? .bold : .medium)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule()
                                                        .fill(selectedGroupId == nil ? Color.pink.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                                                )
                                                .foregroundStyle(selectedGroupId == nil ? .pink : .primary)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(selectedGroupId == nil ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        ForEach(wishlistGroupStore.groups) { group in
                                            Button {
                                                selectedGroupId = group.id
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: group.icon)
                                                        .font(.caption)
                                                    Text(group.name)
                                                        .font(.system(.subheadline, design: .rounded))
                                                        .fontWeight(selectedGroupId == group.id ? .bold : .medium)
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule()
                                                        .fill(selectedGroupId == group.id ? group.color.swiftUIColor.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                                                )
                                                .foregroundStyle(selectedGroupId == group.id ? group.color.swiftUIColor : .primary)
                                                .overlay(
                                                    Capsule()
                                                        .stroke(selectedGroupId == group.id ? group.color.swiftUIColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                        }
                        
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
                            if !store.customDisplayTypes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("历史类型")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    FlowLayout(spacing: 8) {
                                        ForEach(store.customDisplayTypes, id: \.self) { type in
                                            Button {
                                                customDisplayType = type
                                            } label: {
                                                Text(type)
                                                    .font(.system(.subheadline, design: .rounded))
                                                    .fontWeight(customDisplayType == type ? .bold : .medium)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 7)
                                                    .background(
                                                        Capsule()
                                                            .fill(customDisplayType == type
                                                                  ? Color.purple.opacity(0.18)
                                                                  : Color(.tertiarySystemGroupedBackground))
                                                    )
                                                    .foregroundStyle(customDisplayType == type ? .purple : .primary)
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(customDisplayType == type ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                            
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
                            
                            if !customDisplayType.isEmpty {
                                Text("当前：\(customDisplayType)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.purple)
                            }
                            
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
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: selectedTargetType.icon)
                                            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75))
                                        Text(selectedTargetType.rawValue)
                                            .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75))
                                    }
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                            }
                            
                            Text("✨ 实现心愿后将归类到「\(selectedTargetType.rawValue)」")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.75).opacity(0.8))
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(ItemType.allCases, id: \.self) { type in
                                    Button {
                                        selectedDisplayType = type
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: type.icon)
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
                    
                    // 📷 图片卡片
                    VStack(alignment: .leading, spacing: 14) {
                        CartoonSectionHeader(emoji: "📷", title: "心愿美照", color: .secondary)
                        
                        ZStack {
                            if let imageData = selectedImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.pink.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        HStack(spacing: 8) {
                                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.caption)
                                                    Text("更换")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                }
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button {
                                                selectedImageData = nil
                                                compressedImageData = nil
                                                selectedPhoto = nil
                                                imageChanged = true  // 用户删除了图片
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "trash")
                                                        .font(.caption)
                                                    Text("删除")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                }
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.red.opacity(0.7)))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(10)
                                    }
                            } else {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                        .frame(height: 140)
                                        .overlay(
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 32))
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                    imageChanged = true  // 用户更换了图片
                                    // 生成 0.7 压缩版，仅用于同步上传
                                    if let uiImage = UIImage(data: data) {
                                        compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                    }
                                }
                            }
                        }
                    }
                    .cartoonCard()
                    
                    // 📝 心愿描述
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心愿描述")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(.cyan.opacity(0.8))
                        TextEditor(text: $details)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    
                    // 🗑️ 删除按钮
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("🗑️")
                            Text("删除这个心愿")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.red.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .customConfirmAlert(
                        isPresented: $showDeleteConfirm,
                        title: "确定删除？",
                        message: "删除后无法恢复，确定要删除「\(name)」吗？",
                        confirmText: "删除",
                        isDestructive: true,
                        onConfirm: {
                            store.delete(originalItem)
                            dismiss()
                        }
                    )
                    
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
                        saveItem()
                    } label: {
                        Text("保存")
                            .fontWeight(.bold)
                            .foregroundStyle(.pink)
                    }
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
    
    private func saveItem() {
        var updatedItem = originalItem
        updatedItem.name = name
        updatedItem.price = price
        updatedItem.purchaseLink = purchaseLink
        updatedItem.details = details
        updatedItem.imageData = selectedImageData
        updatedItem.compressedImageData = compressedImageData
        updatedItem.imageChanged = imageChanged  // 传递图片变更标记
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
    
    private let icons = ["folder", "star", "heart", "bag", "cart", "gift", "house", "car", "airplane", "gamecontroller", "books.vertical", "tv", "headphones", "shoe", "tshirt", "laptopcomputer", "iphone", "camera", "bicycle"]
    
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
                            .buttonStyle(BorderlessButtonStyle())
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
                            .buttonStyle(BorderlessButtonStyle())
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
    WishlistView(store: ItemStore(), wishlistGroupStore: WishlistGroupStore(), sharedWishlistStore: SharedWishlistStore(), selectedGroupId: .constant(nil))
}
