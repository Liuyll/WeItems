//
//  ThirdPartyLoginManager.swift
//  WeItems
//

import Foundation
import UIKit

// MARK: - 第三方登录管理类

class ThirdPartyLoginManager {
    static let shared = ThirdPartyLoginManager()
    
    private let envId = "weitems-5gn6hs5772d60bb5"
    private var baseUrl: String {
        return "https://\(envId).api.tcloudbasegateway.com"
    }
    
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    private init() {}
    
    // MARK: - 1. 获取第三方登录回调地址
    
    /// 获取第三方身份源登录的回调地址
    /// - Parameters:
    ///   - providerId: 身份源id（如 apple、github、wechat）
    ///   - redirectUri: 重定向地址（可选）
    ///   - state: 客户端状态参数（可选，防止CSRF）
    /// - Returns: 第三方登录回调 URI
    func getProviderUri(
        providerId: String,
        redirectUri: String? = nil,
        state: String? = nil
    ) async throws -> String {
        
        var components = URLComponents(string: "\(baseUrl)/auth/v1/provider/uri")!
        var queryItems = [URLQueryItem(name: "provider_id", value: providerId)]
        if let redirectUri = redirectUri {
            queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectUri))
        }
        if let state = state {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw ThirdPartyLoginError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        
        print("=== [三方登录] 获取回调地址 ===")
        print("URL: \(url)")
        print("provider_id: \(providerId)")
        print("x-device-id: \(deviceId)")
        print("=============================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("=== [三方登录] 回调地址响应 ===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("=============================")
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ThirdPartyLoginError.serverError("获取回调地址失败")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = json["uri"] as? String else {
            throw ThirdPartyLoginError.parseError("解析回调地址失败")
        }
        
        return uri
    }
    
    // MARK: - 2. 获取第三方授权信息（用授权码换取 provider_token）
    
    /// 第三方授权信息响应
    struct ProviderTokenResponse {
        let providerToken: String
        let expiresIn: Int?
        let providerProfile: [String: Any]?
    }
    
    /// 使用第三方授权码换取 provider_token
    /// - Parameters:
    ///   - providerId: 身份源id（如 apple、github、wechat）
    ///   - providerCode: 第三方系统获取的登录code（用于换取用户身份）
    ///   - providerRedirectUri: 身份源回调地址（可选）
    /// - Returns: provider_token 和用户信息
    func getProviderToken(
        providerId: String,
        providerCode: String,
        providerRedirectUri: String? = nil
    ) async throws -> ProviderTokenResponse {
        
        let url = URL(string: "\(baseUrl)/auth/v1/provider/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        
        var body: [String: Any] = [
            "provider_id": providerId,
            "provider_code": providerCode
        ]
        if let redirectUri = providerRedirectUri {
            body["provider_redirect_uri"] = redirectUri
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("=== [三方登录] 获取 provider_token ===")
        print("URL: \(url)")
        print("provider_id: \(providerId)")
        print("provider_code: \(providerCode.prefix(30))...")
        print("x-device-id: \(deviceId)")
        print("======================================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("=== [三方登录] provider_token 响应 ===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("======================================")
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ThirdPartyLoginError.serverError("获取 provider_token 失败 HTTP \(statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThirdPartyLoginError.parseError("解析 provider_token 响应失败")
        }
        
        guard let providerToken = json["provider_token"] as? String else {
            throw ThirdPartyLoginError.parseError("响应中缺少 provider_token")
        }
        
        let expiresIn = json["expires_in"] as? Int
        let providerProfile = json["provider_profile"] as? [String: Any]
        
        print("[三方登录] 获取 provider_token 成功，有效期: \(expiresIn ?? 0)秒")
        if let profile = providerProfile {
            print("[三方登录] provider_profile: \(profile)")
        }
        
        return ProviderTokenResponse(
            providerToken: providerToken,
            expiresIn: expiresIn,
            providerProfile: providerProfile
        )
    }
    
    // MARK: - 3. 使用 provider_token 登录（第三方授权token登录）
    
    /// 使用 provider_token 进行登录（支持自动注册）
    /// - Parameters:
    ///   - providerId: 身份源id（如 apple、github）
    ///   - providerToken: 通过 getProviderToken 获取的 token
    ///   - syncProfile: 是否从第三方同步昵称等信息
    /// - Returns: 标准 Token 响应
    func signInWithProvider(
        providerId: String,
        providerToken: String,
        syncProfile: Bool = true
    ) async throws -> SignupResponse {
        
        let url = URL(string: "\(baseUrl)/auth/v1/signin/with/provider")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        
        let body: [String: Any] = [
            "provider_id": providerId,
            "provider_token": providerToken,
            "force_disable_sign_up": false,
            "sync_profile": syncProfile
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("=== [三方登录] signInWithProvider ===")
        print("URL: \(url)")
        print("provider_id: \(providerId)")
        print("provider_token: \(providerToken.prefix(50))...")
        print("sync_profile: \(syncProfile)")
        print("x-device-id: \(deviceId)")
        print("=====================================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("=== [三方登录] signInWithProvider 响应 ===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("=========================================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ThirdPartyLoginError.networkError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(SignupErrorResponse.self, from: data) {
                throw ThirdPartyLoginError.serverError(errorResponse.errorDescription ?? errorResponse.error)
            }
            throw ThirdPartyLoginError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(SignupResponse.self, from: data)
    }
    
    // MARK: - 4. 完整三方登录流程（授权码 → provider_token → 登录）
    
    /// 完整的第三方登录流程：用授权码换取 provider_token，再用 provider_token 登录
    /// - Parameters:
    ///   - providerId: 身份源id
    ///   - providerCode: 第三方授权码
    ///   - providerRedirectUri: 回调地址（可选）
    /// - Returns: Token 响应和用户信息
    func fullLogin(
        providerId: String,
        providerCode: String,
        providerRedirectUri: String? = nil
    ) async throws -> (tokenResponse: SignupResponse, profile: [String: Any]?) {
        
        // 步骤1：用授权码换取 provider_token
        print("[三方登录] 步骤1：用授权码换取 provider_token...")
        let providerResult = try await getProviderToken(
            providerId: providerId,
            providerCode: providerCode,
            providerRedirectUri: providerRedirectUri
        )
        
        // 步骤2：用 provider_token 登录
        print("[三方登录] 步骤2：用 provider_token 登录...")
        let tokenResponse = try await signInWithProvider(
            providerId: providerId,
            providerToken: providerResult.providerToken,
            syncProfile: true
        )
        
        print("[三方登录] 完整流程成功！sub: \(tokenResponse.sub)")
        return (tokenResponse: tokenResponse, profile: providerResult.providerProfile)
    }
    
    // MARK: - 5. 使用 Apple identityToken 登录/注册
    
    /// 使用 Apple Sign In 的凭证进行登录或注册
    /// 正确流程：authorizationCode → getProviderToken → signInWithProvider
    func loginWithApple(
        identityToken: String,
        authorizationCode: String?,
        userIdentifier: String,
        displayName: String?
    ) async throws -> SignupResponse {
        
        guard let code = authorizationCode, !code.isEmpty else {
            throw ThirdPartyLoginError.parseError("缺少 authorizationCode，无法完成 Apple 登录")
        }
        
        print("[三方登录] Apple 登录流程开始...")
        print("[三方登录] 步骤1：用 authorizationCode 换取 provider_token...")
        
        // 步骤1：用 authorizationCode 换取 provider_token
        let providerResult = try await getProviderToken(
            providerId: "apple",
            providerCode: code
        )
        
        print("[三方登录] 步骤2：用 provider_token 登录...")
        
        // 步骤2：用 provider_token 调用 signInWithProvider 登录（支持自动注册）
        let response = try await signInWithProvider(
            providerId: "apple",
            providerToken: providerResult.providerToken,
            syncProfile: true
        )
        
        print("[三方登录] Apple 登录成功！sub: \(response.sub)")
        
        return response
    }
}

// MARK: - 错误类型

enum ThirdPartyLoginError: Error, LocalizedError {
    case networkError
    case userAlreadyExists
    case serverError(String)
    case parseError(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络请求失败"
        case .userAlreadyExists:
            return "用户已存在"
        case .serverError(let message):
            return "服务器错误：\(message)"
        case .parseError(let message):
            return message
        case .cancelled:
            return "用户取消登录"
        }
    }
}
