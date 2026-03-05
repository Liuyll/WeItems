//
//  WishlistGroupStore.swift
//  WeItems
//

import Foundation
import SwiftUI
import Combine

class WishlistGroupStore: ObservableObject {
    @Published var groups: [ItemGroup] = []
    
    private let fileName = "wishlist_groups.json"
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
    
    init() {
        loadGroups()
    }
    
    func add(_ group: ItemGroup) {
        groups.append(group)
        saveGroups()
    }
    
    func delete(_ group: ItemGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups.remove(at: index)
            saveGroups()
        }
    }
    
    func update(_ group: ItemGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            saveGroups()
        }
    }
    
    func group(for id: UUID?) -> ItemGroup? {
        guard let id = id else { return nil }
        return groups.first(where: { $0.id == id })
    }
    
    private func saveGroups() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(groups)
            try data.write(to: fileURL)
            print("心愿清单分组保存成功: \(fileURL.path)")
        } catch {
            print("保存心愿清单分组失败: \(error)")
        }
    }
    
    private func loadGroups() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            groups = try decoder.decode([ItemGroup].self, from: data)
            print("心愿清单分组加载成功，共 \(groups.count) 个分组")
        } catch {
            print("加载心愿清单分组失败: \(error)")
            groups = []
        }
    }
}
