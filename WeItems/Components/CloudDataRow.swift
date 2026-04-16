//
//  CloudDataRow.swift
//  WeItems
//

import SwiftUI

/// 通用数据行组件：左侧带彩色图标的标题，右侧显示值
struct CloudDataRow: View {
    let icon: String
    var color: Color = .blue
    let title: String
    let value: String
    var titleFont: Font = .subheadline
    var valueFont: Font = .subheadline
    var valueFontWeight: Font.Weight = .medium
    var valueColor: Color = .secondary
    
    var body: some View {
        HStack {
            Label {
                Text(title)
                    .font(titleFont)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(titleFont)
            }
            Spacer()
            Text(value)
                .font(valueFont)
                .fontWeight(valueFontWeight)
                .foregroundStyle(valueColor)
        }
    }
}
