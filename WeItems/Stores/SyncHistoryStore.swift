//
//  SyncHistoryStore.swift
//  WeItems
//

import Foundation
import Combine

/// 单次同步记录
struct SyncRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let trigger: SyncTrigger
    let itemsUploaded: Int
    let itemsUpdated: Int
    let itemsDeletedLocal: Int
    let itemsFailed: Int
    let wishesUploaded: Int
    let wishesUpdated: Int
    let wishesDeletedLocal: Int
    let wishesFailed: Int
    let savingInfoSynced: Bool?       // 收入储蓄：是否同步成功（nil 表示旧记录无此字段）
    let success: Bool
    let message: String
    
    /// 触发方式
    enum SyncTrigger: String, Codable {
        case manual = "远端同步"
        case auto   = "自动同步"
        case icloud = "iCloud 同步"
    }
    
    /// 总操作数
    var totalOperations: Int {
        itemsUploaded + itemsUpdated + itemsDeletedLocal +
        wishesUploaded + wishesUpdated + wishesDeletedLocal
    }
    
    /// 总失败数
    var totalFailed: Int {
        itemsFailed + wishesFailed
    }
}

/// 同步历史管理（本地持久化）
class SyncHistoryStore: ObservableObject {
    static let shared = SyncHistoryStore()
    
    @Published private(set) var records: [SyncRecord] = []
    
    private let maxRecords = 100 // 最多保留条数
    
    private init() {
        loadRecords()
    }
    
    // MARK: - 文件路径
    
    private var storageURL: URL {
        UserStorageHelper.shared.currentUserDirectory
            .appendingPathComponent("sync_history.json")
    }
    
    // MARK: - 添加记录
    
    func addRecord(_ record: SyncRecord) {
        records.insert(record, at: 0) // 最新在前
        // 限制最大数量
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        saveRecords()
    }
    
    // MARK: - 持久化
    
    private func loadRecords() {
        let url = storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([SyncRecord].self, from: data)
        } catch {
            print("[同步历史] 加载失败: \(error)")
        }
    }
    
    private func saveRecords() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[同步历史] 保存失败: \(error)")
        }
    }
    
    /// 切换用户时重新加载
    func reloadForCurrentUser() {
        records = []
        loadRecords()
    }
    
    /// 清空历史
    func clearAll() {
        records = []
        try? FileManager.default.removeItem(at: storageURL)
    }
}
