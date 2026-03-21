//
//  AuthView.swift
//  WeItems
//

import SwiftUI

// MARK: - 登录模式枚举
enum LoginMode {
    case password    // 密码登录
    case verification // 验证码登录/注册
}

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    
    var onLoginSuccess: ((SignupResponse) -> Void)? = nil
    
    // MARK: - 登录模式
    @State private var loginMode: LoginMode = .password
    
    // MARK: - 表单字段
    @State private var phoneNumber = ""  // 手机号
    @State private var password = ""     // 密码
    @State private var verificationCode = "" // 验证码
    
    // MARK: - UI状态
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var timer: Timer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var verificationId: String?
    
    // MARK: - 验证状态
    private var isPhoneValid: Bool {
        phoneNumber.hasPrefix("test_") || isPhoneNumber(phoneNumber)
    }
    
    private var canSendCode: Bool {
        isPhoneValid && countdown == 0 && !isSendingCode
    }
    
    private var canSubmit: Bool {
        if loginMode == .password {
            // 密码登录：手机号有效且密码不为空
            return isPhoneValid && !password.isEmpty
        } else {
            // 验证码登录/注册：手机号有效且验证码至少4位
            return isPhoneValid && verificationCode.count >= 4
        }
    }
    
    private var submitButtonTitle: String {
        if loginMode == .password {
            return "登录"
        } else {
            // 验证码模式根据是否获取过验证码判断是登录还是注册
            return verificationId != nil ? "登录" : "注册"
        }
    }
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [.green.opacity(0.7), .mint.opacity(0.8), .teal.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // 标题
                VStack(spacing: 8) {
                    Text("欢迎")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text(loginMode == .password ? "密码登录" : "验证码登录")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 60)
                
                Spacer()
                
                // 毛玻璃卡片
                VStack(spacing: 20) {
                    // 手机号输入
                    HStack {
                        Image(systemName: "phone")
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 24)
                        
                        TextField("手机号", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    
                    // 手机号格式错误提示
                    if !phoneNumber.isEmpty && !isPhoneValid {
                        HStack {
                            Text("无效的手机号")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, -12)
                    }
                    
                    if loginMode == .password {
                        // 密码输入
                        HStack {
                            Image(systemName: "lock")
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 24)
                            
                            SecureField("密码", text: $password)
                                .foregroundStyle(.white)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    } else {
                        // 验证码输入
                        HStack {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 24)
                            
                            TextField("验证码", text: $verificationCode)
                                .keyboardType(.numberPad)
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    await sendCode()
                                }
                            } label: {
                                if isSendingCode {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else if countdown > 0 {
                                    Text("\(countdown)s")
                                        .foregroundStyle(.white.opacity(0.6))
                                } else {
                                    Text("获取")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                }
                            }
                            .disabled(!canSendCode)
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                    
                    // 登录/注册按钮
                    let submitEnabled = canSubmit && !isLoading
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.green)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(loginMode == .password ? "登录" : (verificationId != nil ? "登录" : "注册"))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(submitEnabled ? .green : .gray)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(submitEnabled ? .white : .white.opacity(0.5))
                    .cornerRadius(16)
                    .disabled(!submitEnabled)
                    .animation(.easeInOut(duration: 0.2), value: submitEnabled)
                    .padding(.top, 10)
                    
                    // 切换登录方式
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            loginMode = loginMode == .password ? .verification : .password
                            // 清空密码和验证码
                            password = ""
                            verificationCode = ""
                        }
                    } label: {
                        Text(loginMode == .password ? "使用验证码登录 / 注册" : "使用密码登录")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                            .underline()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // 关闭按钮
                Button {
                    dismiss()
                } label: {
                    Text("暂时不需要")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.bottom, 40)
            }
        }
        .alert("提示", isPresented: $showingError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func isPhoneNumber(_ text: String) -> Bool {
        let pattern = "^(\\+86\\s?)?1[3-9]\\d{9}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }
    
    private func sendCode() async {
        isSendingCode = true
        errorMessage = nil
        
        do {
            let result = try await VerificationManager.shared.sendPhoneVerificationCode(
                phoneNumber: phoneNumber,
                target: "ANY"
            )
            
            verificationId = result.verificationId
            countdown = min(result.expiresIn, 60)
            startCountdown()
            
            // 打印验证码回包
            print("=== 验证码发送成功 ===")
            print("verificationId: \(result.verificationId)")
            print("expiresIn: \(result.expiresIn)")
            print("isUser: \(result.isUser)")
            print("=====================")
            
            await MainActor.run {
                errorMessage = "验证码已发送"
                showingError = true
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
            if loginMode == .password {
                // 密码登录
                try await submitPasswordLogin()
            } else {
                // 验证码登录/注册
                try await submitVerificationLogin()
            }
        } catch {
            // 错误已在各自方法中处理
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func submitPasswordLogin() async throws {
        do {
            let response = try await LoginManager.shared.loginWithPhone(
                phoneNumber: phoneNumber,
                password: password
            )
            
            // 保存 Token 到本地（同时保存手机号）
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: phoneNumber
            )
            
            print("=== 密码登录成功 ===")
            print("Access Token: \(response.accessToken)")
            print("Refresh Token: \(response.refreshToken)")
            print("Phone Number: \(phoneNumber)")
            print("================")
            
            await MainActor.run {
                // 如果有回调，调用回调
                if let onLoginSuccess = onLoginSuccess {
                    onLoginSuccess(response)
                }
                // 直接关闭页面，不弹 toast
                dismiss()
            }
        } catch let error as LoginError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
            throw error
        } catch {
            await MainActor.run {
                errorMessage = "登录失败：\(error.localizedDescription)"
                showingError = true
            }
            throw error
        }
    }

    private func submitVerificationLogin() async throws {
        // 如果没点击获取验证码，用手机号作为 verification_id
        let finalVerificationId = verificationId ?? phoneNumber
        
        do {
            // 1. 用 verification_id + verification_code 换取 JWT token
            print("正在验证验证码换取 JWT...")
            print("verification_id: \(finalVerificationId)")
            print("verification_code: \(verificationCode)")
            let jwtToken = try await VerificationManager.shared.verifyCode(
                verificationId: finalVerificationId,
                verificationCode: verificationCode
            )
            print("获取到 JWT: \(jwtToken.prefix(30))...")
            
            // 2. 判断是登录还是注册
            // 如果之前获取验证码时返回 isUser=true，则尝试登录
            // 否则尝试注册
            let response: SignupResponse
            
            do {
                // 先尝试登录
                response = try await LoginManager.shared.loginWithPhoneVerification(
                    phoneNumber: phoneNumber,
                    verificationToken: jwtToken
                )
                print("=== 验证码登录成功 ===")
            } catch LoginError.userNotFound {
                // 用户不存在，执行注册流程
                print("用户不存在，开始注册...")
                let username = "user_\(phoneNumber)"
                response = try await SignupManager.shared.signupWithPhone(
                    phoneNumber: phoneNumber,
                    verificationToken: jwtToken,
                    username: username,
                    password: "12345678"  // 默认密码
                )
                print("=== 注册成功 ===")
            }
            
            // 3. 保存 Token 到本地（同时保存手机号）
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: phoneNumber
            )
            
            print("Access Token: \(response.accessToken)")
            print("Refresh Token: \(response.refreshToken)")
            print("Phone Number: \(phoneNumber)")
            print("================")
            
            await MainActor.run {
                // 如果有回调，调用回调
                if let onLoginSuccess = onLoginSuccess {
                    onLoginSuccess(response)
                }
                // 直接关闭页面，不弹 toast
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
