//
//  ContentView.swift
//  WeItems
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isLaunching = true
    
    var body: some View {
        Group {
            if isLaunching {
                // 启动画面
                LaunchScreenView()
                    .onAppear {
                        Task {
                            // 迁移旧数据到 anonymous 目录（仅首次）
                            UserStorageHelper.shared.migrateRootDataIfNeeded()
                            
                            // 启动时验证 token
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
                    }
            }
        }
    }
}

// MARK: - 启动画面
struct LaunchScreenView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景色与图片边缘一致
                Color(red: 0.94, green: 0.93, blue: 0.92)
                    .ignoresSafeArea()
                
                // 背景图片（铺满屏幕，居中裁剪）
                Image("LaunchBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
            
                // Loading 指示器
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.gray)
                        .padding(.bottom, 80)
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
