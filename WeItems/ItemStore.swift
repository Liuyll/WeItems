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
    
    /// 自上次同步以来是否有本地数据变更
    @Published var hasUnsyncedChanges: Bool = false
    
    private let fileName = "items.json"
    private let customTypesFileName = "custom_display_types.json"
    private let unsyncedFlagFileName = "unsynced_flag"
    private let deletedItemsFileName = "deleted_items.json"
    
    /// 已删除物品的记录：[itemId: 删除时间戳]
    private(set) var deletedItemRecords: [String: Date] = [:]
    
    // MARK: - 同步时间管理
    
    private static let lastSyncTimeKey = "lastSyncTime"
    
    /// 上次同步的时间
    var lastSyncTime: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: Self.lastSyncTimeKey + "_" + UserStorageHelper.shared.currentUserKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastSyncTimeKey + "_" + UserStorageHelper.shared.currentUserKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncTimeKey + "_" + UserStorageHelper.shared.currentUserKey)
            }
        }
    }
    
    /// 是否需要自动同步（距离上次同步超过1天 且 有未同步的变更）
    var needsAutoSync: Bool {
        guard hasUnsyncedChanges else { return false }
        guard let lastSync = lastSyncTime else {
            // 从未同步过，只要有变更就需要同步
            return true
        }
        let oneDayInterval: TimeInterval = 24 * 60 * 60
        return Date().timeIntervalSince(lastSync) >= oneDayInterval
    }
    
    /// 标记同步完成
    func markSyncCompleted() {
        lastSyncTime = Date()
        hasUnsyncedChanges = false
        saveUnsyncedFlag(false)
        print("[ItemStore] 同步完成标记已更新")
    }
    
    /// 将指定物品标记为已同步到远端
    func markItemsSynced(itemIds: [String]) {
        var changed = false
        for itemId in itemIds {
            if let index = items.firstIndex(where: { $0.itemId == itemId && !$0.isSynced }) {
                items[index].isSynced = true
                changed = true
            }
        }
        if changed { saveItems() }
    }
    
    /// 将所有物品标记为已同步
    func markAllItemsSynced() {
        var changed = false
        for i in items.indices where !items[i].isSynced {
            items[i].isSynced = true
            changed = true
        }
        if changed { saveItems() }
    }
    
    /// 当前用户的存储目录
    private var userDir: URL {
        UserStorageHelper.shared.currentUserDirectory
    }
    
    private var fileURL: URL {
        userDir.appendingPathComponent(fileName)
    }
    private var customTypesFileURL: URL {
        userDir.appendingPathComponent(customTypesFileName)
    }
    
    init() {
        loadItems()
        loadCustomDisplayTypes()
        loadUnsyncedFlag()
        loadDeletedItemRecords()
    }
    
    /// 切换用户后重新加载数据
    func reloadForCurrentUser() {
        let prevCount = items.count
        loadItems()
        loadCustomDisplayTypes()
        loadUnsyncedFlag()
        loadDeletedItemRecords()
        
        // 登录时合并了 anonymous 数据，需要保存到用户目录以持久化
        if UserStorageHelper.shared.isLoggedIn && items.count > 0 {
            saveItems()
            saveCustomDisplayTypes()
        }
        
        print("[ItemStore] 已切换到用户: \(UserStorageHelper.shared.currentUserKey), 共 \(items.count) 个物品")
    }
    
    var totalPrice: Double {
        items.filter { !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    func totalPrice(forGroup groupId: UUID?, listType: ListType) -> Double {
        itemsForGroup(groupId, listType: listType).filter { !$0.isPriceless }.reduce(0) { $0 + $1.price }
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
        if let index = items.firstIndex(where: { $0.itemId == item.itemId }) {
            var updated = item
            updated.updatedAt = Date()
            objectWillChange.send()
            items[index] = updated
            saveItems()
        }
    }
    
    func delete(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            deleteImage(for: item)
            if item.isSynced {
                recordDeletion(itemId: item.itemId)
            }
        }
        items.remove(atOffsets: offsets)
        saveItems()
    }
    
    func delete(_ item: Item) {
        deleteImage(for: item)
        if item.isSynced {
            recordDeletion(itemId: item.itemId)
        }
        if let index = items.firstIndex(where: { $0.itemId == item.itemId }) {
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
    
    func toggleArchiveItem(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].isArchived.toggle()
            if !items[index].isArchived {
                // 取消售出时清除售出信息
                items[index].soldPrice = nil
                items[index].soldDate = nil
            }
            saveItems()
        }
    }
    
    /// 标记物品为已售出
    func markAsSold(itemId: UUID, soldPrice: Double) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].isArchived = true
            items[index].soldPrice = soldPrice
            items[index].soldDate = Date()
            saveItems()
        }
    }
    
    func archiveItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.itemId == item.itemId }) {
            items[index].isArchived = true
            saveItems()
        }
    }
    
    func unarchiveItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.itemId == item.itemId }) {
            items[index].isArchived = false
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
    
    /// 从当前所有心愿清单中扫描自定义类型，补充到 customDisplayTypes
    /// 只扫描 displayType 不在预设 ItemType 中的项
    func rebuildCustomDisplayTypesFromWishes() {
        let presetTypes = Set(ItemType.allCases.map { $0.rawValue })
        var scannedTypes: [String] = []
        
        for item in items where item.listType == .wishlist {
            let display = item.effectiveDisplayType
            if !presetTypes.contains(display) && !display.isEmpty && !scannedTypes.contains(display) {
                scannedTypes.append(display)
            }
        }
        
        guard !scannedTypes.isEmpty else {
            print("[ItemStore] 扫描心愿清单未发现自定义类型")
            return
        }
        
        // 合并：已有的保持顺序在前，扫描到的新增到后面
        var merged = customDisplayTypes
        for t in scannedTypes where !merged.contains(t) {
            merged.append(t)
        }
        
        // 限制最多20个
        if merged.count > 20 {
            merged = Array(merged.prefix(20))
        }
        
        customDisplayTypes = merged
        saveCustomDisplayTypes()
        print("[ItemStore] 从心愿清单扫描到 \(scannedTypes.count) 个自定义类型，当前共 \(customDisplayTypes.count) 个")
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
        var allTypes: [String] = []
        
        // 加载当前用户目录
        allTypes.append(contentsOf: loadTypesFromFile(customTypesFileURL))
        
        // 已登录用户额外加载 anonymous 目录
        if UserStorageHelper.shared.isLoggedIn {
            let anonymousFile = UserStorageHelper.shared.anonymousDirectory
                .appendingPathComponent(customTypesFileName)
            let anonymousTypes = loadTypesFromFile(anonymousFile)
            for t in anonymousTypes where !allTypes.contains(t) {
                allTypes.append(t)
            }
        }
        
        customDisplayTypes = allTypes
        print("自定义类型加载成功，共 \(customDisplayTypes.count) 个")
        
        // 如果自定义类型列表为空，尝试从已有心愿清单中扫描
        if customDisplayTypes.isEmpty {
            rebuildCustomDisplayTypesFromWishes()
        }
    }
    
    private func loadTypesFromFile(_ url: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("加载自定义类型失败(\(url.lastPathComponent)): \(error)")
            return []
        }
    }
    
    // MARK: - 图片存储
    
    private func imageURL(for itemId: UUID) -> URL {
        userDir.appendingPathComponent("item_\(itemId.uuidString).jpg")
    }
    
    /// 压缩版图片文件路径（仅用于同步上传）
    private func compressedImageURL(for itemId: UUID) -> URL {
        userDir.appendingPathComponent("item_\(itemId.uuidString)_compressed.jpg")
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
    
    /// 保存压缩版图片（0.7 质量），用于同步上传
    func saveCompressedImage(_ imageData: Data, for itemId: UUID) -> Bool {
        guard let uiImage = UIImage(data: imageData) else { return false }
        guard let compressed = uiImage.jpegData(compressionQuality: 0.7) else { return false }
        let url = compressedImageURL(for: itemId)
        do {
            try compressed.write(to: url)
            return true
        } catch {
            print("保存压缩图片失败: \(error)")
            return false
        }
    }
    
    /// 加载压缩版图片
    func loadCompressedImage(for itemId: UUID) -> Data? {
        let url = compressedImageURL(for: itemId)
        if let data = try? Data(contentsOf: url) {
            return data
        }
        // 已登录用户回退到 anonymous 目录查找
        if UserStorageHelper.shared.isLoggedIn {
            let anonymousURL = UserStorageHelper.shared.anonymousDirectory
                .appendingPathComponent("item_\(itemId.uuidString)_compressed.jpg")
            return try? Data(contentsOf: anonymousURL)
        }
        return nil
    }
    
    func loadImage(for itemId: UUID) -> Data? {
        let url = imageURL(for: itemId)
        if let data = try? Data(contentsOf: url) {
            return data
        }
        // 已登录用户回退到 anonymous 目录查找
        if UserStorageHelper.shared.isLoggedIn {
            let anonymousURL = UserStorageHelper.shared.anonymousDirectory
                .appendingPathComponent("item_\(itemId.uuidString).jpg")
            return try? Data(contentsOf: anonymousURL)
        }
        return nil
    }
    
    func deleteImage(for item: Item) {
        guard item.imageData != nil else { return }
        let url = imageURL(for: item.id)
        try? FileManager.default.removeItem(at: url)
        // 同时删除压缩版
        let compressedUrl = compressedImageURL(for: item.id)
        try? FileManager.default.removeItem(at: compressedUrl)
    }
    
    // MARK: - 数据持久化
    
    private func saveItems() {
        // 标记有未同步的变更
        hasUnsyncedChanges = true
        saveUnsyncedFlag(true)
        
        // 标记趋势缓存失效
        TrendDataCache.shared.invalidate()
        
        // 将图片数据保存到文件，items中只保存标记
        for i in 0..<items.count {
            if let imageData = items[i].imageData {
                if saveImage(imageData, for: items[i].id) {
                    // 保存成功后，同时生成压缩版用于同步上传
                    if saveCompressedImage(imageData, for: items[i].id) {
                        // 加载压缩版到内存
                        if let compressed = loadCompressedImage(for: items[i].id) {
                            items[i].compressedImageData = compressed
                        }
                    }
                }
            }
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL)

        } catch {
            print("保存数据失败: \(error)")
        }
    }
    
    private func loadItems() {
        var allItems: [Item] = []
        
        // 1. 加载当前用户目录的数据
        allItems.append(contentsOf: loadItemsFromFile(fileURL))
        
        // 2. 已登录用户额外加载 anonymous 目录的数据
        if UserStorageHelper.shared.isLoggedIn {
            let anonymousFile = UserStorageHelper.shared.anonymousDirectory
                .appendingPathComponent(fileName)
            let anonymousItems = loadItemsFromFile(anonymousFile)
            // 去重：以 itemId 为准，当前用户数据优先
            let existingIds = Set(allItems.map { $0.itemId })
            for item in anonymousItems where !existingIds.contains(item.itemId) {
                allItems.append(item)
            }
        }
        
        items = allItems
        
        // 加载图片数据
        for i in 0..<items.count {
            if let imageData = loadImage(for: items[i].id) {
                items[i].imageData = imageData
            }
            // 加载压缩版图片（用于同步上传）
            if let compressedData = loadCompressedImage(for: items[i].id) {
                items[i].compressedImageData = compressedData
            }
        }
        
        print("数据加载成功，共 \(items.count) 个物品 (用户: \(UserStorageHelper.shared.currentUserKey))")
    }
    
    private func loadItemsFromFile(_ url: URL) -> [Item] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Item].self, from: data)
        } catch {
            print("加载数据失败(\(url.lastPathComponent)): \(error)")
            return []
        }
    }
    
    // MARK: - 未同步标记持久化
    
    private var unsyncedFlagURL: URL {
        userDir.appendingPathComponent(unsyncedFlagFileName)
    }
    
    private func saveUnsyncedFlag(_ flag: Bool) {
        do {
            let data = try JSONEncoder().encode(flag)
            try data.write(to: unsyncedFlagURL)
        } catch {
            print("[ItemStore] 保存未同步标记失败: \(error)")
        }
    }
    
    private func loadUnsyncedFlag() {
        guard FileManager.default.fileExists(atPath: unsyncedFlagURL.path) else {
            hasUnsyncedChanges = false
            return
        }
        do {
            let data = try Data(contentsOf: unsyncedFlagURL)
            hasUnsyncedChanges = try JSONDecoder().decode(Bool.self, from: data)
            print("[ItemStore] 未同步标记: \(hasUnsyncedChanges)")
        } catch {
            hasUnsyncedChanges = false
        }
    }
    
    // MARK: - 删除记录管理
    
    private var deletedItemsFileURL: URL {
        userDir.appendingPathComponent(deletedItemsFileName)
    }
    
    /// 记录一条删除
    private func recordDeletion(itemId: String) {
        deletedItemRecords[itemId] = Date()
        saveDeletedItemRecords()
    }
    
    /// 同步完成后清理已同步的删除记录
    func clearDeletedRecords(itemIds: [String]) {
        for id in itemIds {
            deletedItemRecords.removeValue(forKey: id)
        }
        saveDeletedItemRecords()
    }
    
    /// 清空所有删除记录（同步全部完成后调用）
    func clearAllDeletedRecords() {
        deletedItemRecords.removeAll()
        saveDeletedItemRecords()
    }
    
    private func saveDeletedItemRecords() {
        do {
            // 转换为 [String: TimeInterval] 方便 JSON 编码
            let dict = deletedItemRecords.mapValues { $0.timeIntervalSince1970 }
            let data = try JSONEncoder().encode(dict)
            try data.write(to: deletedItemsFileURL, options: .atomic)
        } catch {
            print("[ItemStore] 保存删除记录失败: \(error)")
        }
    }
    
    private func loadDeletedItemRecords() {
        guard FileManager.default.fileExists(atPath: deletedItemsFileURL.path) else {
            deletedItemRecords = [:]
            return
        }
        do {
            let data = try Data(contentsOf: deletedItemsFileURL)
            let dict = try JSONDecoder().decode([String: TimeInterval].self, from: data)
            deletedItemRecords = dict.mapValues { Date(timeIntervalSince1970: $0) }
            print("[ItemStore] 加载删除记录: \(deletedItemRecords.count) 条")
        } catch {
            deletedItemRecords = [:]
        }
    }
}
