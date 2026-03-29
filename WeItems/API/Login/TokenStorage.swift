//
//  TokenStorage.swift
//  WeItems
//

import Foundation
import Security

/// Token 存储管理类
class TokenStorage {
    static let shared = TokenStorage()
    
    private let accessTokenKey = "com.weitems.access_token"
    private let refreshTokenKey = "com.weitems.refresh_token"
    private let expiresInKey = "com.weitems.expires_in"
    private let tokenTypeKey = "com.weitems.token_type"
    private let subKey = "com.weitems.sub"
    private let phoneNumberKey = "com.weitems.phone_number"
    private let saveTimeKey = "com.weitems.save_time"
    private let lastVerifyTimeKey = "com.weitems.last_verify_time"
    
    /// Token 有效期（24 小时，单位秒）
    static let tokenValidDuration: TimeInterval = 24 * 60 * 60
    
    private init() {}
    
    /// 保存 Token 信息
    func saveToken(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        tokenType: String,
        sub: String,
        phoneNumber: String? = nil
    ) {
        // 保存到 Keychain（安全存储）
        saveToKeychain(key: accessTokenKey, value: accessToken)
        saveToKeychain(key: refreshTokenKey, value: refreshToken)
        
        // 保存到 UserDefaults
        UserDefaults.standard.set(expiresIn, forKey: expiresInKey)
        UserDefaults.standard.set(tokenType, forKey: tokenTypeKey)
        UserDefaults.standard.set(sub, forKey: subKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: saveTimeKey)
        
        // 保存手机号
        if let phoneNumber = phoneNumber {
            UserDefaults.standard.set(phoneNumber, forKey: phoneNumberKey)
        }
        
        print("=== Token 已保存到本地 ===")
        print("access_token: \(accessToken.prefix(20))...")
        print("refresh_token: \(refreshToken.prefix(20))...")
        print("expires_in: \(expiresIn)")
        print("token_type: \(tokenType)")
        print("sub: \(sub)")
        print("phone_number: \(phoneNumber ?? "未设置")")
        print("=========================")
    }
    
    /// 获取 Access Token
    func getAccessToken() -> String? {
        return getFromKeychain(key: accessTokenKey)
    }
    
    /// 获取 Refresh Token
    func getRefreshToken() -> String? {
        return getFromKeychain(key: refreshTokenKey)
    }
    
    /// 获取 Token 类型
    func getTokenType() -> String? {
        return UserDefaults.standard.string(forKey: tokenTypeKey)
    }
    
    /// 获取用户ID (sub)
    func getSub() -> String? {
        return UserDefaults.standard.string(forKey: subKey)
    }
    
    /// 获取手机号
    func getPhoneNumber() -> String? {
        return UserDefaults.standard.string(forKey: phoneNumberKey)
    }
    
    /// 获取 owner 字段（user_手机号）
    func getOwner() -> String? {
        guard let phoneNumber = getPhoneNumber(), !phoneNumber.isEmpty else {
            return nil
        }
        return "user_\(phoneNumber)"
    }
    
    /// 检查 Token 是否过期
    func isTokenExpired() -> Bool {
        guard let saveTime = UserDefaults.standard.object(forKey: saveTimeKey) as? TimeInterval,
              let expiresIn = UserDefaults.standard.object(forKey: expiresInKey) as? Int else {
            return true
        }
        
        let currentTime = Date().timeIntervalSince1970
        return currentTime > (saveTime + Double(expiresIn))
    }
    
    // MARK: - 上次验证时间管理
    
    /// 记录本次 auth verify 成功的时间
    func saveLastVerifyTime() {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: lastVerifyTimeKey)
        print("[TokenStorage] 已记录验证时间: \(Date())")
    }
    
    /// 获取上次验证成功的时间戳（秒）
    func getLastVerifyTime() -> TimeInterval? {
        let value = UserDefaults.standard.double(forKey: lastVerifyTimeKey)
        return value > 0 ? value : nil
    }
    
    /// 检查上次验证是否仍在 24 小时有效期内
    /// - Returns: true 表示仍在有效期，无需再次网络验证
    func isLastVerifyStillValid() -> Bool {
        guard let lastVerify = getLastVerifyTime() else {
            return false
        }
        let elapsed = Date().timeIntervalSince1970 - lastVerify
        let valid = elapsed < Self.tokenValidDuration
        print("[TokenStorage] 距上次验证: \(Int(elapsed))秒（\(String(format: "%.1f", elapsed / 3600))小时），\(valid ? "仍有效" : "已过期")")
        return valid
    }
    
    /// 清除所有 Token
    func clearToken() {
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: expiresInKey)
        UserDefaults.standard.removeObject(forKey: tokenTypeKey)
        UserDefaults.standard.removeObject(forKey: subKey)
        UserDefaults.standard.removeObject(forKey: phoneNumberKey)
        UserDefaults.standard.removeObject(forKey: saveTimeKey)
        UserDefaults.standard.removeObject(forKey: lastVerifyTimeKey)
        
        print("=== Token 已清除 ===")
    }
    
    // MARK: - Keychain 操作
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // 先删除已有的
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
