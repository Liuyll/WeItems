//
//  PrivacySettingsView.swift
//  WeItems
//

import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject private var privacySettings = PrivacySettings.shared
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $privacySettings.isClipboardReadEnabled) {
                    Label("读取剪贴板", systemImage: "doc.on.clipboard")
                }
                .tint(.green)
            } footer: {
                Text("开启后，启动 App 时会自动读取剪贴板，检测好朋友分享的清单 ID 并快速导入。关闭后将不再自动读取剪贴板。")
            }
        }
        .navigationTitle("我的隐私")
        .navigationBarTitleDisplayMode(.large)
    }
}
