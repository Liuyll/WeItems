//
//  AuthView.swift
//  WeItems
//

import SwiftUI
import AuthenticationServices

/// 登录模式
enum LoginMode {
    case apple   // Apple 登录（默认）
    case phone   // 手机号登录
}

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var onLoginSuccess: ((SignupResponse) -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    
    // MARK: - 登录模式
    @State private var loginMode: LoginMode = .apple
    
    // MARK: - 表单字段
    @State private var account = ""          // 手机号
    @State private var password = ""         // 密码
    @State private var verificationCode = "" // 验证码
    
    // MARK: - UI状态
    @State private var isPasswordVisible = false
    @State private var phoneUsePassword = false
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var timer: Timer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingCreateUserConfirm = false
    @State private var verificationId: String?
    @State private var codeSent = false  // 验证码是否已发送
    @State private var passwordErrorText: String? = nil  // 密码登录错误提示
    
    // MARK: - 计算属性
    private var isPhone: Bool {
        account.hasPrefix("test_") || isPhoneNumber(account)
    }
    
    private var isAccountValid: Bool {
        !account.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var canSendCode: Bool {
        isPhone && countdown == 0 && !isSendingCode
    }
    
    private var canSubmit: Bool {
        if phoneUsePassword {
            return isAccountValid && !password.isEmpty
        }
        return isAccountValid && verificationCode.count >= 4
    }
    
    // MARK: - 标题动画
    private let heroLine = "即是存在的开端"
    @State private var charScales: [CGFloat] = []
    @State private var charOpacities: [Double] = []
    @State private var subtitleOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // 背景色（点击收起键盘）
            Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0)
                .ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
            VStack(spacing: 0) {
                // 右上角跳过
                HStack {
                    Spacer()
                    Button {
                        if let onSkip = onSkip {
                            onSkip()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("跳过")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                
                // 标题区域
                VStack(spacing: 10) {
                    Text("消费陷阱的脱离")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .opacity(subtitleOpacity)
                    
                    HStack(spacing: 0) {
                        ForEach(Array(heroLine.enumerated()), id: \.offset) { index, char in
                            Text(String(char))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .scaleEffect(index < charScales.count ? charScales[index] : 2.5)
                                .opacity(index < charOpacities.count ? charOpacities[index] : 0)
                        }
                    }
                }
                .padding(.top, 40)
                
                Spacer()
                
                // 登录区域
                VStack(spacing: 24) {
                    switch loginMode {
                    case .apple:
                        appleLoginContent
                    case .phone:
                        phoneLoginContent
                    }
                }
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.3), value: loginMode)
                .animation(.easeInOut(duration: 0.3), value: phoneUsePassword)
                .animation(.easeInOut(duration: 0.3), value: codeSent)
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .customInfoAlert(
            isPresented: $showingError,
            title: "提示",
            message: errorMessage ?? ""
        )
        .onAppear {
            startHeroAnimation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Apple 登录视图
    private var appleLoginContent: some View {
        VStack(spacing: 20) {
            // 通过苹果账号登录
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .cornerRadius(12)
            
            // 切换到手机号登录
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    loginMode = .phone
                }
            } label: {
                Text("使用手机号登录")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - 手机号登录视图
    private var phoneLoginContent: some View {
        VStack(spacing: 24) {
            // 手机号输入
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: phoneUsePassword ? "person" : "phone")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .animation(.easeInOut(duration: 0.2), value: phoneUsePassword)
                    
                    TextField(phoneUsePassword ? "用户名" : "手机号", text: $account, prompt: Text(phoneUsePassword ? "用户名" : "手机号").foregroundStyle(.white.opacity(0.35)))
                        .keyboardType(phoneUsePassword ? .default : .phonePad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                        .onChange(of: account) { _, _ in
                            password = ""
                            verificationCode = ""
                        }
                }
                .padding(.bottom, 12)
                
                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(height: 0.5)
            }
            
            // 验证码 / 密码
            if !phoneUsePassword {
                if codeSent {
                    // 验证码已发送，显示输入框
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "number")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.5))
                            
                            TextField("验证码", text: $verificationCode, prompt: Text("请输入验证码").foregroundStyle(.white.opacity(0.35)))
                                .keyboardType(.numberPad)
                                .foregroundStyle(.white)
                                .font(.system(size: 16))
                            
                            // 重新发送
                            Button {
                                Task { await sendCode() }
                            } label: {
                                if isSendingCode {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.white)
                                } else if countdown > 0 {
                                    Text("\(countdown)s")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.4))
                                } else {
                                    Text("重新发送")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .disabled(countdown > 0 || isSendingCode)
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 12)
                        
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(height: 0.5)
                    }
                    .transition(.opacity)
                } else {
                    // 验证码未发送，显示获取验证码按钮
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if isSendingCode {
                            ProgressView()
                                .tint(Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        } else {
                            Text("获取验证码")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                    }
                    .background(isAccountValid && isPhone ? .white : .white.opacity(0.5))
                    .cornerRadius(12)
                    .disabled(!isAccountValid || !isPhone || isSendingCode)
                    .shadow(color: .black.opacity(isAccountValid && isPhone ? 0.08 : 0), radius: 8, y: 4)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            } else {
                // 密码输入
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        if isPasswordVisible {
                            TextField("密码", text: $password, prompt: Text("密码").foregroundStyle(.white.opacity(0.35)))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .font(.system(size: 16))
                        } else {
                            SecureField("密码", text: $password, prompt: Text("密码").foregroundStyle(.white.opacity(0.35)))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .font(.system(size: 16))
                        }
                        
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)
                    
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 0.5)
                }
                .transition(.opacity)
                .onChange(of: password) { _, _ in
                    passwordErrorText = nil
                }
                .onChange(of: account) { _, _ in
                    passwordErrorText = nil
                }
            }
            
            // 登录按钮（验证码模式需发送后才显示）
            if phoneUsePassword || codeSent {
                let hasError = passwordErrorText != nil
                let submitEnabled = canSubmit && !isLoading && !hasError
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    Task { await submit() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    } else {
                        Text(hasError ? "用户名未创建或密码不正确" : (!phoneUsePassword ? "登录 / 注册" : "登录"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(hasError ? .white.opacity(0.5) : Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                }
                .background(submitEnabled ? .white : .white.opacity(0.35))
                .cornerRadius(12)
                .disabled(!submitEnabled)
                .animation(.easeInOut(duration: 0.2), value: submitEnabled)
                .shadow(color: .black.opacity(submitEnabled ? 0.08 : 0), radius: 8, y: 4)
                .padding(.top, 8)
            }
            
            // 底部切换
            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phoneUsePassword.toggle()
                        password = ""
                        verificationCode = ""
                        codeSent = false
                    }
                } label: {
                    Text(phoneUsePassword ? "使用验证码登录" : "使用密码登录")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Text("·").foregroundStyle(.white.opacity(0.3))
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                    loginMode = .apple
                    account = ""
                    password = ""
                    verificationCode = ""
                    codeSent = false
                    }
                } label: {
                    Text("使用 Apple 账户登录")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
    
    // MARK: - 标题动画
    
    private func startHeroAnimation() {
        let totalChars = heroLine.count
        charScales = Array(repeating: 2.5, count: totalChars)
        charOpacities = Array(repeating: 0, count: totalChars)
        subtitleOpacity = 0
        
        withAnimation(.easeOut(duration: 0.6)) {
            subtitleOpacity = 1
        }
        
        let staggerDelay = 0.8 / Double(totalChars)
        for i in 0..<totalChars {
            let delay = 0.3 + staggerDelay * Double(i)
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.7)
                .delay(delay)
            ) {
                charScales[i] = 1.0
                charOpacities[i] = 1.0
            }
        }
    }
    
    // MARK: - 工具方法
    
    private func isPhoneNumber(_ text: String) -> Bool {
        let pattern = "^(\\+86\\s?)?1[3-9]\\d{9}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }
    
    // MARK: - Apple 登录处理
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple 登录失败：无法获取凭证"
                showingError = true
                return
            }
            
            // 🔑 核心凭证（每次都返回）
            let userIdentifier = credential.user
            
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Apple 登录失败：无法获取 identityToken"
                showingError = true
                return
            }
            
            var authorizationCode: String? = nil
            if let codeData = credential.authorizationCode {
                authorizationCode = String(data: codeData, encoding: .utf8)
            }
            
            // 👤 用户信息（通常仅首次返回，必须立即保存）
            let fullName = credential.fullName
            let givenName = fullName?.givenName
            let familyName = fullName?.familyName
            let displayName = [givenName, familyName].compactMap { $0 }.joined(separator: " ")
            let email = credential.email
            
            // 首次授权时保存用户信息（后续不再返回）
            if let email = email {
                UserDefaults.standard.set(email, forKey: "apple_user_email")
            }
            if !displayName.isEmpty {
                UserDefaults.standard.set(displayName, forKey: "apple_user_name")
            }
            UserDefaults.standard.set(userIdentifier, forKey: "apple_user_id")
            
            print("=== Apple 登录凭证 ===")
            print("userIdentifier: \(userIdentifier)")
            print("identityToken (JWT):\n\(identityToken)")
            print("authorizationCode: \(authorizationCode ?? "nil")")
            print("displayName: \(displayName.isEmpty ? "(未提供)" : displayName)")
            print("email: \(email ?? "(未提供)")")
            print("=====================")
            
            Task {
                await appleLogin(
                    identityToken: identityToken,
                    userIdentifier: userIdentifier,
                    displayName: displayName,
                    email: email,
                    authorizationCode: authorizationCode
                )
            }
            
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Apple 登录失败：\(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func appleLogin(identityToken: String, userIdentifier: String, displayName: String, email: String?, authorizationCode: String?) async {
        await MainActor.run { isLoading = true }
        
        do {
            let response = try await ThirdPartyLoginManager.shared.loginWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier,
                displayName: displayName.isEmpty ? nil : displayName
            )
            
            let sanitized = userIdentifier.lowercased()
                .replacingOccurrences(of: ".", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            let username = "apple-\(sanitized.prefix(18))"
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: username
            )
            
            // 确保 CloudBaseClient 已创建（thirdInfo 同步需要）
            if AuthManager.shared.getCloudBaseClient() == nil {
                // loginSuccess 会在 onLoginSuccess 回调中被调用，这里先手动创建 client
                if let envId = Bundle.main.object(forInfoDictionaryKey: "CLOUDBASE_ENV_ID") as? String ?? Self.loadEnvId() {
                    let _ = CloudBaseClient(envId: envId, accessToken: response.accessToken)
                }
            }
            
            // 构造 third_info 并打印
            let dateFormatter = ISO8601DateFormatter()
            let savedEmail = email ?? UserDefaults.standard.string(forKey: "apple_user_email")
            let savedName = displayName.isEmpty ? UserDefaults.standard.string(forKey: "apple_user_name") : displayName
            
            let thirdInfo: [String: Any] = [
                "provider": "apple",
                "userId": userIdentifier,
                "email": savedEmail ?? "",
                "name": savedName ?? "",
                "identityToken": identityToken,
                "authorizationCode": authorizationCode ?? "",
                "loginTime": dateFormatter.string(from: Date()),
                "sub": response.sub
            ]
            
            print("========== Apple 登录成功 - thirdInfo ==========")
            print("provider:          apple")
            print("userId:            \(userIdentifier)")
            print("email:             \(savedEmail ?? "(无)")")
            print("name:              \(savedName ?? "(无)")")
            print("identityToken:     \(identityToken.prefix(80))...")
            print("authorizationCode: \(authorizationCode ?? "(无)")")
            print("loginTime:         \(dateFormatter.string(from: Date()))")
            print("sub:               \(response.sub)")
            print("=================================================")
            
            // 异步保存 third_info 到远端 userinfo
            Task {
                if let client = AuthManager.shared.getCloudBaseClient() {
                    await client.updateUserInfoThirdInfo(thirdInfo: thirdInfo)
                    print("[Apple登录] third_info 已同步到远端")
                } else {
                    // 登录刚完成，需要用新 token 创建 client
                    if let envId = Bundle.main.object(forInfoDictionaryKey: "CLOUDBASE_ENV_ID") as? String ?? Self.loadEnvId() {
                        let client = CloudBaseClient(envId: envId, accessToken: response.accessToken)
                        await client.updateUserInfoThirdInfo(thirdInfo: thirdInfo)
                        print("[Apple登录] third_info 已同步到远端（新建 client）")
                    }
                }
            }
            
            await MainActor.run {
                isLoading = false
                AuthManager.shared.loginSuccess(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    expiresIn: response.expiresIn,
                    tokenType: response.tokenType,
                    sub: response.sub
                )
                onLoginSuccess?(response)
                dismiss()
            }
        } catch ThirdPartyLoginError.cancelled {
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "登录失败：\(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    /// 从 Config.plist 加载环境 ID
    private static func loadEnvId() -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CLOUDBASE_ENV_ID"] as? String
    }
    
    // MARK: - 网络请求
    
    private func sendCode() async {
        isSendingCode = true
        errorMessage = nil
        
        do {
            let result = try await VerificationManager.shared.sendPhoneVerificationCode(
                phoneNumber: account,
                target: "ANY"
            )
            
            verificationId = result.verificationId
            countdown = min(result.expiresIn, 60)
            startCountdown()
            
            print("=== 验证码发送成功 ===")
            print("verificationId: \(result.verificationId)")
            print("expiresIn: \(result.expiresIn)")
            print("isUser: \(result.isUser)")
            print("=====================")
            
            await MainActor.run {
                codeSent = true
            }
            
        } catch let error as VerificationError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "发送失败：\(error.localizedDescription)"
                showingError = true
            }
        }
        
        await MainActor.run {
            isSendingCode = false
        }
    }
    
    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer?.invalidate()
            }
        }
    }
    
    private func submit() async {
        isLoading = true
        
        do {
            if !phoneUsePassword {
                try await submitPhoneLogin()
            } else {
                try await submitPasswordLogin()
            }
        } catch {
            // 错误已在各自方法中处理
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    /// 手机号 + 密码登录
    private func submitPasswordLogin() async throws {
        print("[AuthView] 手机号密码登录: \(account)")
        do {
            let response = try await LoginManager.shared.loginWithPhone(
                phoneNumber: account,
                password: "Password_\(password)"
            )
            
            // 先保存 phoneNumber（loginSuccess 不带此参数）
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: account
            )
            
            print("=== 密码登录成功 ===")
            
            await MainActor.run {
                // 直接调用 loginSuccess 触发数据加载和自动同步
                AuthManager.shared.loginSuccess(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    expiresIn: response.expiresIn,
                    tokenType: response.tokenType,
                    sub: response.sub
                )
                onLoginSuccess?(response)
                dismiss()
            }
        } catch {
            await MainActor.run {
                passwordErrorText = "用户未创建或密码不正确"
            }
            throw error
        }
    }
    private func submitPhoneLogin() async throws {
        let finalVerificationId = verificationId ?? account
        
        do {
            let jwtToken = try await VerificationManager.shared.verifyCode(
                verificationId: finalVerificationId,
                verificationCode: verificationCode
            )
            
            let response: SignupResponse
            
            do {
                response = try await LoginManager.shared.loginWithPhoneVerification(
                    phoneNumber: account,
                    verificationToken: jwtToken
                )
                print("=== 验证码登录成功 ===")
            } catch LoginError.userNotFound {
                print("用户不存在，开始注册...")
                let username = "user_\(account)"
                response = try await SignupManager.shared.signupWithPhone(
                    phoneNumber: account,
                    verificationToken: jwtToken,
                    username: username,
                    password: "Password_12345678"
                )
                print("=== 注册成功 ===")
            }
            
            // 先保存 phoneNumber（loginSuccess 不带此参数）
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: account
            )
            
            await MainActor.run {
                // 直接调用 loginSuccess 触发数据加载和自动同步
                AuthManager.shared.loginSuccess(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    expiresIn: response.expiresIn,
                    tokenType: response.tokenType,
                    sub: response.sub
                )
                onLoginSuccess?(response)
                dismiss()
            }
        } catch let error as SignupError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
            throw error
        } catch let error as VerificationError {
            await MainActor.run {
                errorMessage = "验证码错误：\(error.localizedDescription)"
                showingError = true
            }
            throw error
        } catch let error as LoginError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
            throw error
        } catch {
            await MainActor.run {
                errorMessage = "操作失败：\(error.localizedDescription)"
                showingError = true
            }
            throw error
        }
    }
    
}

#Preview {
    AuthView()
}
