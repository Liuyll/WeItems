//
//  PrivacySettingsView.swift
//  WeItems
//

import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject private var privacySettings = PrivacySettings.shared
    @ObservedObject private var iapManager = IAPManager.shared
    @State private var showingProUpgrade = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Label("iCloud 自动同步", systemImage: "icloud.fill")
                    Spacer()
                    if iapManager.isVIPActive {
                        Toggle("", isOn: Binding(
                            get: {
                                if UserDefaults.standard.object(forKey: "iCloudAutoSyncEnabled") == nil {
                                    return true
                                }
                                return UserDefaults.standard.bool(forKey: "iCloudAutoSyncEnabled")
                            },
                            set: { UserDefaults.standard.set($0, forKey: "iCloudAutoSyncEnabled") }
                        ))
                        .labelsHidden()
                        .tint(.cyan)
                    } else {
                        Button {
                            showingProUpgrade = true
                        } label: {
                            Text("Pro")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                }
            } footer: {
                Text("开启后，数据将会自动同步到 iCloud")
            }
            
            Section {
                Toggle(isOn: $privacySettings.isClipboardReadEnabled) {
                    Label("读取剪贴板", systemImage: "doc.on.clipboard")
                }
                .tint(.green)
            } footer: {
                Text("开启后，可以快捷导入共享心愿清单")
            }
        }
        .navigationTitle("功能设置")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView()
        }
    }
}
