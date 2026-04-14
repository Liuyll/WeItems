//
//  UserStorageHelper.swift
//  WeItems
//

import Foundation

/// 用户存储隔离管理
/// - 已登录用户：数据存储在 Documents/{sub}/ 目录下（按用户ID隔离）
/// - 未登录用户：数据存储在 Documents/anonymous/ 目录下
/// - 所有用户都能访问 anonymous 目录的数据
class UserStorageHelper {
    static let shared = UserStorageHelper()
    
    private let anonymousDir = "anonymous"
    
    private init() {}
    
    /// 获取当前用户标识（优先用 sub，兼容旧的 phoneNumber）
    var currentUserKey: String {
        if let sub = TokenStorage.shared.getSub(), !sub.isEmpty {
            return sub
        }
        if let phone = TokenStorage.shared.getPhoneNumber(), !phone.isEmpty {
            return phone
        }
        return anonymousDir
    }
    
    /// 获取当前用户的存储根目录
    var currentUserDirectory: URL {
        let dir = userDirectory(for: currentUserKey)
        // 首次用 sub 目录时，尝试从旧的 phoneNumber 目录迁移数据
        migrateFromPhoneDirectoryIfNeeded(to: dir)
        return dir
    }
    
    /// 获取 anonymous 目录
    var anonymousDirectory: URL {
        return userDirectory(for: anonymousDir)
    }
    
    /// 获取指定用户的存储目录
    func userDirectory(for userKey: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent(userKey)
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        return dir
    }
    
    /// 当前用户是否已登录
    var isLoggedIn: Bool {
        if let sub = TokenStorage.shared.getSub(), !sub.isEmpty {
            return true
        }
        if let phone = TokenStorage.shared.getPhoneNumber(), !phone.isEmpty {
            return true
        }
        return false
    }
    
    // MARK: - 从旧的 phoneNumber 目录迁移到 sub 目录
    
    /// 如果 sub 目录为空但旧的 phoneNumber 目录有数据，则迁移过来
    private func migrateFromPhoneDirectoryIfNeeded(to subDir: URL) {
        guard let sub = TokenStorage.shared.getSub(), !sub.isEmpty,
              let phone = TokenStorage.shared.getPhoneNumber(), !phone.isEmpty,
              phone != sub else { return }
        
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let phoneDir = documents.appendingPathComponent(phone)
        
        // 旧目录不存在则不需要迁移
        guard FileManager.default.fileExists(atPath: phoneDir.path) else { return }
        
        // sub 目录已有 items.json 说明已迁移过
        let subItemsFile = subDir.appendingPathComponent("items.json")
        guard !FileManager.default.fileExists(atPath: subItemsFile.path) else { return }
        
        // 迁移旧目录的所有文件到 sub 目录
        if let files = try? FileManager.default.contentsOfDirectory(atPath: phoneDir.path) {
            for file in files {
                let source = phoneDir.appendingPathComponent(file)
                let dest = subDir.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: source, to: dest)
                    print("[迁移] \(phone)/\(file) -> \(sub)/\(file)")
                }
            }
            print("[迁移] 已从旧目录(\(phone))迁移数据到 sub 目录(\(sub))")
        }
    }
    
    /// 清空 anonymous 目录的数据（登录成功且数据已合并到用户目录后调用）
    func clearAnonymousData() {
        let anonDir = anonymousDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: anonDir.path) else { return }
        
        var cleared = 0
        for file in files {
            let filePath = anonDir.appendingPathComponent(file)
            do {
                try FileManager.default.removeItem(at: filePath)
                cleared += 1
            } catch {
                print("[UserStorage] 清理 anonymous/\(file) 失败: \(error)")
            }
        }
        if cleared > 0 {
            print("[UserStorage] 已清空 anonymous 目录 \(cleared) 个文件")
        }
    }
    
    /// 将旧的根目录数据迁移到 anonymous 目录（仅首次执行）
    func migrateRootDataIfNeeded() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let migrationFlag = documents.appendingPathComponent(".migration_done")
        
        // 如果已迁移过，跳过
        guard !FileManager.default.fileExists(atPath: migrationFlag.path) else { return }
        
        let filesToMigrate = [
            "items.json",
            "groups.json",
            "wishlist_groups.json",
            "custom_display_types.json"
        ]
        
        let anonymousDir = self.anonymousDirectory
        var migrated = false
        
        for fileName in filesToMigrate {
            let source = documents.appendingPathComponent(fileName)
            let destination = anonymousDir.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: source.path) &&
               !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    print("[迁移] \(fileName) -> anonymous/\(fileName)")
                    migrated = true
                } catch {
                    print("[迁移] 迁移 \(fileName) 失败: \(error)")
                }
            }
        }
        
        // 迁移图片文件 (item_*.jpg)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: documents.path) {
            for file in files where file.hasPrefix("item_") && file.hasSuffix(".jpg") {
                let source = documents.appendingPathComponent(file)
                let destination = anonymousDir.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    do {
                        try FileManager.default.copyItem(at: source, to: destination)
                        print("[迁移] \(file) -> anonymous/\(file)")
                        migrated = true
                    } catch {
                        print("[迁移] 迁移 \(file) 失败: \(error)")
                    }
                }
            }
        }
        
        if migrated {
            print("[迁移] 旧数据迁移到 anonymous 目录完成")
        }
        
        // 标记已完成迁移
        FileManager.default.createFile(atPath: migrationFlag.path, contents: nil)
    }
}
