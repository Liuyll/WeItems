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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
