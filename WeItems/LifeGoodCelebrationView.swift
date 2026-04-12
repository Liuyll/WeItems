//
//  LifeGoodCelebrationView.swift
//  WeItems
//

import SwiftUI

struct LifeGoodCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    let itemName: String
    var imageData: Data? = nil
    var details: String = ""
    
    @State private var showBackground = false
    @State private var showParticles = false
    @State private var showText = false
    @State private var showButton = false
    
    private var itemImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
    
    var body: some View {
        ZStack {
            // 渐变背景（暖色调）
            LinearGradient(
                colors: [
                    Color(red: 0.6, green: 0.3, blue: 0.1),
                    Color(red: 0.8, green: 0.5, blue: 0.2),
                    Color(red: 0.7, green: 0.4, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(showBackground ? 1 : 0)
            
            // 装饰性圆形
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 300, height: 300)
                        .offset(x: -100, y: -200)
                    
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 200, height: 200)
                        .offset(x: 150, y: 300)
                    
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 150, height: 150)
                        .offset(x: 120, y: -100)
                }
            }
            
            // 粒子效果
            if showParticles {
                ParticleView()
            }
            
            // 烟花效果
            FireworkView()
            
            // 主要内容
            VStack(spacing: 30) {
                Spacer()
                
                // 图标 / 图片
                if let uiImage = itemImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 40)
                        .scaleEffect(showText ? 1 : 0.8)
                        .opacity(showText ? 1 : 0)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 140, height: 140)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "heart.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(showText ? 1 : 0.5)
                    .opacity(showText ? 1 : 0)
                }
                
                // 标题文字
                Text("人生漫漫，幸福相伴。")
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundStyle(.white)
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 20)
                
                // 主要内容
                VStack(spacing: 16) {
                    Text("您拥有了第")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    // 数字
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(count)")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Text("件")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    VStack(spacing: 6) {
                        Text("精神好物")
                            .font(.system(size: 32, weight: .medium, design: .serif))
                            .foregroundStyle(.white)
                        
                        Text("「\(itemName)」")
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        
                        // 备注
                        if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(details)
                                .font(.system(size: 14, weight: .light, design: .serif))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 8)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 30)
                
                Spacer()
                
                // 完成按钮
                Button {
                    dismiss()
                } label: {
                    Text("继续收藏")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(red: 0.6, green: 0.3, blue: 0.1))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                }
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 20)
                .padding(.bottom, 50)
            }
            .padding()
        }
        .onAppear {
            // 动画序列
            withAnimation(.easeInOut(duration: 0.8)) {
                showBackground = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showParticles = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showText = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showButton = true
                }
            }
        }
    }
}

#Preview {
    LifeGoodCelebrationView(count: 3, itemName: "索尼降噪耳机", details: "陪伴我度过无数个深夜")
}
