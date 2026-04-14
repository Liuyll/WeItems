//
//  DailyExpenseView.swift
//  WeItems
//

import SwiftUI
import Charts
import Combine

/// 自定义数字格式：0 显示为空（Double）
struct EmptyZeroNumberStyle: ParseableFormatStyle {
    var parseStrategy: EmptyZeroParseStrategy { EmptyZeroParseStrategy() }
    func format(_ value: Double) -> String {
        value == 0 ? "" : String(format: value == value.rounded() ? "%.0f" : "%.2f", value)
    }
}
struct EmptyZeroParseStrategy: ParseStrategy {
    func parse(_ value: String) throws -> Double {
        Double(value) ?? 0
    }
}
extension FormatStyle where Self == EmptyZeroNumberStyle {
    static var emptyZero: EmptyZeroNumberStyle { EmptyZeroNumberStyle() }
}

/// 自定义数字格式：0 显示为空（Int）
struct EmptyZeroIntStyle: ParseableFormatStyle {
    var parseStrategy: EmptyZeroIntParseStrategy { EmptyZeroIntParseStrategy() }
    func format(_ value: Int) -> String {
        value == 0 ? "" : "\(value)"
    }
}
struct EmptyZeroIntParseStrategy: ParseStrategy {
    func parse(_ value: String) throws -> Int {
        Int(value) ?? 0
    }
}
extension FormatStyle where Self == EmptyZeroIntStyle {
    static var emptyZeroInt: EmptyZeroIntStyle { EmptyZeroIntStyle() }
}

// MARK: - 数据模型

/// 记录类型
enum FinanceType: String, Codable, CaseIterable {
    case income = "收入"
    case debt = "负债"
    case investment = "投资"
    
    var color: Color {
        switch self {
        case .income: return .green
        case .debt: return .red
        case .investment: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .income: return "arrow.up.circle.fill"
        case .debt: return "arrow.down.circle.fill"
        case .investment: return "chart.line.uptrend.xyaxis.circle.fill"
        }
    }
}

/// 收入类型
enum IncomePeriod: String, Codable, CaseIterable {
    case salary = "工资"
    case oneTime = "一次性收入"
    case unrealized = "未归属收入"
    case savings = "储蓄"
}

/// 负债类型
enum DebtType: String, Codable, CaseIterable {
    case mortgage = "房贷"
    case carLoan = "车贷"
    case creditCard = "信用卡"
    case otherLoan = "其他借款"
}

/// 还款方式
enum RepaymentType: String, Codable, CaseIterable {
    case standard = "默认"         // 每期本金+固定手续费
    case equalPrincipal = "等额本金"  // 每月本金固定，利息递减
    case equalInstallment = "等额本息" // 每月还款固定
}

/// 基本工资条目（支持多项，考虑涨薪/换工作）
struct SalaryBaseItem: Identifiable, Codable {
    let id: UUID
    var amount: Double               // 月薪
    var startDate: Date              // 开始时间
    var endDate: Date?               // 结束时间（nil 表示长期/至今）
    var isLongTerm: Bool             // 是否长期
    var note: String
    
    init(id: UUID = UUID(), amount: Double = 0, startDate: Date = Date(), endDate: Date? = nil, isLongTerm: Bool = true, note: String = "") {
        self.id = id
        self.amount = amount
        self.startDate = startDate
        self.endDate = endDate
        self.isLongTerm = isLongTerm
        self.note = note
    }
    
    /// 判断给定日期是否在此工资有效期内
    func isActive(at date: Date) -> Bool {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        if monthStart < calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))! {
            return false
        }
        if !isLongTerm, let end = endDate {
            let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: end))!
            if monthStart > endMonth { return false }
        }
        return true
    }
}

/// 长期激励类型
enum IncentiveType: String, Codable, CaseIterable {
    case equity = "股权"
    case cash = "现金"
}

/// 长期激励条目（原股权激励，支持股权/现金）
struct EquityItem: Identifiable, Codable {
    let id: UUID
    var incentiveType: IncentiveType  // 股权 or 现金
    var amount: Double               // 现金：激励总额；长期时为单次金额
    var grantPrice: Double?          // 股权：授予时股价
    var shareCount: Double?          // 股权：股数
    var vestingDate: Date?           // 首次归属时间
    var vestingMonths: Int           // 归属频率（月数）
    var vestingCount: Int?           // 归属次数（nil 表示长期）
    var isLongTermVesting: Bool      // 是否长期归属
    var note: String
    
    init(id: UUID = UUID(), incentiveType: IncentiveType = .cash, amount: Double = 0, grantPrice: Double? = nil, shareCount: Double? = nil, vestingDate: Date? = nil, vestingMonths: Int = 12, vestingCount: Int? = 4, isLongTermVesting: Bool = false, note: String = "") {
        self.id = id
        self.incentiveType = incentiveType
        self.amount = amount
        self.grantPrice = grantPrice
        self.shareCount = shareCount
        self.vestingDate = vestingDate
        self.vestingMonths = vestingMonths
        self.vestingCount = vestingCount
        self.isLongTermVesting = isLongTermVesting
        self.note = note
    }
    
    /// 总价值（股权=股价×股数，现金=amount）
    var totalValue: Double {
        if incentiveType == .equity, let price = grantPrice, let count = shareCount {
            return price * count
        }
        return amount
    }
    
    /// 单次归属金额
    var perVestingAmount: Double {
        if isLongTermVesting {
            // 长期：amount 就是单次金额
            return incentiveType == .equity ? totalValue : amount
        }
        guard let count = vestingCount, count > 0 else { return 0 }
        return totalValue / Double(count)
    }
    
    /// 折算月度金额（用于汇总）
    var monthlyAmount: Double {
        guard vestingMonths > 0 else { return 0 }
        if isLongTermVesting {
            return perVestingAmount / Double(vestingMonths)
        }
        guard let count = vestingCount, count > 0 else { return 0 }
        let totalMonths = vestingMonths * count
        return totalValue / Double(totalMonths)
    }
}

/// 年终奖条目
struct BonusItem: Identifiable, Codable {
    let id: UUID
    var amount: Double
    var date: Date                   // 发放时间
    var separateTax: Bool            // 单独计税
    var note: String
    
    init(id: UUID = UUID(), amount: Double = 0, date: Date = Date(), separateTax: Bool = true, note: String = "") {
        self.id = id
        self.amount = amount
        self.date = date
        self.separateTax = separateTax
        self.note = note
    }
    
    var monthlyAmount: Double { amount / 12.0 }
}

/// 其他收入条目
struct OtherIncomeItem: Identifiable, Codable {
    let id: UUID
    var amount: Double               // 每月金额
    var note: String
    
    init(id: UUID = UUID(), amount: Double = 0, note: String = "") {
        self.id = id
        self.amount = amount
        self.note = note
    }
}

/// 结构性收入明细（工资类型专用）
struct SalaryBreakdown: Codable {
    var salaryBaseItems: [SalaryBaseItem]   // 基本工资（多项，支持时间段）
    var equityItems: [EquityItem]          // 长期激励（多个）
    var bonusItems: [BonusItem]            // 年终奖（多个）
    var otherIncomeItems: [OtherIncomeItem] // 其他收入（多个）
    var annualTax: Double                  // 年度个税（手动或自动计算）
    var autoCalculateTax: Bool             // 是否自动计算个税
    var socialInsurance: Double            // 每月社保公积金个人缴纳
    var specialDeduction: Double           // 每月专项附加扣除
    var pensionRate: Double                // 养老保险比例(%)
    var medicalRate: Double                // 医疗保险比例(%)
    var unemploymentRate: Double           // 失业保险比例(%)
    var housingFundRate: Double            // 住房公积金比例(%)
    var payDay: Int                        // 每月发薪日（1-31，默认10号）
    
    init(salaryBaseItems: [SalaryBaseItem] = [], equityItems: [EquityItem] = [], bonusItems: [BonusItem] = [], otherIncomeItems: [OtherIncomeItem] = [], annualTax: Double = 0, autoCalculateTax: Bool = false, socialInsurance: Double = 0, specialDeduction: Double = 0, pensionRate: Double = 8, medicalRate: Double = 2, unemploymentRate: Double = 0.2, housingFundRate: Double = 5, payDay: Int = 10) {
        self.salaryBaseItems = salaryBaseItems
        self.equityItems = equityItems
        self.bonusItems = bonusItems
        self.otherIncomeItems = otherIncomeItems
        self.annualTax = annualTax
        self.autoCalculateTax = autoCalculateTax
        self.socialInsurance = socialInsurance
        self.specialDeduction = specialDeduction
        self.pensionRate = pensionRate
        self.medicalRate = medicalRate
        self.unemploymentRate = unemploymentRate
        self.housingFundRate = housingFundRate
        self.payDay = payDay
    }
    
    /// 当前生效的月基本工资
    var currentMonthlyBase: Double {
        let now = Date()
        return salaryBaseItems.filter { $0.isActive(at: now) }.reduce(0) { $0 + $1.amount }
    }
    
    /// 折算月度总收入（税前）
    var totalMonthlyGross: Double {
        var total = currentMonthlyBase
        total += equityItems.reduce(0) { $0 + $1.monthlyAmount }
        total += bonusItems.reduce(0) { $0 + $1.monthlyAmount }
        total += otherIncomeItems.reduce(0) { $0 + $1.amount }
        return total
    }
    
    /// 实际使用的年度个税（自动计算或手动填写）
    var effectiveAnnualTax: Double {
        if autoCalculateTax {
            return TaxCalculator.calculateAnnualTax(breakdown: self)
        }
        return annualTax
    }
    
    /// 折算月度净收入（税后）
    var totalMonthlyIncome: Double {
        return totalMonthlyGross - effectiveAnnualTax / 12.0
    }
    
    /// 年度总收入（净）
    var totalAnnualIncome: Double {
        return totalMonthlyIncome * 12
    }
}

// MARK: - 个税计算引擎

struct TaxCalculator {
    
    // 综合所得税率表（累计预扣法，用于每月工资）
    private static let annualBrackets: [(threshold: Double, rate: Double, deduction: Double)] = [
        (36_000,   0.03, 0),
        (144_000,  0.10, 2_520),
        (300_000,  0.20, 16_920),
        (420_000,  0.25, 31_920),
        (660_000,  0.30, 52_920),
        (960_000,  0.35, 85_920),
        (Double.infinity, 0.45, 181_920)
    ]
    
    // 按月换算税率表（用于年终奖、长期激励单独计税）
    private static let monthlyBrackets: [(threshold: Double, rate: Double, deduction: Double)] = [
        (3_000,    0.03, 0),
        (12_000,   0.10, 210),
        (25_000,   0.20, 1_410),
        (35_000,   0.25, 2_660),
        (55_000,   0.30, 4_410),
        (80_000,   0.35, 7_160),
        (Double.infinity, 0.45, 15_160)
    ]
    
    /// 计算年度总个税
    static func calculateAnnualTax(breakdown: SalaryBreakdown) -> Double {
        let salaryTax = calculateSalaryTax(breakdown: breakdown)
        let bonusTax = calculateBonusTax(breakdown: breakdown)
        let incentiveTax = calculateIncentiveTax(breakdown: breakdown)
        return salaryTax + bonusTax + incentiveTax
    }
    
    /// 工资个税（累计预扣法，计算12个月）
    static func calculateSalaryTax(breakdown: SalaryBreakdown) -> Double {
        let monthlyIncome = breakdown.currentMonthlyBase + breakdown.otherIncomeItems.reduce(0) { $0 + $1.amount }
        let monthlySocial = breakdown.socialInsurance
        let monthlySpecial = breakdown.specialDeduction
        let threshold: Double = 5_000
        
        var totalTax: Double = 0
        
        for month in 1...12 {
            let cumulativeIncome = monthlyIncome * Double(month)
            let cumulativeDeductions = (threshold + monthlySocial + monthlySpecial) * Double(month)
            let cumulativeTaxableIncome = max(cumulativeIncome - cumulativeDeductions, 0)
            
            let cumulativeTax = taxForCumulativeIncome(cumulativeTaxableIncome)
            let monthTax = max(cumulativeTax - totalTax, 0)
            totalTax += monthTax
        }
        
        return totalTax
    }
    
    /// 年终奖个税
    static func calculateBonusTax(breakdown: SalaryBreakdown) -> Double {
        var separateTax: Double = 0
        var mergedBonusTotal: Double = 0
        
        for bonus in breakdown.bonusItems {
            guard bonus.amount > 0 else { continue }
            if bonus.separateTax {
                // 单独计税：÷12 查月度换算表
                separateTax += taxForBonus(bonus.amount)
            } else {
                // 合并计税：累加
                mergedBonusTotal += bonus.amount
            }
        }
        
        // 合并计税：(全年工资+年终奖)的税 - 全年工资的税 = 年终奖增量税
        if mergedBonusTotal > 0 {
            let monthlyIncome = breakdown.currentMonthlyBase + breakdown.otherIncomeItems.reduce(0) { $0 + $1.amount }
            let annualIncome = monthlyIncome * 12
            let annualDeduction = (5_000 + breakdown.socialInsurance + breakdown.specialDeduction) * 12
            let taxableWithout = max(annualIncome - annualDeduction, 0)
            let taxableWith = taxableWithout + mergedBonusTotal
            separateTax += max(taxForCumulativeIncome(taxableWith) - taxForCumulativeIncome(taxableWithout), 0)
        }
        
        return separateTax
    }
    
    /// 长期激励个税（与年终奖计税方式一致）
    static func calculateIncentiveTax(breakdown: SalaryBreakdown) -> Double {
        var totalTax: Double = 0
        for equity in breakdown.equityItems {
            let annualVestingAmount: Double
            if equity.isLongTermVesting {
                // 长期：按每年归属次数 × 单次金额
                let vestingsPerYear = equity.vestingMonths > 0 ? 12.0 / Double(equity.vestingMonths) : 0
                annualVestingAmount = equity.perVestingAmount * vestingsPerYear
            } else {
                guard let count = equity.vestingCount, count > 0, equity.vestingMonths > 0 else { continue }
                let vestingsPerYear = min(12.0 / Double(equity.vestingMonths), Double(count))
                annualVestingAmount = equity.perVestingAmount * vestingsPerYear
            }
            guard annualVestingAmount > 0 else { continue }
            totalTax += taxForBonus(annualVestingAmount)
        }
        return totalTax
    }
    
    /// 累计预扣法：根据累计应纳税所得额计算累计税额
    private static func taxForCumulativeIncome(_ income: Double) -> Double {
        for bracket in annualBrackets {
            if income <= bracket.threshold {
                return income * bracket.rate - bracket.deduction
            }
        }
        return income * 0.45 - 181_920
    }
    
    /// 年终奖单独计税（公开方法，供趋势计算使用）
    static func taxForSingleBonus(_ amount: Double) -> Double {
        return taxForBonus(amount)
    }
    
    /// 年终奖/长期激励单独计税（÷12 查月度表）
    private static func taxForBonus(_ amount: Double) -> Double {
        let monthlyEquivalent = amount / 12.0
        for bracket in monthlyBrackets {
            if monthlyEquivalent <= bracket.threshold {
                return amount * bracket.rate - bracket.deduction
            }
        }
        return amount * 0.45 - 15_160
    }
    
    /// 综合所得直接计税（全额查年度表，用于一次性收入、未归属收入、非单独计税的年终奖）
    private static func taxForAnnualIncome(_ amount: Double) -> Double {
        for bracket in annualBrackets {
            if amount <= bracket.threshold {
                return max(amount * bracket.rate - bracket.deduction, 0)
            }
        }
        return max(amount * 0.45 - 181_920, 0)
    }
    
    /// 获取每月工资个税明细（用于展示）
    static func monthlyTaxBreakdown(breakdown: SalaryBreakdown) -> [Double] {
        let monthlyIncome = breakdown.currentMonthlyBase + breakdown.otherIncomeItems.reduce(0) { $0 + $1.amount }
        let monthlySocial = breakdown.socialInsurance
        let monthlySpecial = breakdown.specialDeduction
        let threshold: Double = 5_000
        
        var result: [Double] = []
        var cumulativeTaxPaid: Double = 0
        
        for month in 1...12 {
            let cumulativeIncome = monthlyIncome * Double(month)
            let cumulativeDeductions = (threshold + monthlySocial + monthlySpecial) * Double(month)
            let cumulativeTaxableIncome = max(cumulativeIncome - cumulativeDeductions, 0)
            
            let cumulativeTax = taxForCumulativeIncome(cumulativeTaxableIncome)
            let monthTax = max(cumulativeTax - cumulativeTaxPaid, 0)
            cumulativeTaxPaid += monthTax
            result.append(monthTax)
        }
        
        return result
    }
}

/// 单笔记录
struct FinanceRecord: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var type: FinanceType
    var category: String
    var date: Date
    var note: String
    
    // 收入相关
    var incomePeriod: IncomePeriod?      // 收入类型
    var salaryBreakdown: SalaryBreakdown? // 结构性收入明细（工资类型专用）
    var countAsIncome: Bool?             // 是否计入收入（nil 视为旧数据默认行为）
    
    // 负债相关
    var debtType: DebtType?              // 贷款类型
    var repaymentType: RepaymentType?    // 还款方式
    var loanMonths: Int?                 // 贷款总月数
    var monthlyPayment: Double?          // 每月还款额
    var loanRate: Double?                // 每期利率(%)
    var loanStartDate: Date?             // 贷款起始日期
    var repayDay: Int?                   // 每月还款日（1-31）
    
    // 投资相关
    var expectedReturn: Double?          // 预期年化收益率(%)
    var investmentPlatform: String?      // 投资平台
    
    init(id: UUID = UUID(), title: String, amount: Double, type: FinanceType,
         category: String = "", date: Date = Date(), note: String = "",
         incomePeriod: IncomePeriod? = nil, salaryBreakdown: SalaryBreakdown? = nil, countAsIncome: Bool? = nil,
         debtType: DebtType? = nil, repaymentType: RepaymentType? = nil, loanMonths: Int? = nil, monthlyPayment: Double? = nil, loanRate: Double? = nil, loanStartDate: Date? = nil, repayDay: Int? = nil,
         expectedReturn: Double? = nil, investmentPlatform: String? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.note = note
        self.incomePeriod = incomePeriod
        self.salaryBreakdown = salaryBreakdown
        self.countAsIncome = countAsIncome
        self.debtType = debtType
        self.repaymentType = repaymentType
        self.loanMonths = loanMonths
        self.monthlyPayment = monthlyPayment
        self.loanRate = loanRate
        self.loanStartDate = loanStartDate
        self.repayDay = repayDay
        self.expectedReturn = expectedReturn
        self.investmentPlatform = investmentPlatform
    }
    
    /// 负债剩余月数
    var remainingLoanMonths: Int? {
        guard let loanMonths, let loanStartDate else { return nil }
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents([.month], from: loanStartDate, to: Date()).month ?? 0
        return max(loanMonths - elapsed, 0)
    }
    
    /// 负债剩余总额
    var remainingDebtAmount: Double? {
        guard let monthlyPayment, let remaining = remainingLoanMonths else { return nil }
        return monthlyPayment * Double(remaining)
    }
    
    /// 收入折算为月度金额
    var monthlyIncomeAmount: Double {
        guard type == .income else { return 0 }
        switch incomePeriod {
        case .salary:
            // 工资类型：使用结构性收入明细
            if let breakdown = salaryBreakdown {
                return breakdown.totalMonthlyIncome
            }
            return amount  // 没有明细则直接用 amount
        case .oneTime, .savings, .none:
            return 0  // 一次性收入/储蓄不折算月度
        case .unrealized:
            return 0  // 未变现收入不折算月度
        }
    }
}

/// 财务自由目标
struct SavingsGoal: Codable {
    var targetAmount: Double
    var name: String
    
    init(targetAmount: Double = 0, name: String = "财务自由目标") {
        self.targetAmount = targetAmount
        self.name = name
    }
}

// MARK: - 数据存储

class FinanceStore: ObservableObject {
    @Published var records: [FinanceRecord] = []
    @Published var savingsGoal: SavingsGoal = SavingsGoal()
    @Published var totalAssets: Double = 0
    
    private var recordsFileURL: URL {
        UserStorageHelper.shared.currentUserDirectory.appendingPathComponent("finance_records.json")
    }
    private var goalFileURL: URL {
        UserStorageHelper.shared.currentUserDirectory.appendingPathComponent("savings_goal.json")
    }
    private var assetsFileURL: URL {
        UserStorageHelper.shared.currentUserDirectory.appendingPathComponent("total_assets.json")
    }
    
    init() {
        loadAll()
    }
    
    /// 用户切换后重新加载数据
    func reloadForCurrentUser() {
        loadAll()
    }
    
    // MARK: - 计算属性
    
    /// 指定时间范围 & 类型的总额
    func totalAmount(type: FinanceType, from startDate: Date, to endDate: Date) -> Double {
        records.filter { $0.type == type && $0.date >= startDate && $0.date <= endDate }
            .reduce(0) { $0 + $1.amount }
    }
    
    func totalIncome(from startDate: Date, to endDate: Date) -> Double {
        var total: Double = 0
        let calendar = Calendar.current
        
        for record in records where record.type == .income {
            switch record.incomePeriod {
            case .salary:
                // 工资类型：按结构性收入真实分布到每个月
                if let bd = record.salaryBreakdown {
                    // 基本工资：按时间段判断哪些在当月有效
                    for base in bd.salaryBaseItems {
                        if base.isActive(at: startDate) {
                            total += base.amount
                        }
                    }
                    
                    // 长期激励：按归属频率和次数判断当月是否归属
                    for equity in bd.equityItems {
                        if equity.perVestingAmount > 0, equity.vestingMonths > 0, let vestDate = equity.vestingDate {
                            let vestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: vestDate))!
                            let queryMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
                            let monthsSinceVest = calendar.dateComponents([.month], from: vestMonth, to: queryMonth).month ?? 0
                            
                            if monthsSinceVest >= 0 && monthsSinceVest % equity.vestingMonths == 0 {
                                let vestingIndex = monthsSinceVest / equity.vestingMonths
                                if equity.isLongTermVesting || equity.vestingCount == nil {
                                    total += equity.perVestingAmount
                                } else if let count = equity.vestingCount, vestingIndex < count {
                                    total += equity.perVestingAmount
                                }
                            }
                        }
                    }
                    
                    // 年终奖：只在发放月份显示
                    for bonus in bd.bonusItems {
                        let bonusMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: bonus.date))!
                        let queryMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
                        if bonusMonth == queryMonth {
                            total += bonus.amount
                        }
                    }
                    
                    // 其他收入：每月都有
                    for other in bd.otherIncomeItems {
                        total += other.amount
                    }
                    
                    // 扣除个税
                    if bd.autoCalculateTax {
                        // 自动计算：累计预扣法，每月税额不同
                        let monthIndex = calendar.component(.month, from: startDate) - 1 // 0-11
                        let monthlyTaxes = TaxCalculator.monthlyTaxBreakdown(breakdown: bd)
                        if monthIndex < monthlyTaxes.count {
                            total -= monthlyTaxes[monthIndex]
                        }
                        // 年终奖个税：在发年终奖的月份扣除
                        for bonus in bd.bonusItems {
                            let bonusMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: bonus.date))!
                            let queryMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
                            if bonusMonth == queryMonth && bonus.separateTax {
                                total -= TaxCalculator.taxForSingleBonus(bonus.amount)
                            }
                        }
                        // 长期激励个税：在归属月份扣除
                        for equity in bd.equityItems {
                            if equity.perVestingAmount > 0, equity.vestingMonths > 0, let vestDate = equity.vestingDate {
                                let vestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: vestDate))!
                                let queryMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
                                let monthsSinceVest = calendar.dateComponents([.month], from: vestMonth, to: queryMonth).month ?? 0
                                if monthsSinceVest >= 0 && monthsSinceVest % equity.vestingMonths == 0 {
                                    let vestingIndex = monthsSinceVest / equity.vestingMonths
                                    let shouldVest = equity.isLongTermVesting || equity.vestingCount == nil || (equity.vestingCount != nil && vestingIndex < equity.vestingCount!)
                                    if shouldVest {
                                        let annualVesting: Double
                                        if equity.isLongTermVesting {
                                            let vestingsPerYear = equity.vestingMonths > 0 ? 12.0 / Double(equity.vestingMonths) : 0
                                            annualVesting = equity.perVestingAmount * vestingsPerYear
                                        } else {
                                            guard let count = equity.vestingCount, count > 0 else { continue }
                                            let vestingsPerYear = min(12.0 / Double(equity.vestingMonths), Double(count))
                                            annualVesting = equity.perVestingAmount * vestingsPerYear
                                        }
                                        if annualVesting > 0 {
                                            let taxPerVesting = TaxCalculator.taxForSingleBonus(annualVesting) / (12.0 / Double(equity.vestingMonths))
                                            total -= taxPerVesting
                                        }
                                    }
                                }
                            }
                        }
                    } else if bd.annualTax > 0 {
                        // 手动填写：按月均摊
                        total -= bd.annualTax / 12.0
                    }
                } else {
                    // 没有结构性明细的工资，按记录日期
                    if record.date >= startDate && record.date <= endDate {
                        total += record.amount
                    }
                }
                
            case .oneTime, .savings:
                // 一次性收入/储蓄：仅 countAsIncome 为 true 时计入收入
                if record.countAsIncome == true, record.date >= startDate && record.date <= endDate {
                    total += record.amount
                }
                
            case .unrealized, .none:
                // 未变现收入不计入
                break
            }
        }
        
        return total
    }
    
    func totalDebt(from startDate: Date, to endDate: Date) -> Double {
        totalAmount(type: .debt, from: startDate, to: endDate)
    }
    
    func totalInvestment(from startDate: Date, to endDate: Date) -> Double {
        totalAmount(type: .investment, from: startDate, to: endDate)
    }
    
    /// 本年度总收入（按月累加，确保结构性收入正确分布）
    func totalIncomeForYear() -> Double {
        let calendar = Calendar.current
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: Date()))!
        var total: Double = 0
        for m in 0..<12 {
            guard let mStart = calendar.date(byAdding: .month, value: m, to: yearStart) else { continue }
            guard let mEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: mStart) else { continue }
            total += totalIncome(from: mStart, to: mEnd)
        }
        return total
    }
    
    /// 从当前往前数12个月的总收入
    func trailing12MonthsIncome() -> Double {
        let calendar = Calendar.current
        let now = Date()
        let curMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        var total: Double = 0
        for i in 0..<12 {
            guard let mStart = calendar.date(byAdding: .month, value: -i, to: curMonth) else { continue }
            guard let mEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: mStart) else { continue }
            total += totalIncome(from: mStart, to: mEnd)
        }
        return total
    }
    
    /// 月均收入：最近12个月中有收入的月份的平均值
    /// 从当前月往前最多12个月，起始点为第一个有收入的月份
    func averageMonthlyIncome() -> Double {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        // 收集最近12个月的收入
        var monthlyIncomes: [(month: Date, income: Double)] = []
        for i in (0..<12).reversed() {
            guard let mStart = calendar.date(byAdding: .month, value: -i, to: currentMonthStart) else { continue }
            guard let mEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: mStart) else { continue }
            let income = totalIncome(from: mStart, to: mEnd)
            monthlyIncomes.append((mStart, income))
        }
        
        // 找到第一个有收入的月份
        guard let firstActiveIndex = monthlyIncomes.firstIndex(where: { $0.income != 0 }) else { return 0 }
        
        // 从有收入的月份开始到当前月
        let activeMonths = Array(monthlyIncomes[firstActiveIndex...])
        guard !activeMonths.isEmpty else { return 0 }
        
        let totalIncome = activeMonths.reduce(0.0) { $0 + $1.income }
        return totalIncome / Double(activeMonths.count)
    }
    
    /// 本年度起止
    var yearRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start)!
        return (start, end)
    }
    
    /// 本月起止
    var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return (start, end)
    }
    
    /// 月度固定收入总和（月度收入 + 年度收入/12）
    var monthlyRecurringIncome: Double {
        records.filter { $0.type == .income }
            .reduce(0) { $0 + $1.monthlyIncomeAmount }
    }
    
    /// 月度固定负债（每月还款总和）
    var monthlyRecurringDebt: Double {
        records.filter { $0.type == .debt }
            .reduce(0) { $0 + ($1.monthlyPayment ?? 0) }
    }
    
    /// 月净收入
    var monthlyNetIncome: Double {
        monthlyRecurringIncome - monthlyRecurringDebt
    }
    
    /// 投资总额
    var totalInvestmentAmount: Double {
        records.filter { $0.type == .investment }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// 投资加权平均年化收益率
    var weightedAverageReturn: Double {
        let investments = records.filter { $0.type == .investment && ($0.expectedReturn ?? 0) > 0 }
        let totalAmount = investments.reduce(0) { $0 + $1.amount }
        guard totalAmount > 0 else { return 0 }
        let weightedSum = investments.reduce(0) { $0 + $1.amount * ($1.expectedReturn ?? 0) }
        return weightedSum / totalAmount
    }
    
    /// 负债总额（剩余）
    var totalRemainingDebt: Double {
        records.filter { $0.type == .debt }
            .reduce(0) { $0 + ($1.remainingDebtAmount ?? $1.amount) }
    }
    
    /// 收入总额（所有收入记录的 amount 之和）
    /// 收入总额（排除工资，工资不纳入个人资产）
    var totalIncomeAmount: Double {
        records.filter { $0.type == .income && $0.incomePeriod != .salary }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// 储蓄总额
    var totalSavingsAmount: Double {
        records.filter { $0.type == .income && $0.incomePeriod == .savings }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// 计算总资产 = 储蓄 + 投资 - 负债（物品总价由外部传入）
    func calculatedTotalAssets(itemsTotalPrice: Double = 0) -> Double {
        totalSavingsAmount + totalInvestmentAmount - totalRemainingDebt + itemsTotalPrice
    }
    
    /// 收入情况预估
    enum IncomeOutlook: String, CaseIterable {
        case fluctuating = "波动"
        case optimistic = "积极"
        case pessimistic = "悲观"
    }
    
    /// 目标达成预估时间（月）- 根据收入情况
    func estimatedMonthsToGoal(itemsTotalPrice: Double = 0, outlook: IncomeOutlook = .fluctuating) -> Int? {
        guard savingsGoal.targetAmount > 0 else { return nil }
        let currentAssets = totalSavingsAmount + totalInvestmentAmount + itemsTotalPrice
        let remaining = savingsGoal.targetAmount - currentAssets
        guard remaining > 0 else { return 0 }
        
        let monthlyNet: Double
        switch outlook {
        case .fluctuating:
            monthlyNet = fluctuatingMonthlyNet()
        case .optimistic:
            monthlyNet = optimisticMonthlyNet()
        case .pessimistic:
            monthlyNet = pessimisticMonthlyNet()
        }
        
        guard monthlyNet > 0 else { return nil }
        return Int(ceil(remaining / monthlyNet))
    }
    
    /// 波动：最近18个月（从有收入开始）平均月净收入
    private func fluctuatingMonthlyNet() -> Double {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        var monthlyNets: [Double] = []
        for i in (0..<18).reversed() {
            guard let mStart = calendar.date(byAdding: .month, value: -i, to: currentMonthStart) else { continue }
            guard let mEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: mStart) else { continue }
            let income = totalIncome(from: mStart, to: mEnd)
            monthlyNets.append(income)
        }
        
        // 从第一个有收入的月份开始
        guard let firstActive = monthlyNets.firstIndex(where: { $0 != 0 }) else {
            return monthlyNetIncome // fallback
        }
        let active = Array(monthlyNets[firstActive...])
        guard !active.isEmpty else { return monthlyNetIncome }
        
        let avg = active.reduce(0, +) / Double(active.count)
        let investmentMonthlyReturn = totalInvestmentAmount * (weightedAverageReturn / 100.0) / 12.0
        return avg + investmentMonthlyReturn
    }
    
    /// 积极：最高月工资 + top3年终奖均值/12 + top2长期激励均值/12 + 投资回报
    private func optimisticMonthlyNet() -> Double {
        var monthlyIncome: Double = 0
        
        for record in records where record.type == .income {
            guard let bd = record.salaryBreakdown else { continue }
            
            // 最高月工资
            let maxSalary = bd.salaryBaseItems.map { $0.amount }.max() ?? 0
            monthlyIncome = max(monthlyIncome, maxSalary)
            
            // 其他月收入
            monthlyIncome += bd.otherIncomeItems.reduce(0) { $0 + $1.amount }
            
            // top3 年终奖平均值
            let bonusAmounts = bd.bonusItems.map { $0.amount }.sorted(by: >)
            let topBonuses = Array(bonusAmounts.prefix(3))
            if !topBonuses.isEmpty {
                monthlyIncome += topBonuses.reduce(0, +) / Double(topBonuses.count) / 12.0
            }
            
            // top2 长期激励平均值
            let equityAmounts = bd.equityItems.map { $0.perVestingAmount * (12.0 / max(Double($0.vestingMonths), 1)) }.sorted(by: >)
            let topEquities = Array(equityAmounts.prefix(2))
            if !topEquities.isEmpty {
                monthlyIncome += topEquities.reduce(0, +) / Double(topEquities.count) / 12.0
            }
        }
        
        let investmentMonthlyReturn = totalInvestmentAmount * (weightedAverageReturn / 100.0) / 12.0
        return monthlyIncome + investmentMonthlyReturn
    }
    
    /// 悲观：中位数月工资 + 最低3次年终奖均值/12 + 最低2次长期激励均值/12 + 投资回报/2
    private func pessimisticMonthlyNet() -> Double {
        var monthlyIncome: Double = 0
        
        for record in records where record.type == .income {
            guard let bd = record.salaryBreakdown else { continue }
            
            // 中位数月工资
            let salaries = bd.salaryBaseItems.map { $0.amount }.sorted()
            if !salaries.isEmpty {
                let mid = salaries.count / 2
                let median = salaries.count % 2 == 0 ? (salaries[mid - 1] + salaries[mid]) / 2.0 : salaries[mid]
                monthlyIncome = max(monthlyIncome, median)
            }
            
            // 其他月收入
            monthlyIncome += bd.otherIncomeItems.reduce(0) { $0 + $1.amount }
            
            // 最低3次年终奖平均值
            let bonusAmounts = bd.bonusItems.map { $0.amount }.sorted()
            let bottomBonuses = Array(bonusAmounts.prefix(3))
            if !bottomBonuses.isEmpty {
                monthlyIncome += bottomBonuses.reduce(0, +) / Double(bottomBonuses.count) / 12.0
            }
            
            // 最低2次长期激励平均值
            let equityAmounts = bd.equityItems.map { $0.perVestingAmount * (12.0 / max(Double($0.vestingMonths), 1)) }.sorted()
            let bottomEquities = Array(equityAmounts.prefix(2))
            if !bottomEquities.isEmpty {
                monthlyIncome += bottomEquities.reduce(0, +) / Double(bottomEquities.count) / 12.0
            }
        }
        
        // 投资回报率减半
        let investmentMonthlyReturn = totalInvestmentAmount * (weightedAverageReturn / 100.0 / 2.0) / 12.0
        return monthlyIncome + investmentMonthlyReturn
    }
    
    /// 近 6 个月图表数据
    func monthlyChartData() -> [MonthlyFinanceData] {
        return chartDataForMonths(count: 6)
    }
    
    /// 近 N 个月图表数据
    func chartDataForMonths(count: Int) -> [MonthlyFinanceData] {
        let calendar = Calendar.current
        let now = Date()
        var result: [MonthlyFinanceData] = []
        
        for i in (0..<count).reversed() {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!) else { continue }
            guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) else { continue }
            
            let income = totalIncome(from: monthStart, to: monthEnd)
            let debt = totalDebt(from: monthStart, to: monthEnd)
            let investment = totalInvestment(from: monthStart, to: monthEnd)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "M月"
            let label = formatter.string(from: monthStart)
            
            result.append(MonthlyFinanceData(month: label, income: income, debt: debt, investment: investment, date: monthStart))
        }
        return result
    }
    
    /// 近 N 年图表数据（按年汇总，跳过前面连续无收入无负债的年度）
    func chartDataForYears(count: Int) -> [MonthlyFinanceData] {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        var result: [MonthlyFinanceData] = []
        
        for i in (0..<count).reversed() {
            let year = currentYear - i
            guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { continue }
            
            var yearIncome: Double = 0
            var yearDebt: Double = 0
            var yearInvestment: Double = 0
            
            // 按月累加（确保结构性收入正确分布）
            for m in 0..<12 {
                guard let mStart = calendar.date(byAdding: .month, value: m, to: yearStart) else { continue }
                guard let mEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: mStart) else { continue }
                yearIncome += totalIncome(from: mStart, to: mEnd)
                yearDebt += totalDebt(from: mStart, to: mEnd)
                yearInvestment += totalInvestment(from: mStart, to: mEnd)
            }
            
            result.append(MonthlyFinanceData(month: "\(year)年", income: yearIncome, debt: yearDebt, investment: yearInvestment, date: yearStart))
        }
        
        // 去掉前面连续没有任何收入和负债的年度（保留当前年度）
        if let firstActiveIndex = result.firstIndex(where: { $0.income > 0 || $0.debt > 0 }) {
            result = Array(result[firstActiveIndex...])
        } else {
            // 全部无数据时只保留当前年度
            result = result.suffix(1).map { $0 }
        }
        
        return result
    }
    
    /// 完整月度趋势（从最早记录到现在）
    func fullMonthlyChartData() -> [MonthlyFinanceData] {
        let calendar = Calendar.current
        let now = Date()
        // 找到最早的记录日期
        let earliest = records.map { $0.date }.min() ?? now
        let monthsDiff = calendar.dateComponents([.month], from: earliest, to: now).month ?? 0
        return chartDataForMonths(count: max(monthsDiff + 1, 12))
    }
    
    /// 完整年度趋势（从最早记录到现在）
    func fullYearlyChartData() -> [MonthlyFinanceData] {
        let calendar = Calendar.current
        let now = Date()
        let earliest = records.map { $0.date }.min() ?? now
        let yearsDiff = calendar.component(.year, from: now) - calendar.component(.year, from: earliest)
        return chartDataForYears(count: max(yearsDiff + 1, 3))
    }
    
    /// 资产趋势（月度）：基础资产 + 从最早月到各月的累计净收支
    func assetChartDataMonths(count: Int, baseAssets: Double) -> [MonthlyFinanceData] {
        let cal = Calendar.current
        let now = Date()
        let curMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        var result: [MonthlyFinanceData] = []
        
        // 先收集每月净收支
        var monthlyNets: [(date: Date, label: String, net: Double)] = []
        for i in (0..<count).reversed() {
            let mStart = cal.date(byAdding: .month, value: -i, to: curMonth)!
            let mEnd = cal.date(byAdding: DateComponents(month: 1, second: -1), to: mStart)!
            let net = totalIncome(from: mStart, to: mEnd) - totalDebt(from: mStart, to: mEnd) + totalInvestment(from: mStart, to: mEnd)
            let fmt = DateFormatter(); fmt.dateFormat = "M月"
            monthlyNets.append((mStart, fmt.string(from: mStart), net))
        }
        
        // 基础资产 + 累计净变化
        var cumNet: Double = 0
        for item in monthlyNets {
            cumNet += item.net
            let assetValue = baseAssets + cumNet
            if abs(assetValue) >= 10 {
                result.append(MonthlyFinanceData(month: item.label, income: assetValue, debt: 0, investment: 0, date: item.date))
            }
        }
        return result
    }
    
    /// 资产趋势（年度）
    func assetChartDataYears(count: Int, baseAssets: Double) -> [MonthlyFinanceData] {
        let cal = Calendar.current
        let curYear = cal.component(.year, from: Date())
        var result: [MonthlyFinanceData] = []
        var cumNet: Double = 0
        
        for i in (0..<count).reversed() {
            let year = curYear - i
            let yStart = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            var yearNet: Double = 0
            for m in 0..<12 {
                let mS = cal.date(byAdding: .month, value: m, to: yStart)!
                let mE = cal.date(byAdding: DateComponents(month: 1, second: -1), to: mS)!
                yearNet += totalIncome(from: mS, to: mE) - totalDebt(from: mS, to: mE) + totalInvestment(from: mS, to: mE)
            }
            cumNet += yearNet
            let assetValue = baseAssets + cumNet
            if abs(assetValue) >= 10 {
                result.append(MonthlyFinanceData(month: "\(year)年", income: assetValue, debt: 0, investment: 0, date: yStart))
            }
        }
        return result
    }
    
    // MARK: - CRUD
    
    /// 当前工资配置记录（取第一条工资类型记录）
    var salaryRecord: FinanceRecord? {
        records.first { $0.type == .income && $0.incomePeriod == .salary && $0.salaryBreakdown != nil }
    }
    
    func addRecord(_ record: FinanceRecord) {
        records.append(record)
        records.sort { $0.date > $1.date }
        saveRecords()
    }
    
    func deleteRecord(_ record: FinanceRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }
    
    func updateRecord(_ record: FinanceRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            records.sort { $0.date > $1.date }
            saveRecords()
        }
    }
    
    func updateAssets(_ amount: Double) {
        totalAssets = amount
        saveAssets()
    }
    
    func updateGoal(_ goal: SavingsGoal) {
        savingsGoal = goal
        saveGoal()
    }
    
    // MARK: - 持久化
    
    private func loadAll() {
        if let data = try? Data(contentsOf: recordsFileURL),
           let decoded = try? JSONDecoder().decode([FinanceRecord].self, from: data) {
            records = decoded.sorted { $0.date > $1.date }
        }
        if let data = try? Data(contentsOf: goalFileURL),
           let decoded = try? JSONDecoder().decode(SavingsGoal.self, from: data) {
            savingsGoal = decoded
        }
        if let data = try? Data(contentsOf: assetsFileURL),
           let decoded = try? JSONDecoder().decode(Double.self, from: data) {
            totalAssets = decoded
        }
    }
    
    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: recordsFileURL)
        }
    }
    
    private func saveGoal() {
        if let data = try? JSONEncoder().encode(savingsGoal) {
            try? data.write(to: goalFileURL)
        }
    }
    
    private func saveAssets() {
        if let data = try? JSONEncoder().encode(totalAssets) {
            try? data.write(to: assetsFileURL)
        }
    }
}

/// 月度图表数据
struct MonthlyFinanceData: Identifiable {
    let id = UUID()
    let month: String
    let income: Double
    let debt: Double
    let investment: Double
    let date: Date
    
    /// 该条数据中最大的单值
    var maxValue: Double {
        max(income, debt, investment)
    }
}

/// 计算图表 Y 轴上限，避免异常大值压扁其他月波动
/// 规则：如果最大值 > 其余月平均值的 3 倍，则上限 = 平均值 × 3
func chartYCap(for data: [MonthlyFinanceData]) -> Double {
    let allValues = data.flatMap { [$0.income, $0.debt, $0.investment] }.filter { $0 > 0 }
    guard allValues.count > 1 else { return allValues.first ?? 1 }
    
    let maxVal = allValues.max() ?? 1
    // 计算排除最大值后的平均值
    let othersSum = allValues.reduce(0, +) - maxVal
    let othersAvg = othersSum / Double(allValues.count - 1)
    
    if othersAvg > 0 && maxVal > othersAvg * 3 {
        return othersAvg * 3
    }
    return maxVal
}

/// 将图表数据截断到 cap 上限（用于展示，实际数据不变）
func cappedChartData(_ data: [MonthlyFinanceData], cap: Double) -> [MonthlyFinanceData] {
    data.map { d in
        MonthlyFinanceData(
            month: d.month,
            income: min(d.income, cap),
            debt: min(d.debt, cap),
            investment: min(d.investment, cap),
            date: d.date
        )
    }
}

// MARK: - 主视图

struct DailyExpenseView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    @ObservedObject var financeStore: FinanceStore
    
    @State private var showingAddRecord = false
    @State private var showingEditGoal = false
    @State private var showingFullTrend = false
    @State private var showingSalaryConfig = false
    @State private var showingSavingsConfig = false
    @State private var showingAssetDetail = false
    @State private var selectedRecord: FinanceRecord? = nil
    @State private var periodMode: PeriodMode = .year
    @State private var showCurrentMonthIncome = false
    @State private var incomeOutlook: FinanceStore.IncomeOutlook = .fluctuating
    @State private var chartMode: ChartMode = .income
    
    enum PeriodMode: String, CaseIterable {
        case year = "年度"
        case month = "月度"
    }
    
    enum ChartMode: String, CaseIterable {
        case income = "收入"
        case assets = "资产"
    }
    
    private var incomeAmount: Double {
        if periodMode == .month {
            if showCurrentMonthIncome {
                let range = financeStore.monthRange
                return financeStore.totalIncome(from: range.start, to: range.end)
            }
            return financeStore.averageMonthlyIncome()
        } else {
            return financeStore.trailing12MonthsIncome()
        }
    }
    
    private var debtAmount: Double {
        let range = periodMode == .year ? financeStore.yearRange : financeStore.monthRange
        return financeStore.totalDebt(from: range.start, to: range.end)
    }
    
    private var investmentAmount: Double {
        let range = periodMode == .year ? financeStore.yearRange : financeStore.monthRange
        return financeStore.totalInvestment(from: range.start, to: range.end)
    }
    
    /// 我的物品总价（非归档、非无价之物）
    private var itemsTotalPrice: Double {
        store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                totalAssetsCard
                incomeDebtOverview
                incomeStatusCard
                chartCard
                goalEstimateCard
                recentRecordsCard
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddRecord) {
            AddFinanceRecordView(financeStore: financeStore)
        }
        .sheet(item: $selectedRecord) { record in
            AddFinanceRecordView(financeStore: financeStore, editingRecord: record)
        }
        .sheet(isPresented: $showingEditGoal) {
            EditGoalView(financeStore: financeStore, incomeOutlook: $incomeOutlook)
        }
        .sheet(isPresented: $showingFullTrend) {
            FullTrendView(financeStore: financeStore)
        }
        .sheet(isPresented: $showingSalaryConfig) {
            SalaryConfigView(financeStore: financeStore)
        }
        .sheet(isPresented: $showingSavingsConfig) {
            SavingsConfigView(financeStore: financeStore)
        }
        .sheet(isPresented: $showingAssetDetail) {
            AssetDetailView(financeStore: financeStore, store: store, selectedRecord: $selectedRecord)
        }
    }
    
    // MARK: - 总资产卡片
    
    private var totalAssetsCard: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("当前总资产")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("¥\(financeStore.calculatedTotalAssets(itemsTotalPrice: itemsTotalPrice), specifier: "%.2f")")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 快速统计行
            HStack(spacing: 0) {
                miniStatItem(title: "总资产价值", value: financeStore.totalSavingsAmount + financeStore.totalInvestmentAmount + itemsTotalPrice, color: .orange)
                Divider().frame(height: 30)
                miniStatItem(title: "剩余负债", value: financeStore.totalRemainingDebt, color: .red)
                Divider().frame(height: 30)
                miniStatItem(title: "年度收入", value: financeStore.trailing12MonthsIncome(), color: .green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func miniStatItem(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("¥\(value, specifier: "%.0f")")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 收入/负债/投资概览
    
    /// 大件物品总价
    private var largeItemsTotalPrice: Double {
        store.items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem && !$0.isPriceless }.reduce(0) { $0 + $1.price }
    }
    
    private var incomeDebtOverview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("资产状况")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showingAssetDetail = true
                } label: {
                    HStack(spacing: 2) {
                        Text("资产详情")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
            
            HStack(spacing: 8) {
                overviewTile(
                    icon: "banknote.fill",
                    label: "储蓄金额",
                    amount: financeStore.totalSavingsAmount,
                    color: .green
                )
                .onTapGesture { showingSavingsConfig = true }
                overviewTile(
                    icon: "house.fill",
                    label: "大件价值",
                    amount: largeItemsTotalPrice,
                    color: .orange
                )
                overviewTile(
                    icon: "chart.line.uptrend.xyaxis.circle.fill",
                    label: "投资价值",
                    amount: financeStore.totalInvestmentAmount,
                    color: .blue
                )
            }
            
            // 管理储蓄入口
            Button {
                showingSavingsConfig = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("管理储蓄")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(financeStore.totalSavingsAmount > 0 ? "储蓄总额 ¥\(financeStore.totalSavingsAmount, specifier: "%.0f")" : "添加定期存款、银行储蓄等")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.green.gradient)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private func overviewTile(icon: String, label: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("¥\(amount, specifier: "%.0f")")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - 收入状况
    
    private var incomeStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("收入状况")
                    .font(.headline)
                Spacer()
                if financeStore.salaryRecord != nil {
                    Picker("", selection: $periodMode) {
                        ForEach(PeriodMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    Button {
                        showingSalaryConfig = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            if let record = financeStore.salaryRecord, let bd = record.salaryBreakdown {
                // 收入/负债/投资概览
                if periodMode == .month {
                HStack(spacing: 8) {
                    overviewTile(
                        icon: "arrow.up.circle.fill",
                        label: showCurrentMonthIncome ? "本月收入" : "月均收入",
                        amount: incomeAmount,
                        color: .green
                    )
                    .onTapGesture {
                        withAnimation { showCurrentMonthIncome.toggle() }
                    }
                    overviewTile(
                        icon: "arrow.down.circle.fill",
                        label: "月度负债",
                        amount: debtAmount,
                        color: .red
                    )
                    overviewTile(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        label: "月度投资",
                        amount: investmentAmount,
                        color: .blue
                    )
                }
            } else {
                let annualSalary = bd.currentMonthlyBase
                let annualIncentive = bd.equityItems.reduce(0.0) { $0 + $1.perVestingAmount * (12.0 / max(Double($1.vestingMonths), 1)) }
                
                HStack(spacing: 8) {
                    overviewTile(
                        icon: "arrow.up.circle.fill",
                        label: "全年收入",
                        amount: incomeAmount,
                        color: .green
                    )
                    overviewTile(
                        icon: "briefcase.fill",
                        label: "全年工资",
                        amount: annualSalary * 12,
                        color: .primary
                    )
                    overviewTile(
                        icon: "star.fill",
                        label: "长期激励",
                        amount: annualIncentive,
                        color: .purple
                    )
                }
            }
            
                // 已配置工资 - 根据模式展示摘要
                let gross = bd.totalMonthlyGross
                let net = bd.totalMonthlyIncome
                let social = bd.socialInsurance
                let tax = bd.effectiveAnnualTax
                
                HStack(spacing: 8) {
                    if periodMode == .month {
                        VStack(spacing: 4) {
                            Text("月税前")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(gross, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 4) {
                            Text("月社保")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(social, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 4) {
                            Text("月净收入")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(net, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 4) {
                            Text("年税前")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(gross * 12, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 4) {
                            Text("年个税")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(tax, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.red)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 4) {
                            Text("年社保")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(social * 12, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 4) {
                            Text("年净收入")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("¥\(net * 12, specifier: "%.0f")")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
            } else {
                // 未配置 - 绿色提示块
                Button {
                    showingSalaryConfig = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "briefcase.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("配置结构性工资")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("设置基本工资、长期激励、年终奖等，自动计算个税")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.green.gradient)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - 图表
    
    private func chartCardData() -> [MonthlyFinanceData] {
        periodMode == .year
            ? financeStore.chartDataForYears(count: 6)
            : financeStore.monthlyChartData()
    }
    
    private var chartCard: some View {
        let chartData = chartCardData()
        let assetData = chartMode == .assets
            ? (periodMode == .year
                ? financeStore.assetChartDataYears(count: 6, baseAssets: 0)
                : financeStore.assetChartDataMonths(count: 6, baseAssets: 0))
            : []
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(periodMode == .year ? "近 \(chartData.count) 年趋势" : "近 6 个月趋势")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Picker("", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                Button {
                    showingFullTrend = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            
            if chartMode == .income {
                if chartData.contains(where: { $0.income > 0 || $0.debt > 0 || $0.investment > 0 }) {
                    let yCap = chartYCap(for: chartData)
                    let displayData = cappedChartData(chartData, cap: yCap)
                    Chart {
                        ForEach(displayData) { data in
                            BarMark(x: .value("时间", data.month), y: .value("金额", data.income))
                                .foregroundStyle(.green.opacity(0.7))
                                .position(by: .value("类型", "收入"))
                            BarMark(x: .value("时间", data.month), y: .value("金额", data.debt))
                                .foregroundStyle(.red.opacity(0.7))
                                .position(by: .value("类型", "负债"))
                            BarMark(x: .value("时间", data.month), y: .value("金额", data.investment))
                                .foregroundStyle(.blue.opacity(0.7))
                                .position(by: .value("类型", "投资"))
                        }
                    }
                    .chartYScale(domain: 0...yCap)
                    .chartForegroundStyleScale(["收入": .green.opacity(0.7), "负债": .red.opacity(0.7), "投资": .blue.opacity(0.7)])
                    .chartLegend(position: .bottom)
                    .frame(height: 200)
                } else {
                    emptyChartPlaceholder
                }
            } else {
                if assetData.contains(where: { $0.income > 0 }) {
                    Chart {
                        ForEach(assetData) { data in
                            LineMark(x: .value("时间", data.month), y: .value("资产", data.income))
                                .foregroundStyle(.orange)
                                .interpolationMethod(.catmullRom)
                            AreaMark(x: .value("时间", data.month), y: .value("资产", data.income))
                                .foregroundStyle(.orange.opacity(0.15))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("时间", data.month), y: .value("资产", data.income))
                                .foregroundStyle(.orange)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 200)
                } else {
                    emptyChartPlaceholder
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.9))
            Text("添加记录后展示趋势图")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.blue.opacity(0.6))
        )
    }
    
    // MARK: - 目标达成预估
    
    private var goalEstimateCard: some View {
        VStack(spacing: 12) {
            if financeStore.savingsGoal.targetAmount > 0 {
                HStack {
                    Text(financeStore.savingsGoal.name)
                        .font(.headline)
                    Spacer()
                    Button {
                        showingEditGoal = true
                    } label: {
                        Image(systemName: "gearshape.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
                
                let progress = min((financeStore.totalSavingsAmount + financeStore.totalInvestmentAmount) / financeStore.savingsGoal.targetAmount, 1.0)
                
                Text("目标：¥\(financeStore.savingsGoal.targetAmount, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ProgressView(value: progress)
                    .tint(.orange)
                    .scaleEffect(y: 2)
                    .padding(.vertical, 4)
                
                HStack {
                    Text("进度 \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let months = financeStore.estimatedMonthsToGoal(itemsTotalPrice: 0, outlook: incomeOutlook) {
                        if months == 0 {
                            Text("🎉 目标已达成！")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        } else {
                            let years = months / 12
                            let remainMonths = months % 12
                            if years > 0 {
                                Text("预计 \(years) 年 \(remainMonths) 个月达成")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("预计 \(months) 个月达成")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("净收入不足，无法预估")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
            } else {
                Button {
                    showingEditGoal = true
                } label: {
                    Text("添加财务自由目标")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.purple)
                    )
                }
            }
        }
        .padding(financeStore.savingsGoal.targetAmount > 0 ? 16 : 0)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(financeStore.savingsGoal.targetAmount > 0 ? Color(.secondarySystemGroupedBackground) : Color.clear)
        )
    }
    
    // MARK: - 近期财务事件
    
    /// 财务事件类型
    private enum FinanceEventType {
        case salary       // 工资发放
        case debt         // 负债扣款
        case equity       // 长期激励归属
        case unrealized   // 未归属收入归属
        case bonus        // 年终奖发放
        
        var icon: String {
            switch self {
            case .salary: return "yensign.circle.fill"
            case .debt: return "creditcard.fill"
            case .equity: return "star.circle.fill"
            case .unrealized: return "clock.arrow.circlepath"
            case .bonus: return "gift.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .salary: return .green
            case .debt: return .red
            case .equity: return .purple
            case .unrealized: return .orange
            case .bonus: return .yellow
            }
        }
        
        var label: String {
            switch self {
            case .salary: return "工资发放"
            case .debt: return "负债扣款"
            case .equity: return "激励归属"
            case .unrealized: return "收入归属"
            case .bonus: return "年终奖"
            }
        }
    }
    
    /// 财务事件
    private struct FinanceEvent: Identifiable {
        let id = UUID()
        let date: Date
        let type: FinanceEventType
        let title: String
        let amount: Double
        let isPast: Bool
    }
    
    /// 生成近期财务事件（过去6个月 + 未来1个月）
    private var recentFinanceEvents: [FinanceEvent] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: today),
              let oneMonthLater = calendar.date(byAdding: .month, value: 1, to: today) else {
            return []
        }
        
        /// 生成指定日（day）在某月的日期，超出天数则取月末
        func dateForDay(_ day: Int, inMonthOf base: Date) -> Date {
            var comp = calendar.dateComponents([.year, .month], from: base)
            let range = calendar.range(of: .day, in: .month, for: base)!
            comp.day = min(day, range.upperBound - 1)
            return calendar.date(from: comp) ?? base
        }
        
        var events: [FinanceEvent] = []
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        // 获取工资配置
        if let salaryRecord = financeStore.salaryRecord,
           let bd = salaryRecord.salaryBreakdown {
            
            let payDay = bd.payDay
            
            // 1. 工资发放：使用实际发薪日
            let activeSalary = bd.salaryBaseItems.filter { $0.isActive(at: now) }
            if !activeSalary.isEmpty {
                let monthlyBase = activeSalary.reduce(0) { $0 + $1.amount }
                for offset in -6...1 {
                    guard let monthBase = calendar.date(byAdding: .month, value: offset, to: currentMonthStart) else { continue }
                    let payDate = dateForDay(payDay, inMonthOf: monthBase)
                    if payDate >= sixMonthsAgo && payDate <= oneMonthLater {
                        events.append(FinanceEvent(
                            date: payDate,
                            type: .salary,
                            title: "月薪发放",
                            amount: monthlyBase,
                            isPast: payDate < today
                        ))
                    }
                }
            }
            
            // 2. 长期激励归属
            for equity in bd.equityItems where equity.perVestingAmount > 0 {
                guard let firstVesting = equity.vestingDate else { continue }
                let vestingMonths = max(equity.vestingMonths, 1)
                
                let maxIterations = equity.isLongTermVesting ? 100 : (equity.vestingCount ?? 0)
                for i in 0..<maxIterations {
                    guard let vestDate = calendar.date(byAdding: .month, value: vestingMonths * i, to: firstVesting) else { break }
                    if vestDate > oneMonthLater { break }
                    if vestDate < sixMonthsAgo { continue }
                    
                    let typeName = equity.incentiveType == .equity ? "股权归属" : "现金激励归属"
                    events.append(FinanceEvent(
                        date: vestDate,
                        type: .equity,
                        title: equity.note.isEmpty ? typeName : equity.note,
                        amount: equity.perVestingAmount,
                        isPast: vestDate < today
                    ))
                }
            }
            
            // 3. 年终奖
            for bonus in bd.bonusItems where bonus.amount > 0 {
                if bonus.date >= sixMonthsAgo && bonus.date <= oneMonthLater {
                    events.append(FinanceEvent(
                        date: bonus.date,
                        type: .bonus,
                        title: bonus.note.isEmpty ? "年终奖发放" : bonus.note,
                        amount: bonus.amount,
                        isPast: bonus.date < today
                    ))
                }
            }
        }
        
        // 4. 负债扣款：使用实际还款日
        for record in financeStore.records where record.type == .debt {
            guard let monthlyPayment = record.monthlyPayment, monthlyPayment > 0 else { continue }
            let startDate = record.loanStartDate ?? record.date
            let totalMonths = record.loanMonths ?? 0
            let rDay = record.repayDay ?? calendar.component(.day, from: startDate)
            
            for offset in -6...1 {
                guard let monthBase = calendar.date(byAdding: .month, value: offset, to: currentMonthStart) else { continue }
                let repayDate = dateForDay(rDay, inMonthOf: monthBase)
                if repayDate < startDate { continue }
                if totalMonths > 0 {
                    let elapsed = calendar.dateComponents([.month], from: startDate, to: repayDate).month ?? 0
                    if elapsed >= totalMonths { continue }
                }
                if repayDate >= sixMonthsAgo && repayDate <= oneMonthLater {
                    events.append(FinanceEvent(
                        date: repayDate,
                        type: .debt,
                        title: record.title,
                        amount: monthlyPayment,
                        isPast: repayDate < today
                    ))
                }
            }
        }
        
        // 5. 未归属收入
        for record in financeStore.records where record.type == .income && record.incomePeriod == .unrealized {
            if record.date >= sixMonthsAgo && record.date <= oneMonthLater {
                events.append(FinanceEvent(
                    date: record.date,
                    type: .unrealized,
                    title: record.title,
                    amount: record.amount,
                    isPast: record.date < today
                ))
            }
        }
        
        // 6. 一次性收入
        for record in financeStore.records where record.type == .income && record.incomePeriod == .oneTime {
            if record.date >= sixMonthsAgo && record.date <= oneMonthLater {
                events.append(FinanceEvent(
                    date: record.date,
                    type: .salary,
                    title: record.title,
                    amount: record.amount,
                    isPast: record.date < today
                ))
            }
        }
        
        return events.sorted { $0.date > $1.date }
    }
    
    private var recentRecordsCard: some View {
        let events = recentFinanceEvents
        
        return Group {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("近期事件")
                            .font(.headline)
                        Spacer()
                        Text("近6个月")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(events) { event in
                        eventRow(event)
                        
                        if event.id != events.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }
    
    private func eventRow(_ event: FinanceEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.type.icon)
                .font(.title3)
                .foregroundStyle(event.isPast ? event.type.color.opacity(0.5) : event.type.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(event.isPast ? .secondary : .primary)
                    
                    Text(event.type.label)
                        .font(.caption2)
                        .foregroundStyle(event.type.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(event.type.color.opacity(0.1)))
                }
                
                Text(chineseDateString(event.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(event.type == .debt ? "-" : "+")¥\(event.amount, specifier: "%.0f")")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(event.isPast ? event.type.color.opacity(0.5) : event.type.color)
        }
        .opacity(event.isPast ? 0.7 : 1.0)
        .padding(.vertical, 2)
    }
    
    private func chineseDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        return fmt.string(from: date)
    }
    
    private func recordRow(_ record: FinanceRecord) -> some View {
        HStack(spacing: 10) {
            // 类型图标
            Image(systemName: record.type.icon)
                .font(.title3)
                .foregroundStyle(record.type.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // 标签
                    if record.type == .income, let period = record.incomePeriod {
                        Text(period.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.green.opacity(0.1)))
                        if period == .salary, let bd = record.salaryBreakdown {
                            Text("月入¥\(bd.totalMonthlyIncome, specifier: "%.0f")")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.green.opacity(0.1)))
                        }
                    }
                    if record.type == .debt, let months = record.loanMonths {
                        Text("\(months)期")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red.opacity(0.1)))
                    }
                    if record.type == .investment, let ret = record.expectedReturn {
                        Text("\(ret, specifier: "%.1f")%")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.blue.opacity(0.1)))
                    }
                }
                
                HStack(spacing: 4) {
                    Text(chineseDateString(record.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if record.type == .debt, let mp = record.monthlyPayment {
                        Text("· 月供 ¥\(mp, specifier: "%.0f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let platform = record.investmentPlatform, !platform.isEmpty {
                        Text("· \(platform)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                let prefix = record.type == .income ? "+" : (record.type == .debt ? "-" : "")
                Text("\(prefix)¥\(record.amount, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(record.type.color)
                
                if record.type == .debt, let remaining = record.remainingLoanMonths, remaining > 0 {
                    Text("剩\(remaining)期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRecord = record
        }
        .contextMenu {
            Button {
                selectedRecord = record
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                financeStore.deleteRecord(record)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - 添加记录视图

struct AddFinanceRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    
    /// 编辑模式：传入已有记录
    var editingRecord: FinanceRecord? = nil
    private var isEditing: Bool { editingRecord != nil }
    
    @State private var title = ""
    @State private var amountText = ""
    @State private var type: FinanceType = .income
    @State private var category = ""
    @State private var date = Date()
    @State private var note = ""
    
    // 各类型输入缓存（切换时保存/恢复）
    @State private var cachedInputs: [FinanceType: (title: String, amount: String, note: String)] = [:]
    
    // 收入
    @State private var incomePeriod: IncomePeriod = .oneTime
    @State private var countAsIncome = false
    @State private var addToSavings = true
    @State private var showSalaryBreakdown = false
    @State private var salaryBaseItems: [SalaryBaseItem] = [SalaryBaseItem()]
    @State private var equityItems: [EquityItem] = []
    @State private var bonusItems: [BonusItem] = []
    @State private var otherIncomeItems: [OtherIncomeItem] = []
    @State private var annualTaxText = ""
    @State private var showTax = false
    @State private var autoCalculateTax = true
    @State private var pensionRateText = "8"
    @State private var medicalRateText = "2"
    @State private var unemploymentRateText = "0.2"
    @State private var housingFundRateText = "5"
    @State private var socialInsuranceText = ""
    @State private var specialDeductionText = ""
    
    // 负债
    @State private var debtType: DebtType = .mortgage
    @State private var repaymentType: RepaymentType = .standard
    @State private var loanMonthsText = ""
    @State private var monthlyPaymentText = ""
    @State private var loanRateText = ""
    @State private var repayDay = 1
    
    // 投资
    @State private var expectedReturnText = ""
    @State private var investmentPlatform = ""
    
    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        guard let amt = Double(amountText), amt > 0 else { return false }
        
        if type == .debt {
            if let months = Int(loanMonthsText), months > 0 {
                return true
            }
            return false
        }
        return true
    }
    
    /// 构建当前输入状态的 SalaryBreakdown（用于实时计算）
    private func buildCurrentBreakdown() -> SalaryBreakdown {
        // 自动从比例计算社保公积金
        let base = salaryBaseItems.filter { $0.isActive(at: Date()) }.reduce(0) { $0 + $1.amount }
        let r1 = Double(pensionRateText) ?? 8
        let r2 = Double(medicalRateText) ?? 2
        let r3 = Double(unemploymentRateText) ?? 0.2
        let r4 = Double(housingFundRateText) ?? 5
        let totalRate = r1 + r2 + r3 + r4
        let calculatedSocial = autoCalculateTax ? base * totalRate / 100.0 : (Double(socialInsuranceText) ?? 0)
        
        return SalaryBreakdown(
            salaryBaseItems: salaryBaseItems.filter { $0.amount > 0 },
            equityItems: equityItems,
            bonusItems: bonusItems,
            otherIncomeItems: otherIncomeItems,
            annualTax: Double(annualTaxText) ?? 0,
            autoCalculateTax: autoCalculateTax,
            socialInsurance: calculatedSocial,
            specialDeduction: Double(specialDeductionText) ?? 0,
            pensionRate: r1,
            medicalRate: r2,
            unemploymentRate: r3,
            housingFundRate: r4
        )
    }
    
    /// 结构性收入计算的月度净收入
    private var salaryBreakdownMonthly: Double {
        let bd = buildCurrentBreakdown()
        return bd.totalMonthlyIncome
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 大类型选择
                Section {
                    Picker("类型", selection: $type) {
                        ForEach(FinanceType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .onChange(of: type) { oldType, newType in
                        guard !isEditing else { return }
                        cachedInputs[oldType] = (title, amountText, note)
                        if let cached = cachedInputs[newType] {
                            title = cached.title
                            amountText = cached.amount
                            note = cached.note
                        } else {
                            title = ""
                            amountText = ""
                            note = ""
                        }
                    }
                }
                
                switch type {
                case .income:
                    Section(header: Text("收入类型").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        Picker("类型", selection: $incomePeriod) {
                            Text(IncomePeriod.oneTime.rawValue).font(.system(.body, design: .rounded)).fontWeight(.semibold).tag(IncomePeriod.oneTime)
                            Text(IncomePeriod.unrealized.rawValue).font(.system(.body, design: .rounded)).fontWeight(.semibold).tag(IncomePeriod.unrealized)
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                        
                        if incomePeriod == .oneTime {
                            HStack {
                                Image(systemName: "info.circle").foregroundStyle(.blue)
                                Text("一次性收入不纳入月度净收入计算").font(.caption).foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                        if incomePeriod == .unrealized {
                            HStack {
                                Image(systemName: "info.circle").foregroundStyle(.blue)
                                Text("未归属收入（如期权、长期激励等），不纳入月度净收入").font(.caption).foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    Section(header: Text("收入信息").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        TextField(titlePlaceholder, text: $title)
                            .listRowSeparator(.hidden)
                        HStack {
                            Text("¥").foregroundStyle(.secondary)
                            TextField(amountPlaceholder, text: $amountText).keyboardType(.decimalPad)
                        }
                        .listRowSeparator(.hidden)
                        DatePicker("日期", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            .listRowSeparator(.hidden)
                        Toggle("计入收入", isOn: $countAsIncome)
                            .tint(.green)
                            .listRowSeparator(.hidden)
                        if !countAsIncome {
                            HStack {
                                Image(systemName: "info.circle").foregroundStyle(.blue)
                                Text("仅计入资产，不计入收入统计").font(.caption).foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                        Toggle("加入储蓄", isOn: $addToSavings)
                            .tint(.green)
                            .listRowSeparator(.hidden)
                        if addToSavings {
                            HStack {
                                Image(systemName: "info.circle").foregroundStyle(.green)
                                Text("保存时将同步添加一条同等金额的储蓄记录").font(.caption).foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                case .debt:
                    Section(header: Text("负债信息").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        Picker("贷款类型", selection: $debtType) {
                            ForEach(DebtType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                        TextField(titlePlaceholder, text: $title)
                            .listRowSeparator(.hidden)
                        HStack { Text("¥").foregroundStyle(.secondary); TextField(amountPlaceholder, text: $amountText).keyboardType(.decimalPad) }
                            .listRowSeparator(.hidden)
                        DatePicker("开始日期", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            .listRowSeparator(.hidden)
                    }
                    Section(header: Text("贷款设置").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        Picker("还款方式", selection: $repaymentType) {
                            ForEach(RepaymentType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                        
                        HStack {
                            Text("贷款期数")
                            Spacer()
                            TextField("月数", text: $loanMonthsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("个月")
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                        
                        HStack {
                            Text(repaymentType == .standard ? "每期费率" : "年利率")
                            Spacer()
                            TextField(repaymentType == .standard ? "如 0.35" : "如 3.5", text: $loanRateText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                        
                        Stepper("每月 \(repayDay) 号还款", value: $repayDay, in: 1...31)
                            .listRowSeparator(.hidden)
                        
                        if let months = Int(loanMonthsText), months > 0,
                           let totalAmount = Double(amountText), totalAmount > 0 {
                            let rateInput = (Double(loanRateText) ?? 0) / 100.0
                            
                            let firstMonthPayment: Double = {
                                switch repaymentType {
                                case .standard:
                                    return totalAmount / Double(months) + totalAmount * rateInput
                                case .equalPrincipal:
                                    let monthlyRate = rateInput / 12.0
                                    return totalAmount / Double(months) + totalAmount * monthlyRate
                                case .equalInstallment:
                                    let monthlyRate = rateInput / 12.0
                                    if monthlyRate > 0 {
                                        return totalAmount * monthlyRate * pow(1 + monthlyRate, Double(months)) / (pow(1 + monthlyRate, Double(months)) - 1)
                                    }
                                    return totalAmount / Double(months)
                                }
                            }()
                            
                            let totalPayment: Double = {
                                switch repaymentType {
                                case .standard:
                                    return firstMonthPayment * Double(months)
                                case .equalPrincipal:
                                    let monthlyRate = rateInput / 12.0
                                    let principal = totalAmount / Double(months)
                                    var total: Double = 0
                                    for i in 0..<months {
                                        total += principal + (totalAmount - principal * Double(i)) * monthlyRate
                                    }
                                    return total
                                case .equalInstallment:
                                    return firstMonthPayment * Double(months)
                                }
                            }()
                            
                            let totalInterest = totalPayment - totalAmount
                            
                            HStack {
                                Text(repaymentType == .equalPrincipal ? "首月还款" : "每月还款")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("¥\(firstMonthPayment, specifier: "%.2f")")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                            .listRowSeparator(.hidden)
                            
                            if repaymentType == .equalPrincipal {
                                let monthlyRate = rateInput / 12.0
                                let lastPayment = totalAmount / Double(months) + (totalAmount - totalAmount / Double(months) * Double(months - 1)) * monthlyRate
                                HStack {
                                    Text("末月还款")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("¥\(lastPayment, specifier: "%.2f")")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                }
                                .listRowSeparator(.hidden)
                            }
                            
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("还款总额 ¥\(totalPayment, specifier: "%.2f")，共 \(months) 期")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if totalInterest > 0 {
                                        Text("总利息 ¥\(totalInterest, specifier: "%.2f")")
                                            .font(.caption)
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                }
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                case .investment:
                    Section(header: Text("投资信息").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        TextField(titlePlaceholder, text: $title)
                            .listRowSeparator(.hidden)
                        HStack { Text("¥").foregroundStyle(.secondary); TextField(amountPlaceholder, text: $amountText).keyboardType(.decimalPad) }
                            .listRowSeparator(.hidden)
                        DatePicker("开始日期", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            .listRowSeparator(.hidden)
                    }
                    Section(header: Text("投资设置").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                        HStack {
                            Text("预期年化收益")
                            Spacer()
                            TextField("如 5.0", text: $expectedReturnText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                        
                        TextField("投资平台（可选）", text: $investmentPlatform)
                            .listRowSeparator(.hidden)
                        
                        if let ret = Double(expectedReturnText), ret > 0,
                           let amt = Double(amountText), amt > 0 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                Text("预估年收益 ¥\(amt * ret / 100.0, specifier: "%.2f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                
                // 备注
                Section(header: Text("备注").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                    TextField("备注信息", text: $note)
                        .listRowSeparator(.hidden)
                }
                
                // 编辑模式下显示删除按钮
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let record = editingRecord {
                                financeStore.deleteRecord(record)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("删除此记录")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
            .navigationTitle(isEditing ? "编辑\(type.rawValue)" : "添加\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveRecord()
                    }
                    .disabled(!isValid)
                    .fontWeight(.bold)
                    .foregroundStyle(isValid ? .orange : .gray.opacity(0.35))
                }
            }
            .onAppear {
                if let record = editingRecord {
                    populateFromRecord(record)
                } else {
                    countAsIncome = (incomePeriod == .oneTime)
                }
            }
            .onChange(of: incomePeriod) { _, newValue in
                if !isEditing {
                    countAsIncome = (newValue == .oneTime)
                }
            }
        }
    }
    
    private var titlePlaceholder: String {
        switch type {
        case .income: return "收入信息：Apple 收入"
        case .debt: return "房贷、车贷、花呗"
        case .investment: return "基金定投、股票"
        }
    }
    
    private var amountPlaceholder: String {
        switch type {
        case .income: return "收入金额"
        case .debt: return "贷款总额"
        case .investment: return "投资金额"
        }
    }
    
    private func saveRecord() {
        guard let finalAmount = Double(amountText) else { return }
        
        // 自动计算月供
        var calculatedMonthlyPayment: Double? = nil
        if type == .debt, let months = Int(loanMonthsText), months > 0 {
            let rateInput = (Double(loanRateText) ?? 0) / 100.0
            switch repaymentType {
            case .standard:
                calculatedMonthlyPayment = finalAmount / Double(months) + finalAmount * rateInput
            case .equalPrincipal:
                // 首月还款（最大值）
                let monthlyRate = rateInput / 12.0
                calculatedMonthlyPayment = finalAmount / Double(months) + finalAmount * monthlyRate
            case .equalInstallment:
                let monthlyRate = rateInput / 12.0
                if monthlyRate > 0 {
                    calculatedMonthlyPayment = finalAmount * monthlyRate * pow(1 + monthlyRate, Double(months)) / (pow(1 + monthlyRate, Double(months)) - 1)
                } else {
                    calculatedMonthlyPayment = finalAmount / Double(months)
                }
            }
        }
        
        let record = FinanceRecord(
            id: editingRecord?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            amount: finalAmount,
            type: type,
            category: category,
            date: date,
            note: note,
            incomePeriod: type == .income ? incomePeriod : nil,
            countAsIncome: type == .income ? countAsIncome : nil,
            debtType: type == .debt ? debtType : nil,
            repaymentType: type == .debt ? repaymentType : nil,
            loanMonths: type == .debt ? Int(loanMonthsText) : nil,
            monthlyPayment: calculatedMonthlyPayment,
            loanRate: type == .debt ? Double(loanRateText) : nil,
            loanStartDate: type == .debt ? date : nil,
            repayDay: type == .debt ? repayDay : nil,
            expectedReturn: type == .investment ? Double(expectedReturnText) : nil,
            investmentPlatform: type == .investment ? investmentPlatform : nil
        )
        
        if isEditing {
            financeStore.updateRecord(record)
        } else {
            financeStore.addRecord(record)
            
            // 如果是收入且开启了"加入储蓄"，同步创建一条储蓄记录
            if type == .income && addToSavings {
                let savingsRecord = FinanceRecord(
                    id: UUID(),
                    title: "储蓄 - \(title.trimmingCharacters(in: .whitespaces))",
                    amount: finalAmount,
                    type: .income,
                    date: date,
                    note: "由\(incomePeriod.rawValue)自动转入",
                    incomePeriod: .savings,
                    countAsIncome: false
                )
                financeStore.addRecord(savingsRecord)
            }
        }
        dismiss()
    }
    
    /// 编辑模式下，从已有记录填充各字段
    private func populateFromRecord(_ record: FinanceRecord) {
        title = record.title
        type = record.type
        category = record.category
        date = record.date
        note = record.note
        
        switch record.type {
        case .income:
            incomePeriod = record.incomePeriod ?? .savings
            countAsIncome = record.countAsIncome ?? (record.incomePeriod == .oneTime)
            if let bd = record.salaryBreakdown {
                showSalaryBreakdown = true
                salaryBaseItems = bd.salaryBaseItems.isEmpty ? [SalaryBaseItem()] : bd.salaryBaseItems
                equityItems = bd.equityItems
                bonusItems = bd.bonusItems
                otherIncomeItems = bd.otherIncomeItems
                autoCalculateTax = bd.autoCalculateTax
                annualTaxText = bd.annualTax > 0 ? String(format: "%.0f", bd.annualTax) : ""
                showTax = bd.annualTax > 0 && !bd.autoCalculateTax
                specialDeductionText = bd.specialDeduction > 0 ? String(format: "%.0f", bd.specialDeduction) : ""
                pensionRateText = String(format: "%g", bd.pensionRate)
                medicalRateText = String(format: "%g", bd.medicalRate)
                unemploymentRateText = String(format: "%g", bd.unemploymentRate)
                housingFundRateText = String(format: "%g", bd.housingFundRate)
                if bd.socialInsurance > 0 {
                    socialInsuranceText = String(format: "%.0f", bd.socialInsurance)
                }
            } else {
                amountText = record.amount > 0 ? String(format: "%.2f", record.amount) : ""
            }
            
        case .debt:
            debtType = record.debtType ?? .mortgage
            repaymentType = record.repaymentType ?? .standard
            amountText = record.amount > 0 ? String(format: "%.2f", record.amount) : ""
            loanMonthsText = record.loanMonths != nil ? "\(record.loanMonths!)" : ""
            monthlyPaymentText = record.monthlyPayment != nil ? String(format: "%.2f", record.monthlyPayment!) : ""
            loanRateText = record.loanRate != nil ? String(format: "%.2f", record.loanRate!) : ""
            repayDay = record.repayDay ?? 1
            
        case .investment:
            amountText = record.amount > 0 ? String(format: "%.2f", record.amount) : ""
            expectedReturnText = record.expectedReturn != nil ? String(format: "%.1f", record.expectedReturn!) : ""
            investmentPlatform = record.investmentPlatform ?? ""
        }
    }
}

// MARK: - 编辑财务自由目标

struct EditGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    @Binding var incomeOutlook: FinanceStore.IncomeOutlook
    
    @State private var goalName: String = ""
    @State private var goalAmountText: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("目标名称").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                    TextField("例如：买房首付", text: $goalName)
                }
                Section(header: Text("目标金额").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                    TextField("输入目标金额", text: $goalAmountText)
                        .keyboardType(.decimalPad)
                }
                Section(header: Text("收入情况").font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(.primary).textCase(nil)) {
                    Picker("预估模式", selection: $incomeOutlook) {
                        ForEach(FinanceStore.IncomeOutlook.allCases, id: \.self) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    switch incomeOutlook {
                    case .fluctuating:
                        Text("按最近18个月平均收入预估").font(.caption).foregroundStyle(.secondary)
                    case .optimistic:
                        Text("按最高工资、top年终奖和长期激励预估").font(.caption).foregroundStyle(.secondary)
                    case .pessimistic:
                        Text("按中位数工资、最低年终奖和长期激励、投资回报减半预估").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("系统会根据收入情况和投资收益，预估达成目标所需时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("财务自由目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let amount = Double(goalAmountText) ?? 0
                        let name = goalName.trimmingCharacters(in: .whitespaces).isEmpty ? "财务自由目标" : goalName.trimmingCharacters(in: .whitespaces)
                        financeStore.updateGoal(SavingsGoal(targetAmount: amount, name: name))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                }
            }
            .onAppear {
                goalName = financeStore.savingsGoal.name
                goalAmountText = financeStore.savingsGoal.targetAmount > 0 ? String(format: "%.2f", financeStore.savingsGoal.targetAmount) : ""
            }
        }
    }
}

// MARK: - 完整趋势视图

struct FullTrendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    @State private var trendMode: TrendMode = .monthly
    
    enum TrendMode: String, CaseIterable {
        case monthly = "月度"
        case yearly = "年度"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 切换
                    Picker("", selection: $trendMode) {
                        ForEach(TrendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    let chartData = trendMode == .monthly
                        ? financeStore.fullMonthlyChartData()
                        : financeStore.fullYearlyChartData()
                    
                    if chartData.contains(where: { $0.income > 0 || $0.debt > 0 || $0.investment > 0 }) {
                        let yCap = chartYCap(for: chartData)
                        let displayData = cappedChartData(chartData, cap: yCap)
                        let chartWidth = max(CGFloat(displayData.count) * 60, UIScreen.main.bounds.width - 32)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                Chart {
                                    ForEach(displayData) { data in
                                        BarMark(x: .value("时间", data.month), y: .value("金额", data.income))
                                            .foregroundStyle(.green.opacity(0.7))
                                            .position(by: .value("类型", "收入"))
                                        BarMark(x: .value("时间", data.month), y: .value("金额", data.debt))
                                            .foregroundStyle(.red.opacity(0.7))
                                            .position(by: .value("类型", "负债"))
                                        BarMark(x: .value("时间", data.month), y: .value("金额", data.investment))
                                            .foregroundStyle(.blue.opacity(0.7))
                                            .position(by: .value("类型", "投资"))
                                    }
                                }
                                .chartYScale(domain: 0...yCap)
                                .chartForegroundStyleScale([
                                    "收入": .green.opacity(0.7),
                                    "负债": .red.opacity(0.7),
                                    "投资": .blue.opacity(0.7)
                                ])
                                .chartLegend(position: .bottom)
                                .frame(width: chartWidth, height: 300)
                                .id("trendChart")
                            }
                            .onAppear {
                                proxy.scrollTo("trendChart", anchor: .trailing)
                            }
                            .onChange(of: trendMode) { _, _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo("trendChart", anchor: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // 数据明细列表
                        VStack(spacing: 0) {
                            ForEach(chartData.reversed()) { data in
                                VStack(spacing: 6) {
                                    HStack {
                                        Text(data.month)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                    HStack {
                                        Label("收入", systemImage: "arrow.up.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                        Text("¥\(data.income, specifier: "%.0f")")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                        Spacer()
                                        Label("负债", systemImage: "arrow.down.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                        Text("¥\(data.debt, specifier: "%.0f")")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                        Spacer()
                                        Label("投资", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                        Text("¥\(data.investment, specifier: "%.0f")")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                
                                Divider().padding(.horizontal, 16)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("暂无数据")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                    }
                    
                    Spacer(minLength: 30)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("收支趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 工资配置视图

struct SalaryConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    
    @State private var title = "工资收入"
    @State private var salaryBaseItems: [SalaryBaseItem] = [SalaryBaseItem()]
    @State private var equityItems: [EquityItem] = []
    @State private var bonusItems: [BonusItem] = []
    @State private var otherIncomeItems: [OtherIncomeItem] = []
    @State private var autoCalculateTax = true
    @State private var annualTaxText = ""
    @State private var showTax = false
    @State private var pensionRateText = "8"
    @State private var medicalRateText = "2"
    @State private var unemploymentRateText = "0.2"
    @State private var housingFundRateText = "5"
    @State private var socialInsuranceText = ""
    @State private var specialDeductionText = ""
    @State private var note = ""
    @State private var payDay = 10
    
    private var isValid: Bool {
        salaryBaseItems.contains { $0.amount > 0 }
    }
    
    private func buildCurrentBreakdown() -> SalaryBreakdown {
        let base = salaryBaseItems.filter { $0.isActive(at: Date()) }.reduce(0) { $0 + $1.amount }
        let r1 = Double(pensionRateText) ?? 8
        let r2 = Double(medicalRateText) ?? 2
        let r3 = Double(unemploymentRateText) ?? 0.2
        let r4 = Double(housingFundRateText) ?? 5
        let totalRate = r1 + r2 + r3 + r4
        let calculatedSocial = autoCalculateTax ? base * totalRate / 100.0 : (Double(socialInsuranceText) ?? 0)
        
        return SalaryBreakdown(
            salaryBaseItems: salaryBaseItems.filter { $0.amount > 0 },
            equityItems: equityItems,
            bonusItems: bonusItems,
            otherIncomeItems: otherIncomeItems,
            annualTax: Double(annualTaxText) ?? 0,
            autoCalculateTax: autoCalculateTax,
            socialInsurance: calculatedSocial,
            specialDeduction: Double(specialDeductionText) ?? 0,
            pensionRate: r1,
            medicalRate: r2,
            unemploymentRate: r3,
            housingFundRate: r4,
            payDay: payDay
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("名称") {
                    TextField("如：工资收入", text: $title)
                }
                
                Section("发薪日") {
                    Stepper("每月 \(payDay) 号", value: $payDay, in: 1...31)
                }
                
                Section("基本工资") {
                    ForEach($salaryBaseItems) { $item in
                        VStack(spacing: 8) {
                            HStack { Text("月薪"); Spacer(); TextField("金额", value: $item.amount, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                            DatePicker("开始时间", selection: $item.startDate, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            Toggle("长期", isOn: $item.isLongTerm)
                            if !item.isLongTerm {
                                DatePicker("结束时间", selection: Binding(get: { item.endDate ?? Date() }, set: { item.endDate = $0 }), displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                            }
                            TextField("备注（如涨薪原因）", text: $item.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { salaryBaseItems.remove(atOffsets: $0) }
                    Button { withAnimation { salaryBaseItems.append(SalaryBaseItem()) } } label: {
                        Label("添加工资记录", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                }
                
                if !equityItems.isEmpty {
                    Section("长期激励") {
                        ForEach($equityItems) { $item in
                            VStack(spacing: 8) {
                                Picker("激励方式", selection: $item.incentiveType) {
                                    ForEach(IncentiveType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                if item.incentiveType == .equity {
                                    HStack { Text("授予股价"); Spacer(); TextField("股价", value: $item.grantPrice, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
                                    HStack { Text("股数"); Spacer(); TextField("股数", value: $item.shareCount, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100) }
                                    if item.totalValue > 0 { HStack { Text("总价值").foregroundStyle(.secondary); Spacer(); Text("¥\(item.totalValue, specifier: "%.0f")").foregroundStyle(.green) }.font(.caption) }
                                } else {
                                    HStack { Text(item.isLongTermVesting ? "单次金额" : "激励总额"); Spacer(); TextField("金额", value: $item.amount, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                                }
                                DatePicker("首次归属", selection: Binding(get: { item.vestingDate ?? Date() }, set: { item.vestingDate = $0 }), displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                                HStack { Text("归属频率"); Spacer(); TextField("月数", value: $item.vestingMonths, format: .emptyZeroInt).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60); Text("个月/次").font(.caption).foregroundStyle(.secondary) }
                                Toggle("长期归属", isOn: $item.isLongTermVesting)
                                if !item.isLongTermVesting {
                                    HStack { Text("归属次数"); Spacer(); TextField("次", value: $item.vestingCount, format: .emptyZeroInt).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60); Text("次").font(.caption).foregroundStyle(.secondary) }
                                }
                                if item.perVestingAmount > 0 { Text("单次归属 \(item.perVestingAmount, specifier: "%.0f")").font(.caption).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .trailing) }
                            }
                        }
                        .onDelete { equityItems.remove(atOffsets: $0) }
                    }
                }
                
                if !bonusItems.isEmpty {
                    Section("年终奖") {
                        ForEach($bonusItems) { $item in
                            VStack(spacing: 8) {
                                HStack { Text("金额"); Spacer(); TextField("年终奖", value: $item.amount, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                                DatePicker("发放时间", selection: $item.date, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
                                Toggle("单独计税", isOn: $item.separateTax).tint(.orange)
                            }
                        }
                        .onDelete { bonusItems.remove(atOffsets: $0) }
                    }
                }
                
                if !otherIncomeItems.isEmpty {
                    Section("其他收入") {
                        ForEach($otherIncomeItems) { $item in
                            VStack(spacing: 8) {
                                HStack { Text("每月金额"); Spacer(); TextField("金额", value: $item.amount, format: .emptyZero).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                                TextField("备注（如副业）", text: $item.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { otherIncomeItems.remove(atOffsets: $0) }
                    }
                }
                
                Section("添加收入项") {
                    Button { withAnimation { equityItems.append(EquityItem()) } } label: { Label("添加长期激励", systemImage: "plus.circle").foregroundStyle(.green) }
                        .listRowSeparator(.hidden)
                    Button { withAnimation { bonusItems.append(BonusItem()) } } label: { Label("添加年终奖", systemImage: "plus.circle").foregroundStyle(.green) }
                        .listRowSeparator(.hidden)
                    Button { withAnimation { otherIncomeItems.append(OtherIncomeItem()) } } label: { Label("添加其他收入", systemImage: "plus.circle").foregroundStyle(.green) }
                        .listRowSeparator(.hidden)
                }
                
                // 个税
                Section("个税") {
                    Toggle("自动计算个税", isOn: $autoCalculateTax).tint(.green).foregroundStyle(.green)
                        .listRowSeparator(.hidden)
                    
                    if autoCalculateTax {
                        HStack { Text("养老保险"); Spacer(); TextField("8", text: $pensionRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60); Text("%").foregroundStyle(.secondary) }
                        HStack { Text("医疗保险"); Spacer(); TextField("2", text: $medicalRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60); Text("%").foregroundStyle(.secondary) }
                        HStack { Text("失业保险"); Spacer(); TextField("0.2", text: $unemploymentRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60); Text("%").foregroundStyle(.secondary) }
                        HStack { Text("住房公积金"); Spacer(); TextField("5", text: $housingFundRateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60); Text("%").foregroundStyle(.secondary) }
                        
                        let pr = Double(pensionRateText) ?? 8; let mr = Double(medicalRateText) ?? 2
                        let ur = Double(unemploymentRateText) ?? 0.2; let hr = Double(housingFundRateText) ?? 5
                        let totalRate = pr + mr + ur + hr
                        let base = salaryBaseItems.filter { $0.isActive(at: Date()) }.reduce(0) { $0 + $1.amount }
                        let socialTotal = base * totalRate / 100.0
                        
                        HStack { Text("月社保公积金合计").font(.caption).foregroundStyle(.secondary); Spacer(); Text("¥\(socialTotal, specifier: "%.0f")（\(totalRate, specifier: "%.1f")%）").font(.caption).foregroundStyle(.orange) }
                        HStack { Text("月专项附加扣除"); Spacer(); TextField("如房贷等", text: $specialDeductionText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                        
                        let tempBd = buildCurrentBreakdown()
                        let autoTax = TaxCalculator.calculateAnnualTax(breakdown: tempBd)
                        let salaryTax = TaxCalculator.calculateSalaryTax(breakdown: tempBd)
                        let bonusTax = TaxCalculator.calculateBonusTax(breakdown: tempBd)
                        let incentiveTax = TaxCalculator.calculateIncentiveTax(breakdown: tempBd)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("工资个税").font(.caption).foregroundStyle(.secondary); Spacer(); Text("¥\(salaryTax, specifier: "%.0f")").font(.caption).foregroundStyle(.red) }
                            if bonusTax > 0 { HStack { Text("年终奖个税").font(.caption).foregroundStyle(.secondary); Spacer(); Text("¥\(bonusTax, specifier: "%.0f")").font(.caption).foregroundStyle(.red) } }
                            if incentiveTax > 0 { HStack { Text("长期激励个税").font(.caption).foregroundStyle(.secondary); Spacer(); Text("¥\(incentiveTax, specifier: "%.0f")").font(.caption).foregroundStyle(.red) } }
                            HStack { Text("年社保公积金").font(.caption).foregroundStyle(.secondary); Spacer(); Text("¥\(socialTotal * 12, specifier: "%.0f")").font(.caption).foregroundStyle(.orange) }
                            Divider()
                            HStack { Text("年度个税+社保合计").font(.subheadline).fontWeight(.medium); Spacer(); Text("¥\(autoTax + socialTotal * 12, specifier: "%.0f")").font(.subheadline).fontWeight(.bold).foregroundStyle(.red) }
                        }
                    } else {
                        if showTax {
                            HStack { Text("税额"); Spacer(); TextField("年度总额", text: $annualTaxText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                            Button { withAnimation { showTax = false; annualTaxText = "" } } label: { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary); Text("移除").font(.caption).foregroundStyle(.secondary) } }
                        } else {
                            Button { withAnimation { showTax = true } } label: { Label("添加个税", systemImage: "plus.circle").foregroundStyle(.yellow) }
                        }
                    }
                }
                
                // 收入汇总
                Section("收入汇总") {
                    let bd = buildCurrentBreakdown()
                    let effectiveTax = bd.effectiveAnnualTax
                    let gross = bd.totalMonthlyGross
                    let net = bd.totalMonthlyIncome
                    let monthlySocial = bd.socialInsurance
                    HStack { Text("月度税前"); Spacer(); Text("¥\(gross, specifier: "%.0f")").foregroundStyle(.secondary) }
                    if monthlySocial > 0 {
                        HStack { Text("月社保公积金"); Spacer(); Text("-¥\(monthlySocial, specifier: "%.0f")").foregroundStyle(.orange) }
                    }
                    if effectiveTax > 0 {
                        HStack { Text("年度个税\(autoCalculateTax ? "（自动）" : "")"); Spacer(); Text("-¥\(effectiveTax, specifier: "%.0f")").foregroundStyle(.red) }
                        HStack { Text("折合月均").font(.caption); Spacer(); Text("-¥\(effectiveTax / 12.0, specifier: "%.0f")/月").font(.caption).foregroundStyle(.red) }
                    }
                    HStack { Text("月度净收入").fontWeight(.medium); Spacer(); Text("¥\(net, specifier: "%.0f")").fontWeight(.bold).foregroundStyle(.green) }
                    HStack { Text("预估年净收入").fontWeight(.medium); Spacer(); Text("¥\(net * 12, specifier: "%.0f")").fontWeight(.bold).foregroundStyle(.green) }
                }
                
                Section("备注") {
                    TextField("备注信息", text: $note)
                        .listRowSeparator(.hidden)
                }
                
                // 编辑已有记录时显示删除
                if financeStore.salaryRecord != nil {
                    Section {
                        Button(role: .destructive) {
                            if let record = financeStore.salaryRecord {
                                financeStore.deleteRecord(record)
                            }
                            dismiss()
                        } label: {
                            HStack { Spacer(); Text("删除工资配置"); Spacer() }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .headerProminence(.increased)
            .navigationTitle("工资配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { saveConfig() }
                        .disabled(!isValid)
                        .fontWeight(.bold)
                        .foregroundStyle(isValid ? .orange : .gray.opacity(0.35))
                }
            }
            .onAppear { loadExisting() }
        }
    }
    
    private func loadExisting() {
        guard let record = financeStore.salaryRecord, let bd = record.salaryBreakdown else { return }
        title = record.title
        note = record.note
        salaryBaseItems = bd.salaryBaseItems.isEmpty ? [SalaryBaseItem()] : bd.salaryBaseItems
        equityItems = bd.equityItems
        bonusItems = bd.bonusItems
        otherIncomeItems = bd.otherIncomeItems
        autoCalculateTax = bd.autoCalculateTax
        annualTaxText = bd.annualTax > 0 ? String(format: "%.0f", bd.annualTax) : ""
        showTax = bd.annualTax > 0 && !bd.autoCalculateTax
        specialDeductionText = bd.specialDeduction > 0 ? String(format: "%.0f", bd.specialDeduction) : ""
        pensionRateText = String(format: "%g", bd.pensionRate)
        medicalRateText = String(format: "%g", bd.medicalRate)
        unemploymentRateText = String(format: "%g", bd.unemploymentRate)
        housingFundRateText = String(format: "%g", bd.housingFundRate)
        if bd.socialInsurance > 0 { socialInsuranceText = String(format: "%.0f", bd.socialInsurance) }
        payDay = bd.payDay
    }
    
    private func saveConfig() {
        let bd = buildCurrentBreakdown()
        let record = FinanceRecord(
            id: financeStore.salaryRecord?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "工资收入" : title.trimmingCharacters(in: .whitespaces),
            amount: bd.totalAnnualIncome,
            type: .income,
            date: financeStore.salaryRecord?.date ?? Date(),
            note: note,
            incomePeriod: .salary,
            salaryBreakdown: bd
        )
        if financeStore.salaryRecord != nil {
            financeStore.updateRecord(record)
        } else {
            financeStore.addRecord(record)
        }
        dismiss()
    }
}

// MARK: - 储蓄配置视图

struct SavingsConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    
    @State private var showingAddSavings = false
    @State private var editingRecord: FinanceRecord? = nil
    
    // 添加/编辑表单状态
    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var countAsIncome = false
    @State private var annualRateText = ""
    
    private var savingsRecords: [FinanceRecord] {
        financeStore.records.filter { $0.type == .income && $0.incomePeriod == .savings }
    }
    
    private var totalSavings: Double {
        savingsRecords.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 总额
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("储蓄总额")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("¥\(totalSavings, specifier: "%.2f")")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                
                // 储蓄记录列表
                Section {
                    if savingsRecords.isEmpty {
                        Text("暂无储蓄记录，点击右上角 + 添加")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(savingsRecords) { record in
                            Button {
                                editingRecord = record
                                title = record.title
                                amountText = String(format: "%.2f", record.amount)
                                date = record.date
                                note = record.note
                                countAsIncome = record.countAsIncome ?? false
                                annualRateText = record.expectedReturn != nil ? String(format: "%g", record.expectedReturn!) : ""
                                showingAddSavings = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.title)
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 8) {
                                            Text(chineseDateStr(record.date))
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(.secondary)
                                            if let rate = record.expectedReturn, rate > 0 {
                                                Text("\(rate, specifier: "%g")%")
                                                    .font(.system(.caption, design: .rounded))
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text("¥\(record.amount, specifier: "%.2f")")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                }
                            }
                            .listRowSeparator(.hidden)
                        }
                        .onDelete { offsets in
                            let records = savingsRecords
                            for index in offsets {
                                financeStore.deleteRecord(records[index])
                            }
                        }
                    }
                } header: {
                    Text("储蓄记录")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("储蓄管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingRecord = nil
                        title = ""
                        amountText = ""
                        date = Date()
                        note = ""
                        countAsIncome = false
                        annualRateText = ""
                        showingAddSavings = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSavings) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("储蓄名称（如：定期存款）", text: $title)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .listRowSeparator(.hidden)
                            HStack {
                                Text("¥")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                TextField("金额", text: $amountText)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .keyboardType(.decimalPad)
                            }
                            .listRowSeparator(.hidden)
                            DatePicker(selection: $date, displayedComponents: .date) {
                                Text("日期")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                            }
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .listRowSeparator(.hidden)
                            HStack {
                                Text("年利率")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                Spacer()
                                TextField("0", text: $annualRateText)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("%")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                        } header: {
                            Text("储蓄信息")
                                .font(.system(.footnote, design: .rounded))
                                .fontWeight(.semibold)
                        }
                        
                        Section {
                            TextField("备注", text: $note)
                                .font(.system(.body, design: .rounded))
                                .listRowSeparator(.hidden)
                        } header: {
                            Text("备注")
                                .font(.system(.footnote, design: .rounded))
                                .fontWeight(.semibold)
                        }
                    }
                    .navigationTitle(editingRecord != nil ? "编辑储蓄" : "添加储蓄")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("取消") { showingAddSavings = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("保存") {
                                saveSavingsRecord()
                            }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || Double(amountText) == nil)
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
    
    private func saveSavingsRecord() {
        guard let amount = Double(amountText) else { return }
        let rate = Double(annualRateText)
        let record = FinanceRecord(
            id: editingRecord?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            type: .income,
            date: date,
            note: note,
            incomePeriod: .savings,
            countAsIncome: countAsIncome,
            expectedReturn: rate
        )
        if editingRecord != nil {
            financeStore.updateRecord(record)
        } else {
            financeStore.addRecord(record)
        }
        showingAddSavings = false
    }
    
    private func chineseDateStr(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        return fmt.string(from: date)
    }
}

// MARK: - 资产详情视图

struct AssetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var financeStore: FinanceStore
    @ObservedObject var store: ItemStore
    @Binding var selectedRecord: FinanceRecord?
    
    private func chineseDateStr(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        return fmt.string(from: date)
    }
    
    private var savingsRecords: [FinanceRecord] {
        financeStore.records.filter { $0.type == .income && $0.incomePeriod == .savings }
    }
    
    private var investmentRecords: [FinanceRecord] {
        financeStore.records.filter { $0.type == .investment }
    }
    
    private var debtRecords: [FinanceRecord] {
        financeStore.records.filter { $0.type == .debt }
    }
    
    private var largeItems: [Item] {
        store.items.filter { $0.listType == .items && !$0.isArchived && $0.isLargeItem }
    }
    
    /// 非大件物品（去重：排除已标记为大件的物品）
    private var normalItems: [Item] {
        store.items.filter { $0.listType == .items && !$0.isArchived && !$0.isLargeItem && !$0.isPriceless }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 储蓄
                Section {
                    if savingsRecords.isEmpty {
                        Text("暂无储蓄记录")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(savingsRecords) { record in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    selectedRecord = record
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(chineseDateStr(record.date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("¥\(record.amount, specifier: "%.2f")")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.green)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "banknote.fill").foregroundStyle(.green)
                        Text("储蓄")
                        Spacer()
                        Text("¥\(savingsRecords.reduce(0) { $0 + $1.amount }, specifier: "%.0f")")
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                
                // 大件物品
                Section {
                    if largeItems.isEmpty {
                        Text("暂无大件物品")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(largeItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(item.type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("¥\(item.price, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "house.fill").foregroundStyle(.orange)
                        Text("大件物品")
                        Spacer()
                        Text("¥\(largeItems.reduce(0) { $0 + $1.price }, specifier: "%.0f")")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                
                // 物品价值（非大件）
                Section {
                    HStack {
                        Text("共 \(normalItems.count) 件物品")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("¥\(normalItems.reduce(0) { $0 + $1.price }, specifier: "%.2f")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    }
                } header: {
                    HStack {
                        Image(systemName: "cube.fill").foregroundStyle(.purple)
                        Text("物品价值")
                        Spacer()
                        Text("¥\(normalItems.reduce(0) { $0 + $1.price }, specifier: "%.0f")")
                            .foregroundStyle(.purple)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                
                // 投资
                Section {
                    if investmentRecords.isEmpty {
                        Text("暂无投资记录")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(investmentRecords) { record in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    selectedRecord = record
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text(chineseDateStr(record.date))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let ret = record.expectedReturn {
                                                Text("· \(ret, specifier: "%.1f")%")
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                            }
                                            if let platform = record.investmentPlatform, !platform.isEmpty {
                                                Text("· \(platform)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text("¥\(record.amount, specifier: "%.2f")")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill").foregroundStyle(.blue)
                        Text("投资")
                        Spacer()
                        Text("¥\(investmentRecords.reduce(0) { $0 + $1.amount }, specifier: "%.0f")")
                            .foregroundStyle(.blue)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                
                // 负债
                Section {
                    if debtRecords.isEmpty {
                        Text("暂无负债记录")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(debtRecords) { record in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    selectedRecord = record
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text(chineseDateStr(record.date))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let dt = record.debtType {
                                                Text("· \(dt.rawValue)")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                            if let months = record.loanMonths {
                                                Text("· \(months)期")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("¥\(record.remainingDebtAmount ?? record.amount, specifier: "%.0f")")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.red)
                                        if let monthly = record.monthlyPayment {
                                            Text("月供 ¥\(monthly, specifier: "%.0f")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "creditcard.fill").foregroundStyle(.red)
                        Text("负债")
                        Spacer()
                        Text("¥\(financeStore.totalRemainingDebt, specifier: "%.0f")")
                            .foregroundStyle(.red)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("资产详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DailyExpenseView(store: ItemStore(), groupStore: GroupStore(), financeStore: FinanceStore())
}
