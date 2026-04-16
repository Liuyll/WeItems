//
//  ICloudSyncManager.swift
//  WeItems
//
//  iCloud 同步管理器
//  使用 CloudDocuments 将数据同步到 iCloud Drive
//  图片直接存储在 iCloud 中，无需上传到 COS

import Foundation

class ICloudSyncManager {
    static let shared = ICloudSyncManager()
    
    private let containerIdentifier = "iCloud.com.lyl.WeItems"
    private let itemsFileName = "icloud_items.json"
    private let wishesFileName = "icloud_wishes.json"
    private let savingInfoFileName = "icloud_savinginfo.json"
    private let imagesDir = "images"
    
    private init() {}
    
    // MARK: - iCloud 容器
    
    /// 获取 iCloud Documents 目录（按用户 sub 隔离）
    var iCloudDocumentsURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            print("[iCloud] 无法获取 iCloud 容器，请确认 iCloud 已登录且权限已配置")
            return nil
        }
        var documentsURL = containerURL.appendingPathComponent("Documents")
        
        // 按用户 sub 隔离目录
        if let sub = TokenStorage.shared.getSub(), !sub.isEmpty {
            documentsURL = documentsURL.appendingPathComponent(sub)
        }
        
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
        return documentsURL
    }
    
    /// 获取 iCloud 图片存储目录
    private func iCloudImagesURL() -> URL? {
        guard let docs = iCloudDocumentsURL else { return nil }
        let imagesURL = docs.appendingPathComponent(imagesDir)
        if !FileManager.default.fileExists(atPath: imagesURL.path) {
            try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        }
        return imagesURL
    }
    
    /// 检查 iCloud 是否可用
    var isICloudAvailable: Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }
    
    // MARK: - iCloud 数据模型
    
    /// iCloud 存储的物品数据结构（包含图片文件名引用）
    struct ICloudItemRecord: Codable {
        let itemId: String
        let itemInfo: Item
        var imageFileName: String?  // iCloud 中的图片文件名
    }
    
    /// iCloud 存储的储蓄数据
    struct ICloudSavingInfo: Codable {
        var records: [FinanceRecord]
        var salaryRecord: FinanceRecord?
        var savingsGoal: SavingsGoal
        var totalAssets: Double
    }
    
    // MARK: - 同步结果
    
    struct ICloudSyncResult {
        let uploadedCount: Int
        let updatedCount: Int
        let deletedLocalItemIds: [String]
        let remoteOnlyItems: [Item]
        let failedCount: Int
    }
    
    // MARK: - 物品同步（与远端 syncItems 逻辑一致）
    
    /// 同步"我的物品"到 iCloud
    func syncItems(
        items: [Item],
        deletedItemRecords: [String: Date] = [:]
    ) async -> ICloudSyncResult? {
        let myItems = items.filter { $0.listType == .items }
        
        guard let docsURL = iCloudDocumentsURL else {
            print("[iCloud 物品同步] iCloud 不可用")
            return nil
        }
        
        // Step 1: 读取 iCloud 中的物品
        let icloudFileURL = docsURL.appendingPathComponent(itemsFileName)
        let remoteRecords = loadICloudRecords(from: icloudFileURL)
        
        // 构建远端字典
        var remoteMap: [String: ICloudItemRecord] = [:]
        for record in remoteRecords {
            remoteMap[record.itemId] = record
        }
        
        print("[iCloud 物品同步] iCloud 共 \(remoteMap.count) 个物品，本地共 \(myItems.count) 个物品")
        
        // Step 2: Merge
        var itemsToCreate: [Item] = []
        var itemsToUpdate: [Item] = []
        var deletedLocalItemIds: [String] = []
        var remoteOnlyItems: [Item] = []
        var itemsToDeleteRemote: [String] = []
        
        let localItemIdSet = Set(myItems.map { $0.itemId })
        
        for localItem in myItems {
            if let remote = remoteMap[localItem.itemId] {
                let localTimestamp = floor(localItem.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.itemInfo.updatedAt.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                    // 无变化
                } else if remoteTimestamp > localTimestamp {
                    // iCloud 更新，用 iCloud 版本替换本地
                    deletedLocalItemIds.append(localItem.itemId)
                    var remoteItem = remote.itemInfo
                    // 从 iCloud 加载图片
                    if let imgFileName = remote.imageFileName {
                        remoteItem.imageData = loadImageFromICloud(fileName: imgFileName)
                    }
                    remoteOnlyItems.append(remoteItem)
                } else {
                    // 本地更新，写入 iCloud
                    itemsToUpdate.append(localItem)
                }
            } else {
                // 本地独有
                itemsToCreate.append(localItem)
            }
        }
        
        // 遍历 iCloud，找出 iCloud 独有
        for (remoteItemId, remote) in remoteMap {
            guard !localItemIdSet.contains(remoteItemId) else { continue }
            
            // 检查本地是否有删除记录
            if let deletedAt = deletedItemRecords[remoteItemId] {
                let remoteTimestamp = floor(remote.itemInfo.updatedAt.timeIntervalSince1970)
                let deletedTimestamp = floor(deletedAt.timeIntervalSince1970)
                if deletedTimestamp >= remoteTimestamp {
                    itemsToDeleteRemote.append(remoteItemId)
                    continue
                }
            }
            
            var remoteItem = remote.itemInfo
            if let imgFileName = remote.imageFileName {
                remoteItem.imageData = loadImageFromICloud(fileName: imgFileName)
            }
            remoteOnlyItems.append(remoteItem)
        }
        
        print("[iCloud 物品同步] 需创建 \(itemsToCreate.count) 个，需更新 \(itemsToUpdate.count) 个，需删除本地 \(deletedLocalItemIds.count) 个，iCloud 独有 \(remoteOnlyItems.count) 个")
        
        // 删除被移除物品的 iCloud 图片
        for itemId in itemsToDeleteRemote {
            if let record = remoteMap[itemId], let imgFileName = record.imageFileName {
                deleteImageFromICloud(fileName: imgFileName)
            }
        }
        
        // Step 3: 写回 iCloud
        // 构建完整的 iCloud 数据
        var finalRecords: [ICloudItemRecord] = []
        
        // 保留未被删除的远端记录
        for (itemId, record) in remoteMap {
            if !itemsToDeleteRemote.contains(itemId) &&
               !deletedLocalItemIds.contains(itemId) &&
               !itemsToUpdate.contains(where: { $0.itemId == itemId }) {
                finalRecords.append(record)
            }
        }
        
        // 添加更新的物品
        for item in itemsToUpdate {
            let imgFileName = saveImageToICloud(item: item, prefix: "items")
            var cleanItem = item
            cleanItem.imageData = nil  // iCloud JSON 不存图片原始数据
            cleanItem.compressedImageData = nil
            finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: imgFileName))
        }
        
        // 添加新创建的物品
        for item in itemsToCreate {
            let imgFileName = saveImageToICloud(item: item, prefix: "items")
            var cleanItem = item
            cleanItem.imageData = nil
            cleanItem.compressedImageData = nil
            finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: imgFileName))
        }
        
        // 添加 iCloud 独有（已被标记删除本地旧版后替换的远端更新版本也在 remoteOnlyItems 中，
        // 但它们的 itemId 对应的旧记录已从 finalRecords 中排除，需要重新加入）
        for item in remoteOnlyItems {
            // 检查是否已经在 finalRecords 中（避免重复）
            if !finalRecords.contains(where: { $0.itemId == item.itemId }) {
                // 这些物品的图片已经在 iCloud 中，保留原始 imageFileName
                if let existingRecord = remoteMap[item.itemId] {
                    finalRecords.append(existingRecord)
                } else {
                    var cleanItem = item
                    cleanItem.imageData = nil
                    cleanItem.compressedImageData = nil
                    finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: nil))
                }
            }
        }
        
        // 写入 iCloud
        let writeSuccess = saveICloudRecords(finalRecords, to: icloudFileURL)
        
        if writeSuccess {
            print("[iCloud 物品同步] 写入 iCloud 成功，共 \(finalRecords.count) 个物品")
        } else {
            print("[iCloud 物品同步] 写入 iCloud 失败")
        }
        
        return ICloudSyncResult(
            uploadedCount: itemsToCreate.count,
            updatedCount: itemsToUpdate.count,
            deletedLocalItemIds: deletedLocalItemIds,
            remoteOnlyItems: remoteOnlyItems,
            failedCount: writeSuccess ? 0 : 1
        )
    }
    
    // MARK: - 心愿同步（与远端 syncWishes 逻辑一致）
    
    /// 同步心愿清单到 iCloud
    func syncWishes(
        items: [Item],
        deletedItemRecords: [String: Date] = [:]
    ) async -> ICloudSyncResult? {
        let myWishes = items.filter { $0.listType == .wishlist }
        
        guard let docsURL = iCloudDocumentsURL else {
            print("[iCloud 心愿同步] iCloud 不可用")
            return nil
        }
        
        let icloudFileURL = docsURL.appendingPathComponent(wishesFileName)
        let remoteRecords = loadICloudRecords(from: icloudFileURL)
        
        var remoteMap: [String: ICloudItemRecord] = [:]
        for record in remoteRecords {
            remoteMap[record.itemId] = record
        }
        
        print("[iCloud 心愿同步] iCloud 共 \(remoteMap.count) 个心愿，本地共 \(myWishes.count) 个心愿")
        
        var wishesToCreate: [Item] = []
        var wishesToUpdate: [Item] = []
        var deletedLocalItemIds: [String] = []
        var remoteOnlyItems: [Item] = []
        var wishesToDeleteRemote: [String] = []
        
        let localItemIdSet = Set(myWishes.map { $0.itemId })
        
        for localWish in myWishes {
            if let remote = remoteMap[localWish.itemId] {
                let localTimestamp = floor(localWish.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.itemInfo.updatedAt.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                    // 无变化
                } else if remoteTimestamp > localTimestamp {
                    deletedLocalItemIds.append(localWish.itemId)
                    var remoteItem = remote.itemInfo
                    if let imgFileName = remote.imageFileName {
                        remoteItem.imageData = loadImageFromICloud(fileName: imgFileName)
                    }
                    remoteOnlyItems.append(remoteItem)
                } else {
                    wishesToUpdate.append(localWish)
                }
            } else {
                wishesToCreate.append(localWish)
            }
        }
        
        for (remoteItemId, remote) in remoteMap {
            guard !localItemIdSet.contains(remoteItemId) else { continue }
            
            if let deletedAt = deletedItemRecords[remoteItemId] {
                let remoteTimestamp = floor(remote.itemInfo.updatedAt.timeIntervalSince1970)
                let deletedTimestamp = floor(deletedAt.timeIntervalSince1970)
                if deletedTimestamp >= remoteTimestamp {
                    wishesToDeleteRemote.append(remoteItemId)
                    continue
                }
            }
            
            var remoteItem = remote.itemInfo
            if let imgFileName = remote.imageFileName {
                remoteItem.imageData = loadImageFromICloud(fileName: imgFileName)
            }
            remoteOnlyItems.append(remoteItem)
        }
        
        print("[iCloud 心愿同步] 需创建 \(wishesToCreate.count) 个，需更新 \(wishesToUpdate.count) 个，需删除本地 \(deletedLocalItemIds.count) 个，iCloud 独有 \(remoteOnlyItems.count) 个")
        
        // 删除被移除心愿的 iCloud 图片
        for itemId in wishesToDeleteRemote {
            if let record = remoteMap[itemId], let imgFileName = record.imageFileName {
                deleteImageFromICloud(fileName: imgFileName)
            }
        }
        
        // 写回 iCloud
        var finalRecords: [ICloudItemRecord] = []
        
        for (itemId, record) in remoteMap {
            if !wishesToDeleteRemote.contains(itemId) &&
               !deletedLocalItemIds.contains(itemId) &&
               !wishesToUpdate.contains(where: { $0.itemId == itemId }) {
                finalRecords.append(record)
            }
        }
        
        for item in wishesToUpdate {
            let imgFileName = saveImageToICloud(item: item, prefix: "wishes")
            var cleanItem = item
            cleanItem.imageData = nil
            cleanItem.compressedImageData = nil
            finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: imgFileName))
        }
        
        for item in wishesToCreate {
            let imgFileName = saveImageToICloud(item: item, prefix: "wishes")
            var cleanItem = item
            cleanItem.imageData = nil
            cleanItem.compressedImageData = nil
            finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: imgFileName))
        }
        
        for item in remoteOnlyItems {
            if !finalRecords.contains(where: { $0.itemId == item.itemId }) {
                if let existingRecord = remoteMap[item.itemId] {
                    finalRecords.append(existingRecord)
                } else {
                    var cleanItem = item
                    cleanItem.imageData = nil
                    cleanItem.compressedImageData = nil
                    finalRecords.append(ICloudItemRecord(itemId: item.itemId, itemInfo: cleanItem, imageFileName: nil))
                }
            }
        }
        
        let writeSuccess = saveICloudRecords(finalRecords, to: icloudFileURL)
        
        if writeSuccess {
            print("[iCloud 心愿同步] 写入 iCloud 成功，共 \(finalRecords.count) 个心愿")
        } else {
            print("[iCloud 心愿同步] 写入 iCloud 失败")
        }
        
        return ICloudSyncResult(
            uploadedCount: wishesToCreate.count,
            updatedCount: wishesToUpdate.count,
            deletedLocalItemIds: deletedLocalItemIds,
            remoteOnlyItems: remoteOnlyItems,
            failedCount: writeSuccess ? 0 : 1
        )
    }
    
    // MARK: - 储蓄投资同步
    
    /// 同步储蓄投资数据到 iCloud
    func syncSavingInfo(
        records: [FinanceRecord],
        salaryRecord: FinanceRecord?,
        goal: SavingsGoal,
        totalAssets: Double
    ) async -> Bool {
        guard let docsURL = iCloudDocumentsURL else {
            print("[iCloud 储蓄同步] iCloud 不可用")
            return false
        }
        
        let savingInfo = ICloudSavingInfo(
            records: records,
            salaryRecord: salaryRecord,
            savingsGoal: goal,
            totalAssets: totalAssets
        )
        
        let fileURL = docsURL.appendingPathComponent(savingInfoFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savingInfo)
            try data.write(to: fileURL, options: .atomic)
            print("[iCloud 储蓄同步] 写入成功")
            return true
        } catch {
            print("[iCloud 储蓄同步] 写入失败: \(error)")
            return false
        }
    }
    
    // MARK: - 图片存储（直接存 iCloud，不走 COS）
    
    /// 将物品图片保存到 iCloud
    /// - Returns: iCloud 中的图片文件名，nil 表示无图片
    private func saveImageToICloud(item: Item, prefix: String) -> String? {
        // 优先压缩版，回退原图
        guard let imageData = item.compressedImageData ?? item.imageData else { return nil }
        guard let imagesURL = iCloudImagesURL() else { return nil }
        
        let fileName = "\(prefix)_\(item.id.uuidString).jpg"
        let fileURL = imagesURL.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            print("[iCloud 图片] 保存失败: \(item.name), \(error)")
            return nil
        }
    }
    
    /// 从 iCloud 加载图片
    private func loadImageFromICloud(fileName: String) -> Data? {
        guard let imagesURL = iCloudImagesURL() else { return nil }
        let fileURL = imagesURL.appendingPathComponent(fileName)
        
        // 触发 iCloud 下载（如果文件还在云端未下载到本地）
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        } catch {
            print("[iCloud 图片] 触发下载失败: \(fileName), \(error)")
        }
        
        // 尝试读取
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            return data
        }
        
        print("[iCloud 图片] 文件暂不可用（可能仍在下载中）: \(fileName)")
        return nil
    }
    
    /// 从 iCloud 删除图片
    private func deleteImageFromICloud(fileName: String) {
        guard let imagesURL = iCloudImagesURL() else { return }
        let fileURL = imagesURL.appendingPathComponent(fileName)
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("[iCloud 图片] 已删除: \(fileName)")
        } catch {
            print("[iCloud 图片] 删除失败: \(fileName), \(error)")
        }
    }
    
    // MARK: - JSON 读写
    
    private func loadICloudRecords(from fileURL: URL) -> [ICloudItemRecord] {
        // 触发 iCloud 下载
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        } catch {
            // 文件不存在时会抛错，忽略
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ICloudItemRecord].self, from: data)
        } catch {
            print("[iCloud] 读取记录失败: \(error)")
            return []
        }
    }
    
    private func saveICloudRecords(_ records: [ICloudItemRecord], to fileURL: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            print("[iCloud] 写入记录失败: \(error)")
            return false
        }
    }
    
    // MARK: - iCloud 数据概览
    
    /// iCloud 数据概览
    struct ICloudDataOverview {
        let itemsCount: Int
        let wishesCount: Int
        let savingRecordsCount: Int
        let hasSalaryRecord: Bool
        let totalAssets: Double
        let savingsGoalName: String
        let savingsGoalAmount: Double
        let imageCount: Int
        let imagesTotalSize: Int64  // bytes
    }
    
    /// 查询 iCloud 中存储的数据概览
    func fetchDataOverview() -> ICloudDataOverview? {
        guard let docsURL = iCloudDocumentsURL else { return nil }
        
        // 物品
        let itemsFileURL = docsURL.appendingPathComponent(itemsFileName)
        let itemRecords = loadICloudRecords(from: itemsFileURL)
        
        // 心愿
        let wishesFileURL = docsURL.appendingPathComponent(wishesFileName)
        let wishRecords = loadICloudRecords(from: wishesFileURL)
        
        // 储蓄
        let savingFileURL = docsURL.appendingPathComponent(savingInfoFileName)
        var savingRecordsCount = 0
        var hasSalary = false
        var totalAssets: Double = 0
        var goalName = ""
        var goalAmount: Double = 0
        
        if FileManager.default.fileExists(atPath: savingFileURL.path),
           let data = try? Data(contentsOf: savingFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let info = try? decoder.decode(ICloudSavingInfo.self, from: data) {
                savingRecordsCount = info.records.count
                hasSalary = info.salaryRecord != nil
                totalAssets = info.totalAssets
                goalName = info.savingsGoal.name
                goalAmount = info.savingsGoal.targetAmount
            }
        }
        
        // 图片
        var imageCount = 0
        var imagesTotalSize: Int64 = 0
        if let imagesURL = iCloudImagesURL(),
           let files = try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path) {
            for file in files where file.hasSuffix(".jpg") {
                imageCount += 1
                let filePath = imagesURL.appendingPathComponent(file).path
                if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? Int64 {
                    imagesTotalSize += size
                }
            }
        }
        
        return ICloudDataOverview(
            itemsCount: itemRecords.count,
            wishesCount: wishRecords.count,
            savingRecordsCount: savingRecordsCount,
            hasSalaryRecord: hasSalary,
            totalAssets: totalAssets,
            savingsGoalName: goalName,
            savingsGoalAmount: goalAmount,
            imageCount: imageCount,
            imagesTotalSize: imagesTotalSize
        )
    }
}
