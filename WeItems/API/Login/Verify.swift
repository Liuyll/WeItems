//
//  Verify.swift
//  WeItems
//

import Foundation

// MARK: - 数据模型

/// 发送验证码响应
struct VerificationResponse: Codable {
    let verificationId: String?
    let expiresIn: Int?
    let isUser: Bool?
    let error: String?
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case verificationId = "verification_id"
        case expiresIn = "expires_in"
        case isUser = "is_user"
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

/// 验证码请求参数
struct VerificationRequest: Codable {
    let phoneNumber: String?
    let email: String?
    let target: String
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case email
        case target
    }
}

/// 验证验证码请求参数（换取 JWT）
struct VerifyCodeRequest: Codable {
    let verificationId: String
    let verificationCode: String
    
    enum CodingKeys: String, CodingKey {
        case verificationId = "verification_id"
        case verificationCode = "verification_code"
    }
}

/// 验证验证码响应（返回 JWT）
struct VerifyCodeResponse: Codable {
    let verificationToken: String?  // JWT token
    let expiresIn: Int?
    let error: String?
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case expiresIn = "expires_in"
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

// MARK: - 错误类型

enum VerificationError: Error, LocalizedError {
    case invalidPhoneNumber
    case userNotFound
    case rateLimitExceeded(retryAfter: Int)
    case captchaRequired
    case networkError
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            return "手机号格式错误，需加上+86前缀"
        case .userNotFound:
            return "用户不存在"
        case .rateLimitExceeded(let seconds):
            return "发送验证码频率过高，请\(seconds)秒后重试"
        case .captchaRequired:
            return "需要完成图片验证码验证"
        case .networkError:
            return "网络请求失败"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - 验证码管理类

class VerificationManager {
    static let shared = VerificationManager()
    
    private let envId = "weitems-5gn6hs5772d60bb5"
    private var baseUrl: String {
        return "https://\(envId).api.tcloudbasegateway.com"
    }
    
    private init() {}
    
    /// 发送手机验证码
    /// - Parameters:
    ///   - phoneNumber: 手机号（需要+86前缀）
    ///   - target: 发送目标类型（ANY: 不限制, USER: 必须已存在）
    ///   - captchaToken: 图片验证码token（可选）
    /// - Returns: 验证码ID和过期时间
    func sendPhoneVerificationCode(
        phoneNumber: String,
        target: String = "ANY",
        captchaToken: String? = nil
    ) async throws -> (verificationId: String, expiresIn: Int, isUser: Bool) {
        
        // 验证手机号格式
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        let url = URL(string: "\(baseUrl)/auth/v1/verification")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 添加图片验证码token（如果需要）
        if let captchaToken = captchaToken {
            request.setValue(captchaToken, forHTTPHeaderField: "x-captcha-token")
        }
        
        let body = VerificationRequest(
            phoneNumber: formattedPhone,
            email: nil,
            target: target
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（手机验证码）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
            print("Headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.networkError
        }
        
        let verificationResponse = try JSONDecoder().decode(VerificationResponse.self, from: data)
        
        // 处理错误响应
        if let error = verificationResponse.error {
            switch error {
            case "invalid_phone_number":
                throw VerificationError.invalidPhoneNumber
            case "user_not_found":
                throw VerificationError.userNotFound
            case "rate_limit_exceeded":
                let retryAfter = verificationResponse.errorDescription?.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                    .first ?? 60
                throw VerificationError.rateLimitExceeded(retryAfter: retryAfter)
            case "captcha_required":
                throw VerificationError.captchaRequired
            default:
                throw VerificationError.unknownError(verificationResponse.errorDescription ?? "未知错误")
            }
        }
        
        // 返回成功结果
        guard let verificationId = verificationResponse.verificationId,
              let expiresIn = verificationResponse.expiresIn else {
            throw VerificationError.unknownError("响应数据不完整")
        }
        
        return (
            verificationId: verificationId,
            expiresIn: expiresIn,
            isUser: verificationResponse.isUser ?? false
        )
    }
    
    /// 格式化手机号，确保有+86前缀
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") {
            return trimmed
        }
        return "+86 \(trimmed)"
    }
    
    /// 验证手机号格式（简单的正则验证）
    func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        // 支持 +86 13800138000 或 13800138000 格式
        let pattern = "^(\\+86\\s?)?1[3-9]\\d{9}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }
    
    /// 发送邮箱验证码
    /// - Parameters:
    ///   - email: 邮箱地址
    ///   - target: 发送目标类型（ANY: 不限制, USER: 必须已存在）
    ///   - captchaToken: 图片验证码token（可选）
    /// - Returns: 验证码ID和过期时间
    func sendEmailVerificationCode(
        email: String,
        target: String = "ANY",
        captchaToken: String? = nil
    ) async throws -> (verificationId: String, expiresIn: Int, isUser: Bool) {
        
        let url = URL(string: "\(baseUrl)/auth/v1/verification")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 添加图片验证码token（如果需要）
        if let captchaToken = captchaToken {
            request.setValue(captchaToken, forHTTPHeaderField: "x-captcha-token")
        }
        
        let body = VerificationRequest(
            phoneNumber: nil,
            email: email,
            target: target
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（邮箱验证码）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
            print("Headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.networkError
        }
        
        let verificationResponse = try JSONDecoder().decode(VerificationResponse.self, from: data)
        
        // 处理错误响应
        if let error = verificationResponse.error {
            switch error {
            case "invalid_email":
                throw VerificationError.unknownError("邮箱格式错误")
            case "user_not_found":
                throw VerificationError.userNotFound
            case "rate_limit_exceeded":
                let retryAfter = verificationResponse.errorDescription?.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                    .first ?? 60
                throw VerificationError.rateLimitExceeded(retryAfter: retryAfter)
            case "captcha_required":
                throw VerificationError.captchaRequired
            default:
                throw VerificationError.unknownError(verificationResponse.errorDescription ?? "未知错误")
            }
        }
        
        // 返回成功结果
        guard let verificationId = verificationResponse.verificationId,
              let expiresIn = verificationResponse.expiresIn else {
            throw VerificationError.unknownError("响应数据不完整")
        }
        
        return (
            verificationId: verificationId,
            expiresIn: expiresIn,
            isUser: verificationResponse.isUser ?? false
        )
    }
    
    /// 验证验证码（换取 JWT token）
    /// - Parameters:
    ///   - verificationId: 验证码ID（从发送验证码接口获取）
    ///   - verificationCode: 用户输入的验证码
    /// - Returns: JWT verification_token
    func verifyCode(
        verificationId: String,
        verificationCode: String
    ) async throws -> String {
        
        let url = URL(string: "\(baseUrl)/auth/v1/verification/verify")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = VerifyCodeRequest(
            verificationId: verificationId,
            verificationCode: verificationCode
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // 打印请求
        print("=== HTTP 请求（验证验证码）===")
        print("URL: \(url)")
        if let requestBody = try? JSONEncoder().encode(body),
           let requestString = String(data: requestBody, encoding: .utf8) {
            print("Body: \(requestString)")
        }
        print("================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（验证验证码）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.networkError
        }
        
        let verifyResponse = try JSONDecoder().decode(VerifyCodeResponse.self, from: data)
        
        // 处理错误响应
        if let error = verifyResponse.error {
            throw VerificationError.unknownError(verifyResponse.errorDescription ?? error)
        }
        
        // 返回 JWT token
        guard let token = verifyResponse.verificationToken else {
            throw VerificationError.unknownError("未返回 verification_token")
        }
        
        return token
    }
}
