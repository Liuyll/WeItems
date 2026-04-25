//
//  SpiritTravelCelebrationView.swift
//  WeItems
//

import SwiftUI

// MARK: - 轻量烟花粒子

struct FireworkDot: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var color: Color
    var size: CGFloat
}

// 烟花视图（轻量版，纯 SwiftUI 动画）
struct FireworkView: View {
    @State private var bursts: [[FireworkDot]] = []
    @State private var animating = false
    
    let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .cyan, .white]
    
    var body: some View {
        ZStack {
            ForEach(bursts.flatMap({ $0 })) { dot in
                Circle()
                    .fill(dot.color)
                    .frame(width: dot.size, height: dot.size)
                    .position(x: animating ? dot.targetX : dot.x,
                              y: animating ? dot.targetY : dot.y)
                    .opacity(animating ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            generateBursts()
            withAnimation(.easeOut(duration: 1.2)) {
                animating = true
            }
        }
    }
    
    private func generateBursts() {
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        
        for _ in 0..<5 {
            let cx = CGFloat.random(in: screenW * 0.15...screenW * 0.85)
            let cy = CGFloat.random(in: screenH * 0.15...screenH * 0.4)
            let burstColor = colors.randomElement()!
            let count = 12
            
            var dots: [FireworkDot] = []
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi
                let dist = CGFloat.random(in: 40...90)
                dots.append(FireworkDot(
                    x: cx, y: cy,
                    targetX: cx + cos(angle) * dist,
                    targetY: cy + sin(angle) * dist + 30,
                    color: burstColor.opacity(Double.random(in: 0.6...1.0)),
                    size: CGFloat.random(in: 3...6)
                ))
            }
            bursts.append(dots)
        }
    }
}

// 冒泡粒子（轻量版）
struct BubbleParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let opacity: Double
}

struct ParticleView: View {
    @State private var animating = false
    
    let particles: [BubbleParticle] = {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        return (0..<20).map { _ in
            BubbleParticle(
                x: CGFloat.random(in: 0...w),
                startY: CGFloat.random(in: h * 0.5...h + 50),
                size: CGFloat.random(in: 3...7),
                duration: Double.random(in: 3...6),
                delay: Double.random(in: 0...2),
                opacity: Double.random(in: 0.1...0.35)
            )
        }
    }()
    
    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(Color.white.opacity(p.opacity))
                    .frame(width: p.size, height: p.size)
                    .position(x: p.x, y: animating ? -20 : p.startY)
                    .animation(
                        .linear(duration: p.duration)
                        .repeatForever(autoreverses: false)
                        .delay(p.delay),
                        value: animating
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            animating = true
        }
    }
}

// 粒子模型（保留兼容旧引用）
struct Particle {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: CGFloat
    var opacity: CGFloat
}

struct SpiritTravelCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    var itemName: String = ""
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
            // 渐变背景
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.4, blue: 0.2),
                    Color(red: 0.2, green: 0.6, blue: 0.3),
                    Color(red: 0.15, green: 0.5, blue: 0.25)
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
                
                // 图片 / 图标
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
                        
                        Image(systemName: "tent")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(showText ? 1 : 0.5)
                    .opacity(showText ? 1 : 0)
                }
                
                // Congratulation 文字
                Text("Congratulation")
                    .font(.system(size: 42, weight: .light, design: .serif))
                    .foregroundStyle(.white)
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 20)
                
                // 主要内容
                VStack(spacing: 16) {
                    Text("这是本年度第")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    // 数字
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(count)")
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Text("次")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Text("精神旅行")
                        .font(.system(size: 32, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    
                    if !itemName.isEmpty {
                        Text("「\(itemName)」")
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(details)
                            .font(.system(size: 14, weight: .light, design: .serif))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 30)
                
                Spacer()
                
                // 完成按钮
                Button {
                    dismiss()
                } label: {
                    Text("继续探索")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 0.2))
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
    SpiritTravelCelebrationView(count: 5)
}
