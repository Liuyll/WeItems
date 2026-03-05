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
    
    init(id: UUID = UUID(), name: String, icon: String = "folder", color: GroupColor = .blue, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
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
