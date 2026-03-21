//
//  Signup.swift
//  WeItems
//

import Foundation

// MARK: - 数据模型

/// 注册请求参数
struct SignupRequest: Codable {
    let phoneNumber: String
    let verificationToken: String
    let username: String?
    let password: String?
    let email: String?
    let name: String?
    let gender: String?
    let picture: String?
    let locale: String?
    let providerToken: String?
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case verificationToken = "verification_token"
        case username
        case password
        case email
        case name
        case gender
        case picture
        case locale
        case providerToken = "provider_token"
    }
}

/// 注册响应数据（Token信息）
struct SignupResponse: Codable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let sub: String
    let scope: String?
    let groups: [String]?
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case sub
        case scope
        case groups
    }
}

/// 注册错误响应
struct SignupErrorResponse: Codable {
    let error: String
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

// MARK: - 错误类型

enum SignupError: Error, LocalizedError {
    case invalidPhoneNumber
    case invalidVerificationCode
    case userAlreadyExists
    case invalidUsername
    case weakPassword
    case networkError
    case serverError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            return "手机号格式错误"
        case .invalidVerificationCode:
            return "验证码错误或已过期"
        case .userAlreadyExists:
            return "用户已存在"
        case .invalidUsername:
            return "用户名格式错误（2-48位，支持英文、数字、-_.:+@）"
        case .weakPassword:
            return "密码强度不足"
        case .networkError:
            return "网络请求失败"
        case .serverError(let message):
            return "服务器错误：\(message)"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - 注册管理类

class SignupManager {
    static let shared = SignupManager()
    
    private let envId = "weitems-5gn6hs5772d60bb5"
    private var baseUrl: String {
        return "https://\(envId).api.tcloudbasegateway.com"
    }
    
    private init() {}
    
    /// 使用手机号+验证码注册新用户
    /// - Parameters:
    ///   - phoneNumber: 手机号（如 "13800138000" 或 "+86 13800138000"）
    ///   - verificationToken: 验证码token（从发送验证码接口获取的 verification_id）
    ///   - username: 用户名（可选，2-48位）
    ///   - password: 密码（可选，至少6位）
    ///   - name: 昵称（可选）
    /// - Returns: 注册成功返回Token信息
    func signupWithPhone(
        phoneNumber: String,
        verificationToken: String,
        username: String? = nil,
        password: String? = nil,
        name: String? = nil
    ) async throws -> SignupResponse {
        
        // 格式化手机号
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        let url = URL(string: "\(baseUrl)/auth/v1/signup")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = SignupRequest(
            phoneNumber: formattedPhone,
            verificationToken: verificationToken,
            username: username,
            password: password,
            email: nil,
            name: name,
            gender: nil,
            picture: nil,
            locale: nil,
            providerToken: nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // 打印请求
        print("=== HTTP 请求（手机注册）===")
        print("URL: \(url)")
        print("Method: POST")
        if let requestBody = try? JSONEncoder().encode(body),
           let requestString = String(data: requestBody, encoding: .utf8) {
            print("Body: \(requestString)")
        }
        print("verification_token: \(verificationToken)")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（手机注册）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
            print("Headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SignupError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(SignupErrorResponse.self, from: data) {
                throw mapError(errorResponse)
            } else {
                throw SignupError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 解析成功响应
        do {
            let signupResponse = try JSONDecoder().decode(SignupResponse.self, from: data)
            return signupResponse
        } catch {
            throw SignupError.unknownError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    /// 使用邮箱+验证码注册新用户
    /// - Parameters:
    ///   - email: 邮箱地址
    ///   - verificationToken: 验证码token
    ///   - username: 用户名（2-48位）
    ///   - password: 密码（至少6位）
    ///   - name: 昵称（可选）
    /// - Returns: 注册成功返回Token信息
    func signupWithEmail(
        email: String,
        verificationToken: String,
        username: String,
        password: String,
        name: String? = nil
    ) async throws -> SignupResponse {
        
        // 验证邮箱格式
        guard isValidEmail(email) else {
            throw SignupError.unknownError("邮箱格式错误")
        }
        
        // 验证用户名格式
        guard isValidUsername(username) else {
            throw SignupError.invalidUsername
        }
        
        // 验证密码长度
        guard password.count >= 6 else {
            throw SignupError.weakPassword
        }
        
        let url = URL(string: "\(baseUrl)/auth/v1/signup")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = SignupRequest(
            phoneNumber: "",
            verificationToken: verificationToken,
            username: username,
            password: password,
            email: email,
            name: name,
            gender: nil,
            picture: nil,
            locale: nil,
            providerToken: nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（邮箱注册）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
            print("Headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SignupError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(SignupErrorResponse.self, from: data) {
                throw mapError(errorResponse)
            } else {
                throw SignupError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 解析成功响应
        do {
            let signupResponse = try JSONDecoder().decode(SignupResponse.self, from: data)
            return signupResponse
        } catch {
            throw SignupError.unknownError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 验证方法
    
    /// 验证用户名格式（2-48位，支持英文大小写、数字、特殊字符-_.:+@，以字母或数字开头）
    func isValidUsername(_ username: String) -> Bool {
        // 长度验证
        guard username.count >= 2 && username.count <= 48 else {
            return false
        }
        
        // 正则验证：以字母或数字开头，支持英文、数字、-_.:+@
        let pattern = "^[a-zA-Z0-9][a-zA-Z0-9_.:\\-+@]*$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: username.utf16.count)
        return regex?.firstMatch(in: username, options: [], range: range) != nil
    }
    
    /// 验证邮箱格式
    func isValidEmail(_ email: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: email.utf16.count)
        return regex?.firstMatch(in: email, options: [], range: range) != nil
    }
    
    // MARK: - 私有方法
    
    /// 格式化手机号，确保有+86前缀
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") {
            return trimmed
        }
        return "+86 \(trimmed)"
    }
    
    /// 映射错误响应
    private func mapError(_ errorResponse: SignupErrorResponse) -> SignupError {
        switch errorResponse.error {
        case "user_already_exists":
            return .userAlreadyExists
        case "invalid_verification_code":
            return .invalidVerificationCode
        case "invalid_phone_number":
            return .invalidPhoneNumber
        case "invalid_username":
            return .invalidUsername
        case "weak_password":
            return .weakPassword
        default:
            return .unknownError(errorResponse.errorDescription ?? errorResponse.error)
        }
    }
}
