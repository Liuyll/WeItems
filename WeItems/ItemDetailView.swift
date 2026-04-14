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
    @State private var showingSoldConfirm = false
    @State private var soldPriceText = ""
    @State private var showingMoveToWishlistConfirm = false
    @State private var showingFulfillWishConfirm = false
    @State private var showingAddToSharedWishlist = false
    @State private var showingEditWish = false
    @State private var toastMessage: String?
    @State private var showToast = false
    
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
                        
                        if item.isPriceless {
                            Text("无价之物")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        } else {
                            Text("¥\(String(format: "%.2f", item.price))")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
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
                    
                    // 详情/心愿描述
                    if !item.details.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.listType == .wishlist ? "心愿描述" : "详情")
                                .font(.system(.headline, design: .rounded))
                            Text(item.details)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    } else if item.listType == .wishlist {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("心愿描述")
                                .font(.system(.headline, design: .rounded))
                            Text("暂无描述")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // 购买链接（仅心愿清单）
                    if item.listType == .wishlist {
                        if !item.purchaseLink.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("购买链接")
                                    .font(.system(.headline, design: .rounded))
                                
                                Button {
                                    UIPasteboard.general.string = item.purchaseLink
                                    toastMessage = "已复制到剪贴板"
                                    withAnimation { showToast = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { showToast = false }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.system(size: 14))
                                        Text(shortenURL(item.purchaseLink))
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
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("购买链接")
                                    .font(.system(.headline, design: .rounded))
                                Text("暂无链接")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
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
                        
                        if item.listType == .items && !item.isPriceless {
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
                    
                    // 售出信息（仅已售出物品显示）
                    if item.isArchived, let soldPrice = item.soldPrice {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("售出信息")
                                .font(.system(.headline, design: .rounded))
                            
                            HStack(spacing: 0) {
                                VStack(spacing: 4) {
                                    Text("售出价格")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("¥\(String(format: "%.2f", soldPrice))")
                                        .font(.system(.title3, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                }
                                .frame(maxWidth: .infinity)
                                
                                if let loss = item.soldLoss {
                                    VStack(spacing: 4) {
                                        Text(loss >= 0 ? "亏损" : "盈利")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(loss >= 0 ? "-" : "+")¥\(String(format: "%.2f", abs(loss)))")
                                            .font(.system(.title3, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundStyle(loss >= 0 ? .red : .green)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            
                            HStack(spacing: 0) {
                                VStack(spacing: 4) {
                                    Text("持有天数")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(item.daysSinceCreated) 天")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack(spacing: 4) {
                                    Text("日均成本")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("¥\(String(format: "%.2f", item.dailyCost))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            if let soldDate = item.soldDate {
                                HStack(spacing: 4) {
                                    Text("售出于")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(soldDateFormatted(soldDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                        )
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
                    
                    // 售出/取消售出按钮（仅在我的物品中显示）
                    if item.listType == .items {
                        Button {
                            if item.isArchived {
                                // 取消售出直接执行
                                withAnimation(.spring(duration: 0.3)) {
                                    store.toggleArchiveItem(itemId: item.id)
                                    // 清除售出信息
                                    if var updatedItem = store.items.first(where: { $0.id == item.id }) {
                                        updatedItem.soldPrice = nil
                                        updatedItem.soldDate = nil
                                        store.update(updatedItem)
                                    }
                                    dismiss()
                                }
                            } else {
                                soldPriceText = ""
                                showingSoldConfirm = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: item.isArchived ? "arrow.uturn.left.circle.fill" : "tag.circle.fill")
                                Text(item.isArchived ? "取消售出" : "我已售出")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: item.isArchived ? "arrow.up.circle.fill" : "yensign.circle.fill")
                            }
                            .padding()
                            .background(item.isArchived ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                            .foregroundStyle(item.isArchived ? .purple : .orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
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
            .customInputAlert(
                isPresented: $showingSoldConfirm,
                title: "确认售出",
                message: "输入「\(item.name)」的售出价格，物品将移入售出列表",
                placeholder: "售出价格",
                text: $soldPriceText,
                confirmText: "确认售出",
                keyboardType: .decimalPad,
                onConfirm: {
                    withAnimation(.spring(duration: 0.3)) {
                        let soldPrice = Double(soldPriceText) ?? 0
                        store.markAsSold(itemId: item.id, soldPrice: soldPrice)
                        dismiss()
                    }
                }
            )
            .customConfirmAlert(
                isPresented: $showingMoveToWishlistConfirm,
                title: "移入心愿列表",
                message: "移入后，该物品将从「我的物品」列表中移除，并移至「心愿列表」中。是否继续？",
                confirmText: "确认移入",
                onConfirm: {
                    UserDefaults.standard.set(true, forKey: "hasShownMoveToWishlistHint")
                    withAnimation(.spring(duration: 0.3)) {
                        store.moveToList(itemId: item.id, listType: .wishlist)
                        dismiss()
                    }
                }
            )
            .customConfirmAlert(
                isPresented: $showingFulfillWishConfirm,
                title: "实现心愿",
                message: "实现心愿后，该物品将从「心愿列表」中移除，并移至「我的物品」中。是否继续？",
                confirmText: "确认实现",
                onConfirm: {
                    UserDefaults.standard.set(true, forKey: "hasShownFulfillWishHint")
                    withAnimation(.spring(duration: 0.3)) {
                        store.moveToList(itemId: item.id, listType: .items)
                        dismiss()
                    }
                }
            )
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
    
    private func soldDateFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private var daysSinceCreation: Int {
        item.daysSinceCreated
    }
    
    private var averageDailyCost: Double {
        return item.dailyCost
    }
    
    /// 将 URL 缩短为域名+路径前缀的短链形式
    private func shortenURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            // 非标准 URL，截断显示
            return urlString.count > 30 ? String(urlString.prefix(30)) + "..." : urlString
        }
        let path = url.path
        if path.isEmpty || path == "/" {
            return host
        }
        let shortPath = path.count > 15 ? String(path.prefix(15)) + "..." : path
        return host + shortPath
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
            .customInputAlert(
                isPresented: $showingCreateNew,
                title: "新建共享清单",
                message: "输入新共享清单的名称，心愿将自动添加到其中",
                placeholder: "清单名称",
                text: $newListName,
                confirmText: "创建",
                onConfirm: {
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
                },
                onCancel: {
                    newListName = ""
                }
            )
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
