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
    let trigger: SyncTrigger          // 触发方式
    let itemsUploaded: Int            // 物品：新上传数
    let itemsUpdated: Int             // 物品：更新数
    let itemsDeletedLocal: Int        // 物品：删除本地数
    let itemsFailed: Int              // 物品：失败数
    let wishesUploaded: Int           // 心愿：新上传数
    let wishesUpdated: Int            // 心愿：更新数
    let wishesDeletedLocal: Int       // 心愿：删除本地数
    let wishesFailed: Int             // 心愿：失败数
    let success: Bool                 // 整体是否成功
    let message: String               // 结果描述
    
    /// 触发方式
    enum SyncTrigger: String, Codable {
        case manual = "手动同步"
        case auto   = "自动同步"
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
