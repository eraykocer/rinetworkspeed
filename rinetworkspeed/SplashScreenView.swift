//
//  SplashScreenView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UIKit

struct SplashScreenView: View {
    @State private var isContentVisible = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.10),
                    Color(red: 0.04, green: 0.09, blue: 0.20),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: -120, y: -250)

            Circle()
                .fill(Color.blue.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 42)
                .offset(x: 150, y: 240)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.white.opacity(0.10))
                        .frame(width: 154, height: 154)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(.white.opacity(0.20), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 14)
                        .scaleEffect(pulse ? 1.03 : 0.97)

                    AppIconArtwork()
                        .frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                VStack(spacing: 8) {
                    Text("Ri Network Speed")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Anlik hiz, ping ve kullanim takibi")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                HStack(spacing: 10) {
                    statusPill(title: "Speed", color: Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255))
                    statusPill(title: "Ping", color: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                    statusPill(title: "Usage", color: Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255))
                }
            }
            .padding(.horizontal, 28)
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.94)
        }
        .task {
            guard !isContentVisible else { return }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                isContentVisible = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
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
                        colors: [Color.blue, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "speedometer")
                        .font(.system(size: 54, weight: .bold))
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
}
