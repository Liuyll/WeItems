//
//  ItemDetailView.swift
//  WeItems
//

import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @State var item: Item
    let group: ItemGroup?
    var sharedStore: SharedWishlistStore?
    var wishlistGroupStore: WishlistGroupStore?
    
    @State private var showingArchiveConfirm = false
    @State private var showingMoveToWishlistConfirm = false
    @State private var showingFulfillWishConfirm = false
    @State private var showingAddToSharedWishlist = false
    @State private var showingEditWish = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 图片
                    if let image = item.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // 名称和价格
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("¥\(String(format: "%.2f", item.price))")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    
                    Divider()
                    
                    // 类型和分组
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: typeIcon(for: item.type))
                                .font(.caption)
                            Text(item.type)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                        
                        if let group = group {
                            HStack(spacing: 4) {
                                Image(systemName: group.icon)
                                    .font(.caption)
                                Text(group.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(group.color.swiftUIColor.opacity(0.1))
                            .foregroundStyle(group.color.swiftUIColor)
                            .clipShape(Capsule())
                        }
                    }
                    
                    // 详情
                    if !item.details.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("详情")
                                .font(.headline)
                            Text(item.details)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 购买链接
                    if !item.purchaseLink.isEmpty, let url = URL(string: item.purchaseLink), 
                       url.scheme?.hasPrefix("http") == true {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买链接")
                                .font(.headline)
                            
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("点击打开链接")
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if !item.purchaseLink.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("购买链接")
                                .font(.headline)
                            Text(item.purchaseLink)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    
                    // 添加日期和天数统计
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(item.listType == .wishlist ? "期盼" : "拥有")
                                .font(.headline)
                            Text("天数")
                                .font(.headline)
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(daysSinceCreation)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(item.listType == .wishlist ? .pink : .blue)
                            Text("天")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        if item.listType == .items {
                            HStack(spacing: 4) {
                                Text("平均每天支付：")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("¥\(String(format: "%.2f", averageDailyCost))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Text("添加于 \(formattedDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 实现心愿按钮（仅在心愿清单中显示）
                    if item.listType == .wishlist {
                        VStack(spacing: 12) {
                            Button {
                                if UserDefaults.standard.bool(forKey: "hasShownFulfillWishHint") {
                                    withAnimation(.spring(duration: 0.3)) {
                                        store.moveToList(itemId: item.id, listType: .items)
                                        dismiss()
                                    }
                                } else {
                                    showingFulfillWishConfirm = true
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("我已实现心愿")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            Button {
                                if let _ = sharedStore {
                                    showingAddToSharedWishlist = true
                                } else {
                                    shareWishToFriends()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "person.2.fill")
                                    Text("让好朋友们帮我实现")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.pink.opacity(0.1))
                                .foregroundStyle(.pink)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    
                    // 移入心愿列表（仅在我的物品中显示）
                    if item.listType == .items {
                        Button {
                            if UserDefaults.standard.bool(forKey: "hasShownMoveToWishlistHint") {
                                withAnimation(.spring(duration: 0.3)) {
                                    store.moveToList(itemId: item.id, listType: .wishlist)
                                    dismiss()
                                }
                            } else {
                                showingMoveToWishlistConfirm = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "heart.circle.fill")
                                Text("移入心愿列表")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .padding()
                            .background(Color.pink.opacity(0.1))
                            .foregroundStyle(.pink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // 归档/取消归档按钮（仅在我的物品中显示）
                    if item.listType == .items {
                        Button {
                            if item.isArchived {
                                // 取消归档直接执行
                                withAnimation(.spring(duration: 0.3)) {
                                    store.toggleArchiveItem(itemId: item.id)
                                    dismiss()
                                }
                            } else {
                                // 归档需要确认
                                showingArchiveConfirm = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: item.isArchived ? "archivebox.fill" : "archivebox")
                                Text(item.isArchived ? "取消归档" : "归档")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: item.isArchived ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            }
                            .padding()
                            .background(item.isArchived ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                            .foregroundStyle(item.isArchived ? .purple : .gray)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(item.listType == .wishlist ? "心愿详情" : "物品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if item.listType == .wishlist {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingEditWish = true
                        } label: {
                            Text("编辑")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditWish) {
                if let groupStore = wishlistGroupStore {
                    EditWishlistItemView(item: item, store: store, wishlistGroupStore: groupStore)
                }
            }
            .alert("确认归档", isPresented: $showingArchiveConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认归档", role: .none) {
                    withAnimation(.spring(duration: 0.3)) {
                        store.toggleArchiveItem(itemId: item.id)
                        dismiss()
                    }
                }
            } message: {
                Text("归档后，该物品将从「我的物品」列表中移除，并移至「归档」标签下。是否继续？")
            }
            .alert("移入心愿列表", isPresented: $showingMoveToWishlistConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认移入", role: .none) {
                    UserDefaults.standard.set(true, forKey: "hasShownMoveToWishlistHint")
                    withAnimation(.spring(duration: 0.3)) {
                        store.moveToList(itemId: item.id, listType: .wishlist)
                        dismiss()
                    }
                }
            } message: {
                Text("移入后，该物品将从「我的物品」列表中移除，并移至「心愿列表」中。是否继续？")
            }
            .alert("实现心愿", isPresented: $showingFulfillWishConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认实现", role: .none) {
                    UserDefaults.standard.set(true, forKey: "hasShownFulfillWishHint")
                    withAnimation(.spring(duration: 0.3)) {
                        store.moveToList(itemId: item.id, listType: .items)
                        dismiss()
                    }
                }
            } message: {
                Text("实现心愿后，该物品将从「心愿列表」中移除，并移至「我的物品」中。是否继续？")
            }
            .sheet(isPresented: $showingAddToSharedWishlist) {
                if let sharedStore = sharedStore {
                    AddToSharedWishlistSheet(item: item, sharedStore: sharedStore)
                }
            }
        }
    }
    
    private func typeIcon(for type: String) -> String {
        if let itemType = ItemType(rawValue: type) {
            return itemType.icon
        }
        return "tag"
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: item.createdAt)
    }
    
    private var daysSinceCreation: Int {
        item.daysSinceCreated
    }
    
    private var averageDailyCost: Double {
        guard daysSinceCreation > 0 else { return item.price }
        return item.price / Double(daysSinceCreation)
    }
    
    private func shareWishToFriends() {
        // 创建要导出的数据结构
        let wishData: [String: Any] = [
            "name": item.name,
            "price": item.price,
            "type": item.type,
            "details": item.details,
            "purchaseLink": item.purchaseLink,
            "displayType": item.displayType ?? item.type,
            "targetType": item.targetType ?? item.type,
            "createdAt": formattedDate,
            "daysSinceCreated": item.daysSinceCreated
        ]
        
        // 转换为 JSON 字符串
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: wishData, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // 复制到剪切板
                PrivacySettings.copyToClipboard(jsonString)
                
                // 显示提示
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } catch {
            print("导出失败: \(error)")
        }
    }
}

// MARK: - 添加到共享心愿清单 Sheet
struct AddToSharedWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @ObservedObject var sharedStore: SharedWishlistStore
    
    @State private var showingCreateNew = false
    @State private var newListName = ""
    @State private var newListEmoji = "🎁"
    @State private var addedToListId: UUID? = nil
    
    private let emojis = ["🎁", "🎂", "🎄", "💝", "🏠", "✈️", "🎮", "📱", "👗", "🎵", "📚", "🍰", "🌟", "💍", "🎯", "🎪"]
    
    private func makeSharedItem() -> SharedWishItem {
        SharedWishItem(
            sourceItemId: item.id,
            name: item.name,
            price: item.price,
            displayType: item.effectiveDisplayType,
            imageData: item.imageData,
            purchaseLink: item.purchaseLink.isEmpty ? nil : item.purchaseLink,
            details: item.details.isEmpty ? nil : item.details
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !sharedStore.lists.isEmpty {
                    Section("添加到已有清单") {
                        ForEach(sharedStore.lists) { list in
                            Button {
                                sharedStore.addItem(listId: list.id, item: makeSharedItem())
                                addedToListId = list.id
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(list.emoji)
                                        .font(.title2)
                                        .frame(width: 40, height: 40)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text("\(list.items.count) 个心愿")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if addedToListId == list.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button {
                        showingCreateNew = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("创建新的共享清单")
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("添加到共享清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("新建共享清单", isPresented: $showingCreateNew) {
                TextField("清单名称", text: $newListName)
                Button("取消", role: .cancel) {
                    newListName = ""
                }
                Button("创建") {
                    guard !newListName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let newList = SharedWishlist(
                        name: newListName.trimmingCharacters(in: .whitespaces),
                        emoji: newListEmoji,
                        items: [makeSharedItem()]
                    )
                    sharedStore.add(newList)
                    newListName = ""
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            } message: {
                Text("输入新共享清单的名称，心愿将自动添加到其中")
            }
        }
    }
}

#Preview {
    ItemDetailView(
        store: ItemStore(),
        item: Item(name: "测试物品", details: "这是一个测试物品的详情描述", purchaseLink: "https://example.com", price: 999, type: "数码", listType: .wishlist),
        group: nil
    )
}
