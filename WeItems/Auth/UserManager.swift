//
//  UserManager.swift
//  WeItems
//

import Foundation

// MARK: - 数据模型

/// 获取 sudo_token 请求参数
struct SudoTokenRequest: Codable {
    let password: String?
    let verificationToken: String?
    
    enum CodingKeys: String, CodingKey {
        case password
        case verificationToken = "verification_token"
    }
}

/// 获取 sudo_token 成功响应
struct SudoTokenResponse: Codable {
    let sudoToken: String?
    let expiresIn: Int?
    let error: String?
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case sudoToken = "sudo_token"
        case expiresIn = "expires_in"
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

/// 用户身份源信息
struct UserProvider: Codable {
    let id: String?
    let providerUserId: String?
    let name: String?
    let picture: String?
    let url: String?
    let meta: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case providerUserId = "provider_user_id"
        case name
        case picture
        case url
        case meta
    }
}

/// 用户分组信息
struct UserGroup: Codable {
    let id: String?
}

/// 当前用户信息响应
struct UserProfile: Codable {
    let sub: String?
    let name: String?
    let picture: String?
    let username: String?
    let email: String?
    let phoneNumber: String?
    let providers: [UserProvider]?
    let status: String?
    let gender: String?
    let groups: [UserGroup]?
    let meta: [String: String]?
    let createdAt: String?
    let updatedAt: String?
    let passwordUpdatedAt: String?
    let userId: String?
    let hasPassword: Bool?
    let password: String?
    let internalUserType: String?
    let type: String?
    let userSource: Int?
    let userDesc: String?
    let openId: String?
    let corpId: String?
    let parentUserId: String?
    let mainDep: String?
    let sort: Int?
    let lastLogin: String?
    
    // 兼容错误响应
    let error: String?
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case sub, name, picture, username, email
        case phoneNumber = "phone_number"
        case providers, status, gender, groups, meta
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case passwordUpdatedAt = "password_updated_at"
        case userId = "user_id"
        case hasPassword = "has_password"
        case password
        case internalUserType = "internal_user_type"
        case type
        case userSource = "user_source"
        case userDesc = "user_desc"
        case openId = "open_id"
        case corpId = "corp_id"
        case parentUserId = "parent_user_id"
        case mainDep = "main_dep"
        case sort
        case lastLogin = "last_login"
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
    
    /// 判断用户是否已设置密码（兼容 has_password 布尔值和 password: "SET" 字符串两种格式）
    var isPasswordSet: Bool {
        if let hasPassword = hasPassword { return hasPassword }
        if let password = password, password.uppercased() == "SET" { return true }
        return false
    }
}

/// 修改密码请求参数
struct ChangePasswordRequest: Codable {
    let sudoToken: String
    let oldPassword: String?
    let newPassword: String
    let confirmPassword: String?
    
    enum CodingKeys: String, CodingKey {
        case sudoToken = "sudo_token"
        case oldPassword = "old_password"
        case newPassword = "new_password"
        case confirmPassword = "confirm_password"
    }
}

/// 修改用户基础信息请求参数
struct EditUserBasicRequest: Codable {
    let nickname: String?
    let username: String?
    let phone: String?
    let description: String?
    let avatarUrl: String?
    let gender: String?
    let email: String?
    
    enum CodingKeys: String, CodingKey {
        case nickname, username, phone, description
        case avatarUrl = "avatar_url"
        case gender, email
    }
}

/// 通用错误响应
struct UserErrorResponse: Codable {
    let error: String?
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

// MARK: - 错误类型

enum UserManagerError: Error, LocalizedError {
    case notLoggedIn
    case invalidPassword
    case invalidVerificationToken
    case weakPassword
    case sudoTokenExpired
    case networkError
    case serverError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "用户未登录，请先登录"
        case .invalidPassword:
            return "密码错误，请重新输入"
        case .invalidVerificationToken:
            return "验证码无效或已过期"
        case .weakPassword:
            return "密码强度不足，请使用包含大小写字母、数字和特殊字符的组合"
        case .sudoTokenExpired:
            return "操作权限已过期，请重新验证"
        case .networkError:
            return "网络请求失败"
        case .serverError(let message):
            return "服务器错误：\(message)"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - 用户账号管理类

class UserManager {
    static let shared = UserManager()
    
    private let envId = "weitems-5gn6hs5772d60bb5"
    private var baseUrl: String {
        return "https://\(envId).api.tcloudbasegateway.com"
    }
    
    private init() {}
    
    // MARK: - 获取当前用户信息
    
    /// 获取当前登录用户的完整信息
    /// - Returns: 用户信息对象
    func getUserProfile() async throws -> UserProfile {
        
        // 检查登录状态
        guard let accessToken = TokenStorage.shared.getAccessToken() else {
            throw UserManagerError.notLoggedIn
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/user/me")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // 打印请求
        print("=== HTTP 请求（获取用户信息）===")
        print("URL: \(url)")
        print("Method: GET")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（获取用户信息）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(SudoTokenResponse.self, from: data),
               let error = errorResponse.error {
                throw mapError(error, description: errorResponse.errorDescription)
            } else {
                throw UserManagerError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 解析用户信息
        do {
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            
            // 检查是否包含错误
            if let error = profile.error {
                throw mapError(error, description: profile.errorDescription)
            }
            
            print("[UserManager] 用户信息获取成功: \(profile.name ?? profile.username ?? profile.sub ?? "未知")")
            return profile
        } catch let error as UserManagerError {
            throw error
        } catch {
            throw UserManagerError.unknownError("解析用户信息失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 修改用户基础信息
    
    /// 修改当前用户的基础信息（昵称、用户名等）
    /// - Parameters:
    ///   - nickname: 昵称（可选）
    ///   - username: 用户名（可选）
    func editUserBasic(
        nickname: String? = nil,
        username: String? = nil
    ) async throws {
        
        guard let accessToken = TokenStorage.shared.getAccessToken() else {
            throw UserManagerError.notLoggedIn
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/user/basic/edit")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body = EditUserBasicRequest(
            nickname: nickname,
            username: username,
            phone: nil,
            description: nil,
            avatarUrl: nil,
            gender: nil,
            email: nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        print("=== HTTP 请求（修改用户信息）===")
        print("URL: \(url)")
        print("Method: POST")
        if let requestBody = try? JSONEncoder().encode(body),
           let requestString = String(data: requestBody, encoding: .utf8) {
            print("Body: \(requestString)")
        }
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("=== HTTP 响应（修改用户信息）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.networkError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(UserErrorResponse.self, from: data),
               let error = errorResponse.error {
                throw mapError(error, description: errorResponse.errorDescription)
            } else {
                throw UserManagerError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        print("[UserManager] 用户信息修改成功")
    }
    
    // MARK: - 修改密码
    
    /// 修改当前用户密码（需要先获取 sudo_token）
    /// - Parameters:
    ///   - sudoToken: 临时管理权限 token
    ///   - oldPassword: 旧密码（用户已有密码时需要提供）
    ///   - newPassword: 新密码（8-64位，包含大小写字母、数字、特殊字符）
    func changePassword(
        sudoToken: String,
        oldPassword: String? = nil,
        newPassword: String
    ) async throws {
        
        // 检查登录状态
        guard let accessToken = TokenStorage.shared.getAccessToken() else {
            throw UserManagerError.notLoggedIn
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/user/password")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body = ChangePasswordRequest(
            sudoToken: sudoToken,
            oldPassword: oldPassword,
            newPassword: newPassword,
            confirmPassword: newPassword
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // 打印请求
        print("=== HTTP 请求（修改密码）===")
        print("URL: \(url)")
        print("Method: PATCH")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（修改密码）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(UserErrorResponse.self, from: data),
               let error = errorResponse.error {
                throw mapError(error, description: errorResponse.errorDescription)
            } else {
                throw UserManagerError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        print("[UserManager] 密码修改成功")
    }
    
    // MARK: - 首次设置密码
    
    /// 首次设置密码（无旧密码用户），用 access_token 作为 sudo_token query 参数
    /// - Parameter newPassword: 新密码（8-64位，包含大小写字母、数字、特殊字符）
    func setPassword(newPassword: String) async throws {
        
        guard let accessToken = TokenStorage.shared.getAccessToken() else {
            throw UserManagerError.notLoggedIn
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/user/password?sudo_token=\(accessToken)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: String] = [
            "new_password": newPassword,
            "confirm_password": newPassword
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("=== HTTP 请求（首次设置密码）===")
        print("URL: \(url)")
        print("Method: PATCH")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("=== HTTP 响应（首次设置密码）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.networkError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(UserErrorResponse.self, from: data),
               let error = errorResponse.error {
                throw mapError(error, description: errorResponse.errorDescription)
            } else {
                throw UserManagerError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        print("[UserManager] 首次设置密码成功")
    }
    
    // MARK: - 获取 sudo_token
    
    /// 使用密码获取临时管理员权限 sudo_token
    /// - Parameter password: 用户密码
    /// - Returns: sudo_token 和过期时间（秒）
    func getSudoTokenWithPassword(
        password: String
    ) async throws -> (sudoToken: String, expiresIn: Int) {
        let body = SudoTokenRequest(
            password: password,
            verificationToken: nil
        )
        return try await requestSudoToken(body: body)
    }
    
    /// 使用验证码 token 获取临时管理员权限 sudo_token
    /// - Parameter verificationToken: 验证码验证后获取的 token
    /// - Returns: sudo_token 和过期时间（秒）
    func getSudoTokenWithVerification(
        verificationToken: String
    ) async throws -> (sudoToken: String, expiresIn: Int) {
        let body = SudoTokenRequest(
            password: nil,
            verificationToken: verificationToken
        )
        return try await requestSudoToken(body: body)
    }
    
    // MARK: - 私有方法
    
    /// 发送 sudo_token 请求
    private func requestSudoToken(
        body: SudoTokenRequest
    ) async throws -> (sudoToken: String, expiresIn: Int) {
        
        // 检查登录状态
        guard let accessToken = TokenStorage.shared.getAccessToken() else {
            throw UserManagerError.notLoggedIn
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/user/sudo")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // 打印请求
        print("=== HTTP 请求（获取 sudo_token）===")
        print("URL: \(url)")
        print("Method: POST")
        if let requestBody = try? JSONEncoder().encode(body),
           let requestString = String(data: requestBody, encoding: .utf8) {
            print("Body: \(requestString)")
        }
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（获取 sudo_token）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.networkError
        }
        
        let sudoResponse = try JSONDecoder().decode(SudoTokenResponse.self, from: data)
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let error = sudoResponse.error {
                throw mapError(error, description: sudoResponse.errorDescription)
            } else {
                throw UserManagerError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 返回成功结果
        guard let sudoToken = sudoResponse.sudoToken else {
            throw UserManagerError.invalidPassword
        }
        let expiresIn = sudoResponse.expiresIn ?? 300
        
        print("[UserManager] sudo_token 获取成功，有效期 \(expiresIn) 秒")
        
        return (sudoToken: sudoToken, expiresIn: expiresIn)
    }
    
    /// 映射错误响应
    private func mapError(_ error: String, description: String?) -> UserManagerError {
        switch error {
        case "invalid_password":
            return .invalidPassword
        case "invalid_verification_token":
            return .invalidVerificationToken
        case "weak_password":
            return .weakPassword
        case "unauthorized", "invalid_token":
            return .notLoggedIn
        case "sudo_token_expired", "invalid_sudo_token":
            return .sudoTokenExpired
        default:
            return .unknownError(description ?? error)
        }
    }
}
