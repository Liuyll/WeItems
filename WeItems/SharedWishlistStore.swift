//
//  SharedWishlistStore.swift
//  WeItems
//

import Foundation
import Combine
import SwiftUI

/// 共享清单中的心愿条目（引用或快照）
struct SharedWishItem: Identifiable, Codable {
    let id: UUID
    var sourceItemId: UUID?  // 关联的原始心愿 ID（可选）
    var name: String
    var price: Double
    var isCompleted: Bool
    var displayType: String?  // 展示类型（用于分组展示）
    var imageData: Data?      // 图片数据
    var purchaseLink: String? // 购买链接
    var details: String?      // 备注/详情
    var completedBy: String?  // 谁实现了这个愿望
    
    init(id: UUID = UUID(), sourceItemId: UUID? = nil, name: String, price: Double, isCompleted: Bool = false, displayType: String? = nil, imageData: Data? = nil, purchaseLink: String? = nil, details: String? = nil, completedBy: String? = nil) {
        self.id = id
        self.sourceItemId = sourceItemId
        self.name = name
        self.price = price
        self.isCompleted = isCompleted
        self.displayType = displayType
        self.imageData = imageData
        self.purchaseLink = purchaseLink
        self.details = details
        self.completedBy = completedBy
    }
    
    // 兼容旧数据
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceItemId = try container.decodeIfPresent(UUID.self, forKey: .sourceItemId)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        displayType = try container.decodeIfPresent(String.self, forKey: .displayType)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        purchaseLink = try container.decodeIfPresent(String.self, forKey: .purchaseLink)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
    }
    
    /// 用于分组的类型名称，无类型时归为"其他"
    var effectiveDisplayType: String {
        displayType ?? "其他"
    }
    
    var image: Image? {
        guard let imageData = imageData,
              let uiImage = UIImage(data: imageData) else { return nil }
        return Image(uiImage: uiImage)
    }
}

/// 共享清单
struct SharedWishlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var items: [SharedWishItem]
    var createdAt: Date
    var updatedAt: Date
    var isSynced: Bool
    var wishGroupId: String?
    var isOwner: Bool
    var ownerName: String?
    var myNickname: String?  // 我在此共享清单中的昵称（本地持久化）
    
    init(id: UUID = UUID(), name: String, emoji: String = "🎁", items: [SharedWishItem] = [], createdAt: Date = Date(), updatedAt: Date? = nil, isSynced: Bool = false, wishGroupId: String? = nil, isOwner: Bool = true, ownerName: String? = nil, myNickname: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isSynced = isSynced
        self.wishGroupId = wishGroupId
        self.isOwner = isOwner
        self.ownerName = ownerName
        self.myNickname = myNickname
    }
    
    // 兼容旧数据
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        items = try container.decode([SharedWishItem].self, forKey: .items)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isSynced = try container.decodeIfPresent(Bool.self, forKey: .isSynced) ?? false
        wishGroupId = try container.decodeIfPresent(String.self, forKey: .wishGroupId)
        ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
        // 兼容旧数据：如果没有 isOwner 字段，通过 ownerName 推断
        // 有 ownerName 说明是导入的他人清单（非 Owner），没有则是自己创建的
        if let savedIsOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) {
            isOwner = savedIsOwner
        } else {
            // 旧数据没有 isOwner 字段，用 ownerName 推断
            if let ownerName = ownerName, !ownerName.isEmpty {
                isOwner = false
            } else {
                isOwner = true
            }
        }
        myNickname = try container.decodeIfPresent(String.self, forKey: .myNickname)
    }
    
    var totalPrice: Double {
        items.reduce(0) { $0 + $1.price }
    }
    
    var completedCount: Int {
        items.filter(\.isCompleted).count
    }
    
    var completedPrice: Double {
        items.filter(\.isCompleted).reduce(0) { $0 + $1.price }
    }
}

/// 共享清单持久化 Store
class SharedWishlistStore: ObservableObject {
    @Published var lists: [SharedWishlist] = []
    
    private let fileName = "shared_wishlists.json"
    
    private var userDir: URL {
        UserStorageHelper.shared.currentUserDirectory
    }
    
    private var fileURL: URL {
        userDir.appendingPathComponent(fileName)
    }
    
    init() {
        load()
    }
    
    func reloadForCurrentUser() {
        load()
    }
    
    // MARK: - CRUD
    
    func add(_ list: SharedWishlist) {
        lists.insert(list, at: 0)
        save()
    }
    
    func update(_ list: SharedWishlist) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            var updated = list
            updated.updatedAt = Date()
            updated.isSynced = false
            lists[index] = updated
            save()
        }
    }
    
    func delete(_ list: SharedWishlist) {
        lists.removeAll { $0.id == list.id }
        save()
    }
    
    func toggleItemCompleted(listId: UUID, itemId: UUID) {
        if let li = lists.firstIndex(where: { $0.id == listId }),
           let ii = lists[li].items.firstIndex(where: { $0.id == itemId }) {
            lists[li].items[ii].isCompleted.toggle()
            if lists[li].items[ii].isCompleted {
                // 优先用 myNickname（自己在清单中的昵称），没有则显示"我"
                let nickname = lists[li].myNickname ?? "我"
                lists[li].items[ii].completedBy = nickname
            } else {
                lists[li].items[ii].completedBy = nil
            }
            lists[li].updatedAt = Date()
            lists[li].isSynced = false
            save()
        }
    }
    
    func updateItem(listId: UUID, item: SharedWishItem) {
        if let li = lists.firstIndex(where: { $0.id == listId }),
           let ii = lists[li].items.firstIndex(where: { $0.id == item.id }) {
            lists[li].items[ii] = item
            lists[li].updatedAt = Date()
            lists[li].isSynced = false
            save()
        }
    }
    
    func addItem(listId: UUID, item: SharedWishItem) {
        if let li = lists.firstIndex(where: { $0.id == listId }) {
            lists[li].items.append(item)
            lists[li].updatedAt = Date()
            lists[li].isSynced = false
            save()
        }
    }
    
    func deleteItem(listId: UUID, itemId: UUID) {
        if let li = lists.firstIndex(where: { $0.id == listId }) {
            lists[li].items.removeAll { $0.id == itemId }
            lists[li].updatedAt = Date()
            lists[li].isSynced = false
            save()
        }
    }
    
    func markSynced(_ listId: UUID, wishGroupId: String? = nil) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].isSynced = true
            if let gid = wishGroupId {
                lists[index].wishGroupId = gid
            }
            save()
        }
    }
    
    /// 保存用户在某个共享清单中的昵称
    func setMyNickname(_ listId: UUID, nickname: String) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].myNickname = nickname
            save()
        }
    }
    
    /// 将远端同步结果 merge 到本地清单
    /// - Parameters:
    ///   - listId: 本地清单 ID
    ///   - mergedItems: merge 后的心愿列表
    ///   - remoteName: 远端清单名称（可选，用于更新非 owner 的清单名）
    ///   - remoteEmoji: 远端清单图标（可选）
    ///   - remoteOwnerName: 远端 owner 名称（可选）
    func applyMergedResult(listId: UUID, mergedItems: [SharedWishItem], isSynced: Bool = true, remoteName: String? = nil, remoteEmoji: String? = nil, remoteOwnerName: String? = nil) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].items = mergedItems
            lists[index].isSynced = isSynced
            lists[index].updatedAt = Date()
            // 对于非 owner 的清单，用远端的名称和图标更新
            if !lists[index].isOwner {
                if let name = remoteName, !name.isEmpty {
                    lists[index].name = name
                }
                if let emoji = remoteEmoji, !emoji.isEmpty {
                    lists[index].emoji = emoji
                }
                if let ownerName = remoteOwnerName, !ownerName.isEmpty {
                    lists[index].ownerName = ownerName
                }
            }
            save()
        }
    }
    
    // MARK: - Persistence
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(lists)
            try data.write(to: fileURL)
        } catch {
            print("[SharedWishlistStore] 保存失败: \(error)")
        }
    }
    
    private func load() {
        var all: [SharedWishlist] = []
        all.append(contentsOf: loadFrom(fileURL))
        
        if UserStorageHelper.shared.isLoggedIn {
            let anonFile = UserStorageHelper.shared.anonymousDirectory.appendingPathComponent(fileName)
            let anonLists = loadFrom(anonFile)
            let existingIds = Set(all.map(\.id))
            for list in anonLists where !existingIds.contains(list.id) {
                all.append(list)
            }
        }
        
        lists = all.sorted { $0.updatedAt > $1.updatedAt }
        
        // 修正旧数据：有 ownerName 说明是导入的他人清单，isOwner 应为 false
        var needsSave = false
        for i in lists.indices {
            if lists[i].isOwner,
               let ownerName = lists[i].ownerName, !ownerName.isEmpty {
                lists[i].isOwner = false
                needsSave = true
            }
        }
        if needsSave {
            save()
        }
    }
    
    private func loadFrom(_ url: URL) -> [SharedWishlist] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SharedWishlist].self, from: data)
        } catch {
            print("[SharedWishlistStore] 加载失败(\(url.lastPathComponent)): \(error)")
            return []
        }
    }
}
