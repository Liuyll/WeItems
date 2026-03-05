//
//  DailyExpenseView.swift
//  WeItems
//

import SwiftUI

struct DailyExpenseView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    @State private var showingAddItem = false
    
    var body: some View {
        VStack {
            // 总价统计
            DailyTotalCard()
                .padding()
            
            Spacer()
            
            Text("日常消费视图")
                .font(.title)
                .foregroundStyle(.secondary)
            
            Text("待开发...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .sheet(isPresented: $showingAddItem) {
            // 添加日常消费物品
        }
    }
}

// 日常消费总价卡片
struct DailyTotalCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("日常消费 - 本月支出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("¥0.00")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("消费笔数")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("0 笔")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    DailyExpenseView(store: ItemStore(), groupStore: GroupStore())
}
