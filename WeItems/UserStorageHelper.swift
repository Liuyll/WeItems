//
//  UserStorageHelper.swift
//  WeItems
//

import Foundation

/// 用户存储隔离管理
/// - 已登录用户：数据存储在 Documents/{手机号}/ 目录下
/// - 未登录用户：数据存储在 Documents/anonymous/ 目录下
/// - 所有用户都能访问 anonymous 目录的数据
class UserStorageHelper {
    static let shared = UserStorageHelper()
    
    private let anonymousDir = "anonymous"
    
    private init() {}
    
    /// 获取当前用户标识（手机号或 "anonymous"）
    var currentUserKey: String {
        if let phone = TokenStorage.shared.getPhoneNumber(), !phone.isEmpty {
            return phone
        }
        return anonymousDir
    }
    
    /// 获取当前用户的存储根目录
    var currentUserDirectory: URL {
        return userDirectory(for: currentUserKey)
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
        if let phone = TokenStorage.shared.getPhoneNumber(), !phone.isEmpty {
            return true
        }
        return false
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
