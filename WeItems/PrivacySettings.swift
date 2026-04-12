//
//  PrivacySettings.swift
//  WeItems
//

import Foundation
import UIKit
import Combine

class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()
    
    private let clipboardReadKey = "privacy_clipboard_read_enabled"
    
    @Published var isClipboardReadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isClipboardReadEnabled, forKey: clipboardReadKey)
        }
    }
    
    private init() {
        // 默认关闭剪贴板读取权限
        if UserDefaults.standard.object(forKey: clipboardReadKey) == nil {
            UserDefaults.standard.set(false, forKey: clipboardReadKey)
        }
        self.isClipboardReadEnabled = UserDefaults.standard.bool(forKey: clipboardReadKey)
    }
    
    /// 复制到剪贴板（始终允许写入）
    @discardableResult
    static func copyToClipboard(_ text: String) -> Bool {
        UIPasteboard.general.string = text
        return true
    }
    
    /// 读取剪贴板内容，仅在用户开启读取权限时执行
    /// - Returns: 剪贴板文本内容，关闭时返回 nil
    static func readFromClipboard() -> String? {
        guard shared.isClipboardReadEnabled else { return nil }
        return UIPasteboard.general.string
    }
}
