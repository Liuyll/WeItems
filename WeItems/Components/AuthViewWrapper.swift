//
//  AuthViewWrapper.swift
//  WeItems
//

import SwiftUI

/// AuthView 的通用包装器，处理登录成功后的状态更新和关闭
struct AuthViewWrapper: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        AuthView(onLoginSuccess: { response in
            authManager.loginSuccess(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn,
                tokenType: response.tokenType,
                sub: response.sub
            )
            dismiss()
        })
    }
}
