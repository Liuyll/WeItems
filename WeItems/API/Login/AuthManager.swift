//
//  AuthManager.swift
//  WeItems
//

import Foundation
import Combine

/// 认证状态枚举
enum AuthState: Equatable {
    case unknown      // 初始状态，正在检查
    case authenticated // 已认证（token 有效或刷新成功）
    case unauthenticated // 未认证（需要登录）
}

/// 认证管理类 - 管理用户登录状态和 Token 验证
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    /// 用户切换通知（登录/登出时发送）
    static let userDidChangeNotification = Notification.Name("AuthManager.userDidChange")
    /// 用户主动登录成功通知（仅登录页登录成功时发送，用于触发自动同步）
    static let userDidLoginNotification = Notification.Name("AuthManager.userDidLogin")
    
    @Published var authState: AuthState = .unknown
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cloudBaseClient: CloudBaseClient?
    
    private init() {
        // 初始化时创建 CloudBaseClient
        if let envId = Self.loadEnvId(),
           let accessToken = TokenStorage.shared.getAccessToken() {
            self.cloudBaseClient = CloudBaseClient(
                envId: envId,
                accessToken: accessToken
            )
        }
    }
    
    /// 从 Config.plist 加载环境 ID
    private static func loadEnvId() -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CLOUDBASE_ENV_ID"] as? String
    }
    
    /// 应用启动时验证 Token
    /// 1. 检查本地是否有 token
    /// 2. 如果 access_token 未过期（还有 >5min 有效期），直接复用
    /// 3. 快过期或已过期，使用 refresh_token 刷新
    /// 4. 如果刷新失败，则标记为未认证
    @MainActor
    func validateTokenOnLaunch() async {
        isLoading = true
        defer { isLoading = false }
        
        // 1. 检查是否有保存的 token
        guard let accessToken = TokenStorage.shared.getAccessToken(),
              let refreshToken = TokenStorage.shared.getRefreshToken() else {
            print("[AuthManager] 未找到本地 token，需要登录")
            authState = .unauthenticated
            return
        }
        
        print("[AuthManager] 发现本地 token，开始验证...")
        
        // 确保 CloudBaseClient 已创建
        if cloudBaseClient == nil, let envId = Self.loadEnvId() {
            cloudBaseClient = CloudBaseClient(envId: envId, accessToken: accessToken)
        }
        
        // 2. 检查 access_token 是否仍有效（还有 >5min 有效期）
        if !TokenStorage.shared.needsRefresh() {
            let remaining = TokenStorage.shared.tokenRemainingSeconds()
            print("[AuthManager] access_token 仍有效（剩余 \(Int(remaining))秒），直接复用")
            authState = .authenticated
            Task { await fetchOrCreateUserInfo() }
            return
        }
        
        // 3. access_token 已过期或即将过期，使用 refresh_token 刷新
        let remaining = TokenStorage.shared.tokenRemainingSeconds()
        print("[AuthManager] access_token 需刷新（剩余 \(Int(remaining))秒），使用 refresh_token...")
        if await refreshTokenWithStoredRefreshToken(refreshToken: refreshToken) {
            print("[AuthManager] Token 刷新成功")
            authState = .authenticated
            Task { await fetchOrCreateUserInfo() }
            return
        }
        
        // 4. refresh 失败，尝试直接验证当前 token（可能 access_token 虽然本地计算过期但服务端还有效）
        print("[AuthManager] Refresh 失败，尝试验证当前 access_token...")
        if await introspectCurrentToken() {
            print("[AuthManager] 当前 access_token 仍然有效")
            TokenStorage.shared.saveLastVerifyTime()
            authState = .authenticated
            Task { await fetchOrCreateUserInfo() }
            return
        }
        
        // 5. 都失败了，标记为未认证（不清除 token，保留本地数据目录）
        print("[AuthManager] Token 刷新和验证均失败，需要重新登录")
        authState = .unauthenticated
    }
    
    /// 验证当前存储的 access_token
    @MainActor
    private func introspectCurrentToken() async -> Bool {
        guard let client = cloudBaseClient else { return false }
        
        let isValid = await client.isTokenValid()
        return isValid
    }
    
    /// 使用存储的 refresh_token 刷新 token
    @MainActor
    private func refreshTokenWithStoredRefreshToken(refreshToken: String) async -> Bool {
        guard let client = cloudBaseClient else { return false }
        
        let response = await client.refreshAccessToken(refreshToken: refreshToken)
        
        if let newToken = response {
            // 保存新的 token 信息
            TokenStorage.shared.saveToken(
                accessToken: newToken.accessToken,
                refreshToken: newToken.refreshToken,
                expiresIn: newToken.expiresIn,
                tokenType: newToken.tokenType,
                sub: newToken.sub
            )
            
            // 更新 cloudBaseClient 的 access_token
            self.cloudBaseClient?.updateAccessToken(newToken.accessToken)
            return true
        }
        
        return false
    }
    
    /// 用户主动登录成功后调用
    func loginSuccess(accessToken: String, refreshToken: String, expiresIn: Int, tokenType: String, sub: String) {
        TokenStorage.shared.saveToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            tokenType: tokenType,
            sub: sub
        )
        
        // 更新 cloudBaseClient
        if let envId = Self.loadEnvId() {
            self.cloudBaseClient = CloudBaseClient(
                envId: envId,
                accessToken: accessToken
            )
        }
        
        authState = .authenticated
        print("[AuthManager] 登录成功，认证状态已更新")
        
        // 通知 Store 重新加载当前用户数据（会合并 anonymous 数据到用户目录）
        NotificationCenter.default.post(name: Self.userDidChangeNotification, object: nil)
        
        // 延迟清空 anonymous 目录，确保 Store 已完成数据加载和合并
        // 同时通知登录成功，触发自动同步
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            UserStorageHelper.shared.clearAnonymousData()
            print("[AuthManager] 发送 userDidLoginNotification，触发自动同步")
            NotificationCenter.default.post(name: Self.userDidLoginNotification, object: nil)
        }
        
        // 异步获取/创建 userinfo 并同步 VIP 信息
        Task {
            await fetchOrCreateUserInfo()
        }
    }
    
    /// 获取 userinfo，如果不存在则创建；仅在本地 VIP 过期时从云端同步 VIP 状态
    @MainActor
    private func fetchOrCreateUserInfo() async {
        guard let client = cloudBaseClient else {
            print("[AuthManager] 无 CloudBaseClient，跳过 userinfo 获取")
            return
        }
        
        let hasLocalRegisterTime = TokenStorage.shared.getRegisterTime() != nil
        
        // 本地 VIP 未过期且已有注册时间，不需要请求云端
        if !IAPManager.shared.isVIPExpiredLocally && hasLocalRegisterTime {
            print("[AuthManager] 本地 VIP 未过期(\(IAPManager.shared.vipLevel.displayName))且已有注册时间，跳过云端获取")
            return
        }
        
        let response = await client.fetchUserInfo()
        
        if let records = response?.data?.records, let record = records.first {
            print("[AuthManager] 已获取 userinfo: _id=\(record._id ?? "nil")")
            
            // 同步远端 VIP 信息到本地
            if let vipInfo = record.vip_type, let vipType = vipInfo.type {
                IAPManager.shared.applyRemoteVIPInfo(
                    type: vipType,
                    startDate: vipInfo.startDate,
                    expireDate: vipInfo.expireDate
                )
                print("[AuthManager] 已同步 VIP 信息: type=\(vipType)")
            }
            
            // 从 anotherinfo 读取注册时间存到本地
            if let registerTime = record.anotherinfo?.registerTime, !registerTime.isEmpty {
                TokenStorage.shared.saveRegisterTime(registerTime)
            }
        } else {
            // userinfo 不存在，创建新记录
            print("[AuthManager] userinfo 不存在，开始创建...")
            let _ = await client.createUserInfo(shareWishList: [])
            print("[AuthManager] userinfo 已创建")
            
            // 如果本地已有 VIP（如之前通过 IAP 购买），同步到云端
            if IAPManager.shared.isPro {
                await IAPManager.shared.syncVIPToCloud()
            }
        }
    }
    
    /// 用户登出
    func logout() {
        TokenStorage.shared.clearToken()
        IAPManager.shared.clearLocalVIPInfo()
        authState = .unauthenticated
        cloudBaseClient = nil
        
        // 清空 anonymous 目录，避免退出后还显示旧数据
        UserStorageHelper.shared.clearAnonymousData()
        
        print("[AuthManager] 用户已登出")
        
        // 通知 Store 重新加载 anonymous 数据（此时 anonymous 目录已清空，显示空数据）
        NotificationCenter.default.post(name: Self.userDidChangeNotification, object: nil)
    }
    
    /// 确保 token 有效：如果 access_token 即将过期则自动刷新
    /// 在进行任何 API 调用前应先调用此方法
    /// - Returns: token 是否有效（刷新成功也算有效）
    @MainActor
    func ensureValidToken() async -> Bool {
        // 1. 检查 access_token 是否仍然有效（还有 5 分钟以上有效期）
        if !TokenStorage.shared.needsRefresh() {
            return true
        }
        
        // 2. 需要刷新，使用 refresh_token
        let remaining = TokenStorage.shared.tokenRemainingSeconds()
        print("[AuthManager] access_token 剩余 \(Int(remaining))秒，开始刷新...")
        return await tryRefreshToken()
    }
    
    /// 尝试使用 refresh_token 刷新，并更新本地状态
    @MainActor
    private func tryRefreshToken() async -> Bool {
        guard let refreshToken = TokenStorage.shared.getRefreshToken() else {
            print("[AuthManager] 无 refresh_token，需要重新登录")
            authState = .unauthenticated
            return false
        }
        
        if await refreshTokenWithStoredRefreshToken(refreshToken: refreshToken) {
            print("[AuthManager] Token 刷新成功")
            authState = .authenticated
            return true
        }
        
        print("[AuthManager] Token 刷新失败，需要重新登录")
        authState = .unauthenticated
        return false
    }
    
    /// 获取当前的 CloudBaseClient（用于 API 调用）
    func getCloudBaseClient() -> CloudBaseClient? {
        return cloudBaseClient
    }
    
    /// 检查是否已认证
    var isAuthenticated: Bool {
        return authState == .authenticated
    }
    
    /// 判断启动时是否需要网络验证 token
    /// - 没有本地 token → 不需要（直接进入首页，显示未登录状态）
    /// - 有 token 且未过期 → 不需要（直接复用，可以跳过开屏页）
    /// - 有 token 但需要刷新 → 需要（要走网络刷新流程，需要开屏页等待）
    func needsNetworkVerification() -> Bool {
        guard TokenStorage.shared.getAccessToken() != nil,
              TokenStorage.shared.getRefreshToken() != nil else {
            // 没有 token，不需要网络验证
            return false
        }
        
        if !TokenStorage.shared.needsRefresh() {
            // access_token 仍有效，不需要网络请求，延迟设置状态避免在视图更新中触发
            DispatchQueue.main.async {
                self.authState = .authenticated
            }
            // 确保 CloudBaseClient 已创建
            if cloudBaseClient == nil, let envId = Self.loadEnvId(),
               let accessToken = TokenStorage.shared.getAccessToken() {
                cloudBaseClient = CloudBaseClient(envId: envId, accessToken: accessToken)
            }
            return false
        }
        
        // 需要网络刷新
        return true
    }
}
