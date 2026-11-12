//
//  SplashScreenView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UIKit

struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isContentVisible = false
    @State private var isGlowing = false

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            // Soft hero-gradient glow behind the icon.
            Circle()
                .fill(
                    LinearGradient(
                        colors: AppTheme.heroGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .opacity(isGlowing ? 0.45 : 0.28)
                .offset(y: -60)
                .accessibilityHidden(true)

            VStack(spacing: 28) {
                AppIconArtwork()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(AppTheme.cardStroke, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 24, x: 0, y: 12)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Ri Network Speed")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Real-time speed, ping & usage monitoring")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .offset(y: isContentVisible || reduceMotion ? 0 : 8)
            }
            .padding(.horizontal, 32)
            .offset(y: -40)
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible || reduceMotion ? 1 : 0.96)
        }
        .task {
            guard !isContentVisible else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) {
                    isContentVisible = true
                }
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                isContentVisible = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}

private struct AppIconArtwork: View {
    var body: some View {
        Group {
            if let icon = UIImage.primaryAppIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: AppTheme.heroGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "speedometer")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private extension UIImage {
    static var primaryAppIcon: UIImage? {
        let iconFiles = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primaryIcon = iconFiles?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconNames = primaryIcon?["CFBundleIconFiles"] as? [String]

        guard let iconName = iconNames?.last else {
            return nil
        }

        return UIImage(named: iconName)
    }
}

#Preview {
    SplashScreenView()
        .preferredColorScheme(.dark)
}
