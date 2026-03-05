//
//  ItemStore.swift
//  WeItems
//

import Foundation
import Combine
import SwiftUI

class ItemStore: ObservableObject {
    @Published var items: [Item] = []
    @Published var customDisplayTypes: [String] = []
    
    private let fileName = "items.json"
    private let customTypesFileName = "custom_display_types.json"
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
    private var customTypesFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(customTypesFileName)
    }
    
    init() {
        loadItems()
        loadCustomDisplayTypes()
    }
    
    var totalPrice: Double {
        items.reduce(0) { $0 + $1.price }
    }
    
    func totalPrice(forGroup groupId: UUID?, listType: ListType) -> Double {
        itemsForGroup(groupId, listType: listType).reduce(0) { $0 + $1.price }
    }
    
    func itemsForGroup(_ groupId: UUID?, listType: ListType) -> [Item] {
        var filtered = items.filter { $0.listType == listType }
        if let groupId = groupId {
            filtered = filtered.filter { $0.groupId == groupId }
        }
        return filtered
    }
    
    func itemCount(forGroup groupId: UUID?, listType: ListType) -> Int {
        itemsForGroup(groupId, listType: listType).count
    }
    
    func itemsByType(listType: ListType) -> [String: [Item]] {
        let filtered = items.filter { $0.listType == listType }
        return Dictionary(grouping: filtered, by: { $0.effectiveDisplayType })
    }
    
    func add(_ item: Item) {
        items.append(item)
        saveItems()
    }
    
    func update(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            saveItems()
        }
    }
    
    func delete(at offsets: IndexSet) {
        // 删除关联的图片
        for index in offsets {
            deleteImage(for: items[index])
        }
        items.remove(atOffsets: offsets)
        saveItems()
    }
    
    func delete(_ item: Item) {
        deleteImage(for: item)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            saveItems()
        }
    }
    
    func moveItems(toGroup groupId: UUID?, items itemIds: [UUID]) {
        for id in itemIds {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].groupId = groupId
            }
        }
        saveItems()
    }
    
    func moveToList(itemId: UUID, listType: ListType) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].listType = listType
            // 如果移动到"我的物品"且有指定归属类型，则更新类型
            if listType == .items, let targetType = items[index].targetType {
                items[index].type = targetType
            }
            saveItems()
        }
    }
    
    func toggleItemSelection(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].isSelected.toggle()
            saveItems()
        }
    }
    
    // MARK: - 自定义展示类型历史
    
    func addCustomDisplayType(_ type: String) {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 移除已存在的相同类型（避免重复）
        customDisplayTypes.removeAll { $0 == trimmed }
        
        // 添加到开头
        customDisplayTypes.insert(trimmed, at: 0)
        
        // 限制最多20个
        if customDisplayTypes.count > 20 {
            customDisplayTypes = Array(customDisplayTypes.prefix(20))
        }
        
        saveCustomDisplayTypes()
    }
    
    private func saveCustomDisplayTypes() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(customDisplayTypes)
            try data.write(to: customTypesFileURL)
            print("自定义类型保存成功")
        } catch {
            print("保存自定义类型失败: \(error)")
        }
    }
    
    private func loadCustomDisplayTypes() {
        do {
            let data = try Data(contentsOf: customTypesFileURL)
            let decoder = JSONDecoder()
            customDisplayTypes = try decoder.decode([String].self, from: data)
            print("自定义类型加载成功，共 \(customDisplayTypes.count) 个")
        } catch {
            print("加载自定义类型失败: \(error)")
            customDisplayTypes = []
        }
    }
    
    // MARK: - 图片存储
    
    private func imageURL(for itemId: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("item_\(itemId.uuidString).jpg")
    }
    
    func saveImage(_ imageData: Data, for itemId: UUID) -> Bool {
        let url = imageURL(for: itemId)
        do {
            try imageData.write(to: url)
            return true
        } catch {
            print("保存图片失败: \(error)")
            return false
        }
    }
    
    func loadImage(for itemId: UUID) -> Data? {
        let url = imageURL(for: itemId)
        return try? Data(contentsOf: url)
    }
    
    func deleteImage(for item: Item) {
        guard item.imageData != nil else { return }
        let url = imageURL(for: item.id)
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - 数据持久化
    
    private func saveItems() {
        // 将图片数据保存到文件，items中只保存标记
        for i in 0..<items.count {
            if let imageData = items[i].imageData {
                if saveImage(imageData, for: items[i].id) {
                    // 保存成功后，内存中保留数据但序列化时会处理
                }
            }
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL)
            print("数据保存成功: \(fileURL.path)")
        } catch {
            print("保存数据失败: \(error)")
        }
    }
    
    private func loadItems() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([Item].self, from: data)
            
            // 加载图片数据
            for i in 0..<items.count {
                if let imageData = loadImage(for: items[i].id) {
                    items[i].imageData = imageData
                }
            }
            
            print("数据加载成功，共 \(items.count) 个物品")
        } catch {
            print("加载数据失败: \(error)")
            items = []
        }
    }
}
