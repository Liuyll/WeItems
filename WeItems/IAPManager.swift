//
//  IAPManager.swift
//  WeItems
//

import StoreKit
import SwiftUI
import Combine
import Security

/// IAP 产品 ID（需要在 App Store Connect 中配置）
enum IAPProduct: String, CaseIterable {
    case proYearly   = "lyl.WeItems.pro.yearly"    // 年度订阅（含7天免费试用）
    case proLifetime = "lyl.WeItems.pro.lifetime"   // 终生买断
}

/// VIP 等级：0=免费用户, 1=VIP(年度订阅), 2=MasterVIP(终生买断)
enum VIPLevel: Int, Codable {
    case free = 0
    case vip = 1
    case masterVIP = 2
    
    var displayName: String {
        switch self {
        case .free: return "免费用户"
        case .vip: return "VIP"
        case .masterVIP: return "MasterVIP"
        }
    }
}

@MainActor
class IAPManager: ObservableObject {
    static let shared = IAPManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// VIP 等级（本地 + 云端）
    @Published var vipLevel: VIPLevel = .free
    /// VIP 开启时间
    @Published var vipStartDate: Date?
    /// VIP 到期时间（终生买断为 9999-12-31）
    @Published var vipExpireDate: Date?
    
    /// 是否为 Pro 用户（VIP 或 MasterVIP）
    var isPro: Bool {
        vipLevel != .free || !purchasedProductIDs.isEmpty
    }
    
    /// VIP 是否在有效期内（等级>=1 且未过期）
    var isVIPActive: Bool {
        guard vipLevel.rawValue >= 1 else { return false }
        if vipLevel == .masterVIP { return true }
        guard let expire = vipExpireDate else { return false }
        return expire > Date()
    }
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        loadLocalVIPInfo()
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await checkSubscriptionStatus() }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - 本地 VIP 信息持久化（Keychain）
    
    private let vipLevelKey = "com.weitems.vip_level"
    private let vipStartDateKey = "com.weitems.vip_start_date"
    private let vipExpireDateKey = "com.weitems.vip_expire_date"
    
    private func loadLocalVIPInfo() {
        if let levelStr = getFromKeychain(key: vipLevelKey), let level = Int(levelStr) {
            vipLevel = VIPLevel(rawValue: level) ?? .free
        }
        if let startStr = getFromKeychain(key: vipStartDateKey) {
            vipStartDate = ISO8601DateFormatter().date(from: startStr)
        }
        if let expireStr = getFromKeychain(key: vipExpireDateKey) {
            let expire = ISO8601DateFormatter().date(from: expireStr)
            vipExpireDate = expire
            // 检查是否过期（非终生）
            if vipLevel == .vip, let expire, expire < Date() {
                vipLevel = .free
                saveLocalVIPInfo()
            }
        }
    }
    
    private func saveLocalVIPInfo() {
        let isoFormatter = ISO8601DateFormatter()
        saveToKeychain(key: vipLevelKey, value: "\(vipLevel.rawValue)")
        if let start = vipStartDate {
            saveToKeychain(key: vipStartDateKey, value: isoFormatter.string(from: start))
        }
        if let expire = vipExpireDate {
            saveToKeychain(key: vipExpireDateKey, value: isoFormatter.string(from: expire))
        }
    }
    
    /// 本地 VIP 是否已过期，需要从云端刷新
    var isVIPExpiredLocally: Bool {
        // 免费用户 → 需要检查云端是否有 VIP
        if vipLevel == .free { return true }
        // MasterVIP 永不过期
        if vipLevel == .masterVIP { return false }
        // VIP 检查到期时间
        guard let expire = vipExpireDate else { return true }
        return expire < Date()
    }
    
    /// 从云端 VIP 信息更新本地状态
    func applyRemoteVIPInfo(type: Int, startDate: String?, expireDate: String?) {
        let isoFormatter = ISO8601DateFormatter()
        vipLevel = VIPLevel(rawValue: type) ?? .free
        if let s = startDate { vipStartDate = isoFormatter.date(from: s) }
        if let e = expireDate { vipExpireDate = isoFormatter.date(from: e) }
        // 检查是否过期
        if vipLevel == .vip, let expire = vipExpireDate, expire < Date() {
            vipLevel = .free
        }
        saveLocalVIPInfo()
    }
    
    /// 清除本地 VIP 信息（登出时调用）
    func clearLocalVIPInfo() {
        vipLevel = .free
        vipStartDate = nil
        vipExpireDate = nil
        deleteFromKeychain(key: vipLevelKey)
        deleteFromKeychain(key: vipStartDateKey)
        deleteFromKeychain(key: vipExpireDateKey)
    }
    
    // MARK: - Keychain 操作
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteFromKeychain(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - 加载产品
    
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            let ids = IAPProduct.allCases.map { $0.rawValue }
            print("[IAP] 请求产品列表: \(ids)")
            let storeProducts = try await Product.products(for: ids)
            products = storeProducts.sorted { $0.price < $1.price }
            isLoading = false
            
            if storeProducts.isEmpty {
                print("[IAP] ⚠️ 未获取到任何产品，请检查 App Store Connect 配置")
                print("[IAP]   - 产品 ID 是否在 App Store Connect 中创建")
                print("[IAP]   - 付费协议是否已签署并激活")
                print("[IAP]   - 产品状态是否为\"准备提交\"")
                errorMessage = "无法获取订阅方案，请检查网络后重试"
            } else {
                print("[IAP] 成功加载 \(storeProducts.count) 个产品: \(storeProducts.map { "\($0.id)(\($0.displayPrice))" })")
            }
        } catch {
            isLoading = false
            errorMessage = "获取产品信息失败：\(error.localizedDescription)"
            print("[IAP] 加载产品失败: \(error)")
        }
    }
    
    // MARK: - 购买
    
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
                isLoading = false
                print("[IAP] 购买成功: \(transaction.productID)")
                
                // 打印交易验证信息
                switch verification {
                case .verified(let signedTransaction):
                    print("[IAP] ===== 交易验证信息 =====")
                    print("[IAP] productID: \(signedTransaction.productID)")
                    print("[IAP] transactionID: \(signedTransaction.id)")
                    print("[IAP] originalID: \(signedTransaction.originalID)")
                    print("[IAP] purchaseDate: \(signedTransaction.purchaseDate)")
                    print("[IAP] expirationDate: \(String(describing: signedTransaction.expirationDate))")
                    print("[IAP] environment: \(signedTransaction.environment.rawValue)")
                    print("[IAP] jwsRepresentation: \(verification.jwsRepresentation)")
                    print("[IAP] ===========================")
                case .unverified(_, let error):
                    print("[IAP] 验证失败: \(error)")
                }
                
                // 更新 VIP 等级
                updateVIPLevelFromTransaction(productID: transaction.productID)
                
                // 确保 token 有效后同步到云端
                Task {
                    let tokenValid = await AuthManager.shared.ensureValidToken()
                    if tokenValid {
                        await syncVIPToCloud()
                        print("[IAP] 购买成功，VIP 信息已同步到云端")
                    } else {
                        print("[IAP] 购买成功，但 token 无效，VIP 信息暂未同步到云端")
                    }
                }
                
                return true
                
            case .userCancelled:
                isLoading = false
                return false
                
            case .pending:
                isLoading = false
                errorMessage = "购买待确认，请稍后查看"
                return false
                
            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            isLoading = false
            errorMessage = "购买失败：\(error.localizedDescription)"
            print("[IAP] 购买失败: \(error)")
            return false
        }
    }
    
    /// 根据购买的产品 ID 更新 VIP 等级
    private func updateVIPLevelFromTransaction(productID: String) {
        let now = Date()
        if productID == IAPProduct.proLifetime.rawValue {
            // 终生买断 → MasterVIP
            vipLevel = .masterVIP
            vipStartDate = now
            // 到期时间设为 9999-12-31
            var components = DateComponents()
            components.year = 9999
            components.month = 12
            components.day = 31
            vipExpireDate = Calendar.current.date(from: components) ?? now
        } else if productID == IAPProduct.proYearly.rawValue {
            // 年度订阅 → VIP（如果已是 MasterVIP 则不降级）
            if vipLevel != .masterVIP {
                vipLevel = .vip
                vipStartDate = now
                vipExpireDate = Calendar.current.date(byAdding: .year, value: 1, to: now)
            }
        }
        saveLocalVIPInfo()
    }
    
    // MARK: - 云端同步 VIP
    
    /// 同步 VIP 信息到云端
    func syncVIPToCloud() async {
        guard let client = AuthManager.shared.getCloudBaseClient() else {
            print("[IAP] 无法获取 CloudBaseClient，跳过 VIP 同步")
            return
        }
        
        await client.syncVIPInfo(
            vipType: vipLevel.rawValue,
            startDate: vipStartDate ?? Date(),
            expireDate: vipExpireDate ?? Date()
        )
        print("[IAP] VIP 信息已同步到云端: level=\(vipLevel.rawValue)")
    }
    
    // MARK: - 恢复购买
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            isLoading = false
            if purchasedProductIDs.isEmpty {
                errorMessage = "没有找到可恢复的购买记录"
            } else {
                // 恢复成功，同步 VIP 到云端
                let tokenValid = await AuthManager.shared.ensureValidToken()
                if tokenValid {
                    await syncVIPToCloud()
                    print("[IAP] 恢复购买成功，VIP 信息已同步到云端")
                }
            }
        } catch {
            isLoading = false
            errorMessage = "恢复购买失败：\(error.localizedDescription)"
        }
    }
    
    // MARK: - 更新已购产品
    
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchased.insert(transaction.productID)
                updateVIPLevelFromTransaction(productID: transaction.productID)
            }
        }
        
        purchasedProductIDs = purchased
    }
    
    // MARK: - 监听交易更新
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    
                    // 检查是否被退款
                    if let revocationDate = transaction.revocationDate {
                        print("")
                        print("[IAP] ⚠️⚠️⚠️ ========== 检测到退款 ==========")
                        print("[IAP] 产品ID: \(transaction.productID)")
                        print("[IAP] 交易ID: \(transaction.id)")
                        print("[IAP] 原始交易ID: \(transaction.originalID)")
                        print("[IAP] 购买时间: \(transaction.purchaseDate)")
                        print("[IAP] 退款时间: \(revocationDate)")
                        if let reason = transaction.revocationReason {
                            print("[IAP] 退款原因: \(reason == .developerIssue ? "开发者问题" : "其他原因")")
                        }
                        print("[IAP] 当前VIP等级: \(await MainActor.run { self.vipLevel.displayName })")
                        print("[IAP] =====================================")
                        print("")
                        
                        await MainActor.run { [self] in
                            self.purchasedProductIDs.remove(transaction.productID)
                            self.revokeVIPIfNeeded()
                        }
                        await transaction.finish()
                        
                        // 同步到云端
                        let tokenValid = await AuthManager.shared.ensureValidToken()
                        if tokenValid {
                            await MainActor.run { [self] in
                                _ = Task { await self.syncVIPToCloud() }
                            }
                        }
                        let newLevel = await MainActor.run { self.vipLevel.displayName }
                        print("[IAP] ✅ 退款处理完成，当前VIP等级: \(newLevel)，已同步到云端: \(tokenValid)")
                        continue
                    }
                    
                    // 检查订阅是否已过期（取消订阅后到期）
                    if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                        print("")
                        print("[IAP] ⚠️⚠️⚠️ ========== 检测到订阅过期 ==========")
                        print("[IAP] 产品ID: \(transaction.productID)")
                        print("[IAP] 交易ID: \(transaction.id)")
                        print("[IAP] 原始交易ID: \(transaction.originalID)")
                        print("[IAP] 购买时间: \(transaction.purchaseDate)")
                        print("[IAP] 过期时间: \(expirationDate)")
                        print("[IAP] 当前时间: \(Date())")
                        print("[IAP] 已过期: \(String(format: "%.0f", Date().timeIntervalSince(expirationDate)))秒")
                        print("[IAP] 当前VIP等级: \(await MainActor.run { self.vipLevel.displayName })")
                        print("[IAP] ==========================================")
                        print("")
                        
                        await MainActor.run { [self] in
                            self.purchasedProductIDs.remove(transaction.productID)
                            self.revokeVIPIfNeeded()
                        }
                        await transaction.finish()
                        
                        // 同步到云端
                        let tokenValid = await AuthManager.shared.ensureValidToken()
                        if tokenValid {
                            await MainActor.run { [self] in
                                _ = Task { await self.syncVIPToCloud() }
                            }
                        }
                        let newLevel = await MainActor.run { self.vipLevel.displayName }
                        print("[IAP] ✅ 订阅过期处理完成，当前VIP等级: \(newLevel)，已同步到云端: \(tokenValid)")
                        continue
                    }
                    
                    // 正常购买/续订
                    print("")
                    print("[IAP] 🎉 ========== 交易更新（购买/续订）==========")
                    print("[IAP] 产品ID: \(transaction.productID)")
                    print("[IAP] 交易ID: \(transaction.id)")
                    print("[IAP] 购买时间: \(transaction.purchaseDate)")
                    if let exp = transaction.expirationDate {
                        print("[IAP] 到期时间: \(exp)")
                    }
                    print("[IAP] =============================================")
                    print("")
                    
                    await MainActor.run { [self] in
                        self.purchasedProductIDs.insert(transaction.productID)
                        self.updateVIPLevelFromTransaction(productID: transaction.productID)
                    }
                    await transaction.finish()
                    
                    // 交易更新后同步 VIP 到云端
                    let tokenValid = await AuthManager.shared.ensureValidToken()
                    if tokenValid {
                        await MainActor.run { [self] in
                            _ = Task { await self.syncVIPToCloud() }
                        }
                    }
                    let newLevel = await MainActor.run { self.vipLevel.displayName }
                    print("[IAP] ✅ 交易处理完成，当前VIP等级: \(newLevel)，已同步到云端: \(tokenValid)")
                }
            }
        }
    }
    
    // MARK: - 退款/取消订阅处理
    
    /// 检查并撤销 VIP（退款或订阅过期时调用）
    private func revokeVIPIfNeeded() {
        // 重新检查当前所有有效权益
        Task {
            var hasYearly = false
            var hasLifetime = false
            
            print("[IAP] 🔍 重新检查当前有效权益...")
            
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    // 跳过已退款的交易
                    if transaction.revocationDate != nil {
                        print("[IAP]   ❌ 跳过已退款: \(transaction.productID)")
                        continue
                    }
                    // 跳过已过期的交易
                    if let exp = transaction.expirationDate, exp < Date() {
                        print("[IAP]   ❌ 跳过已过期: \(transaction.productID), 过期: \(exp)")
                        continue
                    }
                    
                    print("[IAP]   ✅ 有效权益: \(transaction.productID)")
                    
                    if transaction.productID == IAPProduct.proLifetime.rawValue {
                        hasLifetime = true
                    } else if transaction.productID == IAPProduct.proYearly.rawValue {
                        hasYearly = true
                    }
                }
            }
            
            await MainActor.run {
                let previousLevel = self.vipLevel
                if hasLifetime {
                    self.vipLevel = .masterVIP
                } else if hasYearly {
                    self.vipLevel = .vip
                } else {
                    self.vipLevel = .free
                    self.vipStartDate = nil
                    self.vipExpireDate = nil
                }
                self.purchasedProductIDs = hasLifetime || hasYearly ? self.purchasedProductIDs : []
                self.saveLocalVIPInfo()
                
                print("[IAP] 📊 VIP 等级变更: \(previousLevel.displayName) → \(self.vipLevel.displayName)")
            }
        }
    }
    
    /// 检查订阅状态（App 启动和前台恢复时调用）
    func checkSubscriptionStatus() async {
        var validProductIDs: Set<String> = []
        var hasValidSubscription = false
        var hasLifetime = false
        
        print("[IAP] 🔄 检查订阅状态...")
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // 跳过已退款
                if let revDate = transaction.revocationDate {
                    print("[IAP]   ❌ 已退款: \(transaction.productID), 退款时间: \(revDate)")
                    continue
                }
                // 跳过已过期
                if let exp = transaction.expirationDate, exp < Date() {
                    print("[IAP]   ❌ 已过期: \(transaction.productID), 过期时间: \(exp)")
                    continue
                }
                
                print("[IAP]   ✅ 有效: \(transaction.productID)\(transaction.expirationDate.map { ", 到期: \($0)" } ?? "")")
                validProductIDs.insert(transaction.productID)
                
                if transaction.productID == IAPProduct.proLifetime.rawValue {
                    hasLifetime = true
                } else if transaction.productID == IAPProduct.proYearly.rawValue {
                    hasValidSubscription = true
                    if let exp = transaction.expirationDate {
                        vipExpireDate = exp
                    }
                }
            }
        }
        
        purchasedProductIDs = validProductIDs
        
        let previousLevel = vipLevel
        if hasLifetime {
            vipLevel = .masterVIP
        } else if hasValidSubscription {
            vipLevel = .vip
        } else {
            vipLevel = .free
            vipStartDate = nil
            vipExpireDate = nil
        }
        
        saveLocalVIPInfo()
        
        if previousLevel != vipLevel {
            print("[IAP] ⚠️ VIP 等级变化: \(previousLevel.displayName) → \(vipLevel.displayName)")
            let tokenValid = await AuthManager.shared.ensureValidToken()
            if tokenValid {
                await syncVIPToCloud()
                print("[IAP] ✅ VIP 等级变化已同步到云端")
            }
        } else {
            print("[IAP] ℹ️ VIP 等级未变化: \(vipLevel.displayName)")
        }
    }
    
    // MARK: - 验证交易
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
