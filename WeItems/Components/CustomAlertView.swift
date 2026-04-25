//
//  CustomAlertView.swift
//  WeItems
//

import SwiftUI

// MARK: - 自定义弹窗 ViewModifier

/// 纯信息提示弹窗（只有一个"好的"按钮）
struct CustomInfoAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    var buttonText: String = "好的"
    var onDismiss: (() -> Void)? = nil
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { }
                
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                        
                        if !message.isEmpty {
                            Text(message)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.black.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                    
                    Divider()
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        onDismiss?()
                    } label: {
                        Text(buttonText)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                )
                .frame(width: 280)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
    }
}

/// 确认操作弹窗（取消 + 确认按钮）
struct CustomConfirmAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var message: String = ""
    var confirmText: String = "确定"
    var cancelText: String = "取消"
    var isDestructive: Bool = false
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { }
                
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                        
                        if !message.isEmpty {
                            Text(message)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.black.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                    
                    Divider()
                    
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onCancel?()
                        } label: {
                            Text(cancelText)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        
                        Divider()
                            .frame(height: 44)
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onConfirm()
                        } label: {
                            Text(confirmText)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(isDestructive ? .red : .blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                )
                .frame(width: 280)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
    }
}

/// 带输入框的弹窗（取消 + 确认按钮 + TextField）
struct CustomInputAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var message: String = ""
    var placeholder: String = ""
    @Binding var text: String
    var confirmText: String = "确定"
    var cancelText: String = "取消"
    var keyboardType: UIKeyboardType = .default
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { }
                
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                        
                        if !message.isEmpty {
                            Text(message)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.black.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        
                        TextField(placeholder, text: $text)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray6))
                            )
                            .keyboardType(keyboardType)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                    
                    Divider()
                    
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onCancel?()
                        } label: {
                            Text(cancelText)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        
                        Divider()
                            .frame(height: 44)
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onConfirm()
                        } label: {
                            Text(confirmText)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                )
                .frame(width: 280)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
    }
}

/// 蓝色风格确认弹窗（矮胖圆润风格，无标题无分割线）
struct CustomBlueConfirmAlert: ViewModifier {
    @Binding var isPresented: Bool
    var message: String = ""
    var confirmText: String = "确定"
    var cancelText: String = "取消"
    var isDestructive: Bool = false
    var confirmColor: Color? = nil
    var cancelColor: Color? = nil
    var backgroundColor: Color = .blue
    var width: CGFloat = 240
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // 遮罩始终存在，用 opacity 控制，避免移除/添加导致底层视图重新布局闪烁
            Color.black.opacity(isPresented ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isPresented)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            
            if isPresented {
                VStack(spacing: 20) {
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onCancel?()
                        } label: {
                            Text(cancelText)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(cancelColor ?? .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onConfirm()
                        } label: {
                            Text(confirmText)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.heavy)
                                .foregroundStyle(confirmColor ?? (isDestructive ? .red : .white))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(backgroundColor)
                )
                .frame(width: width)
                .shadow(color: backgroundColor.opacity(0.3), radius: 20, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
    }
}

/// 蓝色风格信息提示弹窗（矮胖圆润风格，无标题无分割线，只有一个按钮）
struct CustomBlueInfoAlert: ViewModifier {
    @Binding var isPresented: Bool
    var message: String = ""
    var buttonText: String = "好的"
    var buttonColor: Color = .white
    var backgroundColor: Color = .blue
    var onDismiss: (() -> Void)? = nil
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            Color.black.opacity(isPresented ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isPresented)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                    onDismiss?()
                }
            
            if isPresented {
                VStack(spacing: 20) {
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        onDismiss?()
                    } label: {
                        Text(buttonText)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.heavy)
                            .foregroundStyle(buttonColor)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(backgroundColor)
                )
                .frame(width: 240)
                .shadow(color: backgroundColor.opacity(0.3), radius: 20, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
    }
}

// MARK: - View 扩展方法

extension View {
    /// 纯信息提示弹窗
    func customInfoAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        buttonText: String = "好的",
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        self.modifier(CustomInfoAlert(
            isPresented: isPresented,
            title: title,
            message: message,
            buttonText: buttonText,
            onDismiss: onDismiss
        ))
    }
    
    /// 蓝色风格信息提示弹窗
    func customBlueInfoAlert(
        isPresented: Binding<Bool>,
        message: String,
        buttonText: String = "好的",
        buttonColor: Color = .white,
        backgroundColor: Color = .blue,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        self.modifier(CustomBlueInfoAlert(
            isPresented: isPresented,
            message: message,
            buttonText: buttonText,
            buttonColor: buttonColor,
            backgroundColor: backgroundColor,
            onDismiss: onDismiss
        ))
    }
    
    /// 确认操作弹窗
    func customConfirmAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String = "",
        confirmText: String = "确定",
        cancelText: String = "取消",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        self.modifier(CustomConfirmAlert(
            isPresented: isPresented,
            title: title,
            message: message,
            confirmText: confirmText,
            cancelText: cancelText,
            isDestructive: isDestructive,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }
    
    /// 蓝色风格确认弹窗
    func customBlueConfirmAlert(
        isPresented: Binding<Bool>,
        message: String = "",
        confirmText: String = "确定",
        cancelText: String = "取消",
        isDestructive: Bool = false,
        confirmColor: Color? = nil,
        cancelColor: Color? = nil,
        backgroundColor: Color = .blue,
        width: CGFloat = 240,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        self.modifier(CustomBlueConfirmAlert(
            isPresented: isPresented,
            message: message,
            confirmText: confirmText,
            cancelText: cancelText,
            isDestructive: isDestructive,
            confirmColor: confirmColor,
            cancelColor: cancelColor,
            backgroundColor: backgroundColor,
            width: width,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }
    
    /// 带输入框弹窗
    func customInputAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String = "",
        placeholder: String = "",
        text: Binding<String>,
        confirmText: String = "确定",
        cancelText: String = "取消",
        keyboardType: UIKeyboardType = .default,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        self.modifier(CustomInputAlert(
            isPresented: isPresented,
            title: title,
            message: message,
            placeholder: placeholder,
            text: text,
            confirmText: confirmText,
            cancelText: cancelText,
            keyboardType: keyboardType,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }
}
