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
    /// 2. 验证 token 是否有效
    /// 3. 如果无效，尝试刷新 token
    /// 4. 如果都失败，则标记为未认证
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
        
        // 2. 尝试验证当前 token
        if await introspectCurrentToken() {
            print("[AuthManager] Token 验证成功")
            authState = .authenticated
            return
        }
        
        // 3. Token 无效，尝试刷新
        print("[AuthManager] Token 无效，尝试刷新...")
        if await refreshTokenWithStoredRefreshToken(refreshToken: refreshToken) {
            print("[AuthManager] Token 刷新成功")
            authState = .authenticated
            return
        }
        
        // 4. 都失败了，清除 token 并标记为未认证
        print("[AuthManager] Token 刷新失败，需要重新登录")
        TokenStorage.shared.clearToken()
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
        
        // 通知 Store 重新加载当前用户数据
        NotificationCenter.default.post(name: Self.userDidChangeNotification, object: nil)
    }
    
    /// 用户登出
    func logout() {
        TokenStorage.shared.clearToken()
        authState = .unauthenticated
        cloudBaseClient = nil
        print("[AuthManager] 用户已登出")
        
        // 通知 Store 重新加载 anonymous 数据
        NotificationCenter.default.post(name: Self.userDidChangeNotification, object: nil)
    }
    
    /// 确保 token 有效：如果已过期则自动刷新
    /// 在进行任何 API 调用前应先调用此方法
    /// - Returns: token 是否有效（刷新成功也算有效）
    @MainActor
    func ensureValidToken() async -> Bool {
        // 1. 本地判断 token 是否过期
        guard !TokenStorage.shared.isTokenExpired() else {
            print("[AuthManager] Token 已过期，尝试刷新...")
            return await tryRefreshToken()
        }
        
        // 2. 本地未过期，再向服务端验证一次
        if await introspectCurrentToken() {
            return true
        }
        
        // 3. 服务端验证失败，尝试刷新
        print("[AuthManager] Token 服务端验证失败，尝试刷新...")
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
        TokenStorage.shared.clearToken()
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
}
