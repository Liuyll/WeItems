//
//  TrendView.swift
//  WeItems
//

import SwiftUI

struct TrendView: View {
    @ObservedObject var store: ItemStore
    @State private var lastScrollOffset: CGFloat = 0
    
    // 按月汇总数据
    private var monthlyStats: [(month: String, count: Int, total: Double)] {
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        
        var grouped: [String: (count: Int, total: Double, sortDate: Date)] = [:]
        for item in items {
            let monthStr = formatter.string(from: item.createdAt)
            let existing = grouped[monthStr] ?? (count: 0, total: 0, sortDate: item.createdAt)
            grouped[monthStr] = (count: existing.count + 1, total: existing.total + item.price, sortDate: min(existing.sortDate, item.createdAt))
        }
        
        return grouped.map { (month: $0.key, count: $0.value.count, total: $0.value.total) }
            .sorted { a, b in
                // 按月份倒序
                b.month < a.month
            }
    }
    
    // 按类型汇总数据
    private var typeStats: [(type: String, count: Int, total: Double, percentage: Double)] {
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        let totalPrice = items.reduce(0) { $0 + $1.price }
        
        var grouped: [String: (count: Int, total: Double)] = [:]
        for item in items {
            let existing = grouped[item.type] ?? (count: 0, total: 0)
            grouped[item.type] = (count: existing.count + 1, total: existing.total + item.price)
        }
        
        return grouped.map { (type: $0.key, count: $0.value.count, total: $0.value.total, percentage: totalPrice > 0 ? $0.value.total / totalPrice * 100 : 0) }
            .sorted { $0.total > $1.total }
    }
    
    // 总统计
    private var totalItems: Int {
        store.items.filter { $0.listType == .items && !$0.isArchived }.count
    }
    
    private var totalValue: Double {
        store.items.filter { $0.listType == .items && !$0.isArchived }.reduce(0) { $0 + $1.price }
    }
    
    /// 日均持有价：每个物品的 (价格 ÷ 持有天数) 之和
    private var dailyCost: Double {
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        let calendar = Calendar.current
        let today = Date()
        var total: Double = 0
        for item in items {
            let days = max(1, calendar.dateComponents([.day], from: item.createdAt, to: today).day ?? 1)
            total += item.price / Double(days)
        }
        return total
    }
    
    // 最近30天新增数量
    private var recentCount: Int {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return store.items.filter { $0.listType == .items && !$0.isArchived && $0.createdAt >= thirtyDaysAgo }.count
    }
    
    private let typeColors: [String: Color] = [
        "数码": .blue,
        "服饰": .pink,
        "家电": .cyan,
        "大件": .purple,
        "生活好物": .red,
        "EDC": .brown,
        "户外": .green,
        "其他": .gray
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 滚动检测锚点
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self,
                                            value: proxy.frame(in: .global).minY)
                        }
                    )
                
                // 总览卡片
                overviewCard
                
                // 类型分布
                if !typeStats.isEmpty {
                    typeDistributionCard
                }
                
                // 月度趋势
                if !monthlyStats.isEmpty {
                    monthlyTrendCard
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
            if abs(newOffset - lastScrollOffset) > 2 {
                lastScrollOffset = newOffset
                NotificationCenter.default.post(name: .scrollDidChange, object: nil)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                // 点击空白区域也显示 TabBar
                NotificationCenter.default.post(name: .scrollDidChange, object: nil)
            }
        )
        .navigationTitle("趋势")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - 总览卡片
    private var overviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("📊 物品总览")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            
            HStack(spacing: 12) {
                StatMiniCard(title: "物品总数", value: "\(totalItems)", unit: "件", color: .blue, icon: "cube.fill")
                StatMiniCard(title: "总价值", value: "¥\(String(format: "%.0f", totalValue))", unit: "", color: .orange, icon: "yensign.circle.fill")
            }
            
            HStack(spacing: 12) {
                StatMiniCard(title: "日均", value: "¥\(String(format: "%.2f", dailyCost))", unit: "", color: .green, icon: "clock.arrow.circlepath")
                StatMiniCard(title: "近30天", value: "\(recentCount)", unit: "件新增", color: .purple, icon: "calendar.badge.plus")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - 类型分布卡片
    private var typeDistributionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🏷️ 类型分布")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            
            ForEach(typeStats, id: \.type) { stat in
                HStack(spacing: 12) {
                    // 类型标签
                    Text(stat.type)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 70, alignment: .leading)
                    
                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(typeColors[stat.type] ?? .gray)
                                .frame(width: max(4, geo.size.width * stat.percentage / 100), height: 12)
                        }
                    }
                    .frame(height: 12)
                    
                    // 百分比 + 金额
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(String(format: "%.0f", stat.percentage))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(typeColors[stat.type] ?? .gray)
                        Text("¥\(String(format: "%.0f", stat.total))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 55, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - 月度趋势卡片
    private var monthlyTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📈 月度趋势")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            
            ForEach(monthlyStats.prefix(6), id: \.month) { stat in
                HStack {
                    Text(stat.month)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(width: 85, alignment: .leading)
                    
                    Text("\(stat.count) 件")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                    
                    Spacer()
                    
                    Text("¥\(String(format: "%.0f", stat.total))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
                
                if stat.month != monthlyStats.prefix(6).last?.month {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

// MARK: - 小统计卡片
struct StatMiniCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        TrendView(store: ItemStore())
    }
}
