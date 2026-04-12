//
//  TrendView.swift
//  WeItems
//

import SwiftUI
import Charts

struct TrendView: View {
    @ObservedObject var store: ItemStore
    
    @State private var trendPeriod: TrendPeriod = .monthly
    @State private var recoveryPeriod: TrendPeriod = .monthly
    
    enum TrendPeriod: String, CaseIterable {
        case monthly = "月度"
        case yearly = "年度"
    }
    
    // MARK: - 数据源
    
    /// 按月汇总（近12个月）
    private var monthlyData: [TrendDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        let keyFmt = DateFormatter()
        keyFmt.dateFormat = "yyyy-MM"
        
        var grouped: [String: (count: Int, total: Double)] = [:]
        for item in items {
            let key = keyFmt.string(from: item.createdAt)
            var e = grouped[key] ?? (0, 0)
            e.count += 1
            e.total += item.price
            grouped[key] = e
        }
        
        var result: [TrendDataPoint] = []
        let dispFmt = DateFormatter()
        dispFmt.dateFormat = "M月"
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let key = keyFmt.string(from: date)
            let e = grouped[key]
            result.append(TrendDataPoint(
                label: dispFmt.string(from: date),
                count: e?.count ?? 0,
                total: e?.total ?? 0
            ))
        }
        return result
    }
    
    /// 按年汇总（近5年）
    private var yearlyData: [TrendDataPoint] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        
        var grouped: [Int: (count: Int, total: Double)] = [:]
        for item in items {
            let year = calendar.component(.year, from: item.createdAt)
            var e = grouped[year] ?? (0, 0)
            e.count += 1
            e.total += item.price
            grouped[year] = e
        }
        
        var result: [TrendDataPoint] = []
        for i in (0..<5).reversed() {
            let year = currentYear - i
            let e = grouped[year]
            result.append(TrendDataPoint(
                label: "\(year)年",
                count: e?.count ?? 0,
                total: e?.total ?? 0
            ))
        }
        return result
    }
    
    // 总统计
    private var totalItems: Int {
        store.items.filter { $0.listType == .items && !$0.isArchived }.count
    }
    
    private var totalValue: Double {
        store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    private var dailyCost: Double {
        let items = store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isPriceless }
        let calendar = Calendar.current
        let today = Date()
        var total: Double = 0
        for item in items {
            let days = max(1, calendar.dateComponents([.day], from: item.createdAt, to: today).day ?? 1)
            total += item.price / Double(days)
        }
        return total
    }
    
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
    
    // 按类型汇总
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
    
    // MARK: - 回收数据
    
    private var monthlySoldData: [SoldDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let soldItems = store.items.filter { $0.isArchived && $0.soldDate != nil && $0.soldPrice != nil }
        let keyFmt = DateFormatter()
        keyFmt.dateFormat = "yyyy-MM"
        
        var grouped: [String: (count: Int, soldAmount: Double, originalAmount: Double)] = [:]
        for item in soldItems {
            guard let soldDate = item.soldDate else { continue }
            let key = keyFmt.string(from: soldDate)
            var e = grouped[key] ?? (0, 0, 0)
            e.count += 1
            e.soldAmount += item.soldPrice ?? 0
            e.originalAmount += item.price
            grouped[key] = e
        }
        
        var result: [SoldDataPoint] = []
        let dispFmt = DateFormatter()
        dispFmt.dateFormat = "M月"
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let key = keyFmt.string(from: date)
            let e = grouped[key]
            result.append(SoldDataPoint(
                label: dispFmt.string(from: date),
                count: e?.count ?? 0,
                soldAmount: e?.soldAmount ?? 0,
                originalAmount: e?.originalAmount ?? 0
            ))
        }
        return result
    }
    
    private var yearlySoldData: [SoldDataPoint] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let soldItems = store.items.filter { $0.isArchived && $0.soldDate != nil && $0.soldPrice != nil }
        
        var grouped: [Int: (count: Int, soldAmount: Double, originalAmount: Double)] = [:]
        for item in soldItems {
            guard let soldDate = item.soldDate else { continue }
            let year = calendar.component(.year, from: soldDate)
            var e = grouped[year] ?? (0, 0, 0)
            e.count += 1
            e.soldAmount += item.soldPrice ?? 0
            e.originalAmount += item.price
            grouped[year] = e
        }
        
        var result: [SoldDataPoint] = []
        for i in (0..<5).reversed() {
            let year = currentYear - i
            let e = grouped[year]
            result.append(SoldDataPoint(
                label: "\(year)年",
                count: e?.count ?? 0,
                soldAmount: e?.soldAmount ?? 0,
                originalAmount: e?.originalAmount ?? 0
            ))
        }
        return result
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                overviewCard
                
                if !typeStats.isEmpty {
                    typeDistributionCard
                }
                
                monthlyTrendCard
                
                recoveryTrendCard
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            if abs(newValue - oldValue) > 1 {
                NotificationCenter.default.post(name: .scrollDidChange, object: nil)
            }
        }
        .onTapGesture {
            NotificationCenter.default.post(name: .scrollDidChange, object: nil)
        }
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
                    Text(stat.type)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 70, alignment: .leading)
                    
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
    
    // MARK: - 月度趋势卡片（柱线图 + 月度/年度切换）
    private var monthlyTrendCard: some View {
        let data = trendPeriod == .monthly ? monthlyData : yearlyData
        let hasData = data.contains(where: { $0.count > 0 })
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📈 \(trendPeriod == .monthly ? "近 12 个月趋势" : "近 5 年趋势")")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Picker("", selection: $trendPeriod) {
                    ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            
            if hasData {
                Chart {
                    ForEach(data) { d in
                        BarMark(
                            x: .value("时间", d.label),
                            y: .value("件数", d.count)
                        )
                        .foregroundStyle(.blue.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)件")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                
                // 明细列表
                VStack(spacing: 0) {
                    ForEach(data.reversed().filter { $0.count > 0 }) { d in
                        HStack {
                            Text(d.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 52, alignment: .leading)
                            
                            Text("\(d.count) 件")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.1)))
                            
                            Spacer()
                            
                            Text("¥\(String(format: "%.0f", d.total))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        
                        if d.id != data.reversed().filter({ $0.count > 0 }).last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无物品记录")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
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
    
    // MARK: - 回收趋势卡片
    private var recoveryTrendCard: some View {
        let data = recoveryPeriod == .monthly ? monthlySoldData : yearlySoldData
        let totalSold = store.items.filter { $0.isArchived && $0.soldPrice != nil }
        let totalSoldAmount = totalSold.compactMap(\.soldPrice).reduce(0, +)
        let totalOriginal = totalSold.reduce(0) { $0 + $1.price }
        let totalProfit = totalSoldAmount - totalOriginal
        let hasData = data.contains(where: { $0.count > 0 })
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("♻️ \(recoveryPeriod == .monthly ? "近 12 个月回收趋势" : "近 5 年回收趋势")")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Picker("", selection: $recoveryPeriod) {
                    ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            
            if hasData {
                // 汇总统计
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("回收总额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(String(format: "%.0f", totalSoldAmount))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().frame(height: 30)
                    
                    VStack(spacing: 2) {
                        Text("购入成本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("¥\(String(format: "%.0f", totalOriginal))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().frame(height: 30)
                    
                    VStack(spacing: 2) {
                        Text(totalProfit >= 0 ? "总盈利" : "总亏损")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(totalProfit >= 0 ? "+" : "-")¥\(String(format: "%.0f", abs(totalProfit)))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(totalProfit >= 0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // 柱状图
                Chart {
                    ForEach(data) { d in
                        BarMark(x: .value("时间", d.label), y: .value("金额", d.soldAmount))
                            .foregroundStyle(.green.opacity(0.7))
                            .position(by: .value("类型", "回收"))
                        BarMark(x: .value("时间", d.label), y: .value("金额", d.originalAmount))
                            .foregroundStyle(.orange.opacity(0.5))
                            .position(by: .value("类型", "成本"))
                    }
                }
                .chartForegroundStyleScale(["回收": .green.opacity(0.7), "成本": .orange.opacity(0.5)])
                .chartLegend(position: .bottom)
                .frame(height: 200)
                
                // 明细
                
                // 明细
                VStack(spacing: 0) {
                    ForEach(data.reversed().filter { $0.count > 0 }) { d in
                        HStack {
                            Text(d.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 52, alignment: .leading)
                            Text("\(d.count)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("回收 ¥\(String(format: "%.0f", d.soldAmount))")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(d.profit >= 0 ? "+¥\(String(format: "%.0f", d.profit))" : "-¥\(String(format: "%.0f", abs(d.profit)))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(d.profit >= 0 ? .green : .red)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        
                        if d.id != data.reversed().filter({ $0.count > 0 }).last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无售出记录")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
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

// MARK: - 数据模型

private struct TrendDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let total: Double
}

private struct SoldDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let soldAmount: Double
    let originalAmount: Double
    var profit: Double { soldAmount - originalAmount }
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
