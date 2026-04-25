//
//  WeItemsApp.swift
//  WeItems
//
//  Created by yl Liu on 2026/3/2.
//

import SwiftUI

@main
struct WeItemsApp: App {
    
    init() {
        // 启动时触发系统网络权限弹窗（蜂窝/WiFi）
        triggerNetworkPermission()
        
        #if DEBUG
        // 启动内存日志拦截（自动捕获所有 print 输出）
        DebugLogManager.shared.startCapturing()
        #endif
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // App 回到前台时检查订阅状态（退款/取消订阅）
                        Task { await IAPManager.shared.checkSubscriptionStatus() }
                    }
                }
        }
    }
    
    /// 发起一个轻量网络请求，触发 iOS 网络权限弹窗
    private func triggerNetworkPermission() {
        guard let url = URL(string: "https://apple.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
