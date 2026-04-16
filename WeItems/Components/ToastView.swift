//
//  ToastView.swift
//  WeItems
//

import SwiftUI

/// 通用 Toast ViewModifier
struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var duration: Double = 2.0
    var font: Font = .subheadline
    var fontWeight: Font.Weight = .medium
    var foregroundColor: Color = .white
    var backgroundColor: Color = .black.opacity(0.75)
    var bottomPadding: CGFloat = 60
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                VStack {
                    Spacer()
                    Text(message)
                        .font(font)
                        .fontWeight(fontWeight)
                        .foregroundStyle(foregroundColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(backgroundColor)
                        )
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: isPresented)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}

extension View {
    /// 通用 Toast 提示
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        duration: Double = 2.0,
        bottomPadding: CGFloat = 60
    ) -> some View {
        self.modifier(ToastModifier(
            isPresented: isPresented,
            message: message,
            duration: duration,
            bottomPadding: bottomPadding
        ))
    }
}
