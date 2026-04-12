//
//  ProUpgradeView.swift
//  WeItems
//

import SwiftUI
import StoreKit

struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iapManager = IAPManager.shared
    @EnvironmentObject var authManager: AuthManager
    
    @State private var purchaseSuccess = false
    @State private var showingLogin = false
    
    private let features = [
        ("icloud.fill", "远端同步数据", "数据实时跨设备云端同步"),
        ("heart.fill", "共享心愿清单", "与好朋友一起分享和实现心愿"),
        ("lock.shield.fill", "资产安全保护", "Face ID 保护敏感数据"),
        ("apps.iphone", "小程序便捷记录", "微信小程序快速记录（稍后推出）"),
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 头部
                    headerSection
                    
                    // 功能亮点
                    featuresSection
                    
                    // 产品列表
                    productsSection
                    
                    // 恢复购买
                    restoreButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("返回") { dismiss() }
                }
            }
            .customInfoAlert(
                isPresented: $purchaseSuccess,
                title: "购买成功",
                message: "欢迎成为 Pro 会员！所有高级功能已解锁。",
                onDismiss: { dismiss() }
            )
            .sheet(isPresented: $showingLogin) {
                AuthViewWrapper()
            }
            .overlay {
                if iapManager.isLoading {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .padding(24)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                }
            }
        }
    }
    
    // MARK: - 头部
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ProBadge(fontSize: 32, paddingH: 24, paddingV: 10)
                .padding(.top, 20)
            
            Text("解锁全部高级功能，提升记录体验")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 功能亮点
    
    private var featuresSection: some View {
        VStack(spacing: 0) {
            ForEach(features, id: \.0) { icon, title, desc in
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                
                if icon != features.last?.0 {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - 产品列表
    
    private var productsSection: some View {
        VStack(spacing: 10) {
            if iapManager.products.isEmpty && !iapManager.isLoading {
                VStack(spacing: 8) {
                    Text("暂无可用方案")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重新加载") {
                        Task { await iapManager.loadProducts() }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 20)
            } else {
                ForEach(iapManager.products, id: \.id) { product in
                    productCard(product)
                }
            }
            
            if let error = iapManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }
    
    private func productCard(_ product: Product) -> some View {
        let isPurchased = iapManager.purchasedProductIDs.contains(product.id)
        let isYearly = product.id.contains("yearly")
        let isLifetime = product.id.contains("lifetime")
        
        return Button {
            guard !isPurchased else { return }
            Task {
                // 先校验 token 是否有效
                if !authManager.isAuthenticated {
                    // 未登录，跳转登录
                    await MainActor.run { showingLogin = true }
                    return
                }
                
                // 尝试确保 token 有效（过期则自动刷新）
                let tokenValid = await authManager.ensureValidToken()
                if !tokenValid {
                    // token 刷新失败，跳转登录
                    await MainActor.run { showingLogin = true }
                    return
                }
                
                let success = await iapManager.purchase(product)
                if success { purchaseSuccess = true }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        if isLifetime {
                            Text("最划算")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.purple))
                        }
                    }
                    Text(isYearly ? "\(product.displayPrice)/年，含7天免费试用" : product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isPurchased {
                    Text("已购买")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isYearly ? .blue : .purple)
                        )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isYearly ? Color.blue.opacity(0.4) : isLifetime ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 恢复购买
    
    private var restoreButton: some View {
        Button {
            Task { await iapManager.restorePurchases() }
        } label: {
            Text("恢复购买")
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
    }
    
    // MARK: - 底部说明
    
    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("年度订阅含7天免费试用，试用期内取消不收费")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("订阅将自动续期，可随时在系统设置中取消")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("购买即表示同意服务条款与隐私政策")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    ProUpgradeView()
}
