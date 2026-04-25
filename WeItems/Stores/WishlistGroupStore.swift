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
    
    private var userDir: URL {
        UserStorageHelper.shared.currentUserDirectory
    }
    
    private var fileURL: URL {
        userDir.appendingPathComponent(fileName)
    }
    
    init() {
        loadGroups()
    }
    
    /// 切换用户后重新加载数据
    func reloadForCurrentUser() {
        groups = []
        loadGroups()
        // 登录时合并了 anonymous 数据，保存到用户目录
        if UserStorageHelper.shared.isLoggedIn && !groups.isEmpty {
            saveGroups()
        }
        print("[WishlistGroupStore] 已切换到用户: \(UserStorageHelper.shared.currentUserKey), 共 \(groups.count) 个分组")
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
            var updated = group
            updated.updatedAt = Date()
            groups[index] = updated
            saveGroups()
        }
    }
    
    func group(for id: UUID?) -> ItemGroup? {
        guard let id = id else { return nil }
        return groups.first(where: { $0.id == id })
    }
    
    /// 合并远端分组到本地（与远端 merge 逻辑一致：取 updatedAt 更新的版本）
    func applyRemoteGroups(_ remoteGroups: [ItemGroup]) {
        var changed = false
        for remoteGroup in remoteGroups {
            if let index = groups.firstIndex(where: { $0.id == remoteGroup.id }) {
                // 已存在：取 updatedAt 更新的版本
                let localTimestamp = floor(groups[index].updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remoteGroup.updatedAt.timeIntervalSince1970)
                if remoteTimestamp > localTimestamp {
                    groups[index] = remoteGroup
                    changed = true
                }
            } else {
                // 不存在：添加
                groups.append(remoteGroup)
                changed = true
            }
        }
        if changed {
            saveGroups()
            print("[WishlistGroupStore] 合并远端分组: 更新/新增完成，共 \(groups.count) 个")
        }
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
        var allGroups: [ItemGroup] = []
        
        allGroups.append(contentsOf: loadGroupsFromFile(fileURL))
        
        // 已登录用户额外加载 anonymous 目录
        if UserStorageHelper.shared.isLoggedIn {
            let anonymousFile = UserStorageHelper.shared.anonymousDirectory
                .appendingPathComponent(fileName)
            let anonymousGroups = loadGroupsFromFile(anonymousFile)
            let existingIds = Set(allGroups.map { $0.id })
            for group in anonymousGroups where !existingIds.contains(group.id) {
                allGroups.append(group)
            }
        }
        
        groups = allGroups
        print("心愿清单分组加载成功，共 \(groups.count) 个分组 (用户: \(UserStorageHelper.shared.currentUserKey))")
    }
    
    private func loadGroupsFromFile(_ url: URL) -> [ItemGroup] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ItemGroup].self, from: data)
        } catch {
            print("加载心愿清单分组失败(\(url.lastPathComponent)): \(error)")
            return []
        }
    }
}
