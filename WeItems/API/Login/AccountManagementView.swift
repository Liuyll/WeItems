//
//  AccountManagementView.swift
//  WeItems
//

import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State private var userProfile: UserProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedToast = false
    
    // 修改密码相关
    @State private var showingChangePassword = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChangingPassword = false
    @State private var passwordMessage: String?
    @State private var passwordSuccess = false
    @State private var isOldPasswordVisible = false
    @State private var isNewPasswordVisible = false
    
    // 修改用户名相关
    @State private var showingChangeUsername = false
    @State private var usernameInput = ""
    @State private var isChangingUsername = false
    @State private var usernameMessage: String?
    @State private var usernameSuccess = false
    
    var body: some View {
        List {
            // 账号信息
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("加载中...")
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if let profile = userProfile {
                // 用户ID
                Section {
                    Button {
                        let userId = displayUsername(profile.username ?? profile.sub)
                        UIPasteboard.general.string = userId
                        copiedToast = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 24)
                                Text("用户ID")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(displayUsername(profile.username ?? profile.sub))
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Text("用户 ID 可用于不同平台登录")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .listRowBackground(Color.green)
                    .listRowSeparator(.hidden)
                } header: {
                    Spacer()
                        .frame(height: 20)
                }
                
                // 设置/修改密码 + 修改用户名
                Section {
                    Button {
                        showingChangePassword = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.white)
                                .frame(width: 24)
                            Text(profile.isPasswordSet ? "修改密码" : "设置密码")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.blue)
                    .listRowSeparator(.hidden)
                    
                    Button {
                        usernameInput = ""
                        showingChangeUsername = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "at")
                                .foregroundStyle(.white)
                                .frame(width: 24)
                            Text("修改用户名")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.blue)
                    .listRowSeparator(.hidden)
                }
                
                // 已设置的登录方式
                if let providers = profile.providers, !providers.isEmpty {
                    Section("已设置的登录方式") {
                        ForEach(providers.indices, id: \.self) { index in
                            let provider = providers[index]
                            Label {
                                Text(providerName(provider.id))
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: providerIcon(provider.id))
                                    .foregroundStyle(providerColor(provider.id))
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                
            } else if let error = errorMessage {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await loadProfile() }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的账号")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadProfile()
        }
        .sheet(isPresented: $showingChangePassword) {
            changePasswordSheet
        }
        .sheet(isPresented: $showingChangeUsername) {
            changeUsernameSheet
        }
        .customBlueInfoAlert(
            isPresented: $usernameSuccess,
            message: "用户名已更新"
        )
        .overlay {
            if copiedToast {
                VStack {
                    Spacer()
                    Text("已复制到剪贴板")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: copiedToast)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copiedToast = false }
                    }
                }
            }
        }
        .customBlueInfoAlert(
            isPresented: $passwordSuccess,
            message: "新密码已生效"
        )
    }
    
    // MARK: - 信息行
    
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .listRowSeparator(.hidden)
    }
    
    // MARK: - 加载用户信息
    
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await UserManager.shared.getUserProfile()
            await MainActor.run {
                self.userProfile = profile
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - 修改密码 Sheet
    
    private let themeColor = Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0)
    
    private var changePasswordSheet: some View {
        VStack(spacing: 24) {
            // 旧密码
            if userProfile?.isPasswordSet == true {
                authInputField(icon: "lock", placeholder: "当前密码", text: $oldPassword, isSecure: !isOldPasswordVisible, showEye: true, isEyeOpen: $isOldPasswordVisible)
            }
            
            // 新密码
            authInputField(icon: "lock.fill", placeholder: "新密码", text: $newPassword, isSecure: !isNewPasswordVisible, showEye: true, isEyeOpen: $isNewPasswordVisible)
            
            // 确认密码
            authInputField(icon: "lock.rotation", placeholder: "确认新密码", text: $confirmPassword, isSecure: true, showEye: false, isEyeOpen: .constant(false))
            
            // 错误提示
            if let msg = passwordMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 提交按钮
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                Task { await submitChangePassword() }
            } label: {
                if isChangingPassword {
                    ProgressView()
                        .tint(themeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                } else {
                    Text(userProfile?.isPasswordSet == true ? "确认修改" : "设置密码")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
            }
            .background(canSubmitPassword ? .white : .white.opacity(0.5))
            .cornerRadius(12)
            .buttonStyle(.plain)
            .disabled(!canSubmitPassword || isChangingPassword)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(themeColor)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(themeColor)
        .scrollDismissesKeyboard(.interactively)
    }
    
    private var canSubmitPassword: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && (userProfile?.isPasswordSet != true || !oldPassword.isEmpty)
    }
    
    /// 输入框组件
    private func authInputField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool, showEye: Bool, isEyeOpen: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20)
                
                if isSecure {
                    SecureField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                } else {
                    TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                }
                
                if showEye {
                    Button {
                        isEyeOpen.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isEyeOpen.wrappedValue ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
            
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 0.5)
        }
    }
    
    private func submitChangePassword() async {
        guard newPassword == confirmPassword else {
            passwordMessage = "两次输入的密码不一致"
            return
        }
        guard newPassword.count >= 6 else {
            passwordMessage = "密码至少需要6个字符"
            return
        }
        guard newPassword.count <= 20 else {
            passwordMessage = "密码最多20个字符"
            return
        }
        
        let realNewPassword = "Password_\(newPassword)"
        
        isChangingPassword = true
        passwordMessage = nil
        
        do {
            if userProfile?.isPasswordSet == true {
                // 有旧密码：获取 sudo_token → 修改密码
                guard !oldPassword.isEmpty else {
                    passwordMessage = "请输入当前密码"
                    isChangingPassword = false
                    return
                }
                let realOldPassword = "Password_\(oldPassword)"
                let sudoResult = try await UserManager.shared.getSudoTokenWithPassword(password: realOldPassword)
                try await UserManager.shared.changePassword(
                    sudoToken: sudoResult.sudoToken,
                    oldPassword: realOldPassword,
                    newPassword: realNewPassword
                )
            } else {
                // 首次设置密码：直接用 access_token
                try await UserManager.shared.setPassword(newPassword: realNewPassword)
            }
            
            // 刷新用户信息（确保 hasPassword 更新）
            await loadProfile()
            
            await MainActor.run {
                isChangingPassword = false
                resetPasswordFields()
                showingChangePassword = false
                passwordSuccess = true
            }
        } catch {
            await MainActor.run {
                isChangingPassword = false
                passwordMessage = error.localizedDescription
            }
        }
    }
    
    private func resetPasswordFields() {
        oldPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordMessage = nil
    }
    
    // MARK: - 修改用户名 Sheet
    
    private var changeUsernameSheet: some View {
        VStack(spacing: 24) {
            // 旧用户名（只读置灰）
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "at")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(displayUsername(userProfile?.username))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.bottom, 12)
                
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 0.5)
            }
            
            // 新用户名
            authInputField(icon: "at", placeholder: "新用户名", text: $usernameInput, isSecure: false, showEye: false, isEyeOpen: .constant(false))
            
            // 错误提示
            if let msg = usernameMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 提交按钮
            let canSubmit = !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                Task { await submitChangeUsername() }
            } label: {
                if isChangingUsername {
                    ProgressView()
                        .tint(themeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                } else {
                    Text("确认修改")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
            }
            .background(canSubmit ? .white : .white.opacity(0.5))
            .cornerRadius(12)
            .buttonStyle(.plain)
            .disabled(!canSubmit || isChangingUsername)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(themeColor)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(themeColor)
        .scrollDismissesKeyboard(.interactively)
    }
    
    private func submitChangeUsername() async {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            usernameMessage = "用户名至少需要3个字符"
            return
        }
        guard trimmed.count <= 16 else {
            usernameMessage = "用户名最多16个字符"
            return
        }
        
        isChangingUsername = true
        usernameMessage = nil
        
        do {
            try await UserManager.shared.editUserBasic(username: "user_\(trimmed)")
            await MainActor.run {
                isChangingUsername = false
                showingChangeUsername = false
                usernameSuccess = true
                Task { await loadProfile() }
            }
        } catch {
            await MainActor.run {
                isChangingUsername = false
                usernameMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 实时校验密码（输入时触发）
    private func validatePasswordRealtime(_ password: String) {
        guard !password.isEmpty else {
            passwordMessage = nil
            return
        }
        if password.count < 8 {
            passwordMessage = "密码至少需要8个字符"
            return
        }
        if password.count > 64 {
            passwordMessage = "密码最多64个字符"
            return
        }
        if let error = validatePasswordStrength(password) {
            passwordMessage = error
            return
        }
        // 密码格式通过，检查确认密码一致性
        if !confirmPassword.isEmpty && confirmPassword != password {
            passwordMessage = "两次输入的密码不一致"
            return
        }
        passwordMessage = nil
    }
    
    /// 校验密码强度，返回错误提示或 nil（通过）
    private func validatePasswordStrength(_ password: String) -> String? {
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        
        if !hasUppercase { return "密码需要包含至少一个大写字母" }
        if !hasLowercase { return "密码需要包含至少一个小写字母" }
        if !hasDigit { return "密码需要包含至少一个数字" }
        if !hasSpecial { return "密码需要包含至少一个特殊字符" }
        return nil
    }
    
    /// 展示用户名（去掉 user_ 前缀）
    private func displayUsername(_ username: String?) -> String {
        guard let name = username else { return "未设置" }
        if name.hasPrefix("user_") {
            return String(name.dropFirst(5))
        }
        return name
    }
    
    private func statusText(_ status: String?) -> String {
        switch status {
        case "ACTIVE": return "正常"
        case "BLOCKED": return "已封禁"
        case "PENDING": return "待激活"
        default: return status ?? "未知"
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        // 尝试不带毫秒
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return dateString
    }
    
    private func providerIcon(_ providerId: String?) -> String {
        switch providerId {
        case "phone": return "phone.fill"
        case "apple": return "apple.logo"
        case "wechat": return "bubble.left.fill"
        default: return "link.circle.fill"
        }
    }
    
    private func providerName(_ providerId: String?) -> String {
        switch providerId {
        case "phone": return "手机号"
        case "apple": return "Apple"
        case "wechat": return "微信"
        default: return providerId ?? "未知"
        }
    }
    
    private func providerColor(_ providerId: String?) -> Color {
        switch providerId {
        case "phone": return .green
        case "apple": return .primary
        case "wechat": return .green
        default: return .blue
        }
    }
}
