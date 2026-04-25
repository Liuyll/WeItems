//
//  AppEnvironment.swift
//  WeItems
//

import Foundation

enum AppEnvironment: String {
    case debug = "Debug"
    case testFlight = "TestFlight"
    case appStore = "App Store"
    
    static var current: AppEnvironment {
        #if DEBUG
        return .debug
        #else
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        return .appStore
        #endif
    }
    
    /// 版本号后缀，App Store 不显示
    static var versionSuffix: String {
        let env = current
        if env == .appStore {
            return ""
        }
        return " (\(env.rawValue))"
    }
    
    /// 当前 App 版本号
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    /// 比较两个语义化版本号 (x.x.x)
    /// - Returns: .orderedAscending 表示 v1 < v2，.orderedSame 表示相等，.orderedDescending 表示 v1 > v2
    static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }
    
    /// 判断远端版本是否比当前版本更新
    static func isNewerVersion(_ remoteVersion: String) -> Bool {
        return compareVersions(currentVersion, remoteVersion) == .orderedAscending
    }
    
    /// 是否需要检查强制更新（仅 Debug 和 TestFlight 需要）
    static var needsUpdateCheck: Bool {
        current != .appStore
    }
    
    /// TestFlight 更新链接
    static var testFlightUpdateURL: String {
        "itms-beta://"
    }
}
