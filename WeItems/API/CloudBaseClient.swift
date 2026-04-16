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

/// 兼容服务端返回 code 为数字或字符串的情况
/// 服务端可能返回 "code": 0（Int）或 "code": "SUCCESS"（String），
/// 标准 Codable 无法自动兼容两种类型，因此需要自定义解码。
struct FlexibleCode: Codable {
    let stringValue: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            stringValue = str
        } else if let num = try? container.decode(Int.self) {
            stringValue = String(num)
        } else if let dbl = try? container.decode(Double.self) {
            stringValue = String(Int(dbl))
        } else {
            stringValue = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
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

            // 调试：始终打印原始 JSON 和目标类型
            let rawJSON = String(data: data, encoding: .utf8) ?? "<无法转换>"
            print("[HTTP] 状态码: \(statusCode), 目标类型=\(T.self)")
            print("[HTTP] 原始JSON: \(rawJSON)")
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(T.self, from: data)
                print("[HTTP] 解码成功: \(T.self)")
                completion(result)
            } catch {
                // 尝试作为Any解码
                if let json = try? JSONSerialization.jsonObject(with: data) as? T {
                    completion(json)
                } else {
                    print("[HTTP] JSON解析失败, 目标类型=\(T.self), 错误=\(error)")
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
    /// 注意：
    /// 1. 此接口不需要 Authorization header（旧 access_token 可能已过期）
    /// 2. 刷新成功后，原 refresh_token 立即失效，新的 refresh_token 将替换它
    /// 3. refresh_token 默认有效期 31 天
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
        guard let url = URL(string: "\(baseUrl)/auth/v1/token") else {
            print("[Refresh] 无效的 URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 注意：refresh token 接口不带 Authorization Bearer header
        
        // 设置 x-device-id header（可选）
        let deviceIdToUse = customDeviceId ?? deviceId
        if let deviceIdToUse = deviceIdToUse {
            request.setValue(deviceIdToUse, forHTTPHeaderField: "x-device-id")
        }
        
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId ?? envId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Refresh] JSON 序列化失败: \(error)")
            return nil
        }
        
        print("[Refresh] 请求 URL: \(url.absoluteString)")
        print("[Refresh] client_id: \(clientId ?? envId)")
        print("[Refresh] refresh_token: \(refreshToken.prefix(20))...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let rawJSON = String(data: data, encoding: .utf8) ?? "<无法转换>"
            print("[Refresh] 状态码: \(statusCode)")
            print("[Refresh] 响应: \(rawJSON)")
            
            guard statusCode >= 200 && statusCode <= 299 else {
                print("[Refresh] 刷新失败，状态码: \(statusCode)")
                return nil
            }
            
            let result = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
            
            // 更新本地 access_token
            self.updateAccessToken(result.accessToken)
            print("[Refresh] Token 刷新成功，新 access_token 有效期: \(result.expiresIn) 秒")
            
            return result
        } catch {
            print("[Refresh] 请求异常: \(error)")
            return nil
        }
    }
    
    /// 检查 token 是否即将过期，如果即将过期则自动刷新
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
        if expiresIn < threshold {
            print("Token 即将过期（剩余 \(expiresIn) 秒），开始自动刷新...")
            return await refreshAccessToken(refreshToken: refreshToken, clientId: clientId)
        } else {
            print("Token 仍然有效（剩余 \(expiresIn) 秒），无需刷新")
            return nil
        }
    }
    
    // MARK: - 云函数调用
    
    /// 云函数响应的通用 Decodable 包装
    private struct CloudFunctionRawResponse: Decodable {
        // 使用空结构体占位，实际解析走 JSONSerialization
    }
    
    /// 调用云函数
    ///
    /// - Parameters:
    ///   - functionName: 云函数名称
    ///   - data: 传递给云函数的参数（可选）
    ///   - completion: 结果回调，返回云函数执行结果的字典或 nil
    func callFunction(
        functionName: String,
        data: [String: Any]? = nil,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(baseUrl)/v1/functions/\(functionName)") else {
            print("[云函数] 无效的URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        var bodyString = ""
        if let data = data {
            do {
                let bodyData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
                request.httpBody = bodyData
                bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            } catch {
                print("[云函数] JSON序列化失败: \(error)")
                completion(nil)
                return
            }
        }
        
        print("\n========== 云函数 HTTP REQUEST ==========")
        print("[云函数] 函数名: \(functionName)")
        print("[云函数] URL: \(url.absoluteString)")
        print("[云函数] Method: POST")
        print("[云函数] Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            let maskedValue = key.lowercased() == "authorization" ? "Bearer ***" : value
            print("  \(key): \(maskedValue)")
        }
        print("[云函数] Body:\n\(bodyString)")
        print("==========================================\n")
        
        let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
            if let error = error {
                print("[云函数] 请求失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode < 200 || statusCode > 299 {
                print("[云函数] 状态码异常: \(statusCode)")
                if let responseData = responseData, let body = String(data: responseData, encoding: .utf8) {
                    print("[云函数] 响应: \(body)")
                }
                completion(nil)
                return
            }
            
            guard let responseData = responseData else {
                completion(nil)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                print("[云函数] 调用结果: \(json)")
                completion(json)
            } else {
                print("[云函数] JSON解析失败")
                completion(nil)
            }
        }
        task.resume()
    }
    
    /// 调用云函数（async/await 版本）
    ///
    /// - Parameters:
    ///   - functionName: 云函数名称
    ///   - data: 传递给云函数的参数（可选）
    /// - Returns: 云函数执行结果的字典或 nil
    @available(iOS 13.0, *)
    func callFunction(
        functionName: String,
        data: [String: Any]? = nil
    ) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            callFunction(functionName: functionName, data: data) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - 数据同步
    
    /// 批量上传物品图片到云存储（使用 list 方式一次性获取所有上传凭证）
    ///
    /// 筛选出有 imageData 的物品，通过 `uploadFiles` 批量上传到云存储，
    /// 返回 `[item.id.uuidString: downloadUrl]` 映射。
    ///
    /// - Parameter items: 待同步的物品数组
    /// - Returns: 物品 UUID 字符串 → 云存储下载 URL 的字典
    @available(iOS 13.0, *)
    func uploadItemImages(items: [Item]) async -> [String: String] {
        // 上传条件：有图片数据，且（图片被编辑过 或 远端没有 imageUrl）
        let itemsNeedingUpload = items.filter { $0.imageData != nil && ($0.imageChanged || ($0.imageUrl ?? "").isEmpty) }
        guard !itemsNeedingUpload.isEmpty else {
            print("[图片上传] 没有需要上传的图片，跳过")
            return [:]
        }
        
        print("[图片上传] 开始批量上传 \(itemsNeedingUpload.count) 张图片（共 \(items.filter { $0.imageData != nil }.count) 张有图片，其中 \(itemsNeedingUpload.count) 张需上传）...")
        
        // 构造 UploadItem 列表（优先使用压缩版图片）
        let uploadItems: [UploadItem] = itemsNeedingUpload.compactMap { item in
            // 优先使用压缩版（0.7 质量），没有则回退到原图
            let uploadData = item.compressedImageData ?? item.imageData
            guard let imageData = uploadData else { return nil }
            // 使用 item UUID 作为 objectId，避免重复上传
            let objectId = "items/\(item.id.uuidString).jpg"
            return UploadItem(data: imageData, objectId: objectId)
        }
        
        // 批量上传
        let results = await uploadFiles(items: uploadItems)
        
        // 构建 itemId → downloadUrl 映射
        var imageUrlMap: [String: String] = [:]
        for (index, item) in itemsNeedingUpload.enumerated() {
            guard index < results.count else { break }
            let result = results[index]
            if result.success, !result.downloadUrl.isEmpty {
                imageUrlMap[item.id.uuidString] = result.downloadUrl
                print("[图片上传] ✅ \(item.name) → \(result.downloadUrl)")
            } else {
                print("[图片上传] ❌ \(item.name) 上传失败: \(result.error ?? "未知错误")")
            }
        }
        
        print("[图片上传] 批量上传完成: \(imageUrlMap.count)/\(itemsNeedingUpload.count) 成功")
        return imageUrlMap
    }
    
    /// 创建响应结构体
    struct CreateResponse: Codable {
        let code: FlexibleCode?
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
        let deletedLocalItemIds: [String]  // 远端更新、需删除本地的物品 itemId
        let deletedRemoteItemIds: [String] // 本地删除后同步到远端删除的 itemId
        let remoteOnlyItems: [Item]      // 远端独有、需添加到本地的物品
        let failedIds: [String]
    }
    
    /// 将单个 Item 转为 createMany 所需的字典格式
    /// 格式: {"item_id": "{sub}_{物品名}", "item_info": {物品信息json}}
    /// - Parameters:
    ///   - item: 物品
    ///   - sub: 用户标识
    ///   - imageUrl: 云存储图片下载链接（可选，通过 uploadFiles 批量上传后获得）
    private func itemToDict(_ item: Item, sub: String, imageUrl: String? = nil) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var itemInfo: [String: Any] = [
            "id": item.id.uuidString,
            "itemId": item.itemId,
            "name": item.name,
            "details": item.details,
            "purchaseLink": item.purchaseLink,
            "price": item.price,
            "type": item.type,
            "listType": item.listType.rawValue,
            "isSelected": item.isSelected,
            "isArchived": item.isArchived,
            "isPriceless": item.isPriceless,
            "createdAt": isoFormatter.string(from: item.createdAt),
            "updatedAt": isoFormatter.string(from: item.updatedAt)
        ]
        if let ownedDate = item.ownedDate {
            itemInfo["ownedDate"] = isoFormatter.string(from: ownedDate)
        }
        if let soldPrice = item.soldPrice {
            itemInfo["soldPrice"] = soldPrice
        }
        if let soldDate = item.soldDate {
            itemInfo["soldDate"] = isoFormatter.string(from: soldDate)
        }
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
        // 图片云存储下载链接
        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            itemInfo["imageUrl"] = imageUrl
        }
        
        return [
            "item_id": item.itemId,
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
        let code: FlexibleCode?
        let message: String?
        let data: CreateManyData?
        
        struct CreateManyData: Codable {
            let idList: [String]?
        }
    }
    
    /// updateMany 响应结构体
    struct UpdateManyResponse: Codable {
        let code: FlexibleCode?
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
        deletedItemRecords: [String: Date] = [:],
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
        
        // 构建远端物品字典：itemId -> (updatedAt, record)
        let isoFormatter = ISO8601DateFormatter()
        var remoteMap: [String: (date: Date, record: FetchItemsResponse.RemoteRecord)] = [:]
        for record in remoteRecords {
            if let info = record.item_info, let itemId = info.itemId, !itemId.isEmpty {
                let date: Date
                if let updatedAtStr = info.updatedAt, let parsed = isoFormatter.date(from: updatedAtStr) {
                    date = parsed
                } else if let createdAtStr = info.createdAt, let parsed = isoFormatter.date(from: createdAtStr) {
                    date = parsed
                } else {
                    date = Date.distantPast
                }
                remoteMap[itemId] = (date: date, record: record)
            }
        }
        
        print("[同步] 远端共 \(remoteMap.count) 个物品，本地共 \(myItems.count) 个物品")
        
        // Step 2: Merge 逻辑
        var itemsToCreate: [Item] = []        // 本地独有，需创建到远端
        var itemsToUpdate: [Item] = []        // 本地更新，需更新远端
        var deletedLocalItemIds: [String] = []  // 远端更新、需删除本地的物品 itemId
        var itemsToDeleteRemote: [String] = []  // 本地删除、需同步删除远端的 item_id
        var remoteOnlyItems: [Item] = []      // 远端独有、需添加到本地的物品
        
        // 构建本地物品 itemId 集合，用于检测远端独有
        let localItemIdSet = Set(myItems.map { $0.itemId })
        
        for localItem in myItems {
            if let remote = remoteMap[localItem.itemId] {
                // 同名物品：比较 updatedAt
                // 精度对齐到秒级（ISO8601 只到秒）
                let localTimestamp = floor(localItem.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                    // updatedAt 相同，无需操作
                } else if remoteTimestamp > localTimestamp {
                    // 远端更新，标记删除本地旧版本，并将远端新版本加入 remoteOnlyItems
                    deletedLocalItemIds.append(localItem.itemId)
                    // 将远端版本加入待下载列表，调用方会先删旧再添新
                    let info = remote.record.item_info
                    let remoteItem = Item(
                        id: UUID(uuidString: info?.id ?? "") ?? UUID(),
                        itemId: info?.itemId ?? localItem.itemId,
                        name: info?.name ?? localItem.name,
                        details: info?.details ?? "",
                        purchaseLink: info?.purchaseLink ?? "",
                        price: info?.price ?? 0,
                        type: info?.type ?? "其他",
                        groupId: info?.groupId != nil ? UUID(uuidString: info!.groupId!) : nil,
                        listType: .items,
                        createdAt: isoFormatter.date(from: info?.createdAt ?? "") ?? Date(),
                        updatedAt: isoFormatter.date(from: info?.updatedAt ?? info?.createdAt ?? "") ?? Date(),
                        isSelected: info?.isSelected ?? false,
                        isArchived: info?.isArchived ?? false,
                        isPriceless: info?.isPriceless ?? false,
                        ownedDate: info?.ownedDate != nil ? isoFormatter.date(from: info!.ownedDate!) : nil,
                        displayType: info?.displayType,
                        targetType: info?.targetType,
                        wishlistGroupId: info?.wishlistGroupId != nil ? UUID(uuidString: info!.wishlistGroupId!) : nil,
                        imageUrl: info?.imageUrl,
                        soldPrice: info?.soldPrice,
                        soldDate: info?.soldDate != nil ? isoFormatter.date(from: info!.soldDate!) : nil
                    )
                    remoteOnlyItems.append(remoteItem)
                } else {
                    // 本地更新，调用 updateMany 更新远端
                    itemsToUpdate.append(localItem)
                }
            } else {
                // 本地独有，创建到远端
                itemsToCreate.append(localItem)
            }
        }
        
        // 2b: 遍历远端，找出远端独有的物品（本地没有的）
        for (remoteItemId, remote) in remoteMap {
            guard !localItemIdSet.contains(remoteItemId) else { continue }
            // 远端独有，需要下载到本地
            let info = remote.record.item_info
            let newItem = Item(
                id: UUID(uuidString: info?.id ?? "") ?? UUID(),
                itemId: info?.itemId ?? remoteItemId,
                name: info?.name ?? "",
                details: info?.details ?? "",
                purchaseLink: info?.purchaseLink ?? "",
                price: info?.price ?? 0,
                type: info?.type ?? "其他",
                groupId: info?.groupId != nil ? UUID(uuidString: info!.groupId!) : nil,
                listType: .items,
                createdAt: isoFormatter.date(from: info?.createdAt ?? "") ?? Date(),
                updatedAt: isoFormatter.date(from: info?.updatedAt ?? info?.createdAt ?? "") ?? Date(),
                isSelected: info?.isSelected ?? false,
                isArchived: info?.isArchived ?? false,
                isPriceless: info?.isPriceless ?? false,
                ownedDate: info?.ownedDate != nil ? isoFormatter.date(from: info!.ownedDate!) : nil,
                displayType: info?.displayType,
                targetType: info?.targetType,
                wishlistGroupId: info?.wishlistGroupId != nil ? UUID(uuidString: info!.wishlistGroupId!) : nil,
                imageUrl: info?.imageUrl,
                soldPrice: info?.soldPrice,
                soldDate: info?.soldDate != nil ? isoFormatter.date(from: info!.soldDate!) : nil
            )
            
            // 检查本地是否有删除记录
            if let deletedAt = deletedItemRecords[remoteItemId] {
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                let deletedTimestamp = floor(deletedAt.timeIntervalSince1970)
                if deletedTimestamp >= remoteTimestamp {
                    // 本地删除时间 >= 远端更新时间，需要删除远端
                    itemsToDeleteRemote.append(remoteItemId)
                    continue
                }
                // 远端更新时间更新，保留远端版本
            }
            
            remoteOnlyItems.append(newItem)
        }
        
        print("[同步] 需创建 \(itemsToCreate.count) 个，需更新 \(itemsToUpdate.count) 个，需删除本地 \(deletedLocalItemIds.count) 个，需删除远端 \(itemsToDeleteRemote.count) 个，远端独有 \(remoteOnlyItems.count) 个")
        
        var uploadedCount = 0
        var updatedCount = 0
        var failedIds: [String] = []
        
        // Step 2.5: 批量上传图片到云存储（仅上传图片变更的物品）
        // 合并需要创建和更新的物品，统一上传图片
        let allItemsNeedingSync = itemsToCreate + itemsToUpdate
        let imageUrlMap: [String: String]
        
        // 只对 imageChanged == true 的物品执行云上传
        let uploadedMap = await uploadItemImages(items: allItemsNeedingSync)
        
        // 清理旧 COS 图片：imageChanged == true 且 imageData == nil（用户删除了图片）
        var oldImageObjectIdsToDelete: [String] = []
        let imageDeletedItemIds = Set(allItemsNeedingSync
            .filter { $0.imageChanged && $0.imageData == nil }
            .map { $0.id.uuidString })
        for item in allItemsNeedingSync where imageDeletedItemIds.contains(item.id.uuidString) {
            if let remote = remoteMap[item.itemId],
               let existingUrl = remote.record.item_info?.imageUrl, !existingUrl.isEmpty,
               let itemUUID = remote.record.item_info?.id {
                oldImageObjectIdsToDelete.append("items/\(itemUUID).jpg")
            }
        }
        if !oldImageObjectIdsToDelete.isEmpty {
            let cloudIdMap = await getCloudObjectIds(objectIds: oldImageObjectIdsToDelete)
            let cloudIds = Array(cloudIdMap.values)
            if !cloudIds.isEmpty {
                let _ = await deleteStorageObjects(cloudObjectIds: cloudIds)
            }
        }
        
        // 构建最终 imageUrl 映射：上传成功的用新 URL，未上传的复用远端已有 URL
        var finalImageUrlMap = uploadedMap
        for item in allItemsNeedingSync {
            let itemIdStr = item.id.uuidString
            // 用户主动删除了图片，不复用旧 URL
            if imageDeletedItemIds.contains(itemIdStr) { continue }
            if finalImageUrlMap[itemIdStr] == nil {
                // 未上传（图片未变更），尝试复用远端已有的 imageUrl
                if let remote = remoteMap[item.itemId],
                   let existingUrl = remote.record.item_info?.imageUrl,
                   !existingUrl.isEmpty {
                    finalImageUrlMap[itemIdStr] = existingUrl
                }
            }
        }
        imageUrlMap = finalImageUrlMap
        
        // Step 3: 创建本地独有的物品 (createMany)
        if !itemsToCreate.isEmpty {
            let chunks = splitItemsIntoChunks(itemsToCreate)
            
            for (index, chunk) in chunks.enumerated() {
                let itemDicts = chunk.map { itemToDict($0, sub: sub, imageUrl: imageUrlMap[$0.id.uuidString]) }
                let path = "/v1/model/\(envType)/\(modelName)/createMany"
                let payload: [String: Any] = ["data": itemDicts]
                
                let result: CreateManyResponse? = await request(
                    method: "POST",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    let createdCount = result.data?.idList?.count ?? 0
                    if result.code?.stringValue == "SUCCESS" || result.code?.stringValue == "0" || createdCount > 0 {
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
            for item in itemsToUpdate {
                let itemId = item.itemId
                let dict = itemToDict(item, sub: sub, imageUrl: imageUrlMap[item.id.uuidString])
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
                
                let result: UpdateManyResponse? = await request(
                    method: "PUT",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    if result.code?.stringValue == "SUCCESS" || result.code?.stringValue == "0" || (result.data?.count ?? 0) > 0 {
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
        
        // Step 5: 删除远端物品（本地已删除且删除时间 >= 远端更新时间）
        var deletedRemoteItemIds: [String] = []
        if !itemsToDeleteRemote.isEmpty {
            print("[同步] 开始删除远端 \(itemsToDeleteRemote.count) 个物品...")
            var imageObjectIdsToDelete: [String] = []
            for remoteItemId in itemsToDeleteRemote {
                // 收集需要删除的 COS 图片
                if let remote = remoteMap[remoteItemId],
                   let imageUrl = remote.record.item_info?.imageUrl, !imageUrl.isEmpty,
                   let itemUUID = remote.record.item_info?.id {
                    imageObjectIdsToDelete.append("items/\(itemUUID).jpg")
                }
                
                let path = "/v1/model/\(envType)/\(modelName)/delete"
                let payload: [String: Any] = [
                    "filter": [
                        "where": [
                            "item_id": ["$eq": remoteItemId]
                        ]
                    ]
                ]
                let result: DeleteResponse? = await request(method: "POST", path: path, body: payload)
                if result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || (result?.data?.count ?? 0) > 0 {
                    deletedRemoteItemIds.append(remoteItemId)
                } else {
                    print("[同步] 远端删除失败: \(remoteItemId)")
                    failedIds.append("delete_remote_\(remoteItemId)")
                }
            }
            // 批量删除 COS 图片
            if !imageObjectIdsToDelete.isEmpty {
                let cloudIdMap = await getCloudObjectIds(objectIds: imageObjectIdsToDelete)
                let cloudIds = Array(cloudIdMap.values)
                if !cloudIds.isEmpty {
                    let _ = await deleteStorageObjects(cloudObjectIds: cloudIds)
                }
            }
        }
        
        print("[同步] 同步完成: 创建 \(uploadedCount) 个, 更新 \(updatedCount) 个, 删除本地 \(deletedLocalItemIds.count) 个, 删除远端 \(deletedRemoteItemIds.count) 个, 远端独有 \(remoteOnlyItems.count) 个, 失败 \(failedIds.count) 个")
        return SyncResult(uploadedCount: uploadedCount, updatedCount: updatedCount, deletedLocalItemIds: deletedLocalItemIds, deletedRemoteItemIds: deletedRemoteItemIds, remoteOnlyItems: remoteOnlyItems, failedIds: failedIds)
    }
    
    // MARK: - 远端数据获取
    
    /// 获取远端物品列表的响应模型
    struct FetchItemsResponse: Codable {
        let code: FlexibleCode?
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
            let itemId: String?
            let name: String?
            let details: String?
            let purchaseLink: String?
            let price: Double?
            let type: String?
            let listType: String?
            let isSelected: Bool?
            let isArchived: Bool?
            let isPriceless: Bool?
            let ownedDate: String?
            let soldPrice: Double?
            let soldDate: String?
            let groupId: String?
            let displayType: String?
            let targetType: String?
            let wishlistGroupId: String?
            let createdAt: String?
            let updatedAt: String?
            let imageUrl: String?
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
    
    /// 批量上传心愿图片到云存储（使用 list 方式一次性获取所有上传凭证）
    ///
    /// 筛选出有 imageData 的心愿，通过 `uploadFiles` 批量上传到云存储，
    /// 返回 `[item.id.uuidString: downloadUrl]` 映射。
    ///
    /// - Parameter items: 待同步的心愿数组
    /// - Returns: 心愿 UUID 字符串 → 云存储下载 URL 的字典
    @available(iOS 13.0, *)
    func uploadWishImages(items: [Item]) async -> [String: String] {
        // 上传条件：有图片数据，且（图片被编辑过 或 远端没有 imageUrl）
        let itemsNeedingUpload = items.filter { $0.imageData != nil && ($0.imageChanged || ($0.imageUrl ?? "").isEmpty) }
        guard !itemsNeedingUpload.isEmpty else {
            print("[心愿图片上传] 没有需要上传的图片，跳过")
            return [:]
        }
        
        print("[心愿图片上传] 开始批量上传 \(itemsNeedingUpload.count) 张图片（共 \(items.filter { $0.imageData != nil }.count) 张有图片，其中 \(itemsNeedingUpload.count) 张需上传）...")
        
        // 构造 UploadItem 列表（优先使用压缩版图片）
        let uploadItems: [UploadItem] = itemsNeedingUpload.compactMap { item in
            // 优先使用压缩版（0.7 质量），没有则回退到原图
            let uploadData = item.compressedImageData ?? item.imageData
            guard let imageData = uploadData else { return nil }
            // 使用 wishes/ 前缀区分心愿图片
            let objectId = "wishes/\(item.id.uuidString).jpg"
            return UploadItem(data: imageData, objectId: objectId)
        }
        
        // 批量上传
        let results = await uploadFiles(items: uploadItems)
        
        // 构建 itemId → downloadUrl 映射
        var imageUrlMap: [String: String] = [:]
        for (index, item) in itemsNeedingUpload.enumerated() {
            guard index < results.count else { break }
            let result = results[index]
            if result.success, !result.downloadUrl.isEmpty {
                imageUrlMap[item.id.uuidString] = result.downloadUrl
                print("[心愿图片上传] ✅ \(item.name) → \(result.downloadUrl)")
            } else {
                print("[心愿图片上传] ❌ \(item.name) 上传失败: \(result.error ?? "未知错误")")
            }
        }
        
        print("[心愿图片上传] 批量上传完成: \(imageUrlMap.count)/\(itemsNeedingUpload.count) 成功")
        return imageUrlMap
    }
    
    // MARK: - 心愿清单同步
    
    /// 心愿清单同步结果
    struct WishSyncResult {
        let uploadedCount: Int
        let updatedCount: Int
        let deletedLocalItemIds: [String]
        let deletedRemoteItemIds: [String]
        let remoteOnlyItems: [Item]
        let failedIds: [String]
    }
    
    /// 将单个心愿 Item 转为 wewish createMany 所需的字典格式
    /// 格式: {"wishname": "{sub}_{心愿名}", "wishinfo": {心愿信息json}}
    /// - Parameters:
    ///   - item: 心愿物品
    ///   - sub: 用户标识
    ///   - imageUrl: 云存储图片下载链接（可选，通过 uploadFiles 批量上传后获得）
    private func wishToDict(_ item: Item, sub: String, imageUrl: String? = nil) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var wishInfo: [String: Any] = [
            "id": item.id.uuidString,
            "itemId": item.itemId,
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
        // 图片云存储下载链接
        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            wishInfo["imageUrl"] = imageUrl
        }
        
        return [
            "wishname": item.itemId,
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
        let code: FlexibleCode?
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
            let itemId: String?
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
            let imageUrl: String?
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
        deletedItemRecords: [String: Date] = [:],
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
            if let info = record.wishinfo, let itemId = info.itemId, !itemId.isEmpty {
                let date: Date
                if let updatedAtStr = info.updatedAt, let parsed = isoFormatter.date(from: updatedAtStr) {
                    date = parsed
                } else if let createdAtStr = info.createdAt, let parsed = isoFormatter.date(from: createdAtStr) {
                    date = parsed
                } else {
                    date = Date.distantPast
                }
                remoteMap[itemId] = (date: date, record: record)
            }
        }
        
        print("[心愿同步] 远端共 \(remoteMap.count) 个心愿，本地共 \(myWishes.count) 个心愿")
        
        // Step 2: Merge 逻辑
        var wishesToCreate: [Item] = []
        var wishesToUpdate: [Item] = []
        var deletedLocalItemIds: [String] = []
        var wishesToDeleteRemote: [String] = []
        var remoteOnlyItems: [Item] = []      // 远端独有、需添加到本地的心愿
        
        // 构建本地心愿 itemId 集合，用于检测远端独有
        let localItemIdSet = Set(myWishes.map { $0.itemId })
        
        for localWish in myWishes {
            if let remote = remoteMap[localWish.itemId] {
                let localTimestamp = floor(localWish.updatedAt.timeIntervalSince1970)
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                
                if localTimestamp == remoteTimestamp {
                } else if remoteTimestamp > localTimestamp {
                    deletedLocalItemIds.append(localWish.itemId)
                    // 将远端版本加入待下载列表
                    let info = remote.record.wishinfo
                    let remoteItem = Item(
                        id: UUID(uuidString: info?.id ?? "") ?? UUID(),
                        itemId: info?.itemId ?? localWish.itemId,
                        name: info?.name ?? localWish.name,
                        details: info?.details ?? "",
                        purchaseLink: info?.purchaseLink ?? "",
                        price: info?.price ?? 0,
                        type: info?.type ?? "其他",
                        groupId: info?.groupId != nil ? UUID(uuidString: info!.groupId!) : nil,
                        listType: .wishlist,
                        createdAt: isoFormatter.date(from: info?.createdAt ?? "") ?? Date(),
                        updatedAt: isoFormatter.date(from: info?.updatedAt ?? info?.createdAt ?? "") ?? Date(),
                        isSelected: info?.isSelected ?? false,
                        isArchived: info?.isArchived ?? false,
                        displayType: info?.displayType,
                        targetType: info?.targetType,
                        wishlistGroupId: info?.wishlistGroupId != nil ? UUID(uuidString: info!.wishlistGroupId!) : nil,
                        imageUrl: info?.imageUrl
                    )
                    remoteOnlyItems.append(remoteItem)
                } else {
                    wishesToUpdate.append(localWish)
                }
            } else {
                wishesToCreate.append(localWish)
            }
        }
        
        // 2b: 遍历远端，找出远端独有的心愿（本地没有的）
        for (remoteItemId, remote) in remoteMap {
            guard !localItemIdSet.contains(remoteItemId) else { continue }
            // 远端独有，需要下载到本地
            let info = remote.record.wishinfo
            let newItem = Item(
                id: UUID(uuidString: info?.id ?? "") ?? UUID(),
                itemId: info?.itemId ?? remoteItemId,
                name: info?.name ?? "",
                details: info?.details ?? "",
                purchaseLink: info?.purchaseLink ?? "",
                price: info?.price ?? 0,
                type: info?.type ?? "其他",
                groupId: info?.groupId != nil ? UUID(uuidString: info!.groupId!) : nil,
                listType: .wishlist,
                createdAt: isoFormatter.date(from: info?.createdAt ?? "") ?? Date(),
                updatedAt: isoFormatter.date(from: info?.updatedAt ?? info?.createdAt ?? "") ?? Date(),
                isSelected: info?.isSelected ?? false,
                isArchived: info?.isArchived ?? false,
                displayType: info?.displayType,
                targetType: info?.targetType,
                wishlistGroupId: info?.wishlistGroupId != nil ? UUID(uuidString: info!.wishlistGroupId!) : nil,
                imageUrl: info?.imageUrl
            )
            
            // 检查本地是否有删除记录
            if let deletedAt = deletedItemRecords[remoteItemId] {
                let remoteTimestamp = floor(remote.date.timeIntervalSince1970)
                let deletedTimestamp = floor(deletedAt.timeIntervalSince1970)
                if deletedTimestamp >= remoteTimestamp {
                    wishesToDeleteRemote.append(remoteItemId)
                    continue
                }
            }
            
            remoteOnlyItems.append(newItem)
        }
        
        print("[心愿同步] 需创建 \(wishesToCreate.count) 个，需更新 \(wishesToUpdate.count) 个，需删除本地 \(deletedLocalItemIds.count) 个，远端独有 \(remoteOnlyItems.count) 个")
        
        var uploadedCount = 0
        var updatedCount = 0
        var failedIds: [String] = []
        
        // Step 2.5: 批量上传心愿图片到云存储（仅上传图片变更的心愿）
        // 合并需要创建和更新的心愿，统一上传图片
        let allWishesNeedingSync = wishesToCreate + wishesToUpdate
        let imageUrlMap: [String: String]
        
        // 只对 imageChanged == true 的心愿执行云上传
        let uploadedMap = await uploadWishImages(items: allWishesNeedingSync)
        
        // 清理旧 COS 图片：imageChanged == true 且 imageData == nil（用户删除了图片）
        var oldWishImageObjectIdsToDelete: [String] = []
        let wishImageDeletedIds = Set(allWishesNeedingSync
            .filter { $0.imageChanged && $0.imageData == nil }
            .map { $0.id.uuidString })
        for wish in allWishesNeedingSync where wishImageDeletedIds.contains(wish.id.uuidString) {
            if let remote = remoteMap[wish.itemId],
               let existingUrl = remote.record.wishinfo?.imageUrl, !existingUrl.isEmpty,
               let itemUUID = remote.record.wishinfo?.id {
                oldWishImageObjectIdsToDelete.append("wishes/\(itemUUID).jpg")
            }
        }
        if !oldWishImageObjectIdsToDelete.isEmpty {
            let cloudIdMap = await getCloudObjectIds(objectIds: oldWishImageObjectIdsToDelete)
            let cloudIds = Array(cloudIdMap.values)
            if !cloudIds.isEmpty {
                let _ = await deleteStorageObjects(cloudObjectIds: cloudIds)
            }
        }
        
        // 构建最终 imageUrl 映射：上传成功的用新 URL，未上传的复用远端已有 URL
        var finalImageUrlMap = uploadedMap
        for wish in allWishesNeedingSync {
            let wishIdStr = wish.id.uuidString
            // 用户主动删除了图片，不复用旧 URL
            if wishImageDeletedIds.contains(wishIdStr) { continue }
            if finalImageUrlMap[wishIdStr] == nil {
                // 未上传（图片未变更），尝试复用远端已有的 imageUrl
                if let remote = remoteMap[wish.itemId],
                   let existingUrl = remote.record.wishinfo?.imageUrl,
                   !existingUrl.isEmpty {
                    finalImageUrlMap[wishIdStr] = existingUrl
                }
            }
        }
        imageUrlMap = finalImageUrlMap
        
        // Step 3: 创建本地独有的心愿 (createMany)
        if !wishesToCreate.isEmpty {
            let chunks = splitWishesIntoChunks(wishesToCreate)
            
            for (index, chunk) in chunks.enumerated() {
                let wishDicts = chunk.map { wishToDict($0, sub: sub, imageUrl: imageUrlMap[$0.id.uuidString]) }
                let path = "/v1/model/\(envType)/\(modelName)/createMany"
                let payload: [String: Any] = ["data": wishDicts]
                
                let result: CreateManyResponse? = await request(
                    method: "POST",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    let createdCount = result.data?.idList?.count ?? 0
                    if result.code?.stringValue == "SUCCESS" || result.code?.stringValue == "0" || createdCount > 0 {
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
            for wish in wishesToUpdate {
                let wishId = wish.itemId
                let dict = wishToDict(wish, sub: sub, imageUrl: imageUrlMap[wish.id.uuidString])
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
                
                let result: UpdateManyResponse? = await request(
                    method: "PUT",
                    path: path,
                    body: payload
                )
                
                if let result = result {
                    if result.code?.stringValue == "SUCCESS" || result.code?.stringValue == "0" || (result.data?.count ?? 0) > 0 {
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
        
        // Step 5: 删除远端心愿（本地已删除）
        var deletedRemoteItemIds: [String] = []
        if !wishesToDeleteRemote.isEmpty {
            print("[心愿同步] 开始删除远端 \(wishesToDeleteRemote.count) 个心愿...")
            var imageObjectIdsToDelete: [String] = []
            for remoteItemId in wishesToDeleteRemote {
                // 收集需要删除的 COS 图片
                if let remote = remoteMap[remoteItemId],
                   let imageUrl = remote.record.wishinfo?.imageUrl, !imageUrl.isEmpty,
                   let itemUUID = remote.record.wishinfo?.id {
                    imageObjectIdsToDelete.append("wishes/\(itemUUID).jpg")
                }
                
                let path = "/v1/model/\(envType)/\(modelName)/delete"
                let payload: [String: Any] = [
                    "filter": [
                        "where": [
                            "wishname": ["$eq": remoteItemId]
                        ]
                    ]
                ]
                let result: DeleteResponse? = await request(method: "POST", path: path, body: payload)
                if result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || (result?.data?.count ?? 0) > 0 {
                    deletedRemoteItemIds.append(remoteItemId)
                } else {
                    print("[心愿同步] 远端删除失败: \(remoteItemId)")
                    failedIds.append("wish_delete_remote_\(remoteItemId)")
                }
            }
            // 批量删除 COS 图片
            if !imageObjectIdsToDelete.isEmpty {
                let cloudIdMap = await getCloudObjectIds(objectIds: imageObjectIdsToDelete)
                let cloudIds = Array(cloudIdMap.values)
                if !cloudIds.isEmpty {
                    let _ = await deleteStorageObjects(cloudObjectIds: cloudIds)
                }
            }
        }
        
        print("[心愿同步] 同步完成: 创建 \(uploadedCount) 个, 更新 \(updatedCount) 个, 删除本地 \(deletedLocalItemIds.count) 个, 删除远端 \(deletedRemoteItemIds.count) 个, 远端独有 \(remoteOnlyItems.count) 个, 失败 \(failedIds.count) 个")
        return WishSyncResult(uploadedCount: uploadedCount, updatedCount: updatedCount, deletedLocalItemIds: deletedLocalItemIds, deletedRemoteItemIds: deletedRemoteItemIds, remoteOnlyItems: remoteOnlyItems, failedIds: failedIds)
    }
    
    // MARK: - 共享心愿清单
    
    /// 生成 16 位随机数字字符串作为 wish_group_id
    static func generateWishGroupId() -> String {
        var result = ""
        for _ in 0..<16 {
            result += String(Int.random(in: 0...9))
        }
        return "sharewish_\(result)"
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
        ownerName: String,
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
            if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
                info["imageUrl"] = imageUrl
            }
            return info
        }
        
        // wishinfo 字段类型为 JSONObject，用字典包裹数组
        let wishInfoObject: [String: Any] = ["items": wishInfoArray]
        
        let path = "/v1/model/\(envType)/\(modelName)/create"
        let ownerNumberId = TokenStorage.shared.getSub() ?? ""
        let numbersObject: [String: Any] = [
            "number_list": [
                ["number_name": ownerName, "number_id": ownerNumberId]
            ]
        ]
        let payload: [String: Any] = [
            "data": [
                "wish_group_id": wishGroupId,
                "wishinfo": wishInfoObject,
                "name": listName,
                "emoji": listEmoji,
                "owner_name": ownerName,
                "members": [ownerName],
                "numbers": numbersObject
            ]
        ]
        
        print("[共享心愿] 开始创建共享清单: \(listName), wish_group_id=\(wishGroupId), 心愿数量=\(selectedItems.count)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 创建响应: code=\(result.code?.stringValue ?? "nil"), message=\(result.message ?? "nil"), id=\(result.data?.id ?? "nil")")
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
        ownerName: String? = nil,
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
            if let purchaseLink = item.purchaseLink {
                info["purchaseLink"] = purchaseLink
            }
            if let details = item.details {
                info["details"] = details
            }
            if let completedBy = item.completedBy {
                info["completedBy"] = completedBy
            }
            if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
                info["imageUrl"] = imageUrl
            }
            return info
        }
        
        let wishInfoObject: [String: Any] = ["items": wishInfoArray]
        
        let path = "/v1/model/\(envType)/\(modelName)/create"
        
        var dataDict: [String: Any] = [
            "wish_group_id": wishGroupId,
            "wishinfo": wishInfoObject,
            "name": listName,
            "emoji": listEmoji
        ]
        
        // 如果提供了 ownerName，添加 owner 信息和 number_list
        if let ownerName = ownerName, !ownerName.isEmpty {
            let ownerNumberId = TokenStorage.shared.getSub() ?? ""
            dataDict["owner_name"] = ownerName
            dataDict["members"] = [ownerName]
            dataDict["numbers"] = [
                "number_list": [
                    ["number_name": ownerName, "number_id": ownerNumberId]
                ]
            ] as [String: Any]
        }
        
        let payload: [String: Any] = ["data": dataDict]
        
        print("[共享心愿] 重新同步共享清单: \(listName), wish_group_id=\(wishGroupId)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 同步响应: code=\(result.code?.stringValue ?? "nil"), id=\(result.data?.id ?? "nil")")
        } else {
            print("[共享心愿] 同步失败, 无响应")
        }
        
        return result
    }
    
    /// 更新已有共享心愿清单（使用 update 接口，按 wish_group_id 过滤）
    ///
    /// - Parameters:
    ///   - wishGroupId: 已有的 wish_group_id
    ///   - sharedItems: 当前清单中的所有心愿
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "sharewish"
    /// - Returns: UpdateManyResponse（成功）或 nil
    @available(iOS 13.0, *)
    func updateSharedWishlist(
        wishGroupId: String,
        sharedItems: [SharedWishItem],
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> UpdateManyResponse? {
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
            if let purchaseLink = item.purchaseLink {
                info["purchaseLink"] = purchaseLink
            }
            if let details = item.details {
                info["details"] = details
            }
            if let completedBy = item.completedBy {
                info["completedBy"] = completedBy
            }
            if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
                info["imageUrl"] = imageUrl
            }
            return info
        }
        
        let wishInfoObject: [String: Any] = ["items": wishInfoArray]
        
        let path = "/v1/model/\(envType)/\(modelName)/update"
        let payload: [String: Any] = [
            "data": [
                "wish_group_id": wishGroupId,
                "wishinfo": wishInfoObject
            ],
            "filter": [
                "where": [
                    "wish_group_id": ["$eq": wishGroupId]
                ]
            ]
        ]
        
        print("[共享心愿] 更新共享清单: wish_group_id=\(wishGroupId), 心愿数量=\(sharedItems.count)")
        
        let result: UpdateManyResponse? = await request(
            method: "PUT",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 更新响应: code=\(result.code?.stringValue ?? "nil"), count=\(result.data?.count ?? 0)")
        } else {
            print("[共享心愿] 更新失败, 无响应")
        }
        
        return result
    }
    
    // MARK: - 用户信息（userinfo model）
    
    /// 查询 userinfo 的响应模型
    struct FetchUserInfoResponse: Codable {
        let code: FlexibleCode?
        let message: String?
        let data: FetchUserInfoData?
        
        struct FetchUserInfoData: Codable {
            let records: [UserInfoRecord]?
            let total: Int?
        }
        
        struct UserInfoRecord: Codable {
            let _id: String?
            let share_wish_list: [String]?
            let vip_type: VIPTypeInfo?
            let third_info: ThirdInfoData?
        }
        
        struct ThirdInfoData: Codable {
            let provider: String?
            let userId: String?
            let email: String?
            let name: String?
            let identityToken: String?
            let authorizationCode: String?
            let loginTime: String?
        }
        
        /// VIP 信息 JSON 结构
        /// vip_type: 0=免费用户, 1=VIP, 2=MasterVIP
        struct VIPTypeInfo: Codable {
            let type: Int?           // 0: 免费用户, 1: VIP, 2: MasterVIP
            let startDate: String?   // 开启时间 ISO8601
            let expireDate: String?  // 到期时间 ISO8601
        }
    }
    
    /// 查询当前用户的 userinfo 记录
    @available(iOS 13.0, *)
    func fetchUserInfo(
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async -> FetchUserInfoResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/list"
        let payload: [String: Any] = [
            "pageSize": 10,
            "pageNumber": 1,
            "getCount": true
        ]
        
        print("[userinfo] 查询用户信息...")
        
        let result: FetchUserInfoResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            let count = result.data?.records?.count ?? 0
            print("[userinfo] 查询结果: code=\(result.code?.stringValue ?? "nil"), 记录数=\(count)")
        } else {
            print("[userinfo] 查询失败, 无响应")
        }
        
        return result
    }
    
    /// 创建 userinfo 记录（首次，share_wish_list 为数组）
    @available(iOS 13.0, *)
    func createUserInfo(
        shareWishList: [String],
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async -> CreateResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/create"
        let payload: [String: Any] = [
            "data": [
                "share_wish_list": shareWishList
            ]
        ]
        
        print("[userinfo] 创建用户信息, share_wish_list=\(shareWishList)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[userinfo] 创建响应: code=\(result.code?.stringValue ?? "nil"), id=\(result.data?.id ?? "nil")")
        } else {
            print("[userinfo] 创建失败, 无响应")
        }
        
        return result
    }
    
    /// 更新 userinfo 的 share_wish_list 字段（push 或整体覆盖）
    @available(iOS 13.0, *)
    func updateUserInfoShareWishList(
        dataId: String,
        shareWishList: [String],
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async -> UpdateManyResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/update"
        let payload: [String: Any] = [
            "data": [
                "share_wish_list": shareWishList
            ],
            "filter": [
                "where": [
                    "_id": ["$eq": dataId]
                ]
            ]
        ]
        
        print("[userinfo] 更新 share_wish_list: dataId=\(dataId), list=\(shareWishList)")
        
        let result: UpdateManyResponse? = await request(
            method: "PUT",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[userinfo] 更新响应: code=\(result.code?.stringValue ?? "nil"), count=\(result.data?.count ?? 0)")
        } else {
            print("[userinfo] 更新失败, 无响应")
        }
        
        return result
    }
    
    /// 同步 share_wish_list：查询 userinfo，存在则 push/delete，不存在则 create
    ///
    /// - Parameters:
    ///   - wishGroupId: 要操作的 wish_group_id
    ///   - action: "push" 添加，"delete" 移除
    @available(iOS 13.0, *)
    func syncUserInfoShareWishList(
        wishGroupId: String,
        action: String = "push"
    ) async {
        let response = await fetchUserInfo()
        
        if let records = response?.data?.records, let record = records.first,
           let dataId = record._id {
            // 记录已存在，更新 share_wish_list
            var currentList = record.share_wish_list ?? []
            
            if action == "push" {
                if !currentList.contains(wishGroupId) {
                    currentList.append(wishGroupId)
                }
            } else if action == "delete" {
                currentList.removeAll { $0 == wishGroupId }
            }
            
            let _ = await updateUserInfoShareWishList(
                dataId: dataId,
                shareWishList: currentList
            )
        } else {
            // 记录不存在，创建新记录
            if action == "push" {
                let _ = await createUserInfo(shareWishList: [wishGroupId])
            }
        }
    }
    
    // MARK: - 第三方登录信息同步
    
    /// 更新 userinfo 的 third_info 字段（保存第三方登录信息）
    @available(iOS 13.0, *)
    func updateUserInfoThirdInfo(
        thirdInfo: [String: Any],
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async {
        // 先获取 userinfo 记录
        let response = await fetchUserInfo(envType: envType, modelName: modelName)
        
        if let records = response?.data?.records, let record = records.first, let dataId = record._id {
            // 记录存在，更新 third_info
            let path = "/v1/model/\(envType)/\(modelName)/update"
            let payload: [String: Any] = [
                "data": [
                    "third_info": thirdInfo
                ],
                "filter": [
                    "where": [
                        "_id": ["$eq": dataId]
                    ]
                ]
            ]
            
            print("[userinfo] 更新 third_info: \(thirdInfo)")
            
            let result: UpdateManyResponse? = await request(
                method: "POST",
                path: path,
                body: payload
            )
            
            if let result = result {
                print("[userinfo] third_info 更新结果: code=\(result.code?.stringValue ?? "nil")")
            } else {
                print("[userinfo] third_info 更新失败")
            }
        } else {
            // 记录不存在，创建新记录并带上 third_info
            let path = "/v1/model/\(envType)/\(modelName)/create"
            let payload: [String: Any] = [
                "data": [
                    "share_wish_list": [String](),
                    "third_info": thirdInfo
                ]
            ]
            
            print("[userinfo] 创建用户信息（含 third_info）")
            
            let result: CreateResponse? = await request(
                method: "POST",
                path: path,
                body: payload
            )
            
            if let result = result {
                print("[userinfo] 创建响应: code=\(result.code?.stringValue ?? "nil"), id=\(result.data?.id ?? "nil")")
            }
        }
    }
    
    // MARK: - VIP 信息同步
    
    /// 更新 userinfo 的 vip_type 字段
    @available(iOS 13.0, *)
    func updateUserInfoVIPType(
        dataId: String,
        vipType: Int,
        startDate: String,
        expireDate: String,
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async -> UpdateManyResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/update"
        let vipInfo: [String: Any] = [
            "type": vipType,
            "startDate": startDate,
            "expireDate": expireDate
        ]
        let payload: [String: Any] = [
            "data": [
                "vip_type": vipInfo
            ],
            "filter": [
                "where": [
                    "_id": ["$eq": dataId]
                ]
            ]
        ]
        
        print("[userinfo] 更新 vip_type: dataId=\(dataId), type=\(vipType)")
        
        let result: UpdateManyResponse? = await request(
            method: "PUT",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[userinfo] VIP 更新响应: code=\(result.code?.stringValue ?? "nil"), count=\(result.data?.count ?? 0)")
        } else {
            print("[userinfo] VIP 更新失败, 无响应")
        }
        
        return result
    }
    
    /// 同步 VIP 信息到 userinfo：查询 userinfo，存在则更新 vip_type，不存在则创建
    @available(iOS 13.0, *)
    func syncVIPInfo(
        vipType: Int,
        startDate: Date,
        expireDate: Date
    ) async {
        let isoFormatter = ISO8601DateFormatter()
        let startStr = isoFormatter.string(from: startDate)
        let expireStr = isoFormatter.string(from: expireDate)
        
        let response = await fetchUserInfo()
        
        if let records = response?.data?.records, let record = records.first,
           let dataId = record._id {
            let _ = await updateUserInfoVIPType(
                dataId: dataId,
                vipType: vipType,
                startDate: startStr,
                expireDate: expireStr
            )
        } else {
            // 记录不存在，创建新记录并带上 vip_type
            let _ = await createUserInfoWithVIP(
                vipType: vipType,
                startDate: startStr,
                expireDate: expireStr
            )
        }
    }
    
    /// 创建 userinfo 记录（包含 vip_type）
    @available(iOS 13.0, *)
    func createUserInfoWithVIP(
        vipType: Int,
        startDate: String,
        expireDate: String,
        envType: String = "prod",
        modelName: String = "userinfo"
    ) async -> CreateResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/create"
        let vipInfo: [String: Any] = [
            "type": vipType,
            "startDate": startDate,
            "expireDate": expireDate
        ]
        let payload: [String: Any] = [
            "data": [
                "share_wish_list": [String](),
                "vip_type": vipInfo
            ]
        ]
        
        print("[userinfo] 创建用户信息(含VIP), type=\(vipType)")
        
        let result: CreateResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[userinfo] 创建响应: code=\(result.code?.stringValue ?? "nil"), id=\(result.data?.id ?? "nil")")
        } else {
            print("[userinfo] 创建失败, 无响应")
        }
        
        return result
    }
    
    /// 按 wish_group_id 查询共享心愿清单
    ///
    /// - Parameters:
    ///   - wishGroupId: 要查询的清单 ID
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "sharewish"
    /// - Returns: FetchSharedWishlistResponse 或 nil
    @available(iOS 13.0, *)
    func fetchSharedWishlistByGroupId(
        wishGroupId: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> FetchSharedWishlistResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/list"
        let payload: [String: Any] = [
            "pageSize": 10,
            "pageNumber": 1,
            "getCount": true,
            "filter": [
                "where": [
                    "wish_group_id": ["$eq": wishGroupId]
                ]
            ]
        ]
        
        print("[共享心愿] 查询好友清单: wish_group_id=\(wishGroupId)")
        
        let result: FetchSharedWishlistResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            let count = result.data?.records?.count ?? 0
            print("[共享心愿] 查询结果: code=\(result.code?.stringValue ?? "nil"), 记录数=\(count)")
        } else {
            print("[共享心愿] 查询失败, 无响应")
        }
        
        return result
    }
    
    /// 查询共享心愿清单的响应模型
    struct FetchSharedWishlistResponse: Codable {
        let code: FlexibleCode?
        let message: String?
        let data: FetchSharedWishlistData?
        
        struct FetchSharedWishlistData: Codable {
            let records: [SharedWishRecord]?
            let total: Int?
        }
        
        struct SharedWishRecord: Codable {
            let _id: String?
            let wish_group_id: String?
            let name: String?
            let emoji: String?
            let owner_name: String?
            let wishinfo: WishInfoObject?
            let members: [String]?
            let numbers: NumbersObject?
        }
        
        struct NumbersObject: Codable {
            let number_list: [NumberItem]?
        }
        
        struct NumberItem: Codable {
            let number_name: String?
            let number_id: String?
        }
        
        struct WishInfoObject: Codable {
            let items: [RemoteSharedWishItem]?
        }
        
        struct RemoteSharedWishItem: Codable {
            let id: String?
            let name: String?
            let price: Double?
            let isCompleted: Bool?
            let displayType: String?
            let sourceItemId: String?
            let purchaseLink: String?
            let details: String?
            let completedBy: String?
            let imageBase64: String?  // 旧数据兼容
            let imageUrl: String?     // 新数据
        }
    }
    
    // MARK: - 删除远端共享心愿清单
    
    /// 共享心愿清单同步结果
    struct SharedWishlistSyncResult {
        let remoteItems: [SharedWishItem]  // merge 后的心愿列表
        let remoteName: String?
        let remoteEmoji: String?
        let remoteOwnerName: String?
        let pushSuccess: Bool
    }
    
    /// 同步共享心愿清单（pull -> merge -> push）
    ///
    /// 同步逻辑：
    /// 1. 从远端拉取该 wish_group_id 的最新数据
    /// 2. 将远端数据与本地数据 merge（按心愿 name 匹配）
    ///    - 远端有、本地有：以本地 isCompleted 为准（本地操作优先）
    ///    - 远端有、本地没有：添加到本地（远端新增的心愿）
    ///    - 远端没有、本地有：保留本地（本地新增的心愿）
    /// 3. 将 merge 后的完整列表推送到远端
    /// 4. 返回 merge 后的结果供本地展示
    @available(iOS 13.0, *)
    func syncSharedWishlist(
        wishGroupId: String,
        localItems: [SharedWishItem],
        listName: String,
        listEmoji: String,
        isOwner: Bool = true
    ) async -> SharedWishlistSyncResult? {
        // Step 1: 拉取远端数据
        print("[共享心愿同步] Step 1: 拉取远端数据, wish_group_id=\(wishGroupId)")
        let response = await fetchSharedWishlistByGroupId(wishGroupId: wishGroupId)
        
        guard let record = response?.data?.records?.first, let docId = record._id else {
            print("[共享心愿同步] 远端无数据，跳过 merge，直接 push 本地数据")
            // 远端没有数据，直接 push 本地（使用 REST API 的 update 接口）
            let pushResult = await updateSharedWishlist(
                wishGroupId: wishGroupId,
                sharedItems: localItems
            )
            let success = pushResult != nil
            return SharedWishlistSyncResult(
                remoteItems: localItems,
                remoteName: nil,
                remoteEmoji: nil,
                remoteOwnerName: nil,
                pushSuccess: success
            )
        }
        
        let remoteWishItems = record.wishinfo?.items ?? []
        print("[共享心愿同步] 远端共 \(remoteWishItems.count) 个心愿，本地共 \(localItems.count) 个心愿")
        
        // Step 2: Merge 逻辑
        // 构建本地字典：按 name 索引
        var localMap: [String: SharedWishItem] = [:]
        for item in localItems {
            localMap[item.name] = item
        }
        
        // 构建远端字典：按 name 索引
        var remoteMap: [String: FetchSharedWishlistResponse.RemoteSharedWishItem] = [:]
        for item in remoteWishItems {
            if let name = item.name {
                remoteMap[name] = item
            }
        }
        
        var mergedItems: [SharedWishItem] = []
        var processedNames: Set<String> = []
        
        // 2a. 遍历本地心愿
        for localItem in localItems {
            processedNames.insert(localItem.name)
            if let remote = remoteMap[localItem.name] {
                // 远端有、本地有：合并（以本地 isCompleted 为准，远端的其他字段如 purchaseLink/details 取最新）
                var merged = localItem
                // 如果本地没有 purchaseLink 但远端有，取远端的
                if merged.purchaseLink == nil, let remotePL = remote.purchaseLink {
                    merged.purchaseLink = remotePL
                }
                // 如果本地没有 details 但远端有，取远端的
                if merged.details == nil, let remoteDetails = remote.details {
                    merged.details = remoteDetails
                }
                // 如果本地没有 displayType 但远端有，取远端的
                if merged.displayType == nil, let remoteType = remote.displayType {
                    merged.displayType = remoteType
                }
                // 如果本地没有 completedBy 但远端有，取远端的
                if merged.completedBy == nil, let remoteCompletedBy = remote.completedBy {
                    merged.completedBy = remoteCompletedBy
                }
                // 如果本地没有 imageUrl 但远端有，取远端的
                if merged.imageUrl == nil {
                    if let remoteImageUrl = remote.imageUrl, !remoteImageUrl.isEmpty {
                        merged.imageUrl = remoteImageUrl
                    } else if let remoteImageBase64 = remote.imageBase64, !remoteImageBase64.isEmpty {
                        // 旧数据兼容：从 base64 解码
                        merged.imageData = Data(base64Encoded: remoteImageBase64)
                    }
                }
                // 如果本地没有 sourceItemId 但远端有，恢复关联
                if merged.sourceItemId == nil, let remoteSid = remote.sourceItemId, !remoteSid.isEmpty {
                    merged.sourceItemId = UUID(uuidString: remoteSid)
                }
                print("[共享心愿同步] Merge 保留本地: \(localItem.name), isCompleted=\(merged.isCompleted)")
                mergedItems.append(merged)
            } else {
                // 远端没有、本地有：保留本地新增
                print("[共享心愿同步] 本地独有: \(localItem.name)")
                mergedItems.append(localItem)
            }
        }
        
        // 2b. 遍历远端心愿，找出远端独有的
        for remoteItem in remoteWishItems {
            guard let name = remoteItem.name, !processedNames.contains(name) else { continue }
            // Owner push 同步：本地没有但远端有 = 本地删除了，不加回来
            if isOwner {
                print("[共享心愿同步] Owner 已删除，跳过远端: \(name)")
                continue
            }
            // 非 Owner：远端有、本地没有 → 添加到本地（owner 新增的心愿）
            var remoteImageUrl: String? = nil
            var remoteImageData: Data? = nil
            if let url = remoteItem.imageUrl, !url.isEmpty {
                remoteImageUrl = url
            } else if let base64Str = remoteItem.imageBase64, !base64Str.isEmpty {
                remoteImageData = Data(base64Encoded: base64Str)
            }
            let remoteSourceItemId: UUID? = {
                if let sid = remoteItem.sourceItemId, !sid.isEmpty {
                    return UUID(uuidString: sid)
                }
                return nil
            }()
            let newItem = SharedWishItem(
                sourceItemId: remoteSourceItemId,
                name: name,
                price: remoteItem.price ?? 0,
                isCompleted: remoteItem.isCompleted ?? false,
                displayType: remoteItem.displayType,
                imageUrl: remoteImageUrl,
                imageData: remoteImageData,
                purchaseLink: remoteItem.purchaseLink,
                details: remoteItem.details,
                completedBy: remoteItem.completedBy
            )
            print("[共享心愿同步] 远端独有: \(name)")
            mergedItems.append(newItem)
        }
        
        print("[共享心愿同步] Merge 完成: 合并后共 \(mergedItems.count) 个心愿")
        
        // Step 3: 使用云函数 update_sharewish 提交 merge 结果到远端
        // 之前使用 REST API PUT /v1/model/.../update 解码可能失败，改用可靠的云函数
        print("[共享心愿同步] Step 3: 通过云函数提交 merge 结果到远端, docId=\(docId)")
        
        let wishInfoArray: [[String: Any]] = mergedItems.map { item in
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
            if let purchaseLink = item.purchaseLink {
                info["purchaseLink"] = purchaseLink
            }
            if let details = item.details {
                info["details"] = details
            }
            if let completedBy = item.completedBy {
                info["completedBy"] = completedBy
            }
            if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
                info["imageUrl"] = imageUrl
            }
            return info
        }
        
        let pushResponse = await callFunction(
            functionName: "update_sharewish",
            data: [
                "docId": docId,
                "modelName": "sharewish",
                "updateData": ["wishinfo": ["items": wishInfoArray]]
            ]
        )
        
        // 云函数返回 {"code": 0, "message": "更新成功"} 表示成功
        let pushCode = pushResponse?["code"]
        let success: Bool
        if let codeInt = pushCode as? Int {
            success = (codeInt == 0)
        } else if let codeStr = pushCode as? String {
            success = (codeStr == "0" || codeStr == "SUCCESS")
        } else {
            // 如果云函数返回了响应但没有 code 字段，也视为成功（HTTP 200 + 有响应）
            success = (pushResponse != nil)
        }
        print("[共享心愿同步] Push 结果: \(success ? "成功" : "失败"), code=\(String(describing: pushCode))")
        
        return SharedWishlistSyncResult(
            remoteItems: mergedItems,
            remoteName: record.name,
            remoteEmoji: record.emoji,
            remoteOwnerName: record.owner_name,
            pushSuccess: success
        )
    }
    
    struct DeleteResponse: Codable {
        let code: FlexibleCode?
        let message: String?
        let data: DeleteData?
        
        struct DeleteData: Codable {
            let count: Int?
        }
    }
    
    /// 按 wish_group_id 删除远端共享心愿清单
    ///
    /// - Parameters:
    ///   - wishGroupId: 要删除的清单 wish_group_id
    ///   - envType: 环境类型，默认为 "prod"
    ///   - modelName: 数据模型名称，默认为 "sharewish"
    /// - Returns: DeleteResponse 或 nil
    @available(iOS 13.0, *)
    func deleteSharedWishlist(
        wishGroupId: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> DeleteResponse? {
        let path = "/v1/model/\(envType)/\(modelName)/delete"
        let payload: [String: Any] = [
            "filter": [
                "where": [
                    "wish_group_id": ["$eq": wishGroupId]
                ]
            ]
        ]
        
        print("[共享心愿] 删除远端清单: wish_group_id=\(wishGroupId)")
        
        let result: DeleteResponse? = await request(
            method: "POST",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 删除结果: code=\(result.code?.stringValue ?? "nil"), count=\(result.data?.count ?? 0)")
        } else {
            print("[共享心愿] 删除失败, 无响应")
        }
        
        return result
    }
    
    // MARK: - 共享清单成员管理
    
    /// 将当前用户添加到共享清单的 members 列表和 numbers 字段
    /// 先查询远端 members/numbers，如果不包含该用户则追加
    @available(iOS 13.0, *)
    func addMemberToSharedWishlist(
        wishGroupId: String,
        memberName: String,
        memberId: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async {
        // 先拉取当前记录
        let response = await fetchSharedWishlistByGroupId(wishGroupId: wishGroupId, envType: envType, modelName: modelName)
        guard let record = response?.data?.records?.first else {
            print("[共享心愿] 无法查询到清单，跳过添加成员")
            return
        }
        
        var currentMembers = record.members ?? []
        var currentNumberList = record.numbers?.number_list?.map { item in
            ["number_name": item.number_name ?? "", "number_id": item.number_id ?? ""]
        } ?? []
        
        let alreadyInMembers = currentMembers.contains(memberName)
        let alreadyInNumbers = currentNumberList.contains { $0["number_id"] == memberId }
        
        guard !alreadyInMembers || !alreadyInNumbers else {
            print("[共享心愿] 成员 \(memberName) 已存在，跳过")
            return
        }
        
        if !alreadyInMembers {
            currentMembers.append(memberName)
        }
        if !alreadyInNumbers {
            currentNumberList.append(["number_name": memberName, "number_id": memberId])
        }
        
        let numbersObject: [String: Any] = ["number_list": currentNumberList]
        
        let path = "/v1/model/\(envType)/\(modelName)/update"
        let payload: [String: Any] = [
            "data": [
                "members": currentMembers,
                "numbers": numbersObject
            ],
            "filter": [
                "where": [
                    "wish_group_id": ["$eq": wishGroupId]
                ]
            ]
        ]
        
        print("[共享心愿] 添加成员 \(memberName)(\(memberId)) 到清单 \(wishGroupId)")
        
        let result: UpdateManyResponse? = await request(
            method: "PUT",
            path: path,
            body: payload
        )
        
        if let result = result {
            print("[共享心愿] 添加成员结果: code=\(result.code?.stringValue ?? "nil"), count=\(result.data?.count ?? 0)")
        } else {
            print("[共享心愿] 添加成员失败")
        }
    }
    
    // MARK: - 云存储
    
    /// 上传文件到云存储
    ///
    /// 流程：
    /// 1. 调用 `/v1/storages/get-objects-upload-info` 获取上传凭证和 URL
    /// 2. 使用返回的 uploadUrl、authorization、token 等信息，通过 PUT 请求上传文件
    /// 3. 上传成功后返回 cloudObjectId、downloadUrl、objectId
    ///
    /// - Parameters:
    ///   - filePath: 文件路径（本地文件 URL 字符串）
    ///   - objectId: 云端存储路径（可选，默认自动生成 uploads/{timestamp}-{filename}）
    ///   - completion: 上传结果回调，成功返回包含 cloudObjectId/downloadUrl/objectId 的字典，失败返回 nil
    func uploadFile(
        filePath: String,
        objectId: String? = nil,
        completion: @escaping ([String: String]?) -> Void
    ) {
        // 读取文件数据
        guard let fileUrl = URL(string: filePath),
              let fileData = try? Data(contentsOf: fileUrl) else {
            print("[云存储] 文件不存在: \(filePath)")
            completion(nil)
            return
        }
        
        let filename = fileUrl.lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let finalObjectId = objectId ?? "uploads/\(timestamp)-\(filename)"
        
        // Step 1: 获取上传信息
        guard let infoUrl = URL(string: "\(baseUrl)/v1/storages/get-objects-upload-info") else {
            print("[云存储] 无效的URL")
            completion(nil)
            return
        }
        
        var infoRequest = URLRequest(url: infoUrl)
        infoRequest.httpMethod = "POST"
        infoRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        infoRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        infoRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let bodyArray: [[String: String]] = [["objectId": finalObjectId]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else {
            print("[云存储] JSON序列化失败")
            completion(nil)
            return
        }
        infoRequest.httpBody = bodyData
        
        print("\n========== 云存储 获取上传信息 ==========")
        print("[云存储] objectId: \(finalObjectId)")
        print("==========================================\n")
        
        let infoTask = URLSession.shared.dataTask(with: infoRequest) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                print("[云存储] 获取上传信息失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode), let data = data else {
                print("[云存储] 获取上传信息失败, 状态码: \(statusCode)")
                completion(nil)
                return
            }
            
            // 解析响应（可能是数组或字典包含数组）
            guard let uploadInfoArray = self.parseUploadInfoResponse(data: data),
                  !uploadInfoArray.isEmpty else {
                print("[云存储] 解析上传信息失败")
                completion(nil)
                return
            }
            
            let info = uploadInfoArray[0]
            guard let uploadUrl = info["uploadUrl"] as? String,
                  let authorization = info["authorization"] as? String,
                  let token = info["token"] as? String,
                  let cloudObjectMeta = info["cloudObjectMeta"] as? String else {
                print("[云存储] 上传信息缺少必要字段")
                completion(nil)
                return
            }
            
            // Step 2: 上传文件
            guard let url = URL(string: uploadUrl) else {
                print("[云存储] 无效的上传URL")
                completion(nil)
                return
            }
            
            var uploadRequest = URLRequest(url: url)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
            uploadRequest.setValue(token, forHTTPHeaderField: "X-Cos-Security-Token")
            uploadRequest.setValue(cloudObjectMeta, forHTTPHeaderField: "X-Cos-Meta-Fileid")
            uploadRequest.httpBody = fileData
            
            print("\n========== 云存储 上传文件 ==========")
            print("[云存储] 上传URL: \(uploadUrl)")
            print("[云存储] 文件大小: \(fileData.count) bytes")
            print("======================================\n")
            
            let uploadTask = URLSession.shared.dataTask(with: uploadRequest) { _, uploadResponse, uploadError in
                if let uploadError = uploadError {
                    print("[云存储] 文件上传失败: \(uploadError.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let httpResponse = uploadResponse as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (uploadResponse as? HTTPURLResponse)?.statusCode ?? -1
                    print("[云存储] 文件上传失败, 状态码: \(code)")
                    completion(nil)
                    return
                }
                
                let result = [
                    "cloudObjectId": info["cloudObjectId"] as? String ?? "",
                    "downloadUrl": info["downloadUrl"] as? String ?? "",
                    "objectId": finalObjectId
                ]
                
                print("[云存储] 文件上传成功:")
                print("  - 对象ID: \(result["objectId"] ?? "")")
                print("  - 下载URL: \(result["downloadUrl"] ?? "")")
                print("  - cloudObjectId: \(result["cloudObjectId"] ?? "")")
                
                completion(result)
            }
            
            uploadTask.resume()
        }
        
        infoTask.resume()
    }
    
    /// 解析 get-objects-upload-info 的响应
    /// 兼容返回格式为纯数组 `[{...}]` 或字典包裹 `{"data": [{...}]}` 的情况
    private func parseUploadInfoResponse(data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        
        if let array = json as? [[String: Any]] {
            return array
        }
        
        if let dict = json as? [String: Any] {
            if let dataArray = dict["data"] as? [[String: Any]] {
                return dataArray
            }
        }
        
        return nil
    }
    
    /// 上传文件到云存储（async/await 版本）
    ///
    /// - Parameters:
    ///   - filePath: 文件路径（本地文件 URL 字符串）
    ///   - objectId: 云端存储路径（可选，默认自动生成）
    /// - Returns: 包含 cloudObjectId/downloadUrl/objectId 的字典，失败返回 nil
    @available(iOS 13.0, *)
    func uploadFile(
        filePath: String,
        objectId: String? = nil
    ) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            uploadFile(filePath: filePath, objectId: objectId) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// 从 Data 直接上传到云存储（无需本地文件路径）
    ///
    /// - Parameters:
    ///   - data: 文件数据
    ///   - filename: 文件名（如 "photo.jpg"）
    ///   - objectId: 云端存储路径（可选，默认自动生成 uploads/{timestamp}-{filename}）
    ///   - completion: 上传结果回调
    func uploadData(
        data fileData: Data,
        filename: String,
        objectId: String? = nil,
        completion: @escaping ([String: String]?) -> Void
    ) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let finalObjectId = objectId ?? "uploads/\(timestamp)-\(filename)"
        
        // Step 1: 获取上传信息
        guard let infoUrl = URL(string: "\(baseUrl)/v1/storages/get-objects-upload-info") else {
            print("[云存储] 无效的URL")
            completion(nil)
            return
        }
        
        var infoRequest = URLRequest(url: infoUrl)
        infoRequest.httpMethod = "POST"
        infoRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        infoRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        infoRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let bodyArray: [[String: String]] = [["objectId": finalObjectId]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else {
            print("[云存储] JSON序列化失败")
            completion(nil)
            return
        }
        infoRequest.httpBody = bodyData
        
        print("[云存储] 获取上传信息, objectId: \(finalObjectId)")
        
        let infoTask = URLSession.shared.dataTask(with: infoRequest) { data, response, error in
            if let error = error {
                print("[云存储] 获取上传信息失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode), let data = data else {
                print("[云存储] 获取上传信息失败, 状态码: \(statusCode)")
                completion(nil)
                return
            }
            
            guard let uploadInfoArray = self.parseUploadInfoResponse(data: data),
                  !uploadInfoArray.isEmpty else {
                print("[云存储] 解析上传信息失败")
                completion(nil)
                return
            }
            
            let info = uploadInfoArray[0]
            guard let uploadUrl = info["uploadUrl"] as? String,
                  let authorization = info["authorization"] as? String,
                  let token = info["token"] as? String,
                  let cloudObjectMeta = info["cloudObjectMeta"] as? String else {
                print("[云存储] 上传信息缺少必要字段")
                completion(nil)
                return
            }
            
            // Step 2: 上传文件
            guard let url = URL(string: uploadUrl) else {
                completion(nil)
                return
            }
            
            var uploadRequest = URLRequest(url: url)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
            uploadRequest.setValue(token, forHTTPHeaderField: "X-Cos-Security-Token")
            uploadRequest.setValue(cloudObjectMeta, forHTTPHeaderField: "X-Cos-Meta-Fileid")
            uploadRequest.httpBody = fileData
            
            let uploadTask = URLSession.shared.dataTask(with: uploadRequest) { _, uploadResponse, uploadError in
                if let uploadError = uploadError {
                    print("[云存储] 文件上传失败: \(uploadError.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let httpResponse = uploadResponse as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    print("[云存储] 文件上传失败")
                    completion(nil)
                    return
                }
                
                let result = [
                    "cloudObjectId": info["cloudObjectId"] as? String ?? "",
                    "downloadUrl": info["downloadUrl"] as? String ?? "",
                    "objectId": finalObjectId
                ]
                
                print("[云存储] 文件上传成功: \(result["downloadUrl"] ?? "")")
                completion(result)
            }
            
            uploadTask.resume()
        }
        
        infoTask.resume()
    }
    
    /// 从 Data 直接上传到云存储（async/await 版本）
    @available(iOS 13.0, *)
    func uploadData(
        data: Data,
        filename: String,
        objectId: String? = nil
    ) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            uploadData(data: data, filename: filename, objectId: objectId) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - 批量上传
    
    /// 上传项：描述一个待上传的文件
    struct UploadItem {
        let data: Data                          // 文件数据
        let objectId: String                    // 云端存储路径
        let signedHeader: [String: [String]]?   // 可选的签名头（如 content-md5）
        
        init(data: Data, objectId: String, signedHeader: [String: [String]]? = nil) {
            self.data = data
            self.objectId = objectId
            self.signedHeader = signedHeader
        }
        
        /// 便捷构造：自动生成 objectId
        init(data: Data, filename: String, signedHeader: [String: [String]]? = nil) {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            self.data = data
            self.objectId = "uploads/\(timestamp)-\(filename)"
            self.signedHeader = signedHeader
        }
    }
    
    /// 上传结果
    struct UploadResult {
        let objectId: String
        let cloudObjectId: String
        let downloadUrl: String
        let success: Bool
        let error: String?
    }
    
    /// 批量上传多个文件到云存储
    ///
    /// 流程（参考 Python 示例的 list 方式）：
    /// 1. 一次性调用 `/v1/storages/get-objects-upload-info`，传入所有文件的 objectId 数组
    /// 2. 服务端返回每个文件各自的上传凭证（uploadUrl、authorization、token 等）
    /// 3. 并发上传所有文件
    /// 4. 收集所有上传结果后统一回调
    ///
    /// - Parameters:
    ///   - items: 待上传的文件列表
    ///   - completion: 全部上传完成后回调，返回每个文件的上传结果
    func uploadFiles(
        items: [UploadItem],
        completion: @escaping ([UploadResult]) -> Void
    ) {
        guard !items.isEmpty else {
            completion([])
            return
        }
        
        // Step 1: 构造批量请求 body（支持 signedHeader）
        // 格式参考 Python 示例：[{"objectId": "xxx", "signedHeader": {"content-md5": ["xxx"]}}]
        var bodyArray: [[String: Any]] = []
        for item in items {
            var entry: [String: Any] = ["objectId": item.objectId]
            if let signedHeader = item.signedHeader {
                entry["signedHeader"] = signedHeader
            }
            bodyArray.append(entry)
        }
        
        guard let infoUrl = URL(string: "\(baseUrl)/v1/storages/get-objects-upload-info") else {
            print("[云存储] 无效的URL")
            completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "无效的URL") })
            return
        }
        
        var infoRequest = URLRequest(url: infoUrl)
        infoRequest.httpMethod = "POST"
        infoRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        infoRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        infoRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else {
            print("[云存储] JSON序列化失败")
            completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "JSON序列化失败") })
            return
        }
        infoRequest.httpBody = bodyData
        
        print("\n========== 云存储 批量获取上传信息 ==========")
        print("[云存储] 文件数量: \(items.count)")
        for (i, item) in items.enumerated() {
            print("[云存储]  [\(i)] objectId: \(item.objectId), 大小: \(item.data.count) bytes")
        }
        print("=============================================\n")
        
        let infoTask = URLSession.shared.dataTask(with: infoRequest) { [weak self] data, response, error in
            guard let self = self else {
                completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "self released") })
                return
            }
            
            if let error = error {
                print("[云存储] 批量获取上传信息失败: \(error.localizedDescription)")
                completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: error.localizedDescription) })
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode), let data = data else {
                print("[云存储] 批量获取上传信息失败, 状态码: \(statusCode)")
                completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "HTTP \(statusCode)") })
                return
            }
            
            guard let uploadInfoArray = self.parseUploadInfoResponse(data: data) else {
                print("[云存储] 解析批量上传信息失败")
                completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "解析响应失败") })
                return
            }
            
            // 确保返回的凭证数量与请求数量一致
            guard uploadInfoArray.count == items.count else {
                print("[云存储] 返回凭证数量(\(uploadInfoArray.count))与请求数量(\(items.count))不匹配")
                completion(items.map { UploadResult(objectId: $0.objectId, cloudObjectId: "", downloadUrl: "", success: false, error: "凭证数量不匹配") })
                return
            }
            
            // Step 2: 并发上传所有文件
            let group = DispatchGroup()
            var results = Array(repeating: UploadResult(objectId: "", cloudObjectId: "", downloadUrl: "", success: false, error: "未执行"), count: items.count)
            let resultsLock = NSLock()
            
            for (index, item) in items.enumerated() {
                let info = uploadInfoArray[index]
                
                guard let uploadUrl = info["uploadUrl"] as? String,
                      let authorization = info["authorization"] as? String,
                      let token = info["token"] as? String,
                      let cloudObjectMeta = info["cloudObjectMeta"] as? String,
                      let url = URL(string: uploadUrl) else {
                    resultsLock.lock()
                    results[index] = UploadResult(
                        objectId: item.objectId,
                        cloudObjectId: info["cloudObjectId"] as? String ?? "",
                        downloadUrl: info["downloadUrl"] as? String ?? "",
                        success: false,
                        error: "上传信息缺少必要字段"
                    )
                    resultsLock.unlock()
                    continue
                }
                
                group.enter()
                
                var uploadRequest = URLRequest(url: url)
                uploadRequest.httpMethod = "PUT"
                uploadRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
                uploadRequest.setValue(token, forHTTPHeaderField: "X-Cos-Security-Token")
                uploadRequest.setValue(cloudObjectMeta, forHTTPHeaderField: "X-Cos-Meta-Fileid")
                uploadRequest.httpBody = item.data
                
                let uploadTask = URLSession.shared.dataTask(with: uploadRequest) { _, uploadResponse, uploadError in
                    defer { group.leave() }
                    
                    if let uploadError = uploadError {
                        print("[云存储] [\(index)] 上传失败: \(uploadError.localizedDescription)")
                        resultsLock.lock()
                        results[index] = UploadResult(
                            objectId: item.objectId,
                            cloudObjectId: info["cloudObjectId"] as? String ?? "",
                            downloadUrl: info["downloadUrl"] as? String ?? "",
                            success: false,
                            error: uploadError.localizedDescription
                        )
                        resultsLock.unlock()
                        return
                    }
                    
                    guard let httpResponse = uploadResponse as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let code = (uploadResponse as? HTTPURLResponse)?.statusCode ?? -1
                        print("[云存储] [\(index)] 上传失败, 状态码: \(code)")
                        resultsLock.lock()
                        results[index] = UploadResult(
                            objectId: item.objectId,
                            cloudObjectId: info["cloudObjectId"] as? String ?? "",
                            downloadUrl: info["downloadUrl"] as? String ?? "",
                            success: false,
                            error: "HTTP \(code)"
                        )
                        resultsLock.unlock()
                        return
                    }
                    
                    resultsLock.lock()
                    results[index] = UploadResult(
                        objectId: item.objectId,
                        cloudObjectId: info["cloudObjectId"] as? String ?? "",
                        downloadUrl: info["downloadUrl"] as? String ?? "",
                        success: true,
                        error: nil
                    )
                    resultsLock.unlock()
                    
                    print("[云存储] [\(index)] 上传成功: \(item.objectId)")
                }
                
                uploadTask.resume()
            }
            
            // 等待所有上传完成
            group.notify(queue: .main) {
                let successCount = results.filter { $0.success }.count
                print("\n[云存储] 批量上传完成: \(successCount)/\(items.count) 成功\n")
                completion(results)
            }
        }
        
        infoTask.resume()
    }
    
    /// 批量上传文件到云存储（async/await 版本）
    @available(iOS 13.0, *)
    func uploadFiles(items: [UploadItem]) async -> [UploadResult] {
        await withCheckedContinuation { continuation in
            uploadFiles(items: items) { results in
                continuation.resume(returning: results)
            }
        }
    }
    
    // MARK: - 云存储删除
    
    /// 删除云存储中的对象
    /// - Parameter cloudObjectIds: 云端对象 ID 数组，格式为 cloud://envId.bucket/path
    @available(iOS 13.0, *)
    func deleteStorageObjects(cloudObjectIds: [String]) async -> Bool {
        guard !cloudObjectIds.isEmpty else { return true }
        
        guard let url = URL(string: "\(baseUrl)/v1/storages/delete-objects") else {
            print("[云存储] 删除：无效的URL")
            return false
        }
        
        let bodyArray = cloudObjectIds.map { ["cloudObjectId": $0] }
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else {
            print("[云存储] 删除：JSON序列化失败")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        print("[云存储] 删除 \(cloudObjectIds.count) 个对象: \(cloudObjectIds)")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let success = (200...299).contains(statusCode)
            print("[云存储] 删除结果: \(success ? "成功" : "失败(HTTP \(statusCode))")")
            return success
        } catch {
            print("[云存储] 删除失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 通过 objectId 获取对应的 cloudObjectId（用于删除）
    @available(iOS 13.0, *)
    func getCloudObjectIds(objectIds: [String]) async -> [String: String] {
        guard !objectIds.isEmpty else { return [:] }
        guard let url = URL(string: "\(baseUrl)/v1/storages/get-objects-upload-info") else { return [:] }
        
        let bodyArray = objectIds.map { ["objectId": $0] }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else { return [:] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? -1) else { return [:] }
            guard let infoArray = parseUploadInfoResponse(data: data) else { return [:] }
            
            var result: [String: String] = [:]
            for info in infoArray {
                if let objectId = info["objectId"] as? String,
                   let cloudObjectId = info["cloudObjectId"] as? String {
                    result[objectId] = cloudObjectId
                }
            }
            return result
        } catch {
            return [:]
        }
    }
    
    // MARK: - 图片下载
    
    /// 批量获取云存储对象的下载 URL
    /// 调用 POST /v1/storages/get-objects-download-info
    ///
    /// - Parameter cloudObjectIds: 云端对象 ID 数组
    /// - Returns: [cloudObjectId: downloadUrl] 映射
    @available(iOS 13.0, *)
    func getObjectsDownloadInfo(cloudObjectIds: [String]) async -> [String: String] {
        guard !cloudObjectIds.isEmpty else { return [:] }
        
        guard let url = URL(string: "\(baseUrl)/v1/storages/get-objects-download-info") else {
            print("[图片下载] 无效的URL")
            return [:]
        }
        
        // 构造请求体: [{"cloudObjectId": "xxx"}, ...]
        let bodyArray = cloudObjectIds.map { ["cloudObjectId": $0] }
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyArray) else {
            print("[图片下载] JSON序列化失败")
            return [:]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        
        print("[图片下载] 请求下载信息，共 \(cloudObjectIds.count) 个对象")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            
            guard (200...299).contains(statusCode) else {
                print("[图片下载] 获取下载信息失败, 状态码: \(statusCode)")
                return [:]
            }
            
            // 解析响应：可能是数组 [{cloudObjectId, downloadUrl}] 或字典 {data: [...]}
            var resultMap: [String: String] = [:]
            
            if let json = try? JSONSerialization.jsonObject(with: data) {
                var items: [[String: Any]] = []
                if let array = json as? [[String: Any]] {
                    items = array
                } else if let dict = json as? [String: Any], let dataArray = dict["data"] as? [[String: Any]] {
                    items = dataArray
                }
                
                for item in items {
                    if let objectId = item["cloudObjectId"] as? String,
                       let downloadUrl = item["downloadUrl"] as? String,
                       !downloadUrl.isEmpty {
                        resultMap[objectId] = downloadUrl
                    }
                }
            }
            
            print("[图片下载] 获取到 \(resultMap.count) 个下载链接")
            return resultMap
        } catch {
            print("[图片下载] 请求失败: \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// 从 URL 下载图片数据
    ///
    /// - Parameter urlString: 图片下载链接
    /// - Returns: 图片 Data 或 nil
    @available(iOS 13.0, *)
    func downloadImageData(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else {
            print("[图片下载] 无效的图片URL: \(urlString)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode), !data.isEmpty else {
                print("[图片下载] 下载失败, 状态码: \(statusCode)")
                return nil
            }
            return data
        } catch {
            print("[图片下载] 下载失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 批量下载远端物品/心愿的图片
    /// 对比本地 imageUrl 与远端 imageUrl，不同则下载
    ///
    /// - Parameters:
    ///   - remoteItems: 远端物品列表（需包含 imageUrl）
    ///   - imageUrls: [item name: remote imageUrl] 映射
    /// - Returns: [item id string: downloaded imageData] 映射
    @available(iOS 13.0, *)
    func downloadRemoteImages(imageUrls: [String: String]) async -> [String: Data] {
        guard !imageUrls.isEmpty else { return [:] }
        
        print("[图片下载] 开始下载 \(imageUrls.count) 张远端图片...")
        
        var downloadedImages: [String: Data] = [:]
        
        // 并发下载所有图片
        await withTaskGroup(of: (String, Data?).self) { group in
            for (itemId, imageUrl) in imageUrls {
                group.addTask {
                    let data = await self.downloadImageData(from: imageUrl)
                    return (itemId, data)
                }
            }
            
            for await (itemId, data) in group {
                if let data = data {
                    downloadedImages[itemId] = data
                    print("[图片下载] ✅ 下载成功: \(itemId)")
                } else {
                    print("[图片下载] ❌ 下载失败: \(itemId)")
                }
            }
        }
        
        print("[图片下载] 批量下载完成: \(downloadedImages.count)/\(imageUrls.count) 成功")
        return downloadedImages
    }
    
    /// 获取共享清单的成员列表（优先从 numbers 字段读取名称，回退到 members）
    /// 当前用户会显示为 "xxx（我）"
    @available(iOS 13.0, *)
    func fetchSharedWishlistMembers(
        wishGroupId: String,
        envType: String = "prod",
        modelName: String = "sharewish"
    ) async -> [String] {
        let response = await fetchSharedWishlistByGroupId(wishGroupId: wishGroupId, envType: envType, modelName: modelName)
        guard let record = response?.data?.records?.first else { return [] }
        
        let currentUserId = TokenStorage.shared.getSub() ?? ""
        
        if let numberList = record.numbers?.number_list, !numberList.isEmpty {
            return numberList.compactMap { item -> String? in
                guard let name = item.number_name, !name.isEmpty else { return nil }
                if !currentUserId.isEmpty, item.number_id == currentUserId {
                    return "\(name)（我）"
                }
                return name
            }
        }
        return record.members ?? []
    }
    
    // MARK: - 储蓄投资同步（savinginfo 模型）
    
    /// 同步储蓄投资数据到云端
    /// savinginfo 模型字段：iteminfo(Json), salaryinfo(Json), anotherinfo(Json), assetsinfo(Json)
    /// - iteminfo: 非工资的 FinanceRecord 数组 JSON
    /// - salaryinfo: 工资配置的 FinanceRecord JSON
    /// - anotherinfo: SavingsGoal JSON
    /// - assetsinfo: 资产汇总信息 JSON (totalAssets等)
    @available(iOS 13.0, *)
    func syncSavingInfo(
        records: [FinanceRecord],
        salaryRecord: FinanceRecord?,
        goal: SavingsGoal,
        totalAssets: Double,
        envType: String = "prod",
        modelName: String = "savinginfo"
    ) async -> Bool {
        guard let sub = TokenStorage.shared.getSub(), !sub.isEmpty else {
            print("[储蓄同步] 无法获取用户 sub，取消同步")
            return false
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // 编码各字段为 JSON 字典
        var itemInfoValue: Any = NSNull()
        var salaryInfoValue: Any = NSNull()
        var anotherInfoValue: Any = NSNull()
        
        if let data = try? encoder.encode(records),
           let json = try? JSONSerialization.jsonObject(with: data) {
            itemInfoValue = ["items": json]
        }
        
        if let salary = salaryRecord,
           let data = try? encoder.encode(salary),
           let json = try? JSONSerialization.jsonObject(with: data) {
            salaryInfoValue = json
        }
        
        // 将 totalAssets 合并到 anotherinfo 中（与 SavingsGoal 一起存储）
        if let data = try? encoder.encode(goal),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["totalAssets"] = totalAssets
            anotherInfoValue = json
            print("[储蓄同步] 上传 anotherinfo: name=\(goal.name), target=\(goal.targetAmount), totalAssets=\(totalAssets)")
        } else {
            print("[储蓄同步] ⚠️ SavingsGoal 编码失败！")
        }
        
        // 先查询是否已有记录
        let listPath = "/v1/model/\(envType)/\(modelName)/list"
        let listPayload: [String: Any] = [
            "pageSize": 1,
            "pageNumber": 1,
            "getCount": true
        ]
        
        let listResponse: FetchItemsResponse? = await request(
            method: "POST",
            path: listPath,
            body: listPayload
        )
        
        let existingId = listResponse?.data?.records?.first?._id
        
        let saveData: [String: Any] = [
            "iteminfo": itemInfoValue,
            "salaryinfo": salaryInfoValue,
            "anotherinfo": anotherInfoValue
        ]
        
        if let docId = existingId {
            // 更新已有记录
            let updatePath = "/v1/model/\(envType)/\(modelName)/update"
            let payload: [String: Any] = [
                "data": saveData,
                "filter": [
                    "where": [
                        "_id": ["$eq": docId]
                    ]
                ]
            ]
            
            print("[储蓄同步] 更新远端记录: \(docId)")
            let result: UpdateManyResponse? = await request(method: "PUT", path: updatePath, body: payload)
            let success = result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || (result?.data?.count ?? 0) > 0
            print("[储蓄同步] 更新结果: \(success ? "成功" : "失败")")
            return success
        } else {
            // 创建新记录
            let createPath = "/v1/model/\(envType)/\(modelName)/create"
            let payload: [String: Any] = ["data": saveData]
            
            print("[储蓄同步] 创建远端记录")
            let result: CreateResponse? = await request(method: "POST", path: createPath, body: payload)
            let success = result?.code?.stringValue == "SUCCESS" || result?.code?.stringValue == "0" || result?.data?.id != nil
            print("[储蓄同步] 创建结果: \(success ? "成功" : "失败")")
            return success
        }
    }
    
    /// 从远端拉取储蓄投资数据
    @available(iOS 13.0, *)
    func fetchSavingInfo(
        envType: String = "prod",
        modelName: String = "savinginfo"
    ) async -> (records: [FinanceRecord], salaryRecord: FinanceRecord?, goal: SavingsGoal?, totalAssets: Double?)? {
        let listPath = "/v1/model/\(envType)/\(modelName)/list"
        let listPayload: [String: Any] = [
            "pageSize": 1,
            "pageNumber": 1,
            "getCount": true
        ]
        
        print("[储蓄同步] 拉取远端数据...")
        
        guard let url = URL(string: "\(baseUrl)\(listPath)") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        if let bodyData = try? JSONSerialization.data(withJSONObject: listPayload) {
            request.httpBody = bodyData
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode) else {
                print("[储蓄同步] 拉取失败, 状态码: \(statusCode)")
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let records = dataDict["records"] as? [[String: Any]],
                  let first = records.first else {
                print("[储蓄同步] 无远端数据")
                return nil
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            var financeRecords: [FinanceRecord] = []
            var salaryRecord: FinanceRecord? = nil
            var goal: SavingsGoal? = nil
            var totalAssets: Double? = nil
            
            if let itemInfo = first["iteminfo"] as? [String: Any],
               let itemsArray = itemInfo["items"],
               let itemData = try? JSONSerialization.data(withJSONObject: itemsArray) {
                financeRecords = (try? decoder.decode([FinanceRecord].self, from: itemData)) ?? []
            }
            
            if let salaryInfo = first["salaryinfo"], !(salaryInfo is NSNull),
               let salaryData = try? JSONSerialization.data(withJSONObject: salaryInfo) {
                salaryRecord = try? decoder.decode(FinanceRecord.self, from: salaryData)
            }
            
            // anotherinfo 中同时包含 SavingsGoal 和 totalAssets
            if let anotherInfo = first["anotherinfo"] as? [String: Any] {
                print("[储蓄同步] anotherinfo keys: \(anotherInfo.keys.sorted())")
                if let goalData = try? JSONSerialization.data(withJSONObject: anotherInfo) {
                    goal = try? decoder.decode(SavingsGoal.self, from: goalData)
                    print("[储蓄同步] SavingsGoal 解码: \(goal != nil ? "成功 name=\(goal!.name) target=\(goal!.targetAmount)" : "失败")")
                }
                // 从 anotherinfo 中提取 totalAssets
                if let assets = anotherInfo["totalAssets"] as? Double {
                    totalAssets = assets
                } else if let assets = anotherInfo["totalAssets"] as? Int {
                    totalAssets = Double(assets)
                } else if let assets = anotherInfo["totalAssets"] as? NSNumber {
                    totalAssets = assets.doubleValue
                }
            }
            
            print("[储蓄同步] 拉取成功: \(financeRecords.count) 条记录, 工资配置: \(salaryRecord != nil ? "有" : "无"), 目标: \(goal != nil ? "有" : "无"), 资产: \(totalAssets != nil ? "有" : "无")")
            return (financeRecords, salaryRecord, goal, totalAssets)
        } catch {
            print("[储蓄同步] 拉取异常: \(error.localizedDescription)")
            return nil
        }
    }
}
