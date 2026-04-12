//
//  RegisterView.swift
//  WeItems
//

import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - 表单字段
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    
    // MARK: - UI状态
    @State private var isLoading = false
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var verificationId: String?
    
    // MARK: - 定时器
    @State private var timer: Timer?
    
    // MARK: - 验证状态
    private var isUsernameValid: Bool {
        !username.isEmpty && username.count >= 3
    }
    
    private var isPasswordValid: Bool {
        password.count >= 6
    }
    
    private var isPasswordMatch: Bool {
        password == confirmPassword && !confirmPassword.isEmpty
    }
    
    private var isPhoneValid: Bool {
        VerificationManager.shared.isValidPhoneNumber(phoneNumber)
    }
    
    private var canSendCode: Bool {
        isPhoneValid && countdown == 0 && !isSendingCode
    }
    
    private var canRegister: Bool {
        isUsernameValid && isPasswordValid && isPasswordMatch && isPhoneValid && verificationCode.count >= 4
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 账号信息
                Section("账号信息") {
                    TextField("用户名", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if !username.isEmpty && !isUsernameValid {
                        Text("用户名至少需要3个字符")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // MARK: - 密码
                Section("密码") {
                    SecureField("密码（至少6位）", text: $password)
                    
                    if !password.isEmpty && !isPasswordValid {
                        Text("密码长度不能少于6位")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    SecureField("确认密码", text: $confirmPassword)
                    
                    if !confirmPassword.isEmpty && !isPasswordMatch {
                        Text("两次输入的密码不一致")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // MARK: - 手机号
                Section("手机号") {
                    HStack {
                        TextField("手机号", text: $phoneNumber)
                            .keyboardType(.phonePad)
                        
                        Button {
                            Task {
                                await sendVerificationCode()
                            }
                        } label: {
                            if isSendingCode {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if countdown > 0 {
                                Text("\(countdown)s")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("获取验证码")
                                    .fontWeight(.medium)
                            }
                        }
                        .disabled(!canSendCode)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if !phoneNumber.isEmpty && !isPhoneValid {
                        Text("请输入有效的手机号")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    TextField("验证码", text: $verificationCode)
                        .keyboardType(.numberPad)
                }
                
                // MARK: - 注册按钮
                Section {
                    Button {
                        Task {
                            await register()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("注册")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canRegister || isLoading)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("注册账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .customInfoAlert(
                isPresented: $showingError,
                title: "提示",
                message: errorMessage ?? ""
            )
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - 发送验证码
    private func sendVerificationCode() async {
        isSendingCode = true
        errorMessage = nil
        
        do {
            let result = try await VerificationManager.shared.sendPhoneVerificationCode(
                phoneNumber: phoneNumber,
                target: "ANY"
            )
            
            verificationId = result.verificationId
            
            // 开始倒计时
            countdown = result.expiresIn > 60 ? 60 : result.expiresIn
            startCountdown()
            
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
    
    // MARK: - 开始倒计时
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
    
    // MARK: - 注册
    private func register() async {
        isLoading = true
        errorMessage = nil
        
        guard let verificationId = verificationId else {
            await MainActor.run {
                errorMessage = "请先获取验证码"
                showingError = true
                isLoading = false
            }
            return
        }
        
        do {
            let response = try await SignupManager.shared.signupWithPhone(
                phoneNumber: phoneNumber,
                verificationToken: verificationId,
                username: username,
                password: password,
                name: nil
            )
            
            // 保存 Token 到本地（access_token 和 refresh_token 存入 Keychain）
            TokenStorage.shared.saveToken(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub,
                phoneNumber: phoneNumber
            )
            
            print("注册成功！")
            print("Access Token: \(response.accessToken.prefix(20))...")
            print("Refresh Token: \(response.refreshToken.prefix(20))...")
            print("过期时间: \(response.expiresIn) 秒")
            print("用户ID: \(response.sub)")
            
            await MainActor.run {
                isLoading = false
                // 注册成功，返回登录页
                dismiss()
            }
            
        } catch let error as SignupError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "注册失败：\(error.localizedDescription)"
                showingError = true
                isLoading = false
            }
        }
    }
}

#Preview {
    RegisterView()
}
