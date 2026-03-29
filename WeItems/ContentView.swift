//
//  ContentView.swift
//  WeItems
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isLaunching: Bool
    
    init() {
        // 迁移旧数据到 anonymous 目录（仅首次，同步操作很快）
        UserStorageHelper.shared.migrateRootDataIfNeeded()
        
        // 判断是否需要展示开屏页面：
        // - 没有 token（无需验证）→ 不展示
        // - 有 token 且 24h 内已验证过 → 不展示（不需要网络请求）
        // - 有 token 但超过 24h → 展示（需要网络请求刷新 token）
        let needsLaunchScreen = AuthManager.shared.needsNetworkVerification()
        _isLaunching = State(initialValue: needsLaunchScreen)
    }
    
    var body: some View {
        Group {
            if isLaunching {
                // 启动画面（仅在需要网络验证 token 时展示）
                LaunchScreenView()
                    .onAppear {
                        Task {
                            // 启动时验证 token（需要网络请求）
                            await authManager.validateTokenOnLaunch()
                            
                            // 延迟一点以确保平滑过渡
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                            
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isLaunching = false
                                }
                            }
                        }
                    }
            } else {
                // 主界面
                HomeView()
                    .environmentObject(authManager)
                    .onAppear {
                        print("[ContentView] 认证状态: \(authManager.authState)")
                        // 如果跳过了开屏页面，在后台静默验证 token
                        if authManager.authState == .unknown {
                            Task {
                                await authManager.validateTokenOnLaunch()
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - 启动画面
struct LaunchScreenView: View {
    private let secondLine = "即是存在的开端"
    @State private var charOpacities: [Double] = []
    @State private var charOffsets: [CGFloat] = []
    
    var body: some View {
        ZStack {
            // 暖色调背景
            Color(red: 0.94, green: 0.93, blue: 0.92)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // 主文字
                VStack(spacing: 16) {
                    Text("消费陷阱的脱离")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.gray)
                    
                    // 逐字流畅出现，2倍大粗体，天蓝色
                    HStack(spacing: 0) {
                        ForEach(Array(secondLine.enumerated()), id: \.offset) { index, char in
                            Text(String(char))
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(Color(red: 0.35, green: 0.72, blue: 0.93))
                                .opacity(index < charOpacities.count ? charOpacities[index] : 0)
                                .offset(y: index < charOffsets.count ? charOffsets[index] : 8)
                        }
                    }
                }
                .multilineTextAlignment(.center)
                
                Spacer()
                
                // Loading 指示器
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.gray)
                    .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            let totalChars = secondLine.count
            // 初始化状态
            charOpacities = Array(repeating: 0, count: totalChars)
            charOffsets = Array(repeating: 8, count: totalChars)
            
            let totalDuration = 1.0
            let staggerDelay = totalDuration / Double(totalChars)
            
            for i in 0..<totalChars {
                let delay = staggerDelay * Double(i)
                withAnimation(
                    .easeOut(duration: 0.4)
                    .delay(delay)
                ) {
                    charOpacities[i] = 1
                    charOffsets[i] = 0
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
