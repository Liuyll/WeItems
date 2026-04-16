//
//  ProBadge.swift
//  WeItems
//

import SwiftUI

/// 纯字体实现的 PRO 标签，参考原 pro.png 的渐变样式
struct ProBadge: View {
    var fontSize: CGFloat = 12
    var paddingH: CGFloat = 8
    var paddingV: CGFloat = 3
    
    private var cornerRadius: CGFloat { fontSize * 0.35 }
    private var borderWidth: CGFloat { max(1, fontSize * 0.05) }
    
    var body: some View {
        Text("Pro")
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 0x50/255.0, green: 0x64/255.0, blue: 0xEB/255.0))
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        ProBadge(fontSize: 32, paddingH: 24, paddingV: 10)
        ProBadge(fontSize: 14, paddingH: 8, paddingV: 3)
        ProBadge(fontSize: 9, paddingH: 6, paddingV: 2)
    }
}
