//
//  DebugLogManager.swift
//  WeItems
//

import Foundation
import SwiftUI
import Combine

#if DEBUG
/// DEBUG 模式下的内存日志管理器
/// 通过拦截 stdout 自动捕获所有 print 输出
class DebugLogManager: ObservableObject {
    static let shared = DebugLogManager()
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }
    
    @Published private(set) var logs: [LogEntry] = []
    private let maxLogs = 1000
    private let queue = DispatchQueue(label: "com.weitems.debuglog", qos: .utility)
    
    // stdout 拦截
    private var originalStdout: Int32 = -1
    private var pipe = Pipe()
    private var isCapturing = false
    
    private init() {}
    
    /// 开始拦截 stdout（在 App 启动时调用一次）
    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // 保存原始 stdout
        originalStdout = dup(STDOUT_FILENO)
        
        // 将 stdout 重定向到 pipe
        setvbuf(stdout, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        // 异步读取 pipe 中的数据
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            
            // 同时写到原始 stdout（Xcode 控制台）
            if let self = self, self.originalStdout >= 0 {
                data.withUnsafeBytes { rawBuffer in
                    if let ptr = rawBuffer.baseAddress {
                        write(self.originalStdout, ptr, data.count)
                    }
                }
            }
            
            // 写入内存日志
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                self?.log(line)
            }
        }
    }
    
    func log(_ message: String) {
        let entry = LogEntry(timestamp: Date(), message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logs.append(entry)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    /// 导出所有日志为文本
    var exportText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return logs.map { "[\(formatter.string(from: $0.timestamp))] \($0.message)" }.joined(separator: "\n")
    }
}

// MARK: - 日志查看页面

struct DebugLogView: View {
    @ObservedObject private var logManager = DebugLogManager.shared
    @State private var searchText = ""
    @State private var autoScroll = true
    
    private var filteredLogs: [DebugLogManager.LogEntry] {
        if searchText.isEmpty {
            return logManager.logs
        }
        return logManager.logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
    }
    
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("\(logManager.logs.count) 条日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Toggle("自动滚动", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                
                Button("清空") {
                    logManager.clear()
                }
                .font(.caption)
                .foregroundStyle(.red)
                
                ShareLink(item: logManager.exportText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            
            Divider()
            
            // 日志列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(timeFormatter.string(from: entry.timestamp))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 75, alignment: .leading)
                                
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(logColor(entry.message))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: logManager.logs.count) { _, _ in
                    if autoScroll, let last = filteredLogs.last {
                        withAnimation(.none) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "过滤日志...")
        .navigationTitle("调试日志")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func logColor(_ message: String) -> Color {
        if message.contains("失败") || message.contains("错误") || message.contains("异常") || message.contains("Error") {
            return .red
        }
        if message.contains("成功") || message.contains("完成") {
            return .green
        }
        if message.contains("⚠️") || message.contains("警告") {
            return .orange
        }
        return .primary
    }
}

// MARK: - Debug 测试入口页

struct DebugTestView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingVIPTest = false
    @State private var showingLoginTest = false
    @State private var showingUnsubscribeConfirm = false
    @State private var showingGrantVIPConfirm = false
    
    var body: some View {
        List {
            Section("功能测试") {
                // VIP 购买测试
                Button {
                    showingVIPTest = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VIP 购买测试")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            Text("VIP 状态: \(IAPManager.shared.isVIPActive ? "✅ 已激活" : "❌ 未激活")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .foregroundStyle(.primary)
                
                // 登录测试
                Button {
                    showingLoginTest = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登录测试")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            Text("登录状态: \(authManager.isAuthenticated ? "✅ 已登录" : "❌ 未登录")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.primary)
                
                // 模拟用户退订
                Button {
                    showingUnsubscribeConfirm = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("模拟用户退订")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            Text("将远端和本地 VIP 状态置为 0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(.primary)
                
                // 升级友情账户
                Button {
                    showingGrantVIPConfirm = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("升级友情账户")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            Text("将远端和本地 VIP 状态置为 99")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "heart.circle.fill")
                            .foregroundStyle(.pink)
                    }
                }
                .foregroundStyle(.primary)
            }
            
            Section("日志") {
                NavigationLink {
                    DebugLogView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("查看日志")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                            Text("\(DebugLogManager.shared.logs.count) 条日志")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Section("环境信息") {
                infoRow("用户 Sub", value: TokenStorage.shared.getSub() ?? "无")
                infoRow("Access Token", value: String((TokenStorage.shared.getAccessToken() ?? "无").prefix(20)) + "...")
                infoRow("Refresh Token", value: String((TokenStorage.shared.getRefreshToken() ?? "无").prefix(20)) + "...")
                infoRow("Token 过期", value: tokenExpireDescription())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Debug 测试")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingVIPTest) {
            ProUpgradeView()
        }
        .sheet(isPresented: $showingLoginTest) {
            NavigationStack {
                AuthViewWrapper()
                    .environmentObject(authManager)
            }
        }
        .customBlueConfirmAlert(
            isPresented: $showingUnsubscribeConfirm,
            message: "确定模拟退订？将把远端和本地 VIP 状态置为 0（免费用户）",
            confirmText: "确定退订",
            cancelText: "取消",
            confirmColor: .white,
            cancelColor: .white.opacity(0.7),
            backgroundColor: .red,
            onConfirm: {
                Task {
                    await MainActor.run {
                        IAPManager.shared.applyRemoteVIPInfo(type: 0, startDate: nil, expireDate: nil)
                    }
                    let tokenValid = await AuthManager.shared.ensureValidToken()
                    if tokenValid {
                        await IAPManager.shared.syncVIPToCloud()
                    }
                    print("[Debug] 已模拟退订，VIP 状态置为 free")
                }
            }
        )
        .customBlueConfirmAlert(
            isPresented: $showingGrantVIPConfirm,
            message: "确定升级为友情账户？将把远端和本地 VIP 状态置为 99（永久VIP）",
            confirmText: "确定升级",
            cancelText: "取消",
            confirmColor: .white,
            cancelColor: .white.opacity(0.7),
            backgroundColor: .pink,
            onConfirm: {
                Task {
                    let isoFormatter = ISO8601DateFormatter()
                    let now = isoFormatter.string(from: Date())
                    var components = DateComponents()
                    components.year = 9999; components.month = 12; components.day = 31
                    let forever = isoFormatter.string(from: Calendar.current.date(from: components) ?? Date())
                    await MainActor.run {
                        IAPManager.shared.applyRemoteVIPInfo(type: 99, startDate: now, expireDate: forever)
                    }
                    let tokenValid = await AuthManager.shared.ensureValidToken()
                    if tokenValid {
                        await IAPManager.shared.syncVIPToCloud()
                    }
                    print("[Debug] 已升级为友情账户(99)，VIP 状态置为 grantedVIP")
                }
            }
        )
    }
    
    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
    
    private func tokenExpireDescription() -> String {
        let remaining = TokenStorage.shared.tokenRemainingSeconds()
        if remaining <= 0 {
            return "已过期"
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let expireDate = Date().addingTimeInterval(remaining)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "剩余\(hours)h\(minutes)m (\(formatter.string(from: expireDate)))"
    }
}
#endif
