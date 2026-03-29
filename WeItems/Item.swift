//
//  Item.swift
//  WeItems
//

import Foundation
import SwiftUI

enum ListType: String, Codable, CaseIterable {
    case items = "items"
    case wishlist = "wishlist"
    case daily = "daily"
}

struct Item: Identifiable, Codable {
    let id: UUID
    var name: String
    var details: String
    var purchaseLink: String
    var imageData: Data?
    var compressedImageData: Data?  // 压缩版图片（0.7质量），仅用于云端同步上传
    var imageChanged: Bool          // 标记图片是否被用户编辑过（仅用于同步判断，不持久化）
    var price: Double
    var type: String
    var groupId: UUID?            // 我的物品分组ID
    var listType: ListType
    var createdAt: Date
    var updatedAt: Date           // 最近更新时间
    var isSelected: Bool
    var isArchived: Bool          // 是否归档（仅用于我的物品）
    var isLargeItem: Bool         // 是否大件物品
    
    // 心愿清单专用字段
    var displayType: String?      // 心愿清单中展示的类型（可自定义）
    var targetType: String?       // 实现心愿后归属的类型（必须是预设类型）
    var wishlistGroupId: UUID?    // 心愿清单分组ID
    
    // 云端图片
    var imageUrl: String?         // 云存储图片下载链接（用于同步对比）
    
    // imageChanged 不参与 Codable 编解码
    enum CodingKeys: String, CodingKey {
        case id, name, details, purchaseLink, imageData, compressedImageData
        case price, type, groupId, listType, createdAt, updatedAt
        case isSelected, isArchived, isLargeItem, displayType, targetType, wishlistGroupId
        case imageUrl
    }
    
    init(id: UUID = UUID(), name: String, details: String, purchaseLink: String, imageData: Data? = nil, compressedImageData: Data? = nil, imageChanged: Bool = false, price: Double, type: String, groupId: UUID? = nil, listType: ListType = .items, createdAt: Date = Date(), updatedAt: Date? = nil, isSelected: Bool = false, isArchived: Bool = false, isLargeItem: Bool = false, displayType: String? = nil, targetType: String? = nil, wishlistGroupId: UUID? = nil, imageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.details = details
        self.purchaseLink = purchaseLink
        self.imageData = imageData
        self.compressedImageData = compressedImageData
        self.imageChanged = imageChanged
        self.price = price
        self.type = type
        self.groupId = groupId
        self.listType = listType
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isSelected = isSelected
        self.isArchived = isArchived
        self.isLargeItem = isLargeItem
        self.displayType = displayType
        self.targetType = targetType
        self.wishlistGroupId = wishlistGroupId
        self.imageUrl = imageUrl
    }
    
    // 自定义 Decode，兼容旧数据（缺少 updatedAt 时用 createdAt 补充）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        details = try container.decode(String.self, forKey: .details)
        purchaseLink = try container.decode(String.self, forKey: .purchaseLink)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        compressedImageData = try container.decodeIfPresent(Data.self, forKey: .compressedImageData)
        imageChanged = false  // 从磁盘加载的数据，图片未改变
        price = try container.decode(Double.self, forKey: .price)
        type = try container.decode(String.self, forKey: .type)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        listType = try container.decode(ListType.self, forKey: .listType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isSelected = try container.decode(Bool.self, forKey: .isSelected)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isLargeItem = try container.decodeIfPresent(Bool.self, forKey: .isLargeItem) ?? false
        displayType = try container.decodeIfPresent(String.self, forKey: .displayType)
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        wishlistGroupId = try container.decodeIfPresent(UUID.self, forKey: .wishlistGroupId)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
    }
    
    // 获取展示用的类型（心愿清单优先用 displayType）
    var effectiveDisplayType: String {
        if listType == .wishlist, let displayType = displayType {
            return displayType
        }
        return type
    }
    
    var image: Image? {
        guard let imageData = imageData,
              let uiImage = UIImage(data: imageData) else { return nil }
        return Image(uiImage: uiImage)
    }
    
    // 计算属性用于显示
    var daysSinceCreated: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: createdAt, to: Date())
        return (components.day ?? 0) + 1
    }
}

enum ItemType: String, CaseIterable {
    case digital = "数码"
    case fashion = "装扮"
    case appliance = "家电"
    case largeItem = "大件"
    case lifeGood = "人生好物"
    case edc = "EDC"
    case outdoor = "精神旅行"
    case other = "其他"

    var icon: String {
        switch self {
        case .digital: return "iphone"
        case .fashion: return "tshirt"
        case .appliance: return "tv"
        case .largeItem: return "sofa"
        case .lifeGood: return "heart.fill"
        case .edc: return "wallet.bifold"
        case .outdoor: return "tent"
        case .other: return "square.grid.2x2"
        }
    }
}
