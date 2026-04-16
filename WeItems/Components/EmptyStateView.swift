//
//  EmptyStateView.swift
//  WeItems
//

import SwiftUI

/// 通用空状态占位视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconSize: CGFloat = 60
    var iconColor: Color = .gray.opacity(0.5)
    var titleFont: Font = .title3
    var subtitleFont: Font = .subheadline
    var spacing: CGFloat = 12
    
    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
            
            Text(title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
