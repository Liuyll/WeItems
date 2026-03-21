//
//  SpiritTravelCelebrationView.swift
//  WeItems
//

import SwiftUI
import Combine

// 礼炮状态
enum FireworkState {
    case launching(startPosition: CGPoint, targetPosition: CGPoint, progress: CGFloat)
    case exploding(position: CGPoint, particles: [ExplosionParticle])
}

// 爆炸粒子
struct ExplosionParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var color: Color
    var size: CGFloat
    var opacity: Double
}

// 礼炮
struct FireworkRocket: Identifiable {
    let id = UUID()
    var state: FireworkState
    let color: Color
}

// 烟花视图
struct FireworkView: View {
    @State private var rockets: [FireworkRocket] = []
    @State private var timer: Timer? = nil
    @State private var launchCount = 0
    let maxLaunches = 8
    let duration: TimeInterval = 2.0
    
    let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .blue, .cyan, .white]
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { _ in
            Canvas { context, size in
                for rocket in rockets {
                    switch rocket.state {
                    case .launching(let startPos, let targetPos, let progress):
                        // 绘制上升的礼炮
                        let currentX = startPos.x + (targetPos.x - startPos.x) * progress
                        let currentY = startPos.y + (targetPos.y - startPos.y) * progress
                        
                        var path = Path()
                        path.addEllipse(in: CGRect(x: currentX - 3, y: currentY - 3, width: 6, height: 6))
                        context.fill(path, with: .color(rocket.color))
                        
                        // 拖尾效果
                        for i in 1...5 {
                            let trailProgress = max(0, progress - Double(i) * 0.02)
                            let trailX = startPos.x + (targetPos.x - startPos.x) * trailProgress
                            let trailY = startPos.y + (targetPos.y - startPos.y) * trailProgress
                            let alpha = 1.0 - Double(i) * 0.15
                            var trailPath = Path()
                            trailPath.addEllipse(in: CGRect(x: trailX - 2, y: trailY - 2, width: 4, height: 4))
                            context.fill(trailPath, with: .color(rocket.color.opacity(alpha)))
                        }
                        
                    case .exploding(_, let particles):
                        // 绘制爆炸粒子
                        for particle in particles {
                            var path = Path()
                            path.addEllipse(in: CGRect(
                                x: particle.position.x - particle.size / 2,
                                y: particle.position.y - particle.size / 2,
                                width: particle.size,
                                height: particle.size
                            ))
                            context.fill(path, with: .color(particle.color.opacity(particle.opacity)))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startFireworks()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startFireworks() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // 持续发射礼炮
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard launchCount < maxLaunches else { return }
            
            let startX = CGFloat.random(in: screenWidth * 0.1...screenWidth * 0.9)
            let targetX = startX + CGFloat.random(in: -50...50)
            let targetY = CGFloat.random(in: screenHeight * 0.15...screenHeight * 0.35)
            
            let rocket = FireworkRocket(
                state: .launching(
                    startPosition: CGPoint(x: startX, y: screenHeight),
                    targetPosition: CGPoint(x: targetX, y: targetY),
                    progress: 0
                ),
                color: colors.randomElement()!
            )
            
            rockets.append(rocket)
            launchCount += 1
            
            // 发射动画
            animateLaunch(for: rocket.id)
        }
        
        // 2秒后停止
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            timer?.invalidate()
        }
    }
    
    private func animateLaunch(for rocketId: UUID) {
        let steps = 20
        let interval = 0.015
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * interval) {
                if let index = rockets.firstIndex(where: { $0.id == rocketId }) {
                    if case .launching(let startPos, let targetPos, _) = rockets[index].state {
                        let progress = CGFloat(step) / CGFloat(steps)
                        
                        if progress >= 1.0 {
                            // 到达顶点，爆炸
                            explode(at: targetPos, for: rocketId)
                        } else {
                            rockets[index].state = .launching(
                                startPosition: startPos,
                                targetPosition: targetPos,
                                progress: progress
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func explode(at position: CGPoint, for rocketId: UUID) {
        guard let index = rockets.firstIndex(where: { $0.id == rocketId }) else { return }
        
        let particleCount = 25
        let explosionColors = colors.shuffled().prefix(3)
        
        let particles = (0..<particleCount).map { i in
            let angle = Double(i) / Double(particleCount) * 2 * .pi + Double.random(in: -0.2...0.2)
            let speed = CGFloat.random(in: 4...10)
            return ExplosionParticle(
                position: position,
                velocity: CGPoint(
                    x: cos(angle) * speed,
                    y: sin(angle) * speed
                ),
                color: explosionColors.randomElement()!,
                size: CGFloat.random(in: 3...7),
                opacity: 1.0
            )
        }
        
        rockets[index].state = .exploding(position: position, particles: particles)
        
        // 爆炸粒子动画
        animateExplosion(for: rocketId)
    }
    
    private func animateExplosion(for rocketId: UUID) {
        let steps = 40
        let interval = 0.02
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * interval) {
                if let index = rockets.firstIndex(where: { $0.id == rocketId }) {
                    if case .exploding(let position, var particles) = rockets[index].state {
                        for i in particles.indices {
                            // 更新位置
                            particles[i].position.x += particles[i].velocity.x
                            particles[i].position.y += particles[i].velocity.y
                            
                            // 重力
                            particles[i].velocity.y += 0.2
                            
                            // 阻力
                            particles[i].velocity.x *= 0.96
                            particles[i].velocity.y *= 0.96
                            
                            // 渐隐
                            particles[i].opacity = 1.0 - Double(step) / Double(steps)
                        }
                        
                        rockets[index].state = .exploding(position: position, particles: particles)
                        
                        // 动画结束，移除
                        if step == steps {
                            rockets.remove(at: index)
                        }
                    }
                }
            }
        }
    }
}

struct SpiritTravelCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    
    @State private var showBackground = false
    @State private var showParticles = false
    @State private var showText = false
    @State private var showButton = false
    
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
                
                // 图标
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

// 粒子效果视图
struct ParticleView: View {
    @State private var particles: [Particle] = []
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    var path = Path()
                    path.addEllipse(in: CGRect(x: particle.x, y: particle.y, width: particle.size, height: particle.size))
                    
                    let color = Color.white.opacity(particle.opacity)
                    context.fill(path, with: .color(color))
                }
            }
        }
        .onReceive(timer) { _ in
            updateParticles()
        }
        .onAppear {
            // 初始化粒子
            for _ in 0..<30 {
                particles.append(createParticle())
            }
        }
    }
    
    private func createParticle() -> Particle {
        Particle(
            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
            y: CGFloat.random(in: UIScreen.main.bounds.height...UIScreen.main.bounds.height + 100),
            size: CGFloat.random(in: 3...8),
            speed: CGFloat.random(in: 0.5...2),
            opacity: CGFloat.random(in: 0.1...0.4)
        )
    }
    
    private func updateParticles() {
        for i in particles.indices {
            particles[i].y -= particles[i].speed
            
            // 重置超出屏幕的粒子
            if particles[i].y < -20 {
                particles[i] = createParticle()
            }
        }
    }
}

// 粒子模型
struct Particle {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: CGFloat
    var opacity: CGFloat
}

#Preview {
    SpiritTravelCelebrationView(count: 5)
}
