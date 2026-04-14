//
//  LoginManager.swift
//  WeItems
//

import Foundation

// MARK: - 登录错误类型

enum LoginError: Error, LocalizedError {
    case invalidPhoneNumber
    case invalidCredentials
    case userNotFound
    case networkError
    case serverError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            return "手机号格式错误"
        case .invalidCredentials:
            return "无效的账户名或密码"
        case .userNotFound:
            return "用户不存在"
        case .networkError:
            return "网络请求失败"
        case .serverError(let message):
            return "服务器错误：\(message)"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - 登录错误响应

struct LoginErrorResponse: Codable {
    let error: String
    let errorCode: Int?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }
}

// MARK: - 登录管理类

class LoginManager {
    static let shared = LoginManager()
    
    private let envId = "weitems-5gn6hs5772d60bb5"
    private var baseUrl: String {
        return "https://\(envId).api.tcloudbasegateway.com"
    }
    
    private init() {}
    
    /// 使用手机号+密码登录
    /// - Parameters:
    ///   - phoneNumber: 手机号
    ///   - password: 密码
    /// - Returns: 登录成功返回Token信息
    func loginWithPhone(
        phoneNumber: String,
        password: String
    ) async throws -> SignupResponse {
        
        let username = phoneNumber.count > 16 ? phoneNumber : "user_\(phoneNumber)"
        
        let url = URL(string: "\(baseUrl)/auth/v1/signin")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "username": username,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // 打印请求
        print("=== HTTP 请求（密码登录）===")
        print("URL: \(url)")
        print("Method: POST")
        print("Body: \(body)")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（密码登录）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoginError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(LoginErrorResponse.self, from: data) {
                throw mapError(errorResponse)
            } else {
                throw LoginError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 解析成功响应
        do {
            let loginResponse = try JSONDecoder().decode(SignupResponse.self, from: data)
            return loginResponse
        } catch {
            throw LoginError.unknownError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    /// 使用手机号+验证码登录（已注册用户）
    /// - Parameters:
    ///   - phoneNumber: 手机号
    ///   - verificationToken: 验证码token
    /// - Returns: 登录成功返回Token信息
    func loginWithPhoneVerification(
        phoneNumber: String,
        verificationToken: String
    ) async throws -> SignupResponse {
        
        let url = URL(string: "\(baseUrl)/auth/v1/signin")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "verification_token": verificationToken
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // 打印请求
        print("=== HTTP 请求（验证码登录）===")
        print("URL: \(url)")
        print("Method: POST")
        print("Body: \(body)")
        print("===========================")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印HTTP响应
        print("=== HTTP 响应（验证码登录）===")
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Body: \(responseString)")
        }
        print("================")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoginError.networkError
        }
        
        // 处理错误响应
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(LoginErrorResponse.self, from: data) {
                throw mapError(errorResponse)
            } else {
                throw LoginError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // 解析成功响应
        do {
            let loginResponse = try JSONDecoder().decode(SignupResponse.self, from: data)
            return loginResponse
        } catch {
            throw LoginError.unknownError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 私有方法

    /// 映射错误响应
    private func mapError(_ errorResponse: LoginErrorResponse) -> LoginError {
        switch errorResponse.error {
        case "invalid_grant", "invalid_credentials", "invalid_username_or_password":
            return .invalidCredentials
        case "user_not_found", "not_found":
            return .userNotFound
        case "invalid_phone_number":
            return .invalidPhoneNumber
        default:
            return .unknownError(errorResponse.errorDescription ?? errorResponse.error)
        }
    }
}
