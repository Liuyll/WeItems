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

struct Item: Identifiable, Codable, Equatable {
    let id: UUID
    var itemId: String              // 唯一业务 ID: userid_时间戳_8位随机数
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
    var isPriceless: Bool         // 无价之物（不计入资产和总价值，不计算每天开销）
    var ownedDate: Date?          // 拥有日期（用户自定义的拥有起始日期）
    
    // 心愿清单专用字段
    var displayType: String?      // 心愿清单中展示的类型（可自定义）
    var targetType: String?       // 实现心愿后归属的类型（必须是预设类型）
    var wishlistGroupId: UUID?    // 心愿清单分组ID
    
    // 云端图片
    var imageUrl: String?         // 云存储图片下载链接（用于同步对比）
    
    // 售出相关
    var soldPrice: Double?        // 售出价格
    var soldDate: Date?           // 售出日期
    var recycleMethod: String?    // 回收方式
    
    // 同步状态
    var isSynced: Bool            // 是否已同步到远端（本地新建为 false，同步成功或从远端拉取为 true）
    
    // imageChanged 不参与 Codable 编解码
    enum CodingKeys: String, CodingKey {
        case id, itemId, name, details, purchaseLink, imageData, compressedImageData
        case price, type, groupId, listType, createdAt, updatedAt
        case isSelected, isArchived, isLargeItem, isPriceless, ownedDate
        case displayType, targetType, wishlistGroupId
        case imageUrl, soldPrice, soldDate, recycleMethod, isSynced
    }
    
    // 自定义编码：排除图片数据，JSON 只存元数据，图片单独存文件
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(name, forKey: .name)
        try container.encode(details, forKey: .details)
        try container.encode(purchaseLink, forKey: .purchaseLink)
        // imageData / compressedImageData 不写入 JSON，由独立文件管理
        try container.encode(price, forKey: .price)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encode(listType, forKey: .listType)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(isLargeItem, forKey: .isLargeItem)
        try container.encode(isPriceless, forKey: .isPriceless)
        try container.encodeIfPresent(ownedDate, forKey: .ownedDate)
        try container.encodeIfPresent(displayType, forKey: .displayType)
        try container.encodeIfPresent(targetType, forKey: .targetType)
        try container.encodeIfPresent(wishlistGroupId, forKey: .wishlistGroupId)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(soldPrice, forKey: .soldPrice)
        try container.encodeIfPresent(soldDate, forKey: .soldDate)
        try container.encodeIfPresent(recycleMethod, forKey: .recycleMethod)
        try container.encode(isSynced, forKey: .isSynced)
    }
    
    /// 生成唯一 itemId: userid_时间戳_8位随机数
    static func generateItemId() -> String {
        let userId = TokenStorage.shared.getSub() ?? "anonymous"
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = String(format: "%08d", Int.random(in: 0...99999999))
        return "\(userId)_\(timestamp)_\(random)"
    }
    
    init(id: UUID = UUID(), itemId: String? = nil, name: String, details: String, purchaseLink: String, imageData: Data? = nil, compressedImageData: Data? = nil, imageChanged: Bool = false, price: Double, type: String, groupId: UUID? = nil, listType: ListType = .items, createdAt: Date = Date(), updatedAt: Date? = nil, isSelected: Bool = false, isArchived: Bool = false, isLargeItem: Bool = false, isPriceless: Bool = false, ownedDate: Date? = nil, displayType: String? = nil, targetType: String? = nil, wishlistGroupId: UUID? = nil, imageUrl: String? = nil, soldPrice: Double? = nil, soldDate: Date? = nil, recycleMethod: String? = nil, isSynced: Bool = false) {
        self.id = id
        self.itemId = itemId ?? Item.generateItemId()
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
        self.isPriceless = isPriceless
        self.ownedDate = ownedDate
        self.displayType = displayType
        self.targetType = targetType
        self.wishlistGroupId = wishlistGroupId
        self.imageUrl = imageUrl
        self.soldPrice = soldPrice
        self.soldDate = soldDate
        self.recycleMethod = recycleMethod
        self.isSynced = isSynced
    }
    
    // 自定义 Decode，兼容旧数据（缺少 updatedAt 时用 createdAt 补充）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId) ?? Item.generateItemId()
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
        isPriceless = try container.decodeIfPresent(Bool.self, forKey: .isPriceless) ?? false
        ownedDate = try container.decodeIfPresent(Date.self, forKey: .ownedDate)
        displayType = try container.decodeIfPresent(String.self, forKey: .displayType)
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        wishlistGroupId = try container.decodeIfPresent(UUID.self, forKey: .wishlistGroupId)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        soldPrice = try container.decodeIfPresent(Double.self, forKey: .soldPrice)
        soldDate = try container.decodeIfPresent(Date.self, forKey: .soldDate)
        recycleMethod = try container.decodeIfPresent(String.self, forKey: .recycleMethod)
        isSynced = try container.decodeIfPresent(Bool.self, forKey: .isSynced) ?? false
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
    
    // 计算属性用于显示（优先使用拥有日期）
    var daysSinceCreated: Int {
        let calendar = Calendar.current
        let startDate = ownedDate ?? createdAt
        let endDate = soldDate ?? Date()
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return max((components.day ?? 0) + 1, 1)
    }
    
    /// 售出盈亏金额（正数=亏损，负数=盈利）
    var soldLoss: Double? {
        guard let soldPrice else { return nil }
        return price - soldPrice
    }
    
    /// 日均使用成本（已售出且盈利时为0，未售出：购入价/持有天数）
    var dailyCost: Double {
        guard !isPriceless, daysSinceCreated > 0 else { return 0 }
        let effectivePrice = price - (soldPrice ?? 0)
        return max(effectivePrice, 0) / Double(daysSinceCreated)
    }
}

enum ItemType: String, CaseIterable {
    case digital = "数码"
    case fashion = "装扮"
    case appliance = "家电"
    case largeItem = "大件"
    case lifeGood = "人生好物"
    case edc = "EDC"
    case outdoor = "旅行"
    case other = "其他"

    var icon: String {
        switch self {
        case .digital: return "iphone"
        case .fashion: return "tshirt"
        case .appliance: return "tv"
        case .largeItem: return "largeItem"
        case .lifeGood: return "lifeGood"
        case .edc: return "wallet.bifold"
        case .outdoor: return "tent"
        case .other: return "square.grid.2x2"
        }
    }
    
    /// 是否使用自定义图片（非 SF Symbol）
    var isCustomIcon: Bool {
        switch self {
        case .largeItem, .lifeGood: return true
        default: return false
        }
    }
    
    /// 返回图标 View（自动区分 SF Symbol 和自定义图片）
    /// - Parameter size: 自定义图片的尺寸，SF Symbol 不受此参数影响（由 .font 控制）
    @ViewBuilder
    func iconImage(size: CGFloat = 16) -> some View {
        if isCustomIcon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: icon)
        }
    }
    
    var color: Color {
        switch self {
        case .digital: return .blue
        case .fashion: return .pink
        case .appliance: return .cyan
        case .largeItem: return .purple
        case .lifeGood: return .red
        case .edc: return .brown
        case .outdoor: return .green
        case .other: return .gray
        }
    }
}
