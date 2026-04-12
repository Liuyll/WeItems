//
//  RegisterBubbleView.swift
//  WeItems
//

import SwiftUI

// MARK: - 气泡模型
struct Bubble: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: CGFloat
}

// MARK: - 气泡动画视图
struct BubblesBackground: View {
    @State private var bubbles: [Bubble] = []
    let bubbleCount = 15
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 绿色渐变背景
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.8),
                        Color.green.opacity(0.6),
                        Color.mint.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // 气泡层
                ForEach(bubbles) { bubble in
                    Circle()
                        .fill(.white.opacity(bubble.opacity))
                        .frame(width: bubble.size, height: bubble.size)
                        .position(x: bubble.x, y: bubble.y)
                }
            }
            .onAppear {
                createBubbles(in: geometry.size)
                startAnimation()
            }
        }
    }
    
    private func createBubbles(in size: CGSize) {
        bubbles = (0..<bubbleCount).map { _ in
            Bubble(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: size.height * 0.5...size.height),
                size: CGFloat.random(in: 20...80),
                opacity: Double.random(in: 0.1...0.3),
                speed: CGFloat.random(in: 0.5...2)
            )
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                for i in bubbles.indices {
                    bubbles[i].y -= bubbles[i].speed
                    
                    // 气泡飘到顶部后重置到底部
                    if bubbles[i].y < -bubbles[i].size {
                        bubbles[i].y = UIScreen.main.bounds.height + bubbles[i].size
                        bubbles[i].x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                    }
                }
            }
        }
    }
}

// MARK: - 注册视图
struct RegisterBubbleView: View {
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
        ZStack {
            // 气泡背景
            BubblesBackground()
            
            // 内容层
            ScrollView {
                VStack(spacing: 30) {
                    // 标题
                    VStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 60))
                            .foregroundStyle(.white)
                        
                        Text("创建账号")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        
                        Text("填写信息开始使用")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.top, 50)
                    
                    // 表单卡片
                    VStack(spacing: 20) {
                        // 用户名
                        HStack {
                            Image(systemName: "person")
                                .foregroundStyle(.green)
                                .frame(width: 30)
                            TextField("用户名（至少3位）", text: $username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding()
                        .background(.white)
                        .cornerRadius(12)
                        
                        // 密码
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "lock")
                                    .foregroundStyle(.green)
                                    .frame(width: 30)
                                SecureField("密码（至少6位）", text: $password)
                            }
                            .padding()
                            .background(.white)
                            .cornerRadius(12)
                            
                            HStack {
                                Image(systemName: "lock.shield")
                                    .foregroundStyle(.green)
                                    .frame(width: 30)
                                SecureField("确认密码", text: $confirmPassword)
                            }
                            .padding()
                            .background(.white)
                            .cornerRadius(12)
                        }
                        
                        // 手机号和验证码
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "phone")
                                    .foregroundStyle(.green)
                                    .frame(width: 30)
                                TextField("手机号", text: $phoneNumber)
                                    .keyboardType(.phonePad)
                            }
                            .padding()
                            .background(.white)
                            .cornerRadius(12)
                            
                            HStack {
                                Image(systemName: "envelope.badge")
                                    .foregroundStyle(.green)
                                    .frame(width: 30)
                                TextField("验证码", text: $verificationCode)
                                    .keyboardType(.numberPad)
                                
                                Spacer()
                                
                                Button {
                                    Task {
                                        await sendVerificationCode()
                                    }
                                } label: {
                                    if isSendingCode {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.green)
                                    } else if countdown > 0 {
                                        Text("\(countdown)s")
                                            .foregroundStyle(.gray)
                                    } else {
                                        Text("获取")
                                            .fontWeight(.medium)
                                            .foregroundStyle(.green)
                                    }
                                }
                                .disabled(!canSendCode)
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(.white)
                            .cornerRadius(12)
                        }
                        
                        // 注册按钮
                        Button {
                            Task {
                                await register()
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("注册")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .background(
                            canRegister ? Color.green.opacity(0.9) : Color.gray.opacity(0.5)
                        )
                        .cornerRadius(12)
                        .disabled(!canRegister || isLoading)
                        .padding(.top, 10)
                        
                        // 返回按钮
                        Button {
                            dismiss()
                        } label: {
                            Text("已有账号？返回登录")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 30)
                    
                    Spacer(minLength: 50)
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
            
            await MainActor.run {
                isLoading = false
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
    RegisterBubbleView()
}
