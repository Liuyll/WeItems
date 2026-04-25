//
//  ItemGroup.swift
//  WeItems
//

import Foundation
import SwiftUI

struct ItemGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var color: GroupColor
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, icon: String = "folder", color: GroupColor = .blue, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // 兼容旧数据：缺少 updatedAt 时用 createdAt 兜底
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(GroupColor.self, forKey: .color)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

enum GroupColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray
    
    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}
