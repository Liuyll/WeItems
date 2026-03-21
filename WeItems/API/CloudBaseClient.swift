//
//  CloudBaseClient.swift
//  WeItems
//

import Foundation

// MARK: - Token 验证响应模型
struct TokenInfo: Codable {
    let tokenType: String?
    let clientId: String?
    let sub: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case clientId = "client_id"
        case sub
        case scope
    }
    
    /// 判断 token 是否有效
    var isValid: Bool {
        return sub != nil && !sub!.isEmpty
    }
}

// MARK: - Refresh Token 响应模型
struct RefreshTokenResponse: Codable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let sub: String
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case sub
        case scope
    }
}

class CloudBaseClient {
    let envId: String
    private(set) var accessToken: String
    let baseUrl: String
    
    /// 设备 ID，用于身份认证相关请求
    var deviceId: String?

    init(envId: String, accessToken: String, deviceId: String? = nil) {
        self.envId = envId
        self.accessToken = accessToken
        self.baseUrl = "https://\(envId).api.tcloudbasegateway.com"
        self.deviceId = deviceId
    }

    /// 更新访问令牌
    ///
    /// - Parameter newToken: 新的访问令牌
    func updateAccessToken(_ newToken: String) {
        self.accessToken = newToken
        print("访问令牌已更新")
    }

    /// 统一的HTTP请求方法
    ///
    /// - Parameters:
    ///   - method: 请求方法 (GET, POST, PUT, PATCH, DELETE)
    ///   - path: API路径 (如 /v1/rdb/rest/table_name)
    ///   - body: 请求体数据
    ///   - customHeaders: 自定义headers
    /// - Returns: 响应数据或nil
    func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        customHeaders: [String: String] = [:],
        completion: @escaping (T?) -> Void
    ) {
        guard let url = URL(string: "\(baseUrl)\(path)") else {
            print("[HTTP] 无效的URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // 添加自定义headers
        customHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 设置请求体
        var bodyString: String = ""
        if let body = body {
            do {
                let bodyData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
                request.httpBody = bodyData
                bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            } catch {
                print("[HTTP] JSON序列化失败: \(error)")
                completion(nil)
                return
            }
        }

        // 打印完整请求
        print("\n========== HTTP REQUEST ==========")
        print("[HTTP] 方法: \(method.uppercased())")
        print("[HTTP] URL: \(url.absoluteString)")
        print("[HTTP] Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            let maskedValue = key.lowercased() == "authorization" ? "Bearer ***" : value
            print("  \(key): \(maskedValue)")
        }
        print("[HTTP] Body:\n\(bodyString)")
        print("==================================\n")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("\n========== HTTP RESPONSE ==========")
                print("[HTTP] 请求失败: \(error.localizedDescription)")
                print("===================================\n")
                completion(nil)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            // 非 200 才打印响应详情
            if statusCode < 200 || statusCode > 299 {
                print("\n========== HTTP RESPONSE ==========")
                print("[HTTP] 状态码: \(statusCode)")
                if let httpResponse = response as? HTTPURLResponse {
                    print("[HTTP] Headers:")
                    httpResponse.allHeaderFields.forEach { key, value in
                        print("  \(key): \(value)")
                    }
                }
                if let data = data {
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("[HTTP] Body:\n\(jsonString)")
                    } else {
                        print("[HTTP] Body: <二进制数据 \(data.count) bytes>")
                    }
                } else {
                    print("[HTTP] Body: <无数据>")
                }
                print("[HTTP] 错误: 状态码无效 \(statusCode)")
                print("===================================\n")
                completion(nil)
                return
            }

            guard let data = data else {
                // 如果响应为空，返回true表示成功
                if T.self == Bool.self {
                    completion(true as? T)
                } else {
                    completion(nil)
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(T.self, from: data)
                completion(result)
            } catch {
                // 尝试作为Any解码
                if let json = try? JSONSerialization.jsonObject(with: data) as? T {
                    completion(json)
                } else {
                    print("[HTTP] JSON解析失败: \(error)")
                    completion(nil)
                }
            }
        }

        task.resume()
    }

    /// 同步版本（使用 async/await）
    @available(iOS 13.0, *)
    func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        customHeaders: [String: String] = [:]
    ) async -> T? {
        await withCheckedContinuation { continuation in
            request(method: method, path: path, body: body, customHeaders: customHeaders) { (result: T?) in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Token 验证
    
    /// 验证当前 access_token 是否有效
    ///
    /// - Parameters:
    ///   - clientId: 应用对应的客户端 ID（可选，默认为环境 ID）
    ///   - customDeviceId: 设备 ID（可选，默认使用 CloudBaseClient.deviceId）
    ///   - completion: 验证结果回调，返回 TokenInfo（token 无效时返回空对象，isValid 为 false）
    func introspectToken(
        clientId: String? = nil,
        customDeviceId: String? = nil,
        completion: @escaping (TokenInfo?) -> Void
    ) {
        var queryItems: [String] = []
        if let clientId = clientId {
            queryItems.append("client_id=\(clientId)")
        }
        
        var path = "/auth/v1/token/introspect"
        if !queryItems.isEmpty {
            path += "?\(queryItems.joined(separator: "&"))"
        }
        
        var headers: [String: String] = [:]
        let deviceIdToUse = customDeviceId ?? deviceId
        if let deviceIdToUse = deviceIdToUse {
            headers["x-device-id"] = deviceIdToUse
        }
        
        request(method: "GET", path: path, body: nil, customHeaders: headers) { (result: TokenInfo?) in
            completion(result)
        }
    }
    
    /// 验证当前 access_token 是否有效（async/await 版本）
    ///
    /// - Parameters:
    ///   - clientId: 应用对应的客户端 ID（可选，默认为环境 ID）
    ///   - customDeviceId: 设备 ID（可选，默认使用 CloudBaseClient.deviceId）
    /// - Returns: TokenInfo（token 无效时返回空对象，isValid 为 false）
    @available(iOS 13.0, *)
    func introspectToken(
        clientId: String? = nil,
        customDeviceId: String? = nil
    ) async -> TokenInfo? {
        await withCheckedContinuation { continuation in
            introspectToken(clientId: clientId, customDeviceId: customDeviceId) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 快速检查 token 是否有效
    ///
    /// - Parameter completion: 返回 token 是否有效
    func isTokenValid(completion: @escaping (Bool) -> Void) {
        introspectToken { tokenInfo in
            completion(tokenInfo?.isValid ?? false)
        }
    }
    
    /// 快速检查 token 是否有效（async/await 版本）
    ///
    /// - Returns: token 是否有效
    @available(iOS 13.0, *)
    func isTokenValid() async -> Bool {
        let tokenInfo = await introspectToken()
        return tokenInfo?.isValid ?? false
    }
    
    // MARK: - Token 刷新
    
    /// 使用 refresh_token 刷新 access_token
    ///
    /// 注意：刷新成功后，原 refresh_token 会失效，新的 refresh_token 将替换它
    ///
    /// - Parameters:
    ///   - refreshToken: 刷新令牌（必填，用于获取新的 access_token）
    ///   - clientId: 应用对应的客户端 ID（可选，默认为环境 ID）
    ///   - customDeviceId: 设备 ID（可选，默认使用 CloudBaseClient.deviceId）
    ///   - completion: 刷新结果回调，返回 RefreshTokenResponse（成功）或 nil（失败）
    func refreshAccessToken(
        refreshToken: String,
        clientId: String? = nil,
        customDeviceId: String? = nil,
        completion: @escaping (RefreshTokenResponse?) -> Void
    ) {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId ?? envId
        ]
        
        var headers: [String: String] = [:]
        let deviceIdToUse = customDeviceId ?? deviceId
        if let deviceIdToUse = deviceIdToUse {
            headers["x-device-id"] = deviceIdToUse
        }
        
        request(method: "POST", path: "/auth/v1/token", body: body, customHeaders: headers) { (result: RefreshTokenResponse?) in
            if let response = result {
                // 更新本地存储的 access_token
                self.updateAccessToken(response.accessToken)
                print("Token 刷新成功，新的 access_token 有效期: \(response.expiresIn) 秒")
            } else {
                print("Token 刷新失败")
            }
            completion(result)
        }
    }
    
    /// 使用 refresh_token 刷新 access_token（async/await 版本）
    ///
    /// 注意：刷新成功后，原 refresh_token 会失效，新的 refresh_token 将替换它
    ///
    /// - Parameters:
    ///   - refreshToken: 刷新令牌（必填，用于获取新的 access_token）
    ///   - clientId: 应用对应的客户端 ID（可选，默认为环境 ID）
    ///   - customDeviceId: 设备 ID（可选，默认使用 CloudBaseClient.deviceId）
    /// - Returns: RefreshTokenResponse（成功）或 nil（失败）
    @available(iOS 13.0, *)
    func refreshAccessToken(
        refreshToken: String,
        clientId: String? = nil,
        customDeviceId: String? = nil
    ) async -> RefreshTokenResponse? {
        await withCheckedContinuation { continuation in
            refreshAccessToken(refreshToken: refreshToken, clientId: clientId, customDeviceId: customDeviceId) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 检查 token 是否即将过期，如果即将过期则自动刷新
    ///
    /// - Parameters:
    ///   - refreshToken: 刷新令牌
    ///   - expiresIn: 当前 access_token 的剩余有效时间（秒）
    ///   - threshold: 提前刷新的阈值（秒，默认为 300 秒即 5 分钟）
    ///   - completion: 刷新结果回调
    func autoRefreshTokenIfNeeded(
        refreshToken: String,
        expiresIn: Int,
        threshold: Int = 300,
        clientId: String? = nil,
        completion: @escaping (RefreshTokenResponse?) -> Void
    ) {
        if expiresIn < threshold {
            print("Token 即将过期（剩余 \(expiresIn) 秒），开始自动刷新...")
            refreshAccessToken(refreshToken: refreshToken, clientId: clientId, completion: completion)
        } else {
            print("Token 仍然有效（剩余 \(expiresIn) 秒），无需刷新")
            completion(nil)
        }
    }
    
    /// 检查 token 是否即将过期，如果即将过期则自动刷新（async/await 版本）
    ///
    /// - Parameters:
    ///   - refreshToken: 刷新令牌
    ///   - expiresIn: 当前 access_token 的剩余有效时间（秒）
    ///   - threshold: 提前刷新的阈值（秒，默认为 300 秒即 5 分钟）
    /// - Returns: RefreshTokenResponse（如果需要刷新且成功）或 nil
    @available(iOS 13.0, *)
    func autoRefreshTokenIfNeeded(
        refreshToken: String,
        expiresIn: Int,
        threshold: Int = 300,
        clientId: String? = nil
    ) async -> RefreshTokenResponse? {
        await withCheckedContinuation { continuation in
            autoRefreshTokenIfNeeded(refreshToken: refreshToken, expiresIn: expiresIn, threshold: threshold, clientId: clientId) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - 数据同步
    
    /// 创建响应结构体
    struct CreateResponse: Codable {
        let code: String?
        let message: String?
        let data: CreateData?
        
        struct CreateData: Codable {
            let id: String?
        }
    }
    
    /// 同步结果
    struct SyncResult {
        let uploadedCount: Int           // 新创建到远端的数量
        let updatedCount: Int            // 更新远端的数量
        let deletedLocalNames: [String]  // 远端更新、需删除本地的物品名
        let failedIds: [String]
    }
    
    /// 将单个 Item 转为 createMany 所需的字典格式
    /// 格式: {"item_id": "{sub}_{物品名}", "item_info": {物品信息json}}
    private func itemToDict(_ item: Item, sub: String) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var itemInfo: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "details": item.details,
            "purchaseLink": item.purchaseLink,
            "price": item.price,
            "type": item.type,
            "listType": item.listType.rawValue,
            "isSelected": item.isSelected,
            "isArchived": item.isArchived,
            "createdAt": isoFormatter.string(from: item.createdAt),
            "updatedAt": isoFormatter.string(from: item.updatedAt)
        ]
        if let groupId = item.groupId {
            itemInfo["groupId"] = groupId.uuidString
        }
        if let displayType = item.displayType {
            itemInfo["displayType"] = displayType
        }
        if let targetType = item.targetType {
            itemInfo["targetType"] = targetType
        }
        if let wishlistGroupId = item.wishlistGroupId {
            itemInfo["wishlistGroupId"] = wishlistGroupId.uuidString
        }
        
        return [
            "item_id": "\(sub)_\(item.name)",
            "item_info": itemInfo
        ]
    }
    
    /// 估算字典序列化后的 JSON 大小（字节）
    private func estimateJSONSize(_ dict: [String: Any]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return 0 }
        return data.count
    }
    
    /// 将物品数组按 50KB 为上限分组
    private func splitItemsIntoChunks(_ items: [Item], maxChunkSize: Int = 50 * 1024) -> [[Item]] {
        var chunks: [[Item]] = []
        var currentChunk: [Item] = []
        var currentSize: Int = 0
        
        for item in items {
            let dict = itemToDict(item, sub: "")
            let size = estimateJSONSize(dict)
            
            // 如果当前分组加上这个 item 会超过限制，且当前分组不为空，则先切分
            if currentSize + size > maxChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentSize = 0
            }
            
            currentChunk.append(item)
            currentSize += size
        }
        
        // 追加最后一组
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
    
    /// createMany 响应结构体
    struct CreateManyResponse: Codable {
        let code: String?
        let message: String?
        let data: CreateManyData?
        
        struct CreateManyData: Codable {
            let idList: [String]?
        }
    }
    
    /// updateMany 响应结构体
    struct UpdateManyResponse: Codable {
        let code: String?
        let message: String?
        let data: UpdateManyData?
        
        struct UpdateManyData: Codable {
            let count: Int?
        }
    }
    
    /// 同步"我的物品"到云端（先拉取远端 merge，再上传/更新）
    ///
    /// 同步逻辑：
    /// 1. 从远端拉取所有物品
    /// 2. 按物品名 merge：同名物品比较 updatedAt
    ///    - updatedAt 相同 → 无需操作
    ///    - 远端 updatedAt 更新 → 标记删除本地
    ///    - 本地 updatedAt 更新 → 调用 updateMany 更新远端
    /// 3. 本地独有的物品 → createMany 上传
    ///
    /// - Parameters:
    ///   - items: 本地所有物品数组（只同步 listType == .items 的物品）
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "weitems"
    /// - Returns: 同步结果或 nil
    @available(iOS 13.0, *)
    func syncItems(
        items: [Item],
        envType: String = "prod",
        modelName: String = "weitems"
    ) async -> SyncResult? {
        // 筛选出"我的物品"（listType == .items）
        let myItems = items.filter { $0.listType == .items }
        
        // 获取 owner（当前账户 sub）
        guard let sub = TokenStorage.shared.getSub(), !sub.isEmpty else {
            print("[同步] 无法获取用户 sub，取消同步")
            return nil
        }
        
        // Step 1: 拉取远端数据
        print("[同步] 正在拉取远端数据...")
        let response = await fetchItems(envType: envType, modelName: modelName)
        let remoteRecords = response?.data?.records ?? []
        
        // 构建远端物品字典：name -> (updatedAt, record)
        let isoFormatter = ISO8601DateFormatter()
        var remoteMap: [String: (date: Date, record: FetchItemsResponse.RemoteRecord)] = [:]
        for record in remoteRecords {
            if let info = record.item_info, let name = info.name {
                let date: Date
                if let updatedAtStr = info.updatedAt, let parsed = isoFormatter.date(from: updatedAtStr) {
                    date = parsed
                } else if let createdAtStr = info.createdAt, let parsed = isoFormatter.date(from: createdAtStr) {
                    // 兼容旧数据：远端没有 updatedAt 时用 createdAt
                    date = parsed
                } else {
                    date = Date.distantPast
                }
                remoteMap[name] = (date: date, record: record)
            }
        }
        
        print("[同步] 远端共 \(remoteMap.count) 个物品，本地共 \(myItems.count) 个物品")
        
        // Step 2: Merge 逻辑
        var itemsToCreate: [Item] = []        // 本地独有，需创建到远端
        var itemsToUpdate: [Item] = []        // 本地更新，需更新远端
        var deletedLocalNames: [String] = []  // 远端更新、需删除本地的物品名
        
        for localItem in myItems {
            if let remote = remoteMap[localItem.name] {
                // 同名物品：比较 updatedAt
                // 精度对齐到秒级（ISO8601 只到秒）
                let localTimestamp = floor(localItem.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                    // updatedAt 相同，无需操作
                    print("[同步] 无变化: \(localItem.name)")
                } else if remoteTimestamp > localTimestamp {
                    // 远端更新，标记删除本地
                    print("[同步] 远端更新: \(localItem.name) (远端: \(remote.date), 本地: \(localItem.updatedAt))")
                    deletedLocalNames.append(localItem.name)
                } else {
                    // 本地更新，调用 updateMany 更新远端
                    print("[同步] 本地更新: \(localItem.name) (本地: \(localItem.updatedAt), 远端: \(remote.date))")
                    itemsToUpdate.append(localItem)
                }
            } else {
                // 本地独有，创建到远端
                print("[同步] 本地独有: \(localItem.name)")
                itemsToCreate.append(localItem)
            }
        }
        
        print("[同步] 需创建 \(itemsToCreate.count) 个，需更新 \(itemsToUpdate.count) 个，需删除本地 \(deletedLocalNames.count) 个")
        
        var uploadedCount = 0
        var updatedCount = 0
        var failedIds: [String] = []
        
        // Step 3: 创建本地独有的物品 (createMany)
        if !itemsToCreate.isEmpty {
            let chunks = splitItemsIntoChunks(itemsToCreate)
            print("[同步] 开始创建 \(itemsToCreate.count) 个物品，分为 \(chunks.count) 组...")
            
            for (index, chunk) in chunks.enumerated() {
                let itemDicts = chunk.map { itemToDict($0, sub: sub) }
                let path = "/v1/model/\(envType)/\(modelName)/createMany"
                let payload: [String: Any] = ["data": itemDicts]
                
                print("[同步] 正在创建第 \(index) 组 (\(chunk.count) 个物品)")
                
                let result: CreateManyResponse? = await request(
                    method: "POST",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    print("[同步] 第 \(index) 组响应: code=\(result.code ?? "nil"), message=\(result.message ?? "nil")")
                    let createdCount = result.data?.idList?.count ?? 0
                    if result.code == "SUCCESS" || createdCount > 0 {
                        print("[同步] 第 \(index) 组创建成功 (\(createdCount) 个物品)")
                        uploadedCount += createdCount > 0 ? createdCount : chunk.count
                    } else {
                        print("[同步] 第 \(index) 组创建失败")
                        failedIds.append("create_chunk_\(index)")
                    }
                } else {
                    print("[同步] 第 \(index) 组创建失败, 无响应")
                    failedIds.append("create_chunk_\(index)")
                }
            }
        }
        
        // Step 4: 更新远端同名物品 (updateMany，逐个按 item_id 过滤)
        if !itemsToUpdate.isEmpty {
            print("[同步] 开始更新 \(itemsToUpdate.count) 个远端物品...")
            
            for item in itemsToUpdate {
                let itemId = "\(sub)_\(item.name)"
                let dict = itemToDict(item, sub: sub)
                // 只更新 item_info 部分
                let itemInfoDict = dict["item_info"] as? [String: Any] ?? [:]
                
                let path = "/v1/model/\(envType)/\(modelName)/updateMany"
                let payload: [String: Any] = [
                    "filter": [
                        "where": [
                            "item_id": [
                                "$eq": itemId
                            ]
                        ]
                    ],
                    "data": [
                        "item_info": itemInfoDict
                    ]
                ]
                
                print("[同步] 正在更新远端物品: \(item.name)")
                
                let result: UpdateManyResponse? = await request(
                    method: "PUT",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    print("[同步] 更新响应: code=\(result.code ?? "nil"), count=\(result.data?.count ?? 0)")
                    if result.code == "SUCCESS" || (result.data?.count ?? 0) > 0 {
                        updatedCount += 1
                    } else {
                        print("[同步] 更新失败: \(item.name)")
                        failedIds.append("update_\(item.name)")
                    }
                } else {
                    print("[同步] 更新失败, 无响应: \(item.name)")
                    failedIds.append("update_\(item.name)")
                }
            }
        }
        
        print("[同步] 同步完成: 创建 \(uploadedCount) 个, 更新 \(updatedCount) 个, 删除本地 \(deletedLocalNames.count) 个, 失败 \(failedIds.count) 个")
        return SyncResult(uploadedCount: uploadedCount, updatedCount: updatedCount, deletedLocalNames: deletedLocalNames, failedIds: failedIds)
    }
    
    // MARK: - 远端数据获取
    
    /// 获取远端物品列表的响应模型
    struct FetchItemsResponse: Codable {
        let code: String?
        let message: String?
        let data: FetchItemsData?
        
        struct FetchItemsData: Codable {
            let records: [RemoteRecord]?
            let total: Int?
        }
        
        /// 每条 record 对应一个物品，包含 item_id 和 item_info
        struct RemoteRecord: Codable {
            let _id: String?
            let item_id: String?
            let item_info: RemoteItemInfo?
        }
        
        struct RemoteItemInfo: Codable {
            let id: String?
            let name: String?
            let details: String?
            let purchaseLink: String?
            let price: Double?
            let type: String?
            let listType: String?
            let isSelected: Bool?
            let isArchived: Bool?
            let groupId: String?
            let displayType: String?
            let targetType: String?
            let wishlistGroupId: String?
            let createdAt: String?
            let updatedAt: String?
        }
    }
    
    /// 从远端获取物品列表
    ///
    /// 调用 GET /v1/model/{envType}/{modelName}/list 接口
    ///
    /// - Parameters:
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "weitems"
    ///   - completion: 结果回调
    func fetchItems(
        envType: String = "prod",
        modelName: String = "weitems",
        completion: @escaping (FetchItemsResponse?) -> Void
    ) {
        let path = "/v1/model/\(envType)/\(modelName)/list"
        
        print("[远端] 开始获取远端物品列表...")
        
        request(
            method: "GET",
            path: path
        ) { (result: FetchItemsResponse?) in
            if let result = result {
                let recordCount = result.data?.records?.count ?? 0
                print("[远端] 获取成功，共 \(recordCount) 条记录")
            } else {
                print("[远端] 获取失败，无响应")
            }
            completion(result)
        }
    }
    
    /// 从远端获取物品列表（async/await 版本）
    @available(iOS 13.0, *)
    func fetchItems(
        envType: String = "prod",
        modelName: String = "weitems"
    ) async -> FetchItemsResponse? {
        await withCheckedContinuation { continuation in
            fetchItems(envType: envType, modelName: modelName) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - 心愿清单同步
    
    /// 心愿清单同步结果
    struct WishSyncResult {
        let uploadedCount: Int
        let updatedCount: Int
        let deletedLocalNames: [String]
        let failedIds: [String]
    }
    
    /// 将单个心愿 Item 转为 wewish createMany 所需的字典格式
    /// 格式: {"wishname": "{sub}_{心愿名}", "wishinfo": {心愿信息json}}
    private func wishToDict(_ item: Item, sub: String) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var wishInfo: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "details": item.details,
            "purchaseLink": item.purchaseLink,
            "price": item.price,
            "type": item.type,
            "listType": item.listType.rawValue,
            "isSelected": item.isSelected,
            "isArchived": item.isArchived,
            "createdAt": isoFormatter.string(from: item.createdAt),
            "updatedAt": isoFormatter.string(from: item.updatedAt)
        ]
        if let groupId = item.groupId {
            wishInfo["groupId"] = groupId.uuidString
        }
        if let displayType = item.displayType {
            wishInfo["displayType"] = displayType
        }
        if let targetType = item.targetType {
            wishInfo["targetType"] = targetType
        }
        if let wishlistGroupId = item.wishlistGroupId {
            wishInfo["wishlistGroupId"] = wishlistGroupId.uuidString
        }
        
        return [
            "wishname": "\(sub)_\(item.name)",
            "wishinfo": wishInfo
        ]
    }
    
    /// 估算心愿字典大小
    private func estimateWishJSONSize(_ dict: [String: Any]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return 0 }
        return data.count
    }
    
    /// 将心愿数组按 50KB 为上限分组
    private func splitWishesIntoChunks(_ items: [Item], maxChunkSize: Int = 50 * 1024) -> [[Item]] {
        var chunks: [[Item]] = []
        var currentChunk: [Item] = []
        var currentSize: Int = 0
        
        for item in items {
            let dict = wishToDict(item, sub: "")
            let size = estimateWishJSONSize(dict)
            
            if currentSize + size > maxChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentSize = 0
            }
            
            currentChunk.append(item)
            currentSize += size
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
    
    /// 获取远端心愿清单的响应模型
    struct FetchWishesResponse: Codable {
        let code: String?
        let message: String?
        let data: FetchWishesData?
        
        struct FetchWishesData: Codable {
            let records: [RemoteWishRecord]?
            let total: Int?
        }
        
        struct RemoteWishRecord: Codable {
            let _id: String?
            let wishname: String?
            let wishinfo: RemoteWishInfo?
        }
        
        struct RemoteWishInfo: Codable {
            let id: String?
            let name: String?
            let details: String?
            let purchaseLink: String?
            let price: Double?
            let type: String?
            let listType: String?
            let isSelected: Bool?
            let isArchived: Bool?
            let groupId: String?
            let displayType: String?
            let targetType: String?
            let wishlistGroupId: String?
            let createdAt: String?
            let updatedAt: String?
        }
    }
    
    /// 从远端获取心愿清单列表
    func fetchWishes(
        envType: String = "prod",
        modelName: String = "wewish",
        completion: @escaping (FetchWishesResponse?) -> Void
    ) {
        let path = "/v1/model/\(envType)/\(modelName)/list"
        
        print("[远端] 开始获取远端心愿清单...")
        
        request(
            method: "GET",
            path: path
        ) { (result: FetchWishesResponse?) in
            if let result = result {
                let recordCount = result.data?.records?.count ?? 0
                print("[远端] 心愿清单获取成功，共 \(recordCount) 条记录")
            } else {
                print("[远端] 心愿清单获取失败，无响应")
            }
            completion(result)
        }
    }
    
    /// 从远端获取心愿清单列表（async/await 版本）
    @available(iOS 13.0, *)
    func fetchWishes(
        envType: String = "prod",
        modelName: String = "wewish"
    ) async -> FetchWishesResponse? {
        await withCheckedContinuation { continuation in
            fetchWishes(envType: envType, modelName: modelName) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 同步心愿清单到云端（逻辑与 syncItems 一致，使用 wewish 模型）
    ///
    /// - Parameters:
    ///   - items: 本地所有物品数组（只同步 listType == .wishlist 的心愿）
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "wewish"
    /// - Returns: 同步结果或 nil
    @available(iOS 13.0, *)
    func syncWishes(
        items: [Item],
        envType: String = "prod",
        modelName: String = "wewish"
    ) async -> WishSyncResult? {
        let myWishes = items.filter { $0.listType == .wishlist }
        
        guard let sub = TokenStorage.shared.getSub(), !sub.isEmpty else {
            print("[心愿同步] 无法获取用户 sub，取消同步")
            return nil
        }
        
        // Step 1: 拉取远端数据
        print("[心愿同步] 正在拉取远端心愿数据...")
        let response = await fetchWishes(envType: envType, modelName: modelName)
        let remoteRecords = response?.data?.records ?? []
        
        let isoFormatter = ISO8601DateFormatter()
        var remoteMap: [String: (date: Date, record: FetchWishesResponse.RemoteWishRecord)] = [:]
        for record in remoteRecords {
            if let info = record.wishinfo, let name = info.name {
                let date: Date
                if let updatedAtStr = info.updatedAt, let parsed = isoFormatter.date(from: updatedAtStr) {
                    date = parsed
                } else if let createdAtStr = info.createdAt, let parsed = isoFormatter.date(from: createdAtStr) {
                    date = parsed
                } else {
                    date = Date.distantPast
                }
                remoteMap[name] = (date: date, record: record)
            }
        }
        
        print("[心愿同步] 远端共 \(remoteMap.count) 个心愿，本地共 \(myWishes.count) 个心愿")
        
        // Step 2: Merge 逻辑
        var wishesToCreate: [Item] = []
        var wishesToUpdate: [Item] = []
        var deletedLocalNames: [String] = []
        
        for localWish in myWishes {
            if let remote = remoteMap[localWish.name] {
                let localTimestamp = floor(localWish.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                    print("[心愿同步] 无变化: \(localWish.name)")
                } else if remoteTimestamp > localTimestamp {
                    print("[心愿同步] 远端更新: \(localWish.name)")
                    deletedLocalNames.append(localWish.name)
                } else {
                    print("[心愿同步] 本地更新: \(localWish.name)")
                    wishesToUpdate.append(localWish)
                }
            } else {
                print("[心愿同步] 本地独有: \(localWish.name)")
                wishesToCreate.append(localWish)
            }
        }
        
        print("[心愿同步] 需创建 \(wishesToCreate.count) 个，需更新 \(wishesToUpdate.count) 个，需删除本地 \(deletedLocalNames.count) 个")
        
        var uploadedCount = 0
        var updatedCount = 0
        var failedIds: [String] = []
        
        // Step 3: 创建本地独有的心愿 (createMany)
        if !wishesToCreate.isEmpty {
            let chunks = splitWishesIntoChunks(wishesToCreate)
            print("[心愿同步] 开始创建 \(wishesToCreate.count) 个心愿，分为 \(chunks.count) 组...")
            
            for (index, chunk) in chunks.enumerated() {
                let wishDicts = chunk.map { wishToDict($0, sub: sub) }
                let path = "/v1/model/\(envType)/\(modelName)/createMany"
                let payload: [String: Any] = ["data": wishDicts]
                
                print("[心愿同步] 正在创建第 \(index) 组 (\(chunk.count) 个心愿)")
                
                let result: CreateManyResponse? = await request(
                    method: "POST",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    print("[心愿同步] 第 \(index) 组响应: code=\(result.code ?? "nil"), message=\(result.message ?? "nil")")
                    let createdCount = result.data?.idList?.count ?? 0
                    if result.code == "SUCCESS" || createdCount > 0 {
                        print("[心愿同步] 第 \(index) 组创建成功 (\(createdCount) 个心愿)")
                        uploadedCount += createdCount > 0 ? createdCount : chunk.count
                    } else {
                        print("[心愿同步] 第 \(index) 组创建失败")
                        failedIds.append("wish_create_chunk_\(index)")
                    }
                } else {
                    print("[心愿同步] 第 \(index) 组创建失败, 无响应")
                    failedIds.append("wish_create_chunk_\(index)")
                }
            }
        }
        
        // Step 4: 更新远端同名心愿 (updateMany，按 wishname 过滤)
        if !wishesToUpdate.isEmpty {
            print("[心愿同步] 开始更新 \(wishesToUpdate.count) 个远端心愿...")
            
            for wish in wishesToUpdate {
                let wishId = "\(sub)_\(wish.name)"
                let dict = wishToDict(wish, sub: sub)
                let wishInfoDict = dict["wishinfo"] as? [String: Any] ?? [:]
                
                let path = "/v1/model/\(envType)/\(modelName)/updateMany"
                let payload: [String: Any] = [
                    "filter": [
                        "where": [
                            "wishname": [
                                "$eq": wishId
                            ]
                        ]
                    ],
                    "data": [
                        "wishinfo": wishInfoDict
                    ]
                ]
                
                print("[心愿同步] 正在更新远端心愿: \(wish.name)")
                
                let result: UpdateManyResponse? = await request(
                    method: "PUT",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    print("[心愿同步] 更新响应: code=\(result.code ?? "nil"), count=\(result.data?.count ?? 0)")
                    if result.code == "SUCCESS" || (result.data?.count ?? 0) > 0 {
                        updatedCount += 1
                    } else {
                        print("[心愿同步] 更新失败: \(wish.name)")
                        failedIds.append("wish_update_\(wish.name)")
                    }
                } else {
                    print("[心愿同步] 更新失败, 无响应: \(wish.name)")
                    failedIds.append("wish_update_\(wish.name)")
                }
            }
        }
        
        print("[心愿同步] 同步完成: 创建 \(uploadedCount) 个, 更新 \(updatedCount) 个, 删除本地 \(deletedLocalNames.count) 个, 失败 \(failedIds.count) 个")
        return WishSyncResult(uploadedCount: uploadedCount, updatedCount: updatedCount, deletedLocalNames: deletedLocalNames, failedIds: failedIds)
    }
    
    // MARK: - 共享心愿清单
    
    /// 生成 16 位随机数字字符串作为 wish_group_id
    static func generateWishGroupId() -> String {
        var result = ""
        for _ in 0..<16 {
            result += String(Int.random(in: 0...9))
        }
        return result
    }
    
    /// 创建共享心愿清单
    ///
    /// 参考 weitems / wewish 的请求方式，modelType 为 sharewish
    /// 调用 create 接口，传入 wish_group_id 和 wishinfo（JSON 序列化选中的所有心愿）
    ///
    /// - Parameters:
    ///   - wishGroupId: 16 位随机数 ID
    ///   - selectedItems: 选中的心愿 Item 数组
    ///   - listName: 共享清单名称
    ///   - listEmoji: 共享清单图标
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "sharewish"
    /// - Returns: CreateResponse（成功）或 nil
    @available(iOS 13.0, *)
    func createSharedWishlist(
        wishGroupId: String,
        selectedItems: [Item],
        listName: String,
        listEmoji: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> CreateResponse? {
        let isoFormatter = ISO8601DateFormatter()
        
        // 将选中的心愿序列化为 JSON 格式的数组，再转为 JSON 字符串
        let wishInfoArray: [[String: Any]] = selectedItems.map { item in
            var info: [String: Any] = [
                "id": item.id.uuidString,
                "name": item.name,
                "details": item.details,
                "purchaseLink": item.purchaseLink,
                "price": item.price,
                "type": item.type,
                "listType": item.listType.rawValue,
                "isSelected": item.isSelected,
                "isArchived": item.isArchived,
                "createdAt": isoFormatter.string(from: item.createdAt),
                "updatedAt": isoFormatter.string(from: item.updatedAt)
            ]
            if let groupId = item.groupId {
                info["groupId"] = groupId.uuidString
            }
            if let displayType = item.displayType {
                info["displayType"] = displayType
            }
            if let targetType = item.targetType {
                info["targetType"] = targetType
            }
            if let wishlistGroupId = item.wishlistGroupId {
                info["wishlistGroupId"] = wishlistGroupId.uuidString
            }
            return info
        }
        
        // wishinfo 字段类型为 JSONObject，用字典包裹数组
        let wishInfoObject: [String: Any] = ["items": wishInfoArray]
        
        let path = "/v1/model/\(envType)/\(modelName)/create"
        let payload: [String: Any] = [
            "data": [
                "wish_group_id": wishGroupId,
                "wishinfo": wishInfoObject,
                "name": listName,
                "emoji": listEmoji
            ]
        ]
        
        print("[共享心愿] 开始创建共享清单: \(listName), wish_group_id=\(wishGroupId), 心愿数量=\(selectedItems.count)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 创建响应: code=\(result.code ?? "nil"), message=\(result.message ?? "nil"), id=\(result.data?.id ?? "nil")")
        } else {
            print("[共享心愿] 创建失败, 无响应")
        }
        
        return result
    }
    
    /// 从 SharedWishItem 创建/重新同步共享心愿清单
    @available(iOS 13.0, *)
    func createSharedWishlistFromSharedItems(
        wishGroupId: String,
        sharedItems: [SharedWishItem],
        listName: String,
        listEmoji: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> CreateResponse? {
        let wishInfoArray: [[String: Any]] = sharedItems.map { item in
            var info: [String: Any] = [
                "id": item.id.uuidString,
                "name": item.name,
                "price": item.price,
                "isCompleted": item.isCompleted
            ]
            if let sourceId = item.sourceItemId {
                info["sourceItemId"] = sourceId.uuidString
            }
            if let displayType = item.displayType {
                info["displayType"] = displayType
            }
            return info
        }
        
        let wishInfoObject: [String: Any] = ["items": wishInfoArray]
        
        let path = "/v1/model/\(envType)/\(modelName)/create"
        let payload: [String: Any] = [
            "data": [
                "wish_group_id": wishGroupId,
                "wishinfo": wishInfoObject,
                "name": listName,
                "emoji": listEmoji
            ]
        ]
        
        print("[共享心愿] 重新同步共享清单: \(listName), wish_group_id=\(wishGroupId)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 同步响应: code=\(result.code ?? "nil"), id=\(result.data?.id ?? "nil")")
        } else {
            print("[共享心愿] 同步失败, 无响应")
        }
        
        return result
    }
}

// 配置文件或初始化时创建实例
// let cloudbase = CloudBaseClient(
//     envId: "your-env-id",
//     accessToken: "your-access-token"
// )
