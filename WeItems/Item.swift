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
    var price: Double
    var type: String
    var groupId: UUID?            // 我的物品分组ID
    var listType: ListType
    var createdAt: Date
    var isSelected: Bool
    
    // 心愿清单专用字段
    var displayType: String?      // 心愿清单中展示的类型（可自定义）
    var targetType: String?       // 实现心愿后归属的类型（必须是预设类型）
    var wishlistGroupId: UUID?    // 心愿清单分组ID
    
    init(id: UUID = UUID(), name: String, details: String, purchaseLink: String, imageData: Data? = nil, price: Double, type: String, groupId: UUID? = nil, listType: ListType = .items, createdAt: Date = Date(), isSelected: Bool = false, displayType: String? = nil, targetType: String? = nil, wishlistGroupId: UUID? = nil) {
        self.id = id
        self.name = name
        self.details = details
        self.purchaseLink = purchaseLink
        self.imageData = imageData
        self.price = price
        self.type = type
        self.groupId = groupId
        self.listType = listType
        self.createdAt = createdAt
        self.isSelected = isSelected
        self.displayType = displayType
        self.targetType = targetType
        self.wishlistGroupId = wishlistGroupId
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
    case outdoor = "户外装备"
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
