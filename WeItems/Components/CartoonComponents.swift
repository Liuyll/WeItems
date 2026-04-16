//
//  CartoonComponents.swift
//  WeItems
//

import SwiftUI

// MARK: - 卡通卡片修饰符

struct CartoonCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18
    var backgroundColor: Color = Color(.secondarySystemGroupedBackground)
    var shadowColor: Color = Color.pink.opacity(0.06)
    var shadowRadius: CGFloat = 6
    var shadowY: CGFloat = 3
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func cartoonCard(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 18,
        backgroundColor: Color = Color(.secondarySystemGroupedBackground),
        shadowColor: Color = Color.pink.opacity(0.06),
        shadowRadius: CGFloat = 6,
        shadowY: CGFloat = 3
    ) -> some View {
        modifier(CartoonCardModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            backgroundColor: backgroundColor,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }
}

// MARK: - 卡通区块标题

struct CartoonSectionHeader: View {
    let emoji: String
    let title: String
    var color: Color = .secondary
    var font: Font = .system(.subheadline, design: .rounded)
    var fontWeight: Font.Weight = .bold
    var bottomPadding: CGFloat = 2
    
    var body: some View {
        Text(title)
            .font(font)
            .fontWeight(fontWeight)
            .foregroundStyle(color)
            .padding(.bottom, bottomPadding)
    }
}

// MARK: - 卡通输入框

struct CartoonTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var leadingIcon: String? = nil
    var iconColor: Color = .pink
    var showDivider: Bool = true
    var placeholderColor: Color = .cyan.opacity(0.8)
    var backgroundColor: Color = Color(.secondarySystemGroupedBackground)
    var cornerRadius: CGFloat = 14
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 14
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = leadingIcon {
                Text(icon)
                    .font(.body)
            }
            Text(placeholder)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.heavy)
                .foregroundStyle(placeholderColor)
            
            Spacer()
            
            TextField("", text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
        )
    }
}
