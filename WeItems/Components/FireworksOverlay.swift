//
//  FireworksOverlay.swift
//  WeItems
//

import SwiftUI

// MARK: - 烟花粒子模型

struct FireworkParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var color: Color
    var size: CGFloat
    var opacity: Double
}

// MARK: - 烟花动画视图

struct FireworksOverlay: View {
    @State private var bursts: [[FireworkParticle]] = []
    @State private var animating = false
    var duration: Double = 3.0
    var burstCount: Int = 5
    var colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint, .cyan]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bursts.flatMap { $0 }) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(
                            x: animating ? particle.targetX : particle.x,
                            y: animating ? particle.targetY : particle.y
                        )
                        .opacity(animating ? 0 : particle.opacity)
                }
            }
            .onAppear {
                generateBursts(in: geo.size)
                withAnimation(.easeOut(duration: duration)) {
                    animating = true
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func generateBursts(in size: CGSize) {
        var allBursts: [[FireworkParticle]] = []
        
        for _ in 0..<burstCount {
            let centerX = CGFloat.random(in: size.width * 0.15...size.width * 0.85)
            let centerY = CGFloat.random(in: size.height * 0.1...size.height * 0.5)
            let particleCount = Int.random(in: 12...20)
            var particles: [FireworkParticle] = []
            
            for _ in 0..<particleCount {
                let angle = Double.random(in: 0...(2 * .pi))
                let radius = CGFloat.random(in: 40...120)
                let targetX = centerX + cos(angle) * radius
                let targetY = centerY + sin(angle) * radius
                
                particles.append(FireworkParticle(
                    x: centerX,
                    y: centerY,
                    targetX: targetX,
                    targetY: targetY,
                    color: colors.randomElement()!,
                    size: CGFloat.random(in: 4...8),
                    opacity: Double.random(in: 0.7...1.0)
                ))
            }
            allBursts.append(particles)
        }
        bursts = allBursts
    }
}
