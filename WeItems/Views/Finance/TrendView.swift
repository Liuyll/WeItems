//
//  TrendView.swift
//  WeItems
//

import SwiftUI
import Charts
import Combine

struct TrendView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject private var cache = TrendDataCache.shared
    
    @State private var trendPeriod: TrendPeriod = .monthly
    @State private var recoveryPeriod: TrendPeriod = .monthly
    
    enum TrendPeriod: String, CaseIterable {
        case monthly = "月度"
        case yearly = "年度"
    }
    
    // MARK: - 数据源（优先用缓存）
    
    /// 最早添加物品的日期
    private var earliestItemDate: Date? {
        store.items.filter { $0.listType == .items && !$0.isArchived }.map(\.createdAt).min()
    }
    
    /// 按月汇总（从最早物品月份到当前月份，最多12个月）
    private var monthlyData: [TrendDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        
        // 计算需要展示的月数
        let monthCount: Int
        if let earliest = earliestItemDate {
            let components = calendar.dateComponents([.month], from: earliest, to: now)
            monthCount = min((components.month ?? 0) + 1, 12)
        } else {
            monthCount = 1
        }
        
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
        for i in (0..<monthCount).reversed() {
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
    
    /// 按年汇总（从最早物品年份到当前年份，最多5年）
    private var yearlyData: [TrendDataPoint] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let items = store.items.filter { $0.listType == .items && !$0.isArchived }
        
        // 计算需要展示的年数
        let yearCount: Int
        if let earliest = earliestItemDate {
            let earliestYear = calendar.component(.year, from: earliest)
            yearCount = min(currentYear - earliestYear + 1, 5)
        } else {
            yearCount = 1
        }
        
        var grouped: [Int: (count: Int, total: Double)] = [:]
        for item in items {
            let year = calendar.component(.year, from: item.createdAt)
            var e = grouped[year] ?? (0, 0)
            e.count += 1
            e.total += item.price
            grouped[year] = e
        }
        
        var result: [TrendDataPoint] = []
        for i in (0..<yearCount).reversed() {
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
    
    // 总统计（优先用缓存）
    private var totalItems: Int {
        cache.isLoaded ? cache.totalItems : store.items.filter { $0.listType == .items && !$0.isArchived }.count
    }
    
    private var totalValue: Double {
        cache.isLoaded ? cache.totalValue : store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    private var dailyCost: Double {
        if cache.isLoaded { return cache.dailyCost }
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
        if cache.isLoaded { return cache.recentCount }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return store.items.filter { $0.listType == .items && !$0.isArchived && $0.createdAt >= thirtyDaysAgo }.count
    }
    
    private let typeColors: [String: Color] = [
        "数码": .blue,
        "装扮": .pink,
        "家电": .cyan,
        "大件": .purple,
        "人生好物": .orange,
        "EDC": .brown,
        "旅行": .green,
        "其他": .gray
    ]
    
    // 按类型汇总（优先用缓存）
    private var typeStats: [(type: String, count: Int, total: Double, percentage: Double)] {
        if cache.isLoaded { return cache.typeStats }
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
    
    /// 最早售出物品的日期
    private var earliestSoldDate: Date? {
        store.items.filter { $0.isArchived && $0.soldDate != nil }.compactMap(\.soldDate).min()
    }
    
    private var monthlySoldData: [SoldDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let soldItems = store.items.filter { $0.isArchived && $0.soldDate != nil && $0.soldPrice != nil }
        
        let monthCount: Int
        if let earliest = earliestSoldDate {
            let components = calendar.dateComponents([.month], from: earliest, to: now)
            monthCount = min((components.month ?? 0) + 1, 12)
        } else {
            monthCount = 1
        }
        
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
        for i in (0..<monthCount).reversed() {
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
        
        let yearCount: Int
        if let earliest = earliestSoldDate {
            let earliestYear = calendar.component(.year, from: earliest)
            yearCount = min(currentYear - earliestYear + 1, 5)
        } else {
            yearCount = 1
        }
        
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
        for i in (0..<yearCount).reversed() {
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
    
    @State private var isReady = false
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            if isReady {
                if totalItems == 0 {
                    // 无物品时展示提示
                    VStack(spacing: 20) {
                        Spacer(minLength: 100)
                        VStack(spacing: 8) {
                            Text("添加物品后可查看趋势")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 16)
                } else {
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
                .transition(.opacity)
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .controlSize(.large)
                        .padding(.top, 100)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if cache.isLoaded {
                isReady = true
            } else {
                cache.preload(store: store)
            }
        }
        .onChange(of: cache.isLoaded) { _, loaded in
            if loaded && !isReady {
                withAnimation(.easeIn(duration: 0.2)) {
                    isReady = true
                }
            }
        }
        .onDisappear {
            // 保留 isReady 状态，避免重新进入时完全重建视图
        }
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
        let data = trendPeriod == .monthly
            ? (cache.isLoaded ? cache.monthlyData : monthlyData)
            : (cache.isLoaded ? cache.yearlyData : yearlyData)
        let hasData = data.contains(where: { $0.total > 0 })
        let titleText = trendPeriod == .monthly ? "近 \(data.count) 个月趋势" : "近 \(data.count) 年趋势"
        let yCap = trendChartYCap(for: data)
        let displayData = cappedTrendData(data, cap: yCap)
        let yTicks = trendChartYTicks(for: data, cap: yCap)
        let realValues = Dictionary(uniqueKeysWithValues: data.map { ($0.label, $0.total) })
        
        return VStack(alignment: .leading, spacing: 16) {
            if hasData {
                HStack {
                    Text("📈 \(titleText)")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    Picker("", selection: $trendPeriod) {
                        ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            
                if trendPeriod == .monthly && displayData.count > 6 {
                    // 月度超过6个月时可左右滑动，默认显示最近6个月
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            Chart {
                                ForEach(displayData) { d in
                                    BarMark(
                                        x: .value("时间", d.label),
                                        y: .value("金额", d.total),
                                        width: 25
                                    )
                                    .foregroundStyle(.blue.opacity(0.6))
                                    .annotation(position: .top, spacing: 2) {
                                        if let real = realValues[d.label], real > 0 {
                                            Text("¥\(formatAxisPrice(real))")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .chartYScale(domain: 0...yCap)
                            .chartYAxis {
                                AxisMarks(position: .leading, values: yTicks) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text("¥\(formatAxisPrice(v))")
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 16)
                            .frame(width: CGFloat(displayData.count) * 55, height: 200)
                            .id("chart")
                        }
                        .onAppear {
                            proxy.scrollTo("chart", anchor: .trailing)
                        }
                    }
                } else {
                    Chart {
                        ForEach(displayData) { d in
                            BarMark(
                                x: .value("时间", d.label),
                                y: .value("金额", d.total),
                                width: 25
                            )
                            .foregroundStyle(.blue.opacity(0.6))
                            .annotation(position: .top, spacing: 2) {
                                if let real = realValues[d.label], real > 0 {
                                    Text("¥\(formatAxisPrice(real))")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...yCap)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: yTicks) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("¥\(formatAxisPrice(v))")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                    .frame(height: 200)
                }
                
                // 明细列表
                let filteredData = data.reversed().filter { $0.total > 0 }
                VStack(spacing: 0) {
                    ForEach(filteredData) { d in
                        HStack {
                            Text(d.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(width: 52, alignment: .leading)
                            
                            Text("¥\(String(format: "%.0f", d.total))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            
                            Spacer()
                            
                            Text("\(d.count) 件")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.1)))
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        
                        if d.id != filteredData.last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            } else {
                VStack(spacing: 12) {
                    Text("好物趋势")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("添加物品后即可展示趋势")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(hasData ? Color(.systemBackground) : Color.blue)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(hasData ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - 回收趋势卡片
    private var recoveryTrendCard: some View {
        let data = recoveryPeriod == .monthly
            ? (cache.isLoaded ? cache.monthlySoldData : monthlySoldData)
            : (cache.isLoaded ? cache.yearlySoldData : yearlySoldData)
        let totalSoldAmount: Double
        let totalOriginal: Double
        let totalProfit: Double
        if cache.isLoaded {
            totalSoldAmount = cache.totalSoldAmount
            totalOriginal = cache.totalSoldOriginal
            totalProfit = cache.totalSoldProfit
        } else {
            let soldItems = store.items.filter { $0.isArchived && $0.soldPrice != nil }
            totalSoldAmount = soldItems.compactMap(\.soldPrice).reduce(0, +)
            totalOriginal = soldItems.reduce(0) { $0 + $1.price }
            totalProfit = totalSoldAmount - totalOriginal
        }
        let hasData = data.contains(where: { $0.count > 0 })
        let titleText = recoveryPeriod == .monthly ? "近 \(data.count) 个月回收趋势" : "近 \(data.count) 年回收趋势"
        
        return VStack(alignment: .leading, spacing: 16) {
            if hasData {
                HStack {
                    Text("♻️ \(titleText)")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    Picker("", selection: $recoveryPeriod) {
                        ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
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
                if recoveryPeriod == .monthly && data.count > 6 {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            Chart {
                                ForEach(data) { d in
                                    BarMark(x: .value("时间", d.label), y: .value("金额", d.soldAmount), width: 12)
                                        .foregroundStyle(.green.opacity(0.7))
                                        .position(by: .value("类型", "回收"))
                                    BarMark(x: .value("时间", d.label), y: .value("金额", d.originalAmount), width: 12)
                                        .foregroundStyle(.orange.opacity(0.5))
                                        .position(by: .value("类型", "成本"))
                                }
                            }
                            .chartForegroundStyleScale(["回收": .green.opacity(0.7), "成本": .orange.opacity(0.5)])
                            .chartLegend(position: .bottom)
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text("¥\(formatAxisPrice(v))")
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .frame(width: CGFloat(data.count) * 55, height: 200)
                            .id("recoveryChart")
                        }
                        .onAppear {
                            proxy.scrollTo("recoveryChart", anchor: .trailing)
                        }
                    }
                } else {
                    Chart {
                                ForEach(data) { d in
                                    BarMark(x: .value("时间", d.label), y: .value("金额", d.soldAmount), width: 12)
                                        .foregroundStyle(.green.opacity(0.7))
                                        .position(by: .value("类型", "回收"))
                                    BarMark(x: .value("时间", d.label), y: .value("金额", d.originalAmount), width: 12)
                                        .foregroundStyle(.orange.opacity(0.5))
                                        .position(by: .value("类型", "成本"))
                                }
                    }
                    .chartForegroundStyleScale(["回收": .green.opacity(0.7), "成本": .orange.opacity(0.5)])
                    .chartLegend(position: .bottom)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("¥\(formatAxisPrice(v))")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                }
                
                // 明细
                let filteredSoldData = data.reversed().filter { $0.count > 0 }
                VStack(spacing: 0) {
                    ForEach(filteredSoldData) { d in
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
                        
                        if d.id != filteredSoldData.last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            } else {
                VStack(spacing: 12) {
                    Text("回收趋势")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("标记已售出的物品后即可展示趋势")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(hasData ? Color(.systemBackground) : Color.blue)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(hasData ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

// MARK: - 数据模型

struct TrendDataPoint: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let total: Double
}

/// 格式化 Y 轴价格标签（纯整数显示）
func formatAxisPrice(_ value: Double) -> String {
    if value >= 10_000 {
        // 大数用万为单位，简短不被截断
        let v = value / 10_000
        if v == v.rounded(.down) {
            return "\(Int(v))万"
        }
        return String(format: "%.1f万", v)
    }
    return String(format: "%.0f", value)
}

/// 计算物品趋势图 Y 轴上限（取真实最大值向上取整到美观数字）
func trendChartYCap(for data: [TrendDataPoint]) -> Double {
    let values = data.map(\.total).filter { $0 > 0 }
    guard let maxVal = values.max(), maxVal > 0 else { return 1 }
    return ceilToNice(maxVal)
}

/// 向上取整到"美观"数字（如 1500→2000, 45000→50000, 1234567→2000000）
private func ceilToNice(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let magnitude = pow(10, floor(log10(value)))
    let normalized = value / magnitude  // 1.0 ~ 9.999...
    let nice: Double
    if normalized <= 1.0 { nice = 1.0 }
    else if normalized <= 2.0 { nice = 2.0 }
    else if normalized <= 5.0 { nice = 5.0 }
    else { nice = 10.0 }
    return nice * magnitude
}

/// 计算 Y 轴刻度值：0 + 根据数据分布的中间刻度 + 顶部最大值
func trendChartYTicks(for data: [TrendDataPoint], cap: Double) -> [Double] {
    guard cap > 0 else { return [0] }
    
    // 收集所有非零数据值，取整到美观数字，去重
    let rawValues = Set(data.map(\.total).filter { $0 > 0 }.map { ceilToNice($0) })
    // 去掉等于 cap 的（顶部已有）
    let midValues = rawValues.filter { $0 > 0 && $0 < cap }.sorted()
    
    var ticks: [Double] = [0]
    
    // 逐个加入中间刻度
    for v in midValues {
        let prev = ticks.last!
        // 相邻值量级内太近则合并
        let minGap = max(prev * 0.5, v * 0.3)
        if v - prev >= max(minGap, 1) {
            ticks.append(v)
        }
    }
    
    ticks.append(cap)
    
    // 去掉和 0 太近的刻度（占 cap 不到 3%，会和 ¥0 标签重叠）
    let overlapThreshold = cap * 0.03
    ticks = ticks.filter { $0 == 0 || $0 >= overlapThreshold }
    // 确保 cap 还在
    if ticks.last != cap { ticks.append(cap) }
    
    // 最多保留 5 个刻度
    if ticks.count > 5 {
        let first = ticks.count > 1 && ticks[1] != cap ? ticks[1] : nil
        let mids = ticks.filter { $0 != 0 && $0 != cap && $0 != first }
        var result: [Double] = [0]
        if let f = first { result.append(f) }
        if !mids.isEmpty {
            let step = max(1, mids.count / 2)
            for i in stride(from: 0, to: mids.count, by: step) {
                if result.count < 4 { result.append(mids[i]) }
            }
        }
        result.append(cap)
        return result.sorted()
    }
    
    return ticks
}

/// 将趋势数据截断用于绘图，柱子最高不超过上限的 88%，为顶部注解留出空间
func cappedTrendData(_ data: [TrendDataPoint], cap: Double) -> [TrendDataPoint] {
    let maxBarHeight = cap * 0.88
    let minVisible = cap * 0.05
    return data.map { d in
        TrendDataPoint(
            label: d.label,
            count: d.count,
            total: d.total > 0 ? max(min(d.total, maxBarHeight), minVisible) : 0
        )
    }
}

struct SoldDataPoint: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let soldAmount: Double
    let originalAmount: Double
    var profit: Double { soldAmount - originalAmount }
}

// MARK: - 趋势数据缓存（后台预计算）

@MainActor
class TrendDataCache: ObservableObject {
    static let shared = TrendDataCache()
    
    /// 缓存数据快照（一次性赋值，只触发一次 objectWillChange）
    struct CacheData {
        var monthlyData: [TrendDataPoint] = []
        var yearlyData: [TrendDataPoint] = []
        var monthlySoldData: [SoldDataPoint] = []
        var yearlySoldData: [SoldDataPoint] = []
        var typeStats: [(type: String, count: Int, total: Double, percentage: Double)] = []
        var totalItems: Int = 0
        var totalValue: Double = 0
        var dailyCost: Double = 0
        var recentCount: Int = 0
        var totalSoldAmount: Double = 0
        var totalSoldOriginal: Double = 0
        var totalSoldProfit: Double = 0
    }
    
    @Published private(set) var data = CacheData()
    @Published private(set) var isLoaded = false
    
    // 便捷访问
    var monthlyData: [TrendDataPoint] { data.monthlyData }
    var yearlyData: [TrendDataPoint] { data.yearlyData }
    var monthlySoldData: [SoldDataPoint] { data.monthlySoldData }
    var yearlySoldData: [SoldDataPoint] { data.yearlySoldData }
    var typeStats: [(type: String, count: Int, total: Double, percentage: Double)] { data.typeStats }
    var totalItems: Int { data.totalItems }
    var totalValue: Double { data.totalValue }
    var dailyCost: Double { data.dailyCost }
    var recentCount: Int { data.recentCount }
    var totalSoldAmount: Double { data.totalSoldAmount }
    var totalSoldOriginal: Double { data.totalSoldOriginal }
    var totalSoldProfit: Double { data.totalSoldProfit }
    
    private init() {}
    
    /// 标记缓存失效，下次进入趋势页时重新计算
    func invalidate() {
        isLoaded = false
    }
    
    /// 后台预计算所有趋势数据
    func preload(store: ItemStore) {
        // 在主线程拷贝数据快照
        let itemsSnapshot = store.items
        
        Task.detached(priority: .utility) {
            let items = itemsSnapshot
            let myItems = items.filter { $0.listType == .items }
            let calendar = Calendar.current
            let now = Date()
            
            // 最早日期（按拥有时间）
            let earliestDate = myItems.map { $0.ownedDate ?? $0.createdAt }.min()
            
            // 月度数据
            let monthCount: Int
            if let earliest = earliestDate {
                let components = calendar.dateComponents([.month], from: earliest, to: now)
                monthCount = min((components.month ?? 0) + 1, 12)
            } else {
                monthCount = 1
            }
            
            let keyFmt = DateFormatter()
            keyFmt.dateFormat = "yyyy-MM"
            let dispFmt = DateFormatter()
            dispFmt.dateFormat = "M月"
            
            var monthGrouped: [String: (count: Int, total: Double)] = [:]
            for item in myItems {
                let itemDate = item.ownedDate ?? item.createdAt
                let key = keyFmt.string(from: itemDate)
                var e = monthGrouped[key] ?? (0, 0)
                e.count += 1
                e.total += item.price
                monthGrouped[key] = e
            }
            
            var monthly: [TrendDataPoint] = []
            for i in (0..<monthCount).reversed() {
                guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let key = keyFmt.string(from: date)
                let e = monthGrouped[key]
                monthly.append(TrendDataPoint(label: dispFmt.string(from: date), count: e?.count ?? 0, total: e?.total ?? 0))
            }
            
            // 年度数据
            let currentYear = calendar.component(.year, from: now)
            let yearCount: Int
            if let earliest = earliestDate {
                let earliestYear = calendar.component(.year, from: earliest)
                yearCount = min(currentYear - earliestYear + 1, 5)
            } else {
                yearCount = 1
            }
            
            var yearGrouped: [Int: (count: Int, total: Double)] = [:]
            for item in myItems {
                let itemDate = item.ownedDate ?? item.createdAt
                let year = calendar.component(.year, from: itemDate)
                var e = yearGrouped[year] ?? (0, 0)
                e.count += 1
                e.total += item.price
                yearGrouped[year] = e
            }
            
            var yearly: [TrendDataPoint] = []
            for i in (0..<yearCount).reversed() {
                let year = currentYear - i
                let e = yearGrouped[year]
                yearly.append(TrendDataPoint(label: "\(year)年", count: e?.count ?? 0, total: e?.total ?? 0))
            }
            
            // 售出数据
            let soldItems = items.filter { $0.isArchived && $0.soldDate != nil && $0.soldPrice != nil }
            let earliestSold = soldItems.compactMap(\.soldDate).min()
            
            let soldMonthCount: Int
            if let earliest = earliestSold {
                let components = calendar.dateComponents([.month], from: earliest, to: now)
                soldMonthCount = min((components.month ?? 0) + 1, 12)
            } else {
                soldMonthCount = 1
            }
            
            var soldMonthGrouped: [String: (count: Int, soldAmount: Double, originalAmount: Double)] = [:]
            for item in soldItems {
                guard let soldDate = item.soldDate else { continue }
                let key = keyFmt.string(from: soldDate)
                var e = soldMonthGrouped[key] ?? (0, 0, 0)
                e.count += 1
                e.soldAmount += item.soldPrice ?? 0
                e.originalAmount += item.price
                soldMonthGrouped[key] = e
            }
            
            var monthlySold: [SoldDataPoint] = []
            for i in (0..<soldMonthCount).reversed() {
                guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let key = keyFmt.string(from: date)
                let e = soldMonthGrouped[key]
                monthlySold.append(SoldDataPoint(label: dispFmt.string(from: date), count: e?.count ?? 0, soldAmount: e?.soldAmount ?? 0, originalAmount: e?.originalAmount ?? 0))
            }
            
            let soldYearCount: Int
            if let earliest = earliestSold {
                let earliestYear = calendar.component(.year, from: earliest)
                soldYearCount = min(currentYear - earliestYear + 1, 5)
            } else {
                soldYearCount = 1
            }
            
            var soldYearGrouped: [Int: (count: Int, soldAmount: Double, originalAmount: Double)] = [:]
            for item in soldItems {
                guard let soldDate = item.soldDate else { continue }
                let year = calendar.component(.year, from: soldDate)
                var e = soldYearGrouped[year] ?? (0, 0, 0)
                e.count += 1
                e.soldAmount += item.soldPrice ?? 0
                e.originalAmount += item.price
                soldYearGrouped[year] = e
            }
            
            var yearlySold: [SoldDataPoint] = []
            for i in (0..<soldYearCount).reversed() {
                let year = currentYear - i
                let e = soldYearGrouped[year]
                yearlySold.append(SoldDataPoint(label: "\(year)年", count: e?.count ?? 0, soldAmount: e?.soldAmount ?? 0, originalAmount: e?.originalAmount ?? 0))
            }
            
            // 类型统计
            let totalPrice = myItems.filter { !$0.isPriceless }.reduce(0) { $0 + $1.price }
            var typeGrouped: [String: (count: Int, total: Double)] = [:]
            for item in myItems {
                let existing = typeGrouped[item.type] ?? (count: 0, total: 0)
                typeGrouped[item.type] = (count: existing.count + 1, total: existing.total + item.price)
            }
            let types = typeGrouped.map { (type: $0.key, count: $0.value.count, total: $0.value.total, percentage: totalPrice > 0 ? $0.value.total / totalPrice * 100 : 0) }
                .sorted { $0.total > $1.total }
            
            // 总览
            let total = myItems.count
            let value = myItems.filter { !$0.isPriceless }.reduce(0) { $0 + $1.price }
            var daily: Double = 0
            for item in myItems.filter({ !$0.isPriceless }) {
                let itemDate = item.ownedDate ?? item.createdAt
                let days = max(1, calendar.dateComponents([.day], from: itemDate, to: now).day ?? 1)
                daily += item.price / Double(days)
            }
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let recent = myItems.filter { ($0.ownedDate ?? $0.createdAt) >= thirtyDaysAgo }.count
            
            // 回收汇总
            let soldAll = soldItems
            let soldAmount = soldAll.compactMap(\.soldPrice).reduce(0, +)
            let soldOriginal = soldAll.reduce(0) { $0 + $1.price }
            let soldProfit = soldAmount - soldOriginal
            
            let capturedMonthly = monthly
            let capturedYearly = yearly
            let capturedMonthlySold = monthlySold
            let capturedYearlySold = yearlySold
            let capturedDaily = daily
            
            await MainActor.run {
                self.data = CacheData(
                    monthlyData: capturedMonthly,
                    yearlyData: capturedYearly,
                    monthlySoldData: capturedMonthlySold,
                    yearlySoldData: capturedYearlySold,
                    typeStats: types,
                    totalItems: total,
                    totalValue: value,
                    dailyCost: capturedDaily,
                    recentCount: recent,
                    totalSoldAmount: soldAmount,
                    totalSoldOriginal: soldOriginal,
                    totalSoldProfit: soldProfit
                )
                self.isLoaded = true
            }
        }
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
