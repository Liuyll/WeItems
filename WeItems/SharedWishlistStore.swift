//
//  SharedWishlistStore.swift
//  WeItems
//

import Foundation
import Combine

/// 共享清单中的心愿条目（引用或快照）
struct SharedWishItem: Identifiable, Codable {
    let id: UUID
    var sourceItemId: UUID?  // 关联的原始心愿 ID（可选）
    var name: String
    var price: Double
    var isCompleted: Bool
    var displayType: String?  // 展示类型（用于分组展示）
    
    init(id: UUID = UUID(), sourceItemId: UUID? = nil, name: String, price: Double, isCompleted: Bool = false, displayType: String? = nil) {
        self.id = id
        self.sourceItemId = sourceItemId
        self.name = name
        self.price = price
        self.isCompleted = isCompleted
        self.displayType = displayType
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
    }
    
    /// 用于分组的类型名称，无类型时归为"其他"
    var effectiveDisplayType: String {
        displayType ?? "其他"
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
    
    init(id: UUID = UUID(), name: String, emoji: String = "🎁", items: [SharedWishItem] = [], createdAt: Date = Date(), updatedAt: Date? = nil, isSynced: Bool = false, wishGroupId: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isSynced = isSynced
        self.wishGroupId = wishGroupId
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
    }
    
    var totalPrice: Double {
        items.reduce(0) { $0 + $1.price }
    }
    
    var completedCount: Int {
        items.filter(\.isCompleted).count
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
            lists[li].updatedAt = Date()
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
